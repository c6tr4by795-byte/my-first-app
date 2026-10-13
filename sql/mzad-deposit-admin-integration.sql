-- MZAD PHONE: integrated deposit + payment review backend
-- Apply only after backing up production and confirming mzad-foundation-v2.sql is the active schema.
begin;

-- Generate non-guessable human-readable references without relying on another migration.
create or replace function public.mzad_generate_number(p_prefix text)
returns text language plpgsql volatile security definer set search_path = public
as $$
begin
  return upper(coalesce(nullif(regexp_replace(p_prefix, '[^A-Za-z0-9]', '', 'g'), ''), 'MZ'))
    || '-' || to_char(clock_timestamp(), 'YYMMDDHH24MISS')
    || '-' || upper(substr(encode(gen_random_bytes(5), 'hex'), 1, 10));
end $$;

-- Compatibility columns used by existing UI are replaced by canonical foundation names.
-- No service-role key is used in browser code.

create or replace function public.mzad_get_enabled_payment_methods()
returns table(id uuid, code text, name_ar text, name_en text, recipient_name text, recipient_identifier text, instructions_ar text, is_enabled boolean, sort_order integer)
language sql stable security definer set search_path = public
as $$
  select m.id,
         case m.method_type
           when 'mastercard' then 'mastercard'
           when 'zain_cash' then 'zain_cash'
           when 'phone_account' then 'phone'
           else 'bank'
         end,
         m.display_name_ar, m.display_name_ar,
         m.recipient_name, m.recipient_identifier, m.instructions_ar,
         m.is_enabled, m.sort_order
  from public.mzad_payment_methods m
  where m.is_enabled = true
  order by m.sort_order, m.display_name_ar;
$$;

create or replace function public.mzad_create_auction_deposit(p_auction_id uuid, p_role text)
returns uuid language plpgsql security definer set search_path = public
as $$
declare v_user uuid := auth.uid(); v_a public.mzad_auctions%rowtype; v_dep uuid; v_amount bigint;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_a from public.mzad_auctions where id=p_auction_id for update;
  if not found then raise exception 'AUCTION_NOT_FOUND'; end if;
  if p_role not in ('buyer','seller') then raise exception 'INVALID_DEPOSIT_ROLE'; end if;
  if p_role='seller' and v_a.seller_user_id<>v_user and not public.mzad_is_admin() then raise exception 'ACCESS_DENIED'; end if;
  if p_role='buyer' and v_a.seller_user_id=v_user then raise exception 'SELLER_CANNOT_DEPOSIT'; end if;
  if p_role='buyer' and v_a.status<>'live' then raise exception 'AUCTION_NOT_LIVE'; end if;
  if p_role='seller' and v_a.status not in ('draft','pending_review') then raise exception 'SELLER_DEPOSIT_WINDOW_CLOSED'; end if;
  if p_role='seller' and not exists (
    select 1 from public.mzad_devices dv
    where dv.id=v_a.device_id and dv.owner_user_id=v_a.seller_user_id
  ) then raise exception 'DEVICE_OWNER_MISMATCH'; end if;
  if p_role='seller' then
    select coalesce((value_json #>> '{}')::bigint,5000) into v_amount from public.mzad_settings where key='auction_seller_deposit_iqd';
  else
    select coalesce((value_json #>> '{}')::bigint,5000) into v_amount from public.mzad_settings where key='auction_buyer_deposit_iqd';
  end if;
  v_amount:=coalesce(v_amount,5000);
  select id into v_dep from public.mzad_deposits
   where auction_id=p_auction_id and user_id=v_user and payer_role=p_role
     and status not in ('rejected','cancelled','refunded','forfeited')
   order by created_at desc limit 1;
  if v_dep is not null then return v_dep; end if;
  insert into public.mzad_deposits(deposit_number,user_id,operation_type,auction_id,payer_role,amount_iqd,status,eligible_to_bid)
  values(public.mzad_generate_number('DEP'),v_user,'auction',p_auction_id,p_role,v_amount,'pending',false)
  returning id into v_dep;
  insert into public.mzad_audit_logs(actor_user_id,action,entity_type,entity_id,after_json)
  values(v_user,'deposit_created','deposit',v_dep::text,jsonb_build_object('auction_id',p_auction_id,'payer_role',p_role,'amount_iqd',v_amount));
  return v_dep;
end $$;

-- Direct-sale buyer deposit. Seller deposits are never required for direct sales.
create or replace function public.mzad_create_direct_sale_deposit(p_direct_sale_id uuid)
returns uuid language plpgsql security definer set search_path = public
as $function$
declare
  v_user uuid := auth.uid();
  v_sale public.mzad_direct_sales%rowtype;
  v_deposit uuid;
  v_amount bigint;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_sale from public.mzad_direct_sales where id = p_direct_sale_id for update;
  if not found then raise exception 'DIRECT_SALE_NOT_FOUND'; end if;
  if v_sale.seller_user_id = v_user then raise exception 'SELLER_CANNOT_BUY_OWN_DEVICE'; end if;
  if v_sale.status not in ('active','reserved') then raise exception 'DIRECT_SALE_NOT_AVAILABLE'; end if;
  if v_sale.status = 'reserved' and v_sale.buyer_user_id is distinct from v_user then raise exception 'DIRECT_SALE_RESERVED'; end if;
  select id into v_deposit from public.mzad_deposits
   where direct_sale_id = v_sale.id and user_id = v_user and operation_type = 'direct_sale'
     and payer_role = 'buyer' and status not in ('rejected','cancelled','refunded','forfeited')
   order by created_at desc limit 1;
  if v_deposit is not null then return v_deposit; end if;
  select (value_json #>> '{}')::bigint into v_amount
    from public.mzad_settings where key = 'direct_buyer_deposit_iqd';
  v_amount := coalesce(v_amount,5000);
  if v_amount <> 5000 then raise exception 'INVALID_DIRECT_DEPOSIT_SETTING'; end if;
  if v_sale.status = 'active' then
    update public.mzad_direct_sales set status='reserved', buyer_user_id=v_user, reserved_at=now(), updated_at=now() where id=v_sale.id;
  end if;
  insert into public.mzad_deposits(deposit_number,user_id,operation_type,direct_sale_id,payer_role,amount_iqd,status,eligible_to_bid)
    values(public.mzad_generate_number('DEP'),v_user,'direct_sale',v_sale.id,'buyer',v_amount,'pending',false)
    returning id into v_deposit;
  insert into public.mzad_audit_logs(actor_user_id,action,entity_type,entity_id,after_json)
    values(v_user,'direct_sale_deposit_created','deposit',v_deposit::text,jsonb_build_object('direct_sale_id',v_sale.id,'amount_iqd',v_amount));
  return v_deposit;
end $function$;

create or replace function public.mzad_create_deposit_payment_request(p_deposit_id uuid,p_payment_method_id uuid)
returns uuid language plpgsql security definer set search_path = public
as $$
declare v_user uuid:=auth.uid(); d public.mzad_deposits%rowtype; m public.mzad_payment_methods%rowtype; v_id uuid;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into d from public.mzad_deposits where id=p_deposit_id for update;
 if not found or (d.user_id<>v_user and not public.mzad_is_admin()) then raise exception 'DEPOSIT_NOT_FOUND'; end if;
 if d.status in ('approved','refunded','forfeited','cancelled') then raise exception 'DEPOSIT_NOT_PAYABLE'; end if;
 select * into m from public.mzad_payment_methods where id=p_payment_method_id and is_enabled=true;
 if not found then raise exception 'PAYMENT_METHOD_NOT_FOUND'; end if;
 select id into v_id from public.mzad_payment_requests
  where deposit_id=d.id and user_id=v_user and status in ('pending','proof_submitted')
  order by created_at desc limit 1;
 if v_id is not null then
   update public.mzad_deposits set payment_method_id=p_payment_method_id where id=d.id;
   return v_id;
 end if;
 insert into public.mzad_payment_requests(invoice_number,user_id,deposit_id,amount_iqd,status,expires_at)
 values(public.mzad_generate_number('INV'),v_user,d.id,d.amount_iqd,'pending',now()+interval '48 hours')
 returning id into v_id;
 update public.mzad_deposits set payment_method_id=p_payment_method_id where id=d.id;
 return v_id;
end $$;

create or replace function public.mzad_submit_deposit_proof(
 p_request_id uuid,p_reference_number text,p_proof_storage_path text,p_paid_amount_iqd bigint,p_paid_at timestamptz default now()
) returns uuid language plpgsql security definer set search_path = public
as $$
declare v_user uuid:=auth.uid(); q public.mzad_payment_requests%rowtype; d public.mzad_deposits%rowtype; v_id uuid; v_prefix text;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into q from public.mzad_payment_requests where id=p_request_id for update;
 if not found or (q.user_id<>v_user and not public.mzad_is_admin()) then raise exception 'PAYMENT_REQUEST_NOT_FOUND'; end if;
 select * into d from public.mzad_deposits where id=q.deposit_id for update;
 if not found or d.user_id<>v_user then raise exception 'DEPOSIT_NOT_FOUND'; end if;
 if q.status not in ('pending','rejected') or d.status not in ('pending','rejected') then raise exception 'DEPOSIT_NOT_PAYABLE'; end if;
 if q.expires_at is not null and q.expires_at<=now() then raise exception 'PAYMENT_REQUEST_EXPIRED'; end if;
 if p_proof_storage_path is null or btrim(p_proof_storage_path)='' then raise exception 'PROOF_REQUIRED'; end if;
 if position(v_user::text in p_proof_storage_path)<>1 then raise exception 'INVALID_PROOF_PATH'; end if;
 if q.status='proof_submitted' or d.status in ('proof_submitted','under_review') then raise exception 'PROOF_ALREADY_PENDING'; end if;
 if p_paid_amount_iqd is null or p_paid_amount_iqd<>d.amount_iqd then raise exception 'AMOUNT_MISMATCH'; end if;
 if nullif(trim(coalesce(p_proof_storage_path,'')),'') is null then raise exception 'PROOF_REQUIRED'; end if;
 insert into public.mzad_payment_proofs(payment_request_id,user_id,proof_storage_path,reference_number,paid_amount_iqd,paid_at,status)
 values(q.id,v_user,p_proof_storage_path,nullif(trim(p_reference_number),''),p_paid_amount_iqd,coalesce(p_paid_at,now()),'pending')
 returning id into v_id;
 update public.mzad_payment_requests set status='proof_submitted' where id=q.id;
 update public.mzad_deposits set status='proof_submitted',paid_at=coalesce(p_paid_at,now()) where id=d.id;
 return v_id;
end $$;

create or replace function public.mzad_approve_deposit(p_deposit_id uuid,p_approve boolean,p_note text default null)
returns boolean language plpgsql security definer set search_path = public
as $$
declare d public.mzad_deposits%rowtype; q public.mzad_payment_requests%rowtype; p public.mzad_payment_proofs%rowtype; v_user uuid:=auth.uid();
begin
 if v_user is null or not public.mzad_is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
 select * into d from public.mzad_deposits where id=p_deposit_id for update;
 if not found then raise exception 'DEPOSIT_NOT_FOUND'; end if;
 if d.status not in ('proof_submitted','under_review','pending') then raise exception 'INVALID_DEPOSIT_STATE'; end if;
 if not p_approve then
   update public.mzad_payment_proofs
     set status='rejected',reviewer_user_id=v_user,reviewer_note=coalesce(p_note,''),reviewed_at=now()
     where payment_request_id in (select id from public.mzad_payment_requests where deposit_id=d.id)
       and status='pending';
   update public.mzad_payment_requests set status='rejected'
     where deposit_id=d.id and status in ('pending','proof_submitted');
   update public.mzad_deposits set status='rejected',eligible_to_bid=false where id=d.id;
   if d.operation_type='auction' and d.payer_role='buyer' then
     perform public.mzad_refresh_bid_eligibility(d.auction_id,d.user_id);
   end if;
   if d.operation_type='direct_sale' and d.payer_role='buyer' then
     update public.mzad_direct_sales set status='active',buyer_user_id=null,reserved_at=null,updated_at=now()
       where id=d.direct_sale_id and status='reserved' and buyer_user_id=d.user_id;
   end if;
   insert into public.mzad_audit_logs(actor_user_id,action,entity_type,entity_id,before_json,after_json)
     values(v_user,'deposit_rejected','deposit',d.id::text,jsonb_build_object('status',d.status),
       jsonb_build_object('status','rejected','note',p_note));
   return true;
 end if;
 select * into q from public.mzad_payment_requests where deposit_id=d.id order by created_at desc limit 1 for update;
 if not found then raise exception 'PAYMENT_REQUEST_NOT_FOUND'; end if;
 select * into p from public.mzad_payment_proofs where payment_request_id=q.id order by created_at desc limit 1 for update;
 if not found then raise exception 'PAYMENT_PROOF_NOT_FOUND'; end if;
 if p.status<>'pending' then raise exception 'PROOF_ALREADY_REVIEWED'; end if;
 if p_approve and (q.status<>'proof_submitted' or d.status not in ('proof_submitted','under_review')) then
   raise exception 'PROOF_NOT_READY_FOR_APPROVAL';
 end if;
 if p_approve and coalesce(p.paid_amount_iqd,0)<>d.amount_iqd then
   raise exception 'AMOUNT_MISMATCH';
 end if;
 update public.mzad_payment_proofs set status=case when p_approve then 'approved' else 'rejected' end,
   reviewer_user_id=v_user,reviewer_note=coalesce(p_note,''),reviewed_at=now() where id=p.id;
 update public.mzad_payment_requests set status=case when p_approve then 'approved' else 'rejected' end where id=q.id;
 update public.mzad_deposits set status=case when p_approve then 'approved' else 'rejected' end,
   eligible_to_bid=(p_approve and d.operation_type='auction' and d.payer_role='buyer') where id=d.id;
 if d.operation_type='auction' and d.payer_role='buyer' then
   perform public.mzad_refresh_bid_eligibility(d.auction_id,d.user_id);
 end if;
 if p_approve and d.operation_type='auction' and d.payer_role='seller' then
   update public.mzad_auctions a set status='live',starts_at=now(),
     ends_at=now()+make_interval(secs=>coalesce((select (value_json #>> '{}')::integer from public.mzad_settings where key='auction_duration_seconds'),3600)),
     original_ends_at=now()+make_interval(secs=>coalesce((select (value_json #>> '{}')::integer from public.mzad_settings where key='auction_duration_seconds'),3600))
   where a.id=d.auction_id and a.seller_user_id=d.user_id
     and a.status in ('draft','pending_review')
     and exists(select 1 from public.mzad_devices dv where dv.id=a.device_id
       and dv.owner_user_id=d.user_id and dv.verification_status='approved');
   if not found then raise exception 'DEVICE_NOT_VERIFIED_OR_AUCTION_STATE_INVALID'; end if;
 end if;
 if p_approve and d.operation_type='direct_sale' and d.payer_role='buyer' then
   insert into public.mzad_transactions(transaction_number,operation_type,direct_sale_id,device_id,seller_user_id,buyer_user_id,final_price_iqd,status)
   select public.mzad_generate_number('TRX'),'direct_sale',s.id,s.device_id,s.seller_user_id,d.user_id,s.asking_price_iqd,'open'
   from public.mzad_direct_sales s
   where s.id=d.direct_sale_id and s.status='reserved' and s.buyer_user_id=d.user_id
     and s.seller_user_id<>d.user_id
     and not exists(select 1 from public.mzad_transactions t where t.direct_sale_id=s.id and t.status not in ('cancelled','disputed'));
   if not found then raise exception 'DIRECT_SALE_TRANSACTION_NOT_CREATED'; end if;
   insert into public.mzad_transaction_fees(transaction_id,payer_role,amount_iqd,status)
   select t.id,roles.payer_role,3000,'pending'
   from public.mzad_transactions t
   cross join (values('buyer'::text),('seller'::text)) as roles(payer_role)
   where t.direct_sale_id=d.direct_sale_id and t.buyer_user_id=d.user_id
     and t.status not in ('cancelled','disputed')
   on conflict(transaction_id,payer_role) do nothing;
   update public.mzad_direct_sales set status='pending_handover',updated_at=now()
     where id=d.direct_sale_id and status='reserved' and buyer_user_id=d.user_id;
 end if;
 if not p_approve and d.operation_type='direct_sale' and d.payer_role='buyer' then
   update public.mzad_direct_sales
     set status='active',buyer_user_id=null,reserved_at=null,updated_at=now()
     where id=d.direct_sale_id and status='reserved' and buyer_user_id=d.user_id;
 end if;
 insert into public.mzad_audit_logs(actor_user_id,action,entity_type,entity_id,before_json,after_json)
 values(v_user,case when p_approve then 'deposit_approved' else 'deposit_rejected' end,'deposit',d.id::text,
   jsonb_build_object('status',d.status),jsonb_build_object('status',case when p_approve then 'approved' else 'rejected' end,'note',p_note));
 return true;
end $$;

create or replace function public.mzad_request_deposit_refund(p_deposit_id uuid,p_note text default null)
returns boolean language plpgsql security definer set search_path = public
as $$
declare
 d public.mzad_deposits%rowtype;
 v_user uuid:=auth.uid();
 v_target_status text;
begin
 if v_user is null or not public.mzad_is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
 select * into d from public.mzad_deposits where id=p_deposit_id for update;
 if not found then raise exception 'DEPOSIT_NOT_FOUND'; end if;
 if d.status='refund_pending' then return true; end if;
 if d.status<>'approved' then raise exception 'DEPOSIT_NOT_REFUNDABLE'; end if;
 if d.operation_type='auction' then
   select status into v_target_status from public.mzad_auctions where id=d.auction_id for update;
   if v_target_status is null or v_target_status not in ('ended','cancelled','archived') then
     raise exception 'AUCTION_NOT_FINISHED';
   end if;
   if d.payer_role='buyer' and v_target_status='ended' and exists(
     select 1 from public.mzad_auctions a
     where a.id=d.auction_id and a.winner_user_id=d.user_id
   ) and not exists(
     select 1 from public.mzad_transactions t
     where t.auction_id=d.auction_id and t.buyer_user_id=d.user_id and t.status='completed'
   ) then
     raise exception 'WINNER_DEPOSIT_HELD_UNTIL_SETTLEMENT';
   end if;
 elsif d.operation_type='direct_sale' then
   select status into v_target_status from public.mzad_direct_sales where id=d.direct_sale_id for update;
   if v_target_status is null or v_target_status not in ('completed','cancelled','expired') then
     raise exception 'DIRECT_SALE_NOT_FINISHED';
   end if;
 else
   raise exception 'INVALID_DEPOSIT_OPERATION';
 end if;
 update public.mzad_deposits set status='refund_pending',refund_requested_at=now(),
   refund_reason=coalesce(nullif(btrim(p_note),''),'تمت أهلية التأمين للاسترداد'),updated_at=now()
 where id=d.id and status='approved';
 if not found then raise exception 'REFUND_STATE_CHANGED'; end if;
 insert into public.mzad_audit_logs(actor_user_id,action,entity_type,entity_id,before_json,after_json)
 values(v_user,'deposit_refund_requested','deposit',d.id::text,
   jsonb_build_object('status',d.status),
   jsonb_build_object('status','refund_pending','note',p_note,'target_status',v_target_status));
 return true;
end $$;

create or replace function public.mzad_mark_deposit_refunded(p_deposit_id uuid,p_note text default null)
returns boolean language plpgsql security definer set search_path = public
as $$
declare
 d public.mzad_deposits%rowtype;
 v_user uuid:=auth.uid();
 v_target_status text;
begin
 if v_user is null or not public.mzad_is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
 select * into d from public.mzad_deposits where id=p_deposit_id for update;
 if not found then raise exception 'DEPOSIT_NOT_FOUND'; end if;
 if d.status='refunded' then raise exception 'ALREADY_REFUNDED'; end if;
 if d.status<>'refund_pending' then raise exception 'REFUND_REVIEW_REQUIRED'; end if;
 if d.operation_type='auction' then
   select status into v_target_status from public.mzad_auctions where id=d.auction_id for update;
   if v_target_status is null then raise exception 'AUCTION_NOT_FOUND'; end if;
   if v_target_status not in ('ended','cancelled','archived') then raise exception 'AUCTION_NOT_FINISHED'; end if;
 elsif d.operation_type='direct_sale' then
   select status into v_target_status from public.mzad_direct_sales where id=d.direct_sale_id for update;
   if v_target_status is null then raise exception 'DIRECT_SALE_NOT_FOUND'; end if;
   if v_target_status not in ('completed','cancelled','expired') then raise exception 'DIRECT_SALE_NOT_FINISHED'; end if;
 else
   raise exception 'INVALID_DEPOSIT_OPERATION';
 end if;
 update public.mzad_deposits set status='refunded',refunded_at=now(),
   refund_reason=coalesce(nullif(btrim(p_note),''),'تم التحقق من إعادة المبلغ فعلياً'),updated_at=now()
 where id=d.id and status='refund_pending';
 if not found then raise exception 'REFUND_STATE_CHANGED'; end if;
 insert into public.mzad_audit_logs(actor_user_id,action,entity_type,entity_id,before_json,after_json)
 values(v_user,'deposit_refunded','deposit',d.id::text,
   jsonb_build_object('status',d.status,'operation_type',d.operation_type,'target_status',v_target_status),
   jsonb_build_object('status','refunded','note',p_note,'confirmed_by_admin',v_user));
 return true;
end $$;

create or replace function public.mzad_cancel_auction(p_auction_id uuid,p_reason text default null)
returns boolean language plpgsql security definer set search_path = public
as $$
declare
 a public.mzad_auctions%rowtype;
 v_user uuid:=auth.uid();
begin
 if v_user is null or not public.mzad_is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
 select * into a from public.mzad_auctions where id=p_auction_id for update;
 if not found then raise exception 'AUCTION_NOT_FOUND'; end if;
 if a.status not in ('draft','pending_review','scheduled','live') then raise exception 'AUCTION_NOT_CANCELLABLE'; end if;
 update public.mzad_auctions set status='cancelled',updated_at=now() where id=a.id;
 insert into public.mzad_auction_results(auction_id,winner_user_id,final_price_iqd,result_status)
 values(a.id,null,null,'cancelled')
 on conflict(auction_id) do update set winner_user_id=null,final_price_iqd=null,result_status='cancelled',determined_at=now();
 update public.mzad_devices set locked_for_auction=false,updated_at=now() where id=a.device_id;
 update public.mzad_deposits set status='refund_pending',refund_requested_at=now(),
   refund_reason=coalesce(nullif(btrim(p_reason),''),'تم إلغاء المزاد'),updated_at=now()
 where auction_id=a.id and status='approved';
 insert into public.mzad_auction_events(auction_id,event_type,actor_user_id,payload_json)
 values(a.id,'admin_cancelled',v_user,jsonb_build_object('reason',p_reason,'previous_status',a.status));
 insert into public.mzad_audit_logs(actor_user_id,action,entity_type,entity_id,before_json,after_json)
 values(v_user,'auction_cancelled','auction',a.id::text,jsonb_build_object('status',a.status),
   jsonb_build_object('status','cancelled','reason',p_reason));
 return true;
end $$;

create or replace function public.mzad_finish_auction(p_auction_id uuid)
returns boolean language plpgsql security definer set search_path = public
as $$
declare
 a public.mzad_auctions%rowtype;
 b public.mzad_auction_bids%rowtype;
 v_user uuid:=auth.uid();
 v_result text;
begin
 if v_user is null or not public.mzad_is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
 select * into a from public.mzad_auctions where id=p_auction_id for update;
 if not found then raise exception 'AUCTION_NOT_FOUND'; end if;
 if a.status<>'live' then raise exception 'AUCTION_NOT_LIVE'; end if;
 select * into b from public.mzad_auction_bids
  where auction_id=a.id and accepted=true
  order by amount_iqd desc,placed_at asc limit 1;
 if found then v_result:='sold'; else v_result:='no_winner'; end if;
 update public.mzad_auctions set status='ended',ends_at=least(coalesce(ends_at,now()),now()),
   winner_user_id=case when v_result='sold' then b.bidder_user_id else null end,
   final_price_iqd=case when v_result='sold' then b.amount_iqd else null end,
   updated_at=now() where id=a.id;
 insert into public.mzad_auction_results(auction_id,winner_user_id,final_price_iqd,result_status)
 values(a.id,case when v_result='sold' then b.bidder_user_id else null end,
   case when v_result='sold' then b.amount_iqd else null end,v_result)
 on conflict(auction_id) do update set winner_user_id=excluded.winner_user_id,
   final_price_iqd=excluded.final_price_iqd,result_status=excluded.result_status,determined_at=now();
 insert into public.mzad_auction_events(auction_id,event_type,actor_user_id,payload_json)
 values(a.id,'admin_finished',v_user,jsonb_build_object('result',v_result,'winner_user_id',case when v_result='sold' then b.bidder_user_id else null end,
   'final_price_iqd',case when v_result='sold' then b.amount_iqd else null end));
 if v_result='sold' and b.bidder_user_id<>a.seller_user_id then
   insert into public.mzad_transactions(transaction_number,operation_type,auction_id,device_id,seller_user_id,buyer_user_id,final_price_iqd,status)
   select public.mzad_generate_number('TRX'),'auction',a.id,a.device_id,a.seller_user_id,b.bidder_user_id,b.amount_iqd,'open'
   where not exists(select 1 from public.mzad_transactions t where t.auction_id=a.id and t.status not in ('cancelled','disputed'));
   if not found then raise exception 'AUCTION_TRANSACTION_NOT_CREATED'; end if;
   insert into public.mzad_transaction_fees(transaction_id,payer_role,amount_iqd,status)
   select t.id,roles.payer_role,3000,'pending'
   from public.mzad_transactions t
   cross join (values('buyer'::text),('seller'::text)) as roles(payer_role)
   where t.auction_id=a.id and t.status not in ('cancelled','disputed')
   on conflict(transaction_id,payer_role) do nothing;
 end if;
 insert into public.mzad_audit_logs(actor_user_id,action,entity_type,entity_id,before_json,after_json)
 values(v_user,'auction_finished','auction',a.id::text,jsonb_build_object('status',a.status),
   jsonb_build_object('status','ended','result',v_result));
 return true;
end $$;

create or replace function public.mzad_admin_mark_transaction_fee_paid(
 p_transaction_id uuid,p_payer_role text,p_payment_reference text default null
) returns boolean
language plpgsql security definer set search_path = public
as $
declare
 v_user uuid:=auth.uid();
 f public.mzad_transaction_fees%rowtype;
begin
 if v_user is null or not public.mzad_is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
 if p_payer_role not in ('buyer','seller') then raise exception 'INVALID_PAYER_ROLE'; end if;
 select * into f from public.mzad_transaction_fees
  where transaction_id=p_transaction_id and payer_role=p_payer_role for update;
 if not found then raise exception 'TRANSACTION_FEE_NOT_FOUND'; end if;
 if f.status='paid' then raise exception 'FEE_ALREADY_PAID'; end if;
 if f.status<>'pending' then raise exception 'FEE_NOT_PAYABLE'; end if;
 update public.mzad_transaction_fees
  set status='paid',paid_at=now(),payment_reference=nullif(btrim(p_payment_reference),'')
  where id=f.id and status='pending';
 if not found then raise exception 'FEE_STATE_CHANGED'; end if;
 insert into public.mzad_audit_logs(actor_user_id,action,entity_type,entity_id,before_json,after_json)
 values(v_user,'transaction_fee_marked_paid','transaction_fee',f.id::text,
  jsonb_build_object('status',f.status,'payer_role',f.payer_role,'amount_iqd',f.amount_iqd),
  jsonb_build_object('status','paid','payment_reference',nullif(btrim(p_payment_reference),''),'confirmed_by_admin',v_user));
 return true;
end $;

create or replace function public.mzad_admin_update_setting(p_key text,p_value jsonb,p_description_ar text default null)
returns boolean language plpgsql security definer set search_path = public
as $$
begin
 if auth.uid() is null or not public.mzad_is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
 if p_key is null or length(trim(p_key))=0 then raise exception 'SETTING_KEY_REQUIRED'; end if;
 insert into public.mzad_settings(key,value_json,description_ar,updated_by,updated_at)
 values(trim(p_key),p_value,p_description_ar,auth.uid(),now())
 on conflict(key) do update set value_json=excluded.value_json,
  description_ar=coalesce(excluded.description_ar,public.mzad_settings.description_ar),
  updated_by=auth.uid(),updated_at=now();
 insert into public.mzad_audit_logs(actor_user_id,action,entity_type,entity_id,after_json)
 values(auth.uid(),'setting_updated','setting',p_key,jsonb_build_object('value',p_value));
 return true;
end $$;

revoke all on function public.mzad_get_enabled_payment_methods() from public, anon;
grant execute on function public.mzad_get_enabled_payment_methods() to authenticated;
revoke all on function public.mzad_create_auction_deposit(uuid,text) from public, anon;
grant execute on function public.mzad_create_auction_deposit(uuid,text) to authenticated;
revoke all on function public.mzad_create_direct_sale_deposit(uuid) from public, anon;
grant execute on function public.mzad_create_direct_sale_deposit(uuid) to authenticated;
revoke all on function public.mzad_create_deposit_payment_request(uuid,uuid) from public, anon;
grant execute on function public.mzad_create_deposit_payment_request(uuid,uuid) to authenticated;
revoke all on function public.mzad_submit_deposit_proof(uuid,text,text,bigint,timestamptz) from public, anon;
grant execute on function public.mzad_submit_deposit_proof(uuid,text,text,bigint,timestamptz) to authenticated;
revoke all on function public.mzad_approve_deposit(uuid,boolean,text) from public, anon;
grant execute on function public.mzad_approve_deposit(uuid,boolean,text) to authenticated;
revoke all on function public.mzad_request_deposit_refund(uuid,text) from public, anon;
grant execute on function public.mzad_request_deposit_refund(uuid,text) to authenticated;
revoke all on function public.mzad_mark_deposit_refunded(uuid,text) from public, anon;
grant execute on function public.mzad_mark_deposit_refunded(uuid,text) to authenticated;
revoke all on function public.mzad_cancel_auction(uuid,text) from public, anon;
grant execute on function public.mzad_cancel_auction(uuid,text) to authenticated;
revoke all on function public.mzad_finish_auction(uuid) from public, anon;
grant execute on function public.mzad_finish_auction(uuid) to authenticated;
revoke all on function public.mzad_admin_mark_transaction_fee_paid(uuid,text,text) from public, anon;
grant execute on function public.mzad_admin_mark_transaction_fee_paid(uuid,text,text) to authenticated;
revoke all on function public.mzad_admin_update_setting(text,jsonb,text) from public, anon;
grant execute on function public.mzad_admin_update_setting(text,jsonb,text) to authenticated;

commit;
