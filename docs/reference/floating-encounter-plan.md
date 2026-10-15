# Two-player floating encounter: implementation contract

This is preparation only. Implementation starts after the email-free authentication version has
been deployed and verified, as requested. No battle/encounter source code or production schema is
introduced by this document.

## User flow

1. A signed-in player opens the floating encounter panel and selects an owned individual from the
   current active companion or owned collection. An account without a Pokémon sees an explicit
   empty state; the application does not invent or award one.
2. The host creates an invitation; another signed-in account joins with that invitation and selects
   its own individual. Both participants explicitly choose what they share.
3. Each player sees their own Pokémon at the lower left from behind, and the opponent at the upper
   right from the front, using the classic Blue battle composition. Show aliases, species and level.
   This stage displays the pair only: attack commands, damage, HP simulation, winners and rewards
   require a separate implementation and are not represented as working features.
4. Changing one's selection updates the other participant's floating panel. Leaving, signing out,
   hiding the panel, loss of connectivity and expiry have explicit states and bounded cleanup.

## Server and privacy

- Account authorization uses the existing opaque application session and stable owner UUID. An alias
  is display data only; a caller-supplied alias or owner UUID never selects another player's save.
- The server derives selections from owned instance IDs, not caller-supplied species, shiny flags,
  levels or stats. Released individuals are not selectable. Recheck ownership when returning a choice.
- Invitations admit at most two distinct accounts. Joining is transactional: two simultaneous joins
  cannot both occupy the second slot. Codes are random, expire, and have bounded authenticated usage.
- Only room participants can read that room. Responses expose only the two selected display
  projections, not provider ledgers, wallet, inventory, full rosters, individual seeds, IVs or tokens.
- Store rooms and participants separately from growth saves. Selection never edits Pokémon growth,
  saves locally, grants progress or broadens public table privileges.
- Room revision checks reject stale mutations. The same participant cannot alter the opponent's
  selection. Session revocation also applies to room requests.

## Native integration

Keep room transport, room state, selection UI, battle-composition view and NSPanel lifecycle in
separate domain-named files. Reuse the existing sprite pipeline; fetch front/back assets at runtime
and provide an explicit loading/failure placeholder. Do not bundle Pokémon art in the application.
The existing single-pet feature remains available independently.

Network updates run only while the encounter panel is visible. Serialize refreshes and mutations,
use bounded intervals/backoff, and discard responses from an older room/account generation.
Signing out closes the panel, clears its in-memory display data and cancels pending work.

## Acceptance evidence required

- Two real GitHub accounts select their own server-owned individuals and see both selections.
- Test outsider reads, forged instance IDs, opponent updates, stale revisions, simultaneous joins,
  expired invitations and revoked sessions against real PostgreSQL.
- Verify selection changes from both perspectives, disconnect/reconnect, leaving and account switch.
- Render and inspect actual floating front/back placement and labels; capture both perspectives.
- Re-run existing cloud save/growth and single-floating-pet regressions. Report local fixtures,
  deployed backend checks and real two-device/account outcomes separately.
