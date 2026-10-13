-- MZAD PHONE: integrated deposit + payment review backend
-- Apply only after backing up production and confirming mzad-foundation-v2.sql is the active schema.
begin;

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
declare v_user uuid:=auth.uid(); q public.mzad_payment_requests%rowtype; d public.mzad_deposits%rowtype; v_id uuid;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into q from public.mzad_payment_requests where id=p_request_id for update;
 if not found or (q.user_id<>v_user and not public.mzad_is_admin()) then raise exception 'PAYMENT_REQUEST_NOT_FOUND'; end if;
 select * into d from public.mzad_deposits where id=q.deposit_id for update;
 if not found or d.user_id<>v_user then raise exception 'DEPOSIT_NOT_FOUND'; end if;
 if q.status='proof_submitted' or d.status in ('proof_submitted','under_review') then raise exception 'PROOF_ALREADY_PENDING'; end if;
 if p_paid_amount_iqd is null or p_paid_amount_iqd<>d.amount_iqd then raise exception 'AMOUNT_MISMATCH'; end if;
 if nullif(trim(coalesce(p_proof_storage_path,'')),'') is null then raise exception 'PROOF_REQUIRED'; end if;
 insert into public.mzad_payment_proofs(payment_request_id,user_id,proof_storage_path,reference_number,paid_amount_iqd,paid_at,status)
 values(q.id,v_user,p_proof_storage_path,nullif(trim(p_reference_number),''),p_paid_amount_iqd,coalesce(p_paid_at,now()),'pending')
 returning id into v_id;
 update public.mzad_payment_requests set status='proof_submitted' where id=q.id;
 update public.mzad_deposits set status='proof_submitted',paid_at=coalesce(p_paid_at,now()) where id=d.id;
 insert into public.mzad_notifications(user_id,title,body,created_at)
 select au.user_id,'إثبات تأمين جديد','يوجد إثبات دفع جديد يحتاج مراجعة الإدارة.',now()
 from public.mzad_admin_users au where au.is_active=true
 on conflict do nothing;
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
 select * into q from public.mzad_payment_requests where deposit_id=d.id order by created_at desc limit 1 for update;
 if not found then raise exception 'PAYMENT_REQUEST_NOT_FOUND'; end if;
 select * into p from public.mzad_payment_proofs where payment_request_id=q.id order by created_at desc limit 1 for update;
 if not found then raise exception 'PAYMENT_PROOF_NOT_FOUND'; end if;
 if p.status<>'pending' then raise exception 'PROOF_ALREADY_REVIEWED'; end if;
 update public.mzad_payment_proofs set status=case when p_approve then 'approved' else 'rejected' end,
   reviewer_user_id=v_user,reviewer_note=coalesce(p_note,''),reviewed_at=now() where id=p.id;
 update public.mzad_payment_requests set status=case when p_approve then 'approved' else 'rejected' end where id=q.id;
 update public.mzad_deposits set status=case when p_approve then 'approved' else 'rejected' end,
   eligible_to_bid=(p_approve and payer_role='buyer') where id=d.id;
 if p_approve and d.operation_type='auction' and d.payer_role='seller' then
   update public.mzad_auctions a set status='live',starts_at=now(),
     ends_at=now()+make_interval(secs=>coalesce((select (value_json #>> '{}')::integer from public.mzad_settings where key='auction_duration_seconds'),3600)),
     original_ends_at=now()+make_interval(secs=>coalesce((select (value_json #>> '{}')::integer from public.mzad_settings where key='auction_duration_seconds'),3600))
   where a.id=d.auction_id and a.status in ('draft','pending_review')
     and exists(select 1 from public.mzad_devices dv where dv.id=a.device_id and dv.verification_status='approved');
   if not found then raise exception 'DEVICE_NOT_VERIFIED_OR_AUCTION_STATE_INVALID'; end if;
 end if;
 insert into public.mzad_audit_logs(actor_user_id,action,entity_type,entity_id,before_json,after_json)
 values(v_user,case when p_approve then 'deposit_approved' else 'deposit_rejected' end,'deposit',d.id::text,
   jsonb_build_object('status',d.status),jsonb_build_object('status',case when p_approve then 'approved' else 'rejected' end,'note',p_note));
 insert into public.mzad_notifications(user_id,title,body,created_at)
 values(d.user_id,case when p_approve then 'تم اعتماد التأمين' else 'تم رفض إثبات التأمين' end,
   coalesce(nullif(p_note,''),case when p_approve then 'تمت مراجعة إثبات الدفع واعتماده.' else 'يرجى مراجعة إثبات الدفع وإعادة إرساله.' end),now());
 return true;
end $$;

create or replace function public.mzad_mark_deposit_refunded(p_deposit_id uuid,p_note text default null)
returns boolean language plpgsql security definer set search_path = public
as $$
declare d public.mzad_deposits%rowtype; v_user uuid:=auth.uid();
begin
 if v_user is null or not public.mzad_is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
 select * into d from public.mzad_deposits where id=p_deposit_id for update;
 if not found then raise exception 'DEPOSIT_NOT_FOUND'; end if;
 if d.status='refunded' then raise exception 'ALREADY_REFUNDED'; end if;
 if d.status not in ('approved','refund_pending') then raise exception 'DEPOSIT_NOT_REFUNDABLE'; end if;
 update public.mzad_deposits set status='refunded',refunded_at=now(),refund_reason=coalesce(p_note,'تم التحقق من إعادة المبلغ فعلياً') where id=d.id;
 insert into public.mzad_audit_logs(actor_user_id,action,entity_type,entity_id,before_json,after_json)
 values(v_user,'deposit_refunded','deposit',d.id::text,jsonb_build_object('status',d.status),jsonb_build_object('status','refunded','note',p_note));
 return true;
end $$;

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
revoke all on function public.mzad_create_deposit_payment_request(uuid,uuid) from public, anon;
grant execute on function public.mzad_create_deposit_payment_request(uuid,uuid) to authenticated;
revoke all on function public.mzad_submit_deposit_proof(uuid,text,text,bigint,timestamptz) from public, anon;
grant execute on function public.mzad_submit_deposit_proof(uuid,text,text,bigint,timestamptz) to authenticated;
revoke all on function public.mzad_approve_deposit(uuid,boolean,text) from public, anon;
grant execute on function public.mzad_approve_deposit(uuid,boolean,text) to authenticated;
revoke all on function public.mzad_mark_deposit_refunded(uuid,text) from public, anon;
grant execute on function public.mzad_mark_deposit_refunded(uuid,text) to authenticated;
revoke all on function public.mzad_admin_update_setting(text,jsonb,text) from public, anon;
grant execute on function public.mzad_admin_update_setting(text,jsonb,text) to authenticated;

commit;
