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


## Progress update — 2026-10-13

The following source changes have since been committed to this same draft branch:

- The device page now routes auction items to `auction-deposit.html` and direct-sale items to `direct-deposit.html`, with checks for an active matching listing and seller self-purchase/self-bidding.
- The profile's “مزاداتي” and “مشترياتي” actions now open `my-activity.html`; that page reads the signed-in user's auction listings, direct-sale listings, and buyer transactions.
- Added `transaction.html` as a read-only transaction and handover-status view. It verifies the current user is the buyer or seller before displaying the record.
- The seller auction page now reads auction result rows by `determined_at` and displays the schema's `result_status`.
- The SQL draft adds audited admin cancellation/finalization, staged refund request/confirmation, transaction creation on eligible purchase confirmation/auction finalization, and pending 3,000 IQD fee records for both buyer and seller. These are source edits only and have not been executed against the database.

## Remaining blockers before production

1. The bid submission action itself still needs a verified, connected flow and server-side eligibility/price validation.
2. The SQL draft must be checked against the *actual* deployed schema, all relevant RLS policies, and existing function signatures. A local foundation file alone does not establish production compatibility.
3. The new transaction page is read-only; appointment creation, handover confirmation, fee collection status, and completion transitions still need controlled RPCs and UI.
4. The current branch's Vercel status has been pending during this pass. No successful preview build or live end-to-end test is claimed.
5. Do not merge or apply the SQL migration to production until staging tests pass, including duplicate requests, rejected proof, wrong amount, two simultaneous buyers, self-purchase, unverified device, cancellation, and double-refund attempts.


## Progress update — transaction workflow wiring

- Added `admin/transactions.html` to list transactions for admins, show the current appointment and device, record buyer/seller 3,000 IQD fees as paid only after an explicit confirmation, and invoke the existing admin-only platform handover confirmation RPC.
- Repaired the transaction page's broken render expression and connected its appointment form to the new `mzad_schedule_handover` RPC.
- Added server-side scheduling guards: the actor must be a transaction party or admin, the handover point must be active, the time must be in the future, an active appointment must not already exist, and scheduling is blocked after any handover confirmation has begun.
- Verified by source inspection that the SQL migration has no remaining malformed `as $` / `end $;` delimiter patterns and that the transaction page's `load()` block has balanced braces. This is not a substitute for PostgreSQL execution or browser/E2E testing.
- Vercel preview checks were still pending at the last status query; no successful deployment or live Supabase test is claimed.

## Remaining work before production

1. Run the SQL migration in a staging Supabase project after comparing every referenced column/function to the deployed schema.
2. Run browser tests for the admin transaction page, appointment scheduling, cash-fee recording, and completion requirements.
3. Test direct-sale reservation concurrency and auction bidding with two separate user accounts.
4. Confirm storage bucket policies allow owners to upload only into their own proof path and restrict proof reads to authorized users/admins.
5. Review refunds and forfeiture rules against real business policy before enabling them in production.


## Implementation progress — device verification controls

- Added `sql/mzad-device-verification-controls.sql` on the working branch.
- The migration defines an admin-only RPC for explicit device verification decisions (`approved`, `rejected`, `needs_changes`, `under_review`).
- Approval requires a non-empty checklist object. Rejection/change requests require a reason. Duplicate IMEI/serial values in other relevant listings block approval and create review evidence; the RPC does not automatically ban a user.
- Each review stores a device event and an audit-log entry with the prior state, decision, reason, checklist, and duplicate flags.
- This is a backend foundation only. It has not been applied to Supabase, and the current admin UI has not yet been wired to this RPC. The checklist JSON's semantics must be defined in the admin UI before approval can be considered reliable.
- Important limitation: a duplicate check performed at review time is not a global uniqueness constraint; concurrent submissions can still race. A future pass should add a normalized-identifier strategy and appropriate uniqueness/locking only after product policy for reused/repaired devices is agreed.


## Follow-up review — 2026-10-14

### Auction draft device lock
- `sql/auction-draft-flow.sql` creates an auction row with status `draft` but does not set `mzad_devices.locked_for_auction = true` in the same transaction.
- The draft function rejects a device only when its lock flag is already true and checks existing auctions in `draft`, `scheduled`, `live`, or `ended`; it does not itself reserve the device when creating the draft.
- Risk: another listing/sale path that relies on the device lock may race with a pending auction draft. This must be checked against all device-creation and direct-sale RPCs before changing the lifecycle.
- Fix applied in commit `1cd82d0fb730bffd90be3d41cf0925f59efe5831`: reserve the device atomically when the draft is created. Source review confirms the admin cancellation path unlocks the device and the no-winner completion path unlocks it; sold devices remain locked for the transaction/handover flow. Still requires staging tests and a review of every other direct-sale/listing RPC against the lock flag.

### Verification gate follow-up
- Commit `8c4dcf8a0c3371791869e3bbc2d1488682ae21a8` calls `mzad_admin_require_inspection_report` from the privileged verification-review RPC when approving a device.
- The migration dependency order is `sql/mzad-verification-approval-gate.sql` first, then `sql/mzad-device-verification-controls.sql`.
- This remains repository-level evidence only; neither migration has been confirmed applied to Supabase, and the actual deployed schema has not been queried.

### Auction completion guard follow-up
- Commit `61fd206edb78dfe3c41fa9db0485363829a75903` changes the transaction guard to validate the existing active transaction against auction, buyer, seller, and final price after the insert attempt.
- CI/Vercel was still pending at the last status check. No live database or end-to-end test is claimed.

### Required staging checks before release
1. Create a draft; confirm device lock is set and another sale/auction path rejects the same device.
2. Cancel the draft and verify the device unlocks; test no-winner and sold auctions separately.
3. Attempt device approval without an approved inspection report; expect rejection. Add an approved report and valid checklist; expect success.
4. Finish an auction twice and under concurrent calls; verify exactly one correct active transaction and one buyer/seller fee row each.
5. Exercise seller deposit pending/rejected/approved transitions and verify the auction never goes live before approved device verification and approved seller deposit.


### Auction cancellation payment cleanup — 2026-10-14
- Commits `6ad490e8c5a31e906a7479bb42e11358051719e2` and `34f10aff769c5597aef179687b3001c2e78525d6` update `mzad_cancel_auction` so approved deposits move to `refund_pending` (not falsely marked refunded), while pending/proof-submitted/under-review deposits are cancelled, bid eligibility is cleared, their pending payment requests are cancelled, and pending proof records are rejected with an admin review note.
- The follow-up commit corrects the proof cleanup filter to select deposits before their status is changed to `cancelled`.
- This is a source-level fix. It still needs staging migration and tests covering approved, pending, proof-submitted, under-review, and already-rejected deposits; verify all related payment requests/proofs end in consistent states.


### Auction/direct-sale device exclusivity — 2026-10-14
- Commit `da951eee7b74f5a0ae5d7e24e430793242ade125` adds a guard to direct-sale deposit creation: a device locked for auction or associated with a draft/pending-review/scheduled/live auction cannot be reserved for direct sale.
- Commit `8146389408e67e67aeec281f9fecfb21813627ed` strengthens that guard by locking the device row before checking auction state, serializing the direct-sale reservation path against auction-draft creation's device-row lock.
- Commit `ecfa0cd7b36e1a62e869f2c6f477e8a7f38cb269` prevents auction-draft creation when the same device has an active, reserved, or pending-handover direct-sale listing.
- These are SQL source changes only. Verify against the actual deployed schema and exercise concurrent transactions in staging before applying to production. This review did not verify the direct-sale listing creation RPC or all possible paths that mutate listing status.
