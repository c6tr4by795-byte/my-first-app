# MZAD PHONE trust roadmap
Status: proposal only. Not deployed or tested.

## New ideas
1. Device passport QR with a public, privacy-safe verification summary.
2. Compare seller listing fields with the latest approved inspection report field by field.
3. Seller acknowledgement or field-specific dispute of inspection findings.
4. Reopen review if IMEI, serial, model, storage, condition, or evidence changes.
5. Mask IMEI and serial in public pages, logs, and notifications.
6. Preserve previous inspection reports and evidence as versions.
7. Separate buyer and seller condition checklists at handover.
8. Pause completion and open a dispute if either party reports a mismatch.
9. Missed-appointment workflow with evidence and rescheduling policy.
10. Server-derived settlement-readiness checklist.
11. Completion receipt with transaction ID, verification ID, report number, confirmations, fees, and timestamp.
12. Reason codes for rejection, cancellation, refund, forfeiture, and overrides.
13. Second-admin approval for irreversible actions and verification overrides.
14. Human-reviewed risk queue for duplicate identifiers, repeated proof rejection, suspicious bid patterns, and missed appointments; no automatic bans.
15. Separate permissions for inspection, deposits, refunds, and system settings.
16. Audited export of transaction history.
17. Operations dashboard for long-pending proofs, inspections, appointments, and refunds.
18. Notification delivery trace and safe resend.
19. Seller-visible inspection report with acknowledge/dispute actions.
20. Verification freshness policy and relisting history for authorized staff.

## Guardrails
- Verify deployed schema, statuses, RLS, and RPC signatures before UI wiring.
- Require a current approved inspection report before final device approval.
- Duplicate checks are not concurrency-safe uniqueness guarantees unless backed by database constraints/locking.
- Do not claim a feature is shipped until staging tests pass.
