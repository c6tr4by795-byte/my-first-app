-- MZAD PHONE: read-only schema diagnostic
-- Run manually in Supabase SQL Editor against a TEST project first.
-- This script performs SELECTs only. It does not modify schema or data.
-- Use the results to confirm the legacy-to-canonical device mapping before changing UI queries.

-- 1) Relevant table presence and relation kind.
select n.nspname as schema_name, c.relname as table_name, c.relkind
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in (
    'devices',
    'mzad_devices',
    'mzad_auctions',
    'mzad_direct_sales',
    'mzad_deposits',
    'mzad_transactions'
  )
order by c.relname;

-- 2) Actual columns (do not assume the foundation SQL matches deployed Supabase).
select table_name, ordinal_position, column_name, data_type, udt_name, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name in (
    'devices',
    'mzad_devices',
    'mzad_auctions',
    'mzad_direct_sales',
    'mzad_deposits',
    'mzad_transactions'
  )
order by table_name, ordinal_position;

-- 3) Foreign keys among the legacy and canonical device / listing tables.
select
  con.conname as constraint_name,
  src.relname as source_table,
  src_col.attname as source_column,
  dst.relname as target_table,
  dst_col.attname as target_column,
  pg_get_constraintdef(con.oid) as definition
from pg_constraint con
join pg_class src on src.oid = con.conrelid
join pg_namespace src_ns on src_ns.oid = src.relnamespace
join pg_class dst on dst.oid = con.confrelid
join pg_namespace dst_ns on dst_ns.oid = dst.relnamespace
join lateral unnest(con.conkey) with ordinality as sk(attnum, ord) on true
join lateral unnest(con.confkey) with ordinality as dk(attnum, ord) on dk.ord = sk.ord
join pg_attribute src_col on src_col.attrelid = src.oid and src_col.attnum = sk.attnum
join pg_attribute dst_col on dst_col.attrelid = dst.oid and dst_col.attnum = dk.attnum
where con.contype = 'f'
  and src_ns.nspname = 'public'
  and dst_ns.nspname = 'public'
  and src.relname in ('devices','mzad_devices','mzad_auctions','mzad_direct_sales')
order by source_table, constraint_name, sk.ord;

-- 4) Relevant routines and their signatures. This confirms what is deployed,
-- not whether their internal bodies are correct.
select n.nspname as schema_name, p.proname as function_name,
       pg_get_function_identity_arguments(p.oid) as arguments,
       pg_get_function_result(p.oid) as result_type,
       p.prosecdef as security_definer
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'mzad_create_device',
    'mzad_create_auction_draft',
    'mzad_create_direct_sale_deposit',
    'mzad_create_auction_deposit',
    'mzad_create_deposit_payment_request',
    'mzad_submit_deposit_proof',
    'mzad_approve_deposit',
    'mzad_cancel_auction',
    'mzad_confirm_handover'
  )
order by p.proname, arguments;

-- 5) Storage bucket and object policies used by the proof-upload UI.
-- These queries are read-only. If permission errors occur, run as the project owner.
select id, name, public, file_size_limit, allowed_mime_types
from storage.buckets
where id = 'mzad-payment-proofs' or name = 'mzad-payment-proofs';

select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'storage'
  and tablename = 'objects'
  and (
    coalesce(qual, '') ilike '%mzad-payment-proofs%'
    or coalesce(with_check, '') ilike '%mzad-payment-proofs%'
    or policyname ilike '%mzad%proof%'
  )
order by policyname;

-- 6) Verify whether the browser-facing payment/deposit tables have RLS enabled.
-- Policies must be reviewed separately; RLS being enabled alone does not prove safe access.
select n.nspname as schema_name, c.relname as table_name,
       c.relrowsecurity as rls_enabled, c.relforcerowsecurity as rls_forced
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in (
    'mzad_deposits',
    'mzad_payment_requests',
    'mzad_payment_proofs',
    'mzad_payment_methods',
    'mzad_direct_sales',
    'mzad_auctions'
  )
order by c.relname;

select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in (
    'mzad_deposits',
    'mzad_payment_requests',
    'mzad_payment_proofs',
    'mzad_payment_methods',
    'mzad_direct_sales',
    'mzad_auctions'
  )
order by tablename, policyname;

-- 7) Payment-method schema and admin upsert routine diagnostics.
-- The admin page calls mzad_admin_upsert_payment_method; do not assume it exists
-- or assume the table has legacy columns such as code/account_identifier.
select table_name, ordinal_position, column_name, data_type, udt_name, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name = 'mzad_payment_methods'
order by ordinal_position;

select n.nspname as schema_name, p.proname as function_name,
       pg_get_function_identity_arguments(p.oid) as arguments,
       pg_get_function_result(p.oid) as result_type,
       p.prosecdef as security_definer
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'mzad_admin_upsert_payment_method',
    'mzad_get_enabled_payment_methods',
    'mzad_is_admin'
  )
order by p.proname, arguments;

-- 8) Constraints/indexes on payment methods, to identify a safe upsert key.
select c.conname as constraint_name, c.contype as constraint_type,
       pg_get_constraintdef(c.oid) as definition
from pg_constraint c
join pg_class t on t.oid = c.conrelid
join pg_namespace n on n.oid = t.relnamespace
where n.nspname = 'public' and t.relname = 'mzad_payment_methods'
order by c.contype, c.conname;

select indexname, indexdef
from pg_indexes
where schemaname = 'public' and tablename = 'mzad_payment_methods'
order by indexname;
