# Cloud application updates and upstream integration

The cloud application explicitly selects the `soondragon/hobby` release channel at startup, regardless of packaging identity. Only the exact upstream bundle identifier `io.github.chattymin.poketokenbar` may use `chattymin/PokeTokenBar` and its Homebrew cask updater. Unknown, preview and cloud bundles fail closed to the cloud channel. Both fetched and directly considered release links must belong to the selected repository's HTTPS release-tag path; applying an update validates the link again. Cloud updates never invoke Homebrew or the upstream launch agent.

This is channel isolation, not an automatic source merger. The cloud channel opens its own release page for manual installation. The repository is private: an unauthenticated GitHub latest-release request cannot discover private releases. No repository-scoped token is requested or bundled. A public signed release feed or deliberate public distribution repository remains necessary before unattended release discovery/distribution can be enabled. No cloud release artifact was published by this change.

## Upstream integration, 2026-10-16

Merged upstream `04b12da` from baseline `c328d5c`: alternate species forms, Pokédex back navigation, and stable rare-candy reset handling. The conflicts in `CompanionStore` and `SpriteLoader` were resolved by preserving cloud mutation authorization and the encounter front/back sprite separation while adopting general `PokemonForm` values.

`CloudSaveWire` maps the new domain fields to the existing schema-v1 wire aliases (`form` → `unownForm`, `pendingForm` → `pendingUnownForm`, `representativeForm` → `representativeUnownForm`). Existing server reads are supported by upstream's legacy decoder. Default non-Unown forms remain absent on the wire so preexisting server identity fields do not change just because the app was upgraded. Nondefault forms retain their raw values. No production schema, authentication settings, user credentials or saves were migrated.

Regression coverage includes rejecting a newer upstream release for the cloud bundle, accepting only cloud release URLs, ensuring Homebrew is unavailable in that channel, legacy wire-key round trips, default-form identity stability and separate back-sprite cache keys.

## Local validation

- Upstream HEAD rechecked against the remote: `04b12da9bb426ee4ff1ffc0e124c7cb4011dc914`.
- Focused Swift integration run: 153 executed, 152 passed, one opt-in all-form PokéAPI network parity test skipped, zero failures. Includes updater isolation, cloud persistence/synchronization/wire encoding, GitHub authorization, encounters, form/Unown support, rare candies, Pokédex navigation/filter/paging and save transfer.
- Python backend auth/API/move-catalog regression: 28 passed (Python 3.12).
- Temporary mutation changed the cloud repository to upstream: the cross-channel rejection assertion failed as expected; the unmodified policy passed. Production source was not mutated for that check.
- Release build and strict ad hoc signature verification passed. Local artifact: `build/cloud-integrated-20261016/PokeTokenBar Cloud.app`.
- The full coverage gate was attempted but interrupted after several minutes of unrelated real local-log scanning and macOS Contacts/CoreData XPC retries. It is not reported as passed; no full-suite coverage percentage is claimed. An initial test used shared defaults and failed due to a previously skipped test version; it now uses isolated defaults and passes in the final focused run.
- No remote push, hosted deployment, production schema migration or public release was performed. The existing installed app was left running because it showed unsaved growth input pending the server rate limit. It was not overwritten or forcibly discarded. The new artifact has not been authenticated interactively; its cloud compatibility is covered by the local regression run above.
