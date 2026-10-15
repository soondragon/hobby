# GitHub profile login and future invitation battles

## Implemented scope

GitHub Device Flow signs a desktop user in and displays `@login` in Home, Settings,
and a dedicated account window. The account window survives closing the transient
menu-bar popover. This change does not alter usage readers, growth, inventory,
Pokémon profiles, save import/export, or the companion save schema.

The dedicated OAuth registration is **Hobby Trainer**, owned by `soondragon`:
<https://github.com/settings/applications/3933887>. Device Flow is enabled. Its
Client ID is public configuration, not a secret. No Client Secret was generated.
No scopes are requested; the token response must contain an empty scope. Tokens
from GitHub CLI or other applications are never reused.

1. User chooses GitHub sign-in in the account window.
2. `POST /login/device/code` requests a device challenge.
3. The window displays the user code and the exact GitHub verification URL. Codes
   are displayed locally, not delivered by email or text message.
4. The user opens GitHub, enters the code, checks the account, and authorizes.
5. Polling respects the interval, adds five seconds on `slow_down`, and stops on
   cancellation, denial, network failure, or expiry. Polling is asynchronous.
6. `GET https://api.github.com/user` validates the authenticated user's identity.
7. The access token, client ID, GitHub numeric ID, and optional expiry are saved to
   a dedicated Keychain item. A separate JSON file stores only the public profile.
8. Home and Settings observe the session and update the alias without waiting for
   the usage polling timer. `login` may change; numeric `id` identifies the user.

## Modules

| Responsibility | File |
| --- | --- |
| Public Client ID and override validation | `Authentication/GitHubConfiguration.swift` |
| Device/credential response models | `Authentication/DeviceAuthorization.swift` |
| Ephemeral HTTP transport; redirects refused | `Authentication/GitHubHTTPTransport.swift` |
| Device authorization and token parsing | `Authentication/GitHubAuthenticationClient.swift` |
| Dedicated Keychain storage | `Authentication/ProfileCredentialVault.swift` |
| Stable identity and alias | `Profile/GitHubProfile.swift` |
| Authenticated profile API | `Profile/GitHubProfileClient.swift` |
| Public cache; atomic JSON writes | `Profile/ProfileRepository.swift` |
| Cancellable session state and stale-response guards | `Profile/ProfileSession.swift` |
| Live dependency assembly | `Profile/ProfileSessionFactory.swift` |
| UI entry, account window, presentation | `UI/ProfileEntryView.swift`, `UI/ProfileAccountView.swift`, `UI/ProfileWindowController.swift` |

Paths in this table are relative to `Sources/PokeTokenBar`.

## Local persistence and lifecycle

- No application server or database is required for this local alias feature.
- `user-profile.json` is beside the companion save, but independent from it. It is
  not copied into Pokémon save exports, snapshots, or imports.
- Credentials live under Keychain service `io.github.soondragon.hobby.profile`,
  separated by Client ID; they do not sync to other devices.
- Startup reads only the public cache and labels it **saved / unverified**. It does
  not query the Keychain or call GitHub. An explicit **Verify connection** action
  may prompt for Keychain access, revalidates `/user`, and refreshes a renamed alias.
- Expired or revoked credentials require sign-in again. Refresh tokens returned by
  GitHub are not persisted or used in this version; access-token expiry is respected.
- Disconnect removes local credentials/cache only; it preserves Pokémon progress.
  GitHub-side authorization can be revoked by the user at GitHub's application settings.
- The cache and `isVerified` UI flag are never server authorization evidence.
- Public Client ID can be overridden by `PTB_GITHUB_CLIENT_ID` or Info.plist
  `GitHubClientID`; an explicit empty override disables sign-in.
- Newly introduced copy supports Korean and English fallback for the other app languages.

## Isolated local validation

```sh
swift build
swift test --filter 'GitHubAuthenticationTests|ProfileSessionTests|ProfileRenderingTests'
./scripts/build-profile-preview.sh
```

The debug preview bundle at `build/profile-preview/Hobby Trainer Preview.app`
opens only the account window. It never constructs usage readers or companion
stores, never replaces `/Applications/PokeTokenBar.app`, and writes the public
profile under `build/profile-preview/state`. A real sign-in still uses the
registered app's dedicated Keychain item. The preview-only bootstrap is omitted
from release compilation.

Automated tests inject HTTP, credentials, profile repository, sleep and clock.
They never use the developer's real login, GitHub CLI token, or Pokémon save.
Rendering tests use clearly marked sample identities; these are not live login proof.

## Future invitation battle: server and DB are required

A local alias is enough for display. Two remote users need a common trusted
service for identity verification, invitation redemption, durable room state,
turn order, reconnection, and authoritative results. Recommendation for a first
turn-based version: Python 3.12+ asynchronous API + PostgreSQL + WebSocket
notifications. Redis is optional for presence/pub-sub when running multiple
workers, not the source of truth and not necessary for the first single-worker
version. The service must support persistent WebSocket connections.

The backend must establish its own session from a validated GitHub authorization.
It must not accept a submitted alias, numeric GitHub ID, or the local cache as
proof. For production, use a backend-managed OAuth exchange or validate the token
against the intended OAuth application's token-check endpoint using a server-only
Client Secret, then resolve `/user` and issue a short-lived application session.
The secret would be generated only when that backend is actually introduced; it
must never be embedded in the desktop binary. Do not put GitHub tokens in invite
codes, WebSocket URLs, room events, or logs.

### Proposed normalized PostgreSQL model (not implemented)

| Table | Key fields / constraints |
| --- | --- |
| users | UUID PK, github_user_id BIGINT UNIQUE NOT NULL, current_alias, created_at |
| sessions | token_hash UNIQUE, user_id FK, expires_at, revoked_at |
| battle_rooms | UUID PK, host_user_id FK, status, rules_version, turn_number, state_version, expires_at |
| battle_invites | UUID PK, room_id FK, code_digest UNIQUE, expires_at, redeemed_by FK nullable, redeemed_at |
| battle_members | room_id FK + user_id FK PK, seat, ready; UNIQUE(room_id, seat) |
| battle_rosters | room_id + user_id FK, immutable validated roster and rules snapshot |
| battle_actions | room_id FK, turn_number, actor_user_id FK, request_id; UNIQUE(room_id, turn_number, actor_user_id), UNIQUE(actor_user_id, request_id) |
| battle_events | room_id FK, sequence; PK(room_id, sequence), event type/payload, created_at |

JSON is appropriate for immutable roster/event payloads, not for membership,
identity, invitation redemption, or uniqueness that the database must enforce.

### Room process and concurrency

1. Authenticated host creates a room and a short-lived invitation. Store an HMAC
   digest of a cryptographically random human-friendly code, with a server-only
   key; rate-limit redemption to protect short codes.
2. Another authenticated user redeems the code. A transaction locks the invite and
   room rows in a fixed order, verifies expiry/capacity/not-self/not-redeemed,
   inserts the second member and consumes the invitation atomically. A third user
   or racing request cannot claim the same seat.
3. Both users confirm a server-validated immutable roster. Start the room once.
4. Each action includes turn/version and an idempotency key. The server validates
   membership and legality, commits both actions, resolves the turn exactly once,
   increments the room version, and writes ordered events in the same transaction.
5. Send events only after commit. A transactional outbox or sequence-based catch-up
   closes the gap between DB commit and delivery. Reconnect requests events after
   the last received sequence; duplicated delivery is safe.
6. Use server deadlines for turn timeouts and disconnect grace periods. Results
   and any rewards are committed once; clients never declare victory themselves.

### Fairness boundary to settle before battle implementation

Current Pokémon saves, imported saves, growth difficulty and token logs are local
and editable. GitHub login proves identity, not that a Pokémon's level or IVs were
legitimately earned. The first casual mode should use server-normalized levels,
allowed species/moves, and server-calculated stats with no economic/ranked rewards.
A competitive mode needs a server-owned creature/progression ledger or a separate
battle roster issuance mechanism. A checksum on a client-submitted save does not
solve this trust problem. Existing local growth can remain unchanged in either mode.

### Subsequent implementation stages

1. Server session verification + users/sessions + two-client identity tests.
2. Invite create/redeem + transactional race/expiry/third-user tests.
3. Ready/roster snapshots + fixed rules + deterministic turn resolver.
4. Reconnect/timeout/event replay + duplicate request and multi-worker tests.
5. Desktop battle UI and invitation sharing; then end-to-end validation with two accounts.

No battle service, database, rooms, remote save sync, or battle mechanics are
created by the current profile change.

## Primary references

- [GitHub OAuth Device Flow](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow)
- [OAuth scopes](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/scopes-for-oauth-apps)
- [Authenticated user](https://docs.github.com/en/rest/users/users#get-the-authenticated-user)
- [OAuth application token check](https://docs.github.com/en/rest/apps/oauth-applications#check-a-token)
- [PostgreSQL row-level locks](https://www.postgresql.org/docs/current/explicit-locking.html#LOCKING-ROWS)
- [FastAPI WebSockets](https://fastapi.tiangolo.com/advanced/websockets/)

## Validation recorded for this change

- Debug build and release build completed locally.
- Selected regression run: 179 tests, 177 passed, 2 skipped, 0 failures. The skips
  are existing live-credential gate tests whose external-credential prerequisites
  were absent. This is a focused regression run, not a full-suite result.
- The seven pure authentication/profile logic files listed in the coverage gate
  reported 96.40% line coverage in that run. HTTP transport, Keychain calls,
  dependency assembly, and UI are not included in this percentage.
- Production SwiftUI views were rendered with sample data for signed-out,
  authorization-pending, signed-in, alias-row, and Home before/after states.
- The isolated preview completed real GitHub Device Flow with **public data only**,
  displayed the account's actual alias, saved its public cache, and read credentials
  back from Keychain after an app restart to verify `/user` again.
- After restart, cached identity is displayed as unverified until explicitly checked.
- No access token was printed or written to the public cache. No Client Secret was
  generated. The preview does not load or mutate the Pokémon save.
- Existing companion, usage, Pokémon model, Shop and Bag implementations have no
  code changes. Existing Home and Settings receive only a profile entry row.
- No application server or battle database was deployed.
