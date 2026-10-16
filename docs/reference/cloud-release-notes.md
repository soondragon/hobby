# Hobby Trainer Cloud 0.3.0

## New
- Dedicated signed public update feed and application package, without GitHub repository scopes.
- Publisher signature, SHA-256, archive, bundle identity and version checks; previous installation retained for rollback.
- Upstream general Pokémon forms and improved Pokédex back navigation.

## Fixed
- Oversized offline growth waits for its server-controlled rate budget instead of becoming permanently unsaveable.
- Automatic Retry-After retries preserve the same request and pending progress.
- Schema-v1 cloud compatibility and front/back encounter sprites survive upstream integration.
- Upstream rare-candy reset timestamp handling prevents duplicate rewards.

## Other
- No upstream Homebrew upgrade or launch agent; no new GitHub scopes; server-only saves.
- Apple Silicon/macOS 14+; local ad hoc signing, not Apple notarization.

## Contributors
- Dylan LE FLOUR
- Killian HERZER
- Taeyang Jin (Theo)
- sweatmonday

## Install / Upgrade
Use the dedicated cloud download page. Cloud builds with the signed feed install only verified cloud packages. Upstream PokeTokenBar installations remain separate.
