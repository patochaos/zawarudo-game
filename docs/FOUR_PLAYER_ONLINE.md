# Four-player online playtest

The source supports four human players in a private online free-for-all, one
player per PC. Online defaults to four seats and retains a two-player option.
All five arenas have four-player layouts. No level geometry changes were
needed for this work.

The updated Cloudflare room service was deployed on September 19, 2026
(version `da90ca73-9288-42f7-be6b-e1747dd27566`). Its live health response
advertises protocol 3 and capacities 2/4. Four real Godot clients passed the
HTTP/WebSocket integration test against that live service. Legacy protocol 2
two-player rooms remain supported separately; the hosted game client was not
changed.

## Joining with Play.bat

1. Put the same updated project source on all four PCs and launch `Play.bat`.
2. The host chooses Online, optionally types a name, leaves 4 PLAYERS selected,
   chooses an arena, and creates a private room.
3. Share its six-character code. The other three PCs choose Online, optionally
   type a name, and join.
4. The match starts when all four seats are connected. Each PC controls its
   assigned fighter using its own keyboard/mouse or first connected gamepad.

The host chooses the rematch arena; all four players must request a rematch.
Planning remains private until all four plans arrive. A planning timeout submits
that PC's current plan, rather than bypassing the other players.

## Nicknames

Each PC can register a nickname in the lobby before creating or joining. The
room service sanitizes it (upper case, letters, digits, spaces, `_`, `-`, at most
12 characters), stores it per seat, and includes a `names` array in its
`connected`, `room_state` and `match_start` messages plus a `name` on the
`peer_status` a newcomer triggers. The protocol version is unchanged: a client
without the field sends no name and shows P1..P4, and a service without the
change ignores the field, so mixed versions still play. The nickname is saved in
`settings.cfg` on the device. Deploy the room service for names to appear.

## Disconnect behavior

A brief socket loss reconnects automatically using the same seat. The group waits
at the synchronization barrier for missing plans or results. A four-player
disconnect does not award a winner. If someone closes/reloads the game and loses
their session, leave and create a new room together. Late join, replacement
players, and full state recovery after restarting the application are not supported.

## Fixes

- Four authenticated online seats, lobby occupancy, and automatic full-room start.
- Four-party barriers for plan reveal, state verification, results, and rematches.
- All four fighters' scores and kits included in deterministic checksums.
- Correct keyboard, gamepad, and HUD identity for Players 3 and 4.
- Independent disconnect tracking and recovery of a missed turn-start message.
- Online starts reset local experimental modes and sandbox tuning.
- Protocol separation prevents incompatible clients joining the same room.

## Verification

- Four independent game simulations matched checksums through three turns on
  each of the five arenas, including movement, jumps, and projectiles.
- Arena tests checked four distinct safe starts, moving geometry, full-arena
  camera, simultaneous respawns after cover destruction, and every winning seat.
- Real Godot OnlineClient HTTP/WebSocket tests checked four connections, hidden
  plans, identical four-plan broadcasts, and the four-result turn barrier.
- Backend tests cover capacity overflow, fourth-player wins and desyncs,
  disconnect/reconnect, rematch voting, mixed result disagreements, and versions.
  All 43 tests and TypeScript checks passed.
- Existing local four-player, team battle, menu, core demo, and touch-control
  regressions passed.

These checks do not replace a four-PC session across different internet
connections. Human balance, latency tolerance, and crowded visual readability
remain playtest observations.

## Reproduce the network check

Start `npm run dev` from `backend`. In a PowerShell window at the project root:

```powershell
$env:ZAWARUDO_API_URL = 'http://127.0.0.1:8787'
.\scripts\Test-Godot.ps1 -Suite OnlineClientIntegrationTest
Remove-Item Env:ZAWARUDO_API_URL
```

The integration test skips unless an explicit endpoint override is supplied.
The ordinary launcher uses the configured Cloudflare room service. Source changes
do not themselves deploy the service or update the hosted website.
