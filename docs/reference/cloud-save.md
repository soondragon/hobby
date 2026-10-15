# Account-owned cloud saves

The cloud build uses Supabase Auth and PostgreSQL, with a Python 3.12 FastAPI API on Vercel.
It never loads, imports, exports, backs up, or falls back to a local Pokémon save. The old file
is left untouched. Device preferences and authentication credentials are separate from game saves.

## Runtime flow

1. The user signs in with GitHub through Supabase using authorization code + PKCE (S256).
2. The native app verifies `/auth/v1/user`. Supabase credentials are stored in a dedicated,
   device-only Keychain item. Keychain restoration is an explicit button action.
3. The API verifies the bearer token with Supabase Auth. It forwards that same user token to
   PostgreSQL RPCs; no service-role key is used by the native app or API.
4. The database derives ownership from `auth.uid()` and GitHub identity data maintained by Auth.
   GitHub alias is display data. A caller cannot select someone else's save by supplying an alias.
5. `GET /api/companion` returns the authenticated user's save. An absent save requires an explicit
   **Start on server** action. Only a successful server receipt unlocks gameplay.
6. Native changes are coalesced for 300 ms, then serialized. A version check rejects stale writes.
   An idempotency UUID binds the exact payload and version so a lost acknowledgement can be retried.
7. Authentication, connectivity, or version failures freeze gameplay. There is no local fallback or
   silent last-write-wins merge. Conflict recovery requires explicit discard and server reload.

The server is the durable source of Pokémon state. Unacknowledged changes exist only in memory;
the full app warns before normal termination. Force quitting can lose unacknowledged changes.
This version uses explicit reload/conflict recovery rather than background multi-device merging.
Use one active writer per account; provider usage baselines are currently part of that shared save.

## Save structure and normalization

The original `CompanionState` JSON contained the active individual, collected individuals (`dex`),
wallet/progression counters, egg state, inventory, provider usage baselines, candy grants, and locale.
Difficulty settings are device preferences, not part of this document.

| Table | Responsibility |
| --- | --- |
| `trainer_profiles` | Auth UUID, verified GitHub provider ID, display alias |
| `trainer_saves` | Schema version, revision, bounded core state, update time |
| `trainer_collection` | Individual ID, order, species IDs, shiny flag, remaining individual details |
| `trainer_inventory` | Item kind and quantity per owner |
| `trainer_candy_ledger` | Grant tier and window epoch per owner and provider/window key |
| `trainer_save_operations` | Bounded idempotency history, payload digest, applied revision |

The API and database both validate the payload. Unknown fields, excessive sizes, invalid counters,
duplicate individual IDs, and invalid nested individual profiles are rejected. The database embeds
the strict schema generated from `server/app/models.py`; model changes require a schema migration.
Do not pass individual profile seeds through JavaScript numbers: they are UInt64 values. Python's
integer JSON parser and PostgreSQL JSONB preserve their exact value, including `2^64 - 1`.

## Security boundaries

- RLS restricts direct reads to the owner. Direct client writes and anonymous RPC execution are revoked.
- Only the read/write RPCs are intentionally callable by authenticated users. Their security-definer
  execution is deliberate, with an empty search path and ownership derived inside the function.
  Supabase's advisor reports these two deliberate grants; audit their bodies before changing grants.
- GitHub client secrets live only in Supabase provider configuration. They are absent from source,
  app resources, API environment, and logs. The native bundle contains only public connection settings.
- Credentials are not placed in query strings or preference files. HTTP redirects carrying bearer
  tokens are refused, HTTP caches are disabled, and API errors do not echo private save payloads.
- The automatic-RLS trigger's unnecessary client execute permission is revoked separately.
- This protects one user's data from other users. It does **not** make client-generated XP or stats
  cheat-proof. Future invitation battles require server-authoritative battle rules and commands,
  separate from a player's editable collection save. No battle feature is implemented here.

## Development and deployment

Public configuration: `config/TrainerCloud.json`. Never add a secret/service-role key to it.

```sh
bash scripts/build-cloud-app.sh
open "$HOME/Applications/PokeTokenBar Cloud.app"
```

The cloud app is installed separately from the upstream app and the older local-save hobby app.
`scripts/build-cloud-preview.sh` builds only the authentication/account window for debugging.
The native callback is `hobbytrainer://auth/callback`; Supabase must allow this exact URL.
The GitHub OAuth callback is the project's `/auth/v1/callback` HTTPS URL, with no wildcard.

Vercel project root is `server`, using the FastAPI preset and Python 3.12. Required environment:
`SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`. Preview deployment protection remains enabled; production
API requests are protected by Supabase user authentication. Apply migrations in filename order.
The current API is at `https://hobby-trainer.vercel.app/api/health`.

```sh
cd server
python3.12 -m venv .venv
.venv/bin/pip install -r requirements.lock
.venv/bin/python -m pytest -q
```

Real PostgreSQL isolation/concurrency tests additionally require `TRAINER_TEST_DATABASE_URL` pointing
to a **disposable local** database named `trainer_test`. The fixture refuses remote databases and
preexisting application database names. It bootstraps minimal Auth roles/tables for these tests;
real GitHub sign-in must also be verified independently against the configured Supabase project.

Native regression selection includes `CloudPersistenceTests`, `CloudSynchronizationTests`,
`CompanionStoreTests`, `CompanionIdentityTests`, and the existing balance/save/profile suites.
The callback test invokes the actual adapter on a background queue, including a late cancellation.
Manual checks must cover sign-in, session restoration, new server save, reload, and relaunch.
