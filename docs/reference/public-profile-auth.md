# GitHub public-profile authentication

The current branch signs in with **no GitHub OAuth scopes**. The backend uses `/user` to verify the
immutable numeric GitHub ID and login alias. It never calls `/user/emails`, requests `user:email`,
accepts repository permissions, or stores email addresses in the new account/session tables.
GitHub is an identity provider only. Users need no Vercel or Supabase administration access.

## Authentication and storage

1. The native app generates a fresh 256-bit state and PKCE verifier, opens GitHub with `scope=` and
   an S256 challenge, and accepts only `hobbytrainer://auth/callback` with exactly one matching state
   and code. No Supabase OAuth endpoint or email-based authentication fallback is used.
2. The app sends the one-time code and verifier to `/api/auth/github/exchange` over HTTPS. The server
   exchanges them using its server-only OAuth client secret and the exact registered callback URI.
3. Both the token response scope and GitHub's effective `X-OAuth-Scopes` header must be empty.
   Previously granted email/repository scopes cause a rejection, rather than silent permission reuse.
   The resulting profile contains only the GitHub numeric ID and alias; the GitHub token is discarded.
4. PostgreSQL maps the numeric GitHub ID to an application owner UUID. Existing profiles and legacy
   GitHub Auth identities keep their original UUID, so existing server saves remain attached. Alias
   changes update display data and never select or transfer a save.
5. The server issues independent opaque application tokens. Access expires after 15 minutes, refresh
   after 30 days. Only SHA-256 digests are stored. Refresh rotates both tokens under a row lock and
   accepts the old refresh token once. Logout revokes this device's session immediately.
6. `GET/PUT /api/companion` continue to use the same normalized Supabase tables, growth validators,
   owner-derived identity, revision checks and idempotency logic. The backend calls three authentication/save
   private entry functions (plus one separate encounter entry point) as a dedicated least-privilege database role. It cannot SELECT tables or
   invoke the raw snapshot writer. Transaction-local claims reset before pooled connections are reused.

The native Keychain namespace is versioned separately from the previous Supabase JWT credentials.
Old JWTs are rejected by the new API. Pokémon progress remains server-only; no local save or fallback
has been added. Existing growth, collection, items and other Pokémon mechanics are unchanged.

## Local verification on 2026-10-15

- 45 Python API/PostgreSQL tests passed using a disposable PostgreSQL 17 database. The integration
  test runs the HTTP login flow with a mocked GitHub response and **real** restricted DB execution.
- Existing owner UUID/revision/usage baseline survive login and alias rename, then a new revision
  is written and reloaded. A second identity starts with its own empty save.
- Twenty interleaved requests across two identities preserve owner isolation with a two-connection
  pool. Concurrent refresh has exactly one winner; replayed refresh and old access tokens return 401.
  Logout revokes both tokens without logging out the other identity. Expired access/refresh tokens
  also return 401.
- Unknown owner fields, alias selectors, old Supabase JWTs, direct save/session-table reads, excess
  OAuth scopes, malformed identity data, oversized credential bodies and echoed secrets are rejected.
- 163 focused Swift tests passed, including new empty-scope/state/PKCE tests and existing cloud and
  Pokémon regression suites. Removing the backend scope guard caused three expected regression
  failures; the guard was restored afterward.

The new API was deployed to `https://hobby-trainer.vercel.app` on 2026-10-15 (initial production
activation `dpl_7ssigPVjeZ2LRHnZ9M3SwqgcjW54`). Health returned 200, and missing/forged application
tokens returned 401 through the real restricted database connection. Existing profiles (2), saves
(1) and revision (7) were preserved. A real GitHub code exchange remains pending browser account
selection and removal of prior email grants; the historical two-account audit is not evidence for
this new OAuth exchange. Production build readiness is separate from real login verification.

## Production activation

The migration `20261015071648_public_profile_auth.sql` is applied to production.
Activation uses matching backend/native versions and backend-only configuration
in `server/.env.example`. The OAuth app's registered callback must be exactly
`hobbytrainer://auth/callback`; the public client ID in `config/TrainerCloud.json` must match the
backend client ID. No client secret, DB password, or privileged API key belongs in that JSON or app.
The native callback has been registered exactly with wildcard matching disabled. The old Supabase callback is retained during transition.

Use a dedicated `trainer_api` database login with only the migration's three function grants,
`NOINHERIT`, no memberships or elevated privileges, and TLS `sslmode=verify-full` with the project CA
using `sslrootcert=bundled`. The public Supabase CA is bundled in the server and its absolute path is resolved at runtime; system roots alone do not trust this pooler. Supabase transaction poolers can use `trainer_api.PROJECT_REF` as the login
name; prepared statements are disabled. Pool size is bounded to five per backend instance. The
migration deliberately creates the role without LOGIN or a password; credentials must be provisioned
privately during activation. Do not substitute `postgres`, a service-role key, or an administrator role.

For accounts that previously approved email access, revoke the old GitHub app authorization before
using this same OAuth app with empty scopes, or use a separate public-profile-only OAuth registration.
Changing the request cannot revoke a grant that GitHub already holds. Old Auth data is retained for
save continuity; no existing account, email record, grant or session was deleted by this local change.

References: [GitHub authorization/PKCE](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps),
[GitHub scopes](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/scopes-for-oauth-apps).
