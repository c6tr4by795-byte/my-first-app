# MZAD PHONE — Integration audit (2026-10-13)

## Scope checked
Repository: `c6tr4by795-byte/my-first-app`, default branch `main`.
This is a source-code audit. The linked Supabase production database was not queried, so SQL functions or policies may exist there even if absent from tracked SQL.

## Confirmed integration defects
1. `device.html` still shows placeholder messages for the auction bid and direct purchase actions ("راح نربطه..."). Those user actions are not connected in this page.
2. `profile.html` still shows a placeholder for "مزاداتي".
3. Existing front-end and foundation schema disagree:
   - UI uses `mzad_payment_proofs.review_status`; foundation defines `status`.
   - UI uses proof `request_id`; foundation defines `payment_request_id`.
   - UI uses `mzad_payment_requests.request_number`; foundation defines `invoice_number`.
   - UI uses `mzad_deposits.deposit_type`; foundation defines `operation_type` + `payer_role`.
   - `sql/auction-draft-flow.sql` expects payment-method columns `code/provider/account_label/account_identifier/display_order`, while foundation defines `method_type/recipient_name/recipient_identifier/sort_order`.
   These mismatches can break admin review and user deposit pages when the foundation schema is active.
4. Admin pages call RPCs including `mzad_approve_deposit`, `mzad_mark_deposit_refunded`, `mzad_admin_update_setting`, `mzad_cancel_auction`, and `mzad_finish_auction`. The reviewed foundation file does not define all of them. A live DB may have separate migrations, so production existence must be verified in Supabase.
5. `admin/deposits.html` filters payment proofs by `review_status` and joins via `request_id`, which are inconsistent with the foundation schema.
6. The auction bid RPC in the foundation is designed to require an approved buyer deposit, but the UI and schema need a single consistent deposit/status vocabulary to make that eligibility reliable.
7. The seller deposit approval flow must not start an auction unless the device has passed verification and the auction is in an eligible state.

## Required business rules
- Auction seller deposit: 5,000 IQD, auction only.
- Auction bidder/buyer deposit: 5,000 IQD.
- Direct-sale buyer deposit: 5,000 IQD; no direct-sale seller deposit.
- Deposit is not the device price or the 3,000 IQD fee per side.
- Do not enable bidding before admin approval; refund/forfeiture must be audited and idempotent.

## Branch work
A new branch `fix/mzad-auction-deposits-admin-2026-10` was created. It contains `sql/mzad-deposit-admin-integration.sql`, an initial backend integration migration for deposit creation, payment requests, proof submission, admin approval/refusal, refund recording, settings updates, and payment-method retrieval.

## Important validation limitations
- The migration has not been run against the user's Supabase database.
- Production table columns, notification schema, storage policies, existing RPC signatures, and RLS policies have not been introspected live.
- The UI placeholder purchase/bid paths and "مزاداتي" still require dedicated page changes.
- Do not apply this migration to production until it is reviewed against the actual schema and tested in a staging project. It is not safe to claim the entire platform is fixed from source inspection alone.

## Next verification checklist
1. Inspect live tables/functions and compare them to the tracked SQL migrations.
2. Standardize the frontend to canonical column names or add tested compatibility views.
3. Connect direct purchase to a server-side transaction/reservation RPC.
4. Connect auction detail to the bid/deposit RPC and enforce seller/buyer restrictions server-side.
5. Build the "My Auctions" page from the signed-in user's auctions and status.
6. Verify storage upload/read policies and ensure only authorized admins can view payment proof images.
7. Test end-to-end with two ordinary users and one admin, including duplicate proof, wrong amount, double refund, rejected proof, unverified device, expired auction, and concurrent bids.
