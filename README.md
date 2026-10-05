# CoinPlan
A monthly household finance PWA inspired by Monarch’s organization. Build-free frontend; private optional Supabase backend; optional Plaid bank sync.

## Working now
Accounts and net worth; manual transactions and refunds; owner labels; category budgets carried forward by month; recurring bills anchored across months; savings goals; six-month cash-flow chart; merchant category rules; CSV mapping, preview and repeat-import deduplication; backup export/restore; explicit old CoinPlan import; offline application shell and IndexedDB persistence. Demo data lives in a separate local plan and never connects real banks.

Actual spending excludes transfers, credit-card payments, pending transactions and scheduled bills. Goal progress is a separate earmarking figure, not an additional asset. Manual account balances are snapshots and are not changed by entering transactions.

## Private cloud and bank setup
The CoinPlan database migration and bank function are deployed to the existing MealPlan Supabase project. Live transaction-scoped checks passed for owner isolation, private token denial, revision conflicts, and atomic bank commits; all synthetic fixtures were rolled back. The public frontend configuration is enabled. Household authorization and independent JWT checks are enabled. End-to-end Sandbox linking imported balances and transactions successfully; its synthetic records were removed before enabling Production. Real bank connections are enabled. Supabase Cron refreshes the bank backend twice daily using a separate credential in Vault. The app still requires Refresh bank data to retrieve server changes on each device; cloud plan synchronization remains manual. Never add service keys or Plaid secrets to the repo.

1. Apply `supabase/migrations/001_coinplan.sql` once. It creates new CoinPlan tables and touches no LiftPlan or MealPlan tables.
2. Deploy the `coinplan-bank` Edge Function with JWT verification disabled at the gateway; it independently validates every user JWT through Supabase Auth. Schedule requests use a separate secret. The function requires server-provided `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ANON_KEY`.
3. Add server secrets `PLAID_CLIENT_ID`, `PLAID_SECRET`, `PLAID_ENV=sandbox`, `COINPLAN_TOKEN_KEY` (base64 encoding of 32 random bytes), `COINPLAN_CRON_SECRET` (32 random bytes), `COINPLAN_ALLOWED_USER_IDS` (comma-separated household auth UUIDs), `COINPLAN_REDIRECT_URI` (exact deployed CoinPlan URL), and `COINPLAN_ORIGINS` (comma-separated frontend origins). Local testing may explicitly add `http://127.0.0.1:4173`. Do not deploy with an unrestricted user allowlist.
4. Add the exact OAuth redirect URI to Plaid’s permitted redirect URIs. Capital One requires OAuth. Returning from bank authorization resumes the saved Link token.
5. Use Sandbox to verify sign-in, isolation, token exchange, transaction changes/removals, reconnects, and pending-to-posted replacement. Then switch `PLAID_ENV` and `PLAID_SECRET` to production only after review and user authorization. Do not repeatedly create real connections: Trial lifetime quota is not restored by deleting them.
6. Add scheduled refresh twice daily using Supabase Cron and Vault. Use a POST to the deployed function with JSON `{"action":"scheduled"}` and `x-coinplan-cron` fetched from Vault. Never paste the secret into a checked-in SQL file. `supabase/scheduled-refresh.sql` is the deployment template. Check failures through execution results; scheduled calls do not log tokens or transactions.

Bank access tokens are AES-GCM encrypted in server-only tables. The service role cannot be used from the client. All table reads are scoped to the authenticated owner. The bank service also enforces its household UUID allowlist. Updates are staged through all pages, then committed atomically with the cursor under a five-minute per-connection lease. Pagination mutations restart from the original cursor. Non-USD records are intentionally excluded.

Reconnecting an existing bank uses Plaid update mode instead of creating a new Item. If the first exchange succeeds but storage fails, the function removes the Item; that does not recover its Trial quota. No disconnect UI is provided yet.

Private cloud saves use revision checks. A conflicting cloud revision requires an explicit choice, with a downloaded local backup first. Cloud synchronization is user-triggered in this version; background bank updates arrive on refresh. A shared confirmed sign-in is one household; owner labels are not an access boundary between people sharing it.

## Validation
`npm install --ignore-scripts` then `npm test`; `deno check supabase/functions/coinplan-bank/index.ts`; `deno test --allow-env tests/*.test.ts`.
Run a static server at the repository parent and serve under `/CoinPlan/` for GitHub Pages parity.

## Limits of this version
This is not full Monarch feature parity. No investment holding analytics, custom category editor, rollover budgets, splitting transactions, debt amortization, receipt OCR, or separate-member invitations yet. CSV exports use signed amounts; bank-native separate debit/credit columns require conversion first. Deduplication recognizes identical rows per account but cannot confidently match CSV records to bank-synced purchases, so CSV imports are limited to manual accounts. Avoid importing overlapping partial files that each contain identical purchases; import complete files and review the preview.

App shell works offline after first successful load. Google fonts are optional; system fonts work offline. Cloud sessions are kept only in session storage. Financial data remains in browser storage on sign-out for the relevant user and can be restored after signing back in; it is not encrypted at rest on the local device. Use a device passcode and a trusted browser.
