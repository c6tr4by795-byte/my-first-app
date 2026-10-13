# MZAD PHONE — Account identity and trust controls
Status: design notes for implementation; database migration for stable account codes exists on the working branch but has not been applied to Supabase.

## Account code decision
- Use one permanent, unique account reference per user, regardless of whether the account is acting as buyer or seller.
- The same account can buy and sell; role-specific codes would fragment history and make abuse controls weaker.
- The code is for support, receipts, and matching records only. It is not a password, OTP, identity verification, or authorization credential.
- Protected actions continue to rely on Supabase Auth, ownership checks, admin permissions, RLS, and server-side RPC validation.

## Next feature ideas
1. Show account code in the profile with copy action and explain it is safe to share with support.
2. Include account code on transaction receipts and support cases, but never expose email, phone, payment proof, or private device identifiers.
3. Add a verified-phone state only after a real OTP verification flow; do not label a phone verified merely because it exists in profile.
4. Add account security events: password/email change if supported by trusted auth events, session revocation, and sensitive profile changes.
5. Show account trust history from completed, non-disputed transactions and admin-reviewed outcomes; avoid public scores based on unverified accusations.
6. Separate internal risk flags from public badges. Public badges require a documented policy and human review.
7. Require step-up authentication or recent re-authentication for high-risk changes if the chosen auth provider supports it.
8. Add account recovery and support procedures that do not rely on a public account code as proof of ownership.
9. Make user-facing buyer/seller roles contextual actions on one account, not separate accounts.
10. Add rate limits and monitoring to code generation and account lookup endpoints; do not provide an endpoint that enumerates users by code.

## Acceptance checks
- Each authenticated user receives one stable code; concurrent first calls return the same code.
- Codes are unique and cannot be used to sign in or perform actions.
- Anonymous users cannot query the code table.
- Users cannot read other users' code rows directly.
- Deleting/closing an account follows the platform's documented retention policy.
- Migration and RLS are tested in staging before production.
