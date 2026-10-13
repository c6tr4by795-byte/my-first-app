# MZAD PHONE — Seller trust badge specification
Status: product specification only. Do not display the badge until the data sources and eligibility query are implemented and tested.

## Badge levels
- **حساب مسجل**: account exists; this is not a trust claim.
- **هوية/هاتف متحقق**: only after the configured verification flow returns a verified result.
- **بائع موثوق**: requires minimum completed eligible transactions, no unresolved dispute affecting eligibility, and current approved device inspection where required.
- **MZAD VERIFIED device**: applies to a specific device/report, not automatically to every device sold by that account.

## Suggested initial policy (admin-configurable)
- At least 5 completed transactions as seller.
- No unresolved disputes in the eligibility window.
- At least 90% of eligible transactions completed without seller-attributed cancellation or verified misconduct.
- Latest device inspection is approved and has not been invalidated by changes to sensitive fields.
- Eligibility refreshes server-side whenever a transaction completes, a dispute is resolved, or device verification changes.

These thresholds are proposals and must be approved by the product owner before implementation. Do not compute a public score from raw accusations, unreviewed reports, or incomplete transactions.

## UI requirements
- Show a short explanation and criteria when the user taps the badge.
- Distinguish account verification from device verification.
- Show "غير متاح بعد" rather than a misleading badge when data is missing.
- Keep private dispute details, full IMEI/serial, payment proofs, and admin notes hidden from other users.
- Provide a review/appeal path if a badge is removed.

## Backend requirements
- Calculate eligibility through a server-side query/RPC; do not trust client-provided counts or flags.
- Admin overrides require a reason and audit record.
- Changes to model, storage, IMEI/serial, condition, or inspection evidence invalidate device-specific verification until reviewed.
- Verify exact deployed schema, RLS, status values, and transaction attribution before writing the final query.
- Test boundary cases: 4 vs 5 completed transactions, pending/disputed transactions, seller/buyer role reversal, cancelled transactions, stale inspections, and concurrent status changes.
