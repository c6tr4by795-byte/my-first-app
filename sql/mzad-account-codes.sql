-- MZAD PHONE: one stable public reference code per account.
-- This is an identifier, NOT a password, login credential, or authorization token.
-- Apply in staging first after verifying Supabase auth/RLS policies.

begin;

create table if not exists public.mzad_account_codes (
  user_id uuid primary key references auth.users(id) on delete cascade,
  account_code text not null unique,
  created_at timestamptz not null default now()
);

alter table public.mzad_account_codes enable row level security;

revoke all on public.mzad_account_codes from anon, authenticated;
grant select on public.mzad_account_codes to authenticated;

drop policy if exists mzad_account_codes_select_own on public.mzad_account_codes;
create policy mzad_account_codes_select_own
  on public.mzad_account_codes
  for select to authenticated
  using (user_id = auth.uid());

create or replace function public.mzad_get_my_account_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_code text;
  v_try integer := 0;
begin
  if v_user is null then
    raise exception 'AUTHENTICATION_REQUIRED';
  end if;

  select account_code into v_code
    from public.mzad_account_codes
   where user_id = v_user;

  if v_code is not null then
    return v_code;
  end if;

  loop
    v_try := v_try + 1;
    if v_try > 5 then
      raise exception 'ACCOUNT_CODE_GENERATION_FAILED';
    end if;

    v_code := 'MZ-' || upper(substr(encode(gen_random_bytes(8), 'hex'), 1, 10));

    begin
      insert into public.mzad_account_codes(user_id, account_code)
      values(v_user, v_code)
      on conflict (user_id) do nothing;

      select account_code into v_code
        from public.mzad_account_codes
       where user_id = v_user;

      if v_code is not null then
        return v_code;
      end if;
    exception when unique_violation then
      -- A rare random-code collision; generate a fresh candidate.
      v_code := null;
    end;
  end loop;
end;
$$;

revoke all on function public.mzad_get_my_account_code() from public, anon;
grant execute on function public.mzad_get_my_account_code() to authenticated;

commit;

-- Product rules:
-- * One stable code per account; it works for both seller and buyer roles.
-- * A user may sell and buy with the same account; do not create role-specific identities.
-- * The code is a public reference only. All protected actions must still check auth.uid(),
--   ownership, role/permissions, deposit status, and server-side business rules.
-- * Never use this code as a password, OTP, payment confirmation, or proof of identity.
