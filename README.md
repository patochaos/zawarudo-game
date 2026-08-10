# ZAWARUDO — Tactical Knife Duel

> Diseño de juego: [`docs/GAME_DESIGN.md`](docs/GAME_DESIGN.md) — visión,
> pilares, contratos de experiencia y marco para futuras decisiones.

2D side-view 1v1 duel. Simultaneous planning, then a short burst of real-time
physics. Everything — players and knives — keeps its position and velocity
across the freeze, so a dangerous knife can hang in mid-air for several planning
phases while both players decide what to do about it.

Each throw releases a two-knife fan. Low charge is slow and wide for space
control; full charge is fast and nearly parallel. Knives from different throws
can collide in flight, ricochet, lose force, tumble, and remain lethal as they
fall through later execution windows.

A deflected knife can be struck again. Re-clashes retain progressively more
energy, accumulate tumble, and add a small deterministic glancing angle. The
result looks chaotic but replays exactly, preserving the planning contract.

Long matches build toward a **super**. A clean clash between opposing knives
adds 7.5% to each knife owner's meter only while that owner is moving. Re-clashes
do not count, while claiming a Temporal Core fills the meter outright. At 100%,
the player may toggle the upgrade for their next shot: five consecutive waves
of three fast knives. The waves follow the same narrow lane, spaced far enough
apart to read as a sequence rather than one explosion. Every wave shares one
volley identity, so the burst cannot collide with itself as it leaves the
player, while enemy knives can still deflect it. The meter persists through
hits and turns, and is spent when the first wave actually fires.

Godot 4.7. Double-click one of these:

| File | What it does |
|---|---|
| **`Play.bat`** | Runs the exported build. Needs nothing installed — this is the one to hand a playtester. |
| **`Play-Source.bat`** | Runs the current source with Godot, so code edits show up without re-exporting. Set `GODOT_DIR` at the top if Godot isn't in `D:\Godot`. |
| **`Build.bat`** | Re-exports Windows + Web and packages both zips for itch. |
| **`Build-Web.bat`** | Generates and validates the browser build in `build/web`. |
| **`Deploy-Web.bat`** | Generates the browser build and publishes it to Vercel production. |

Or from a shell:

```bash
godot --path "D:/Zawarudo game"
```

## Online build

Play the current production build at **https://zawarudo-pi.vercel.app**.

The Godot WebAssembly client is hosted on Vercel. Private rooms run through the
Cloudflare Worker in `backend/`, with one hibernating Durable Object per room.
The Worker coordinates the lobby and exchanges locked plans; both browsers then
simulate the exact same deterministic turn and compare a state hash before the
next one begins.

To play online:

1. Player 1 chooses **ONLINE** and **CREATE PRIVATE ROOM**, then sends the
   six-character code to Player 2.
2. Player 2 chooses **ONLINE**, enters that code, and presses **JOIN**.
3. Both players use their own keyboard and mouse. Online, the controls on both
   computers are `A`/`D`, `W`, `S`, mouse aim, hold/release `LMB`, `Left Shift`
   to confirm, `R`/`RMB` to roll back, `F` to reset the path, and `T` for SUPER.

Plans remain private until both players confirm. A disconnected client retries
the room socket automatically; a detected state mismatch stops the match
instead of allowing the two screens to silently diverge.

Vercel is the client host because the current Godot WebAssembly file is larger
than Cloudflare Pages' per-file limit, while it fits within Vercel Hobby's
static upload limit.

Before the first deploy, log in once with `vercel login`. Then double-click
`Deploy-Web.bat`, or run:

```powershell
.\scripts\Deploy-Web.ps1
```

That command exports the current Godot project, validates the required browser
files, copies the Vercel headers, and deploys the `zawarudo` project to
production. Use `.\scripts\Deploy-Web.ps1 -Preview` for a temporary preview URL,
or `-Project another-name` to select a different Vercel project.

The room service can be checked and deployed independently:

```powershell
cd backend
npm test
npm run typecheck
npx wrangler deploy
```

## Menu

The title screen picks the mode and starting level. Every row is clickable;
keyboard navigation remains available (`W`/`S` select, `A`/`D` change level,
`Enter` activate). **HOW TO PLAY** opens a five-line rules summary, and `Esc`
returns to the menu from a match.

* **VS AI** — Player 2 is driven by `Ai.gd`.
* **ONLINE** — private two-player room; separate screens and private plans. Each
  player uses their own mouse and keyboard with the Player 1 control layout.
* **FREE PLAY** — see below.
* **2 PLAYERS** — local, **open information**: both players see each other's
  plans. Nothing on one screen can genuinely hide a plan from the person
  sitting next to you (mirroring or splitting the view does not help — both
  halves are still on the same monitor), so rather than pretend, 2P leans into
  it: you can see the plan, and the game becomes reading and countering it.

## Free play — judging the feel

Turn structure makes movement hard to evaluate: you only ever see 0.75s of it at
a time. **FREE PLAY** drops the freeze entirely — continuous real-time control of
one player, no turns, no timer, no score, with Player 2 as an inert target to
shoot at. Platform destruction still works; the dummy just gets back up.

`A`/`D` run · `W` jump · mouse aim · hold `LMB` to draw, release to fire.

The left panel edits the tuning **live**, and whatever you set carries into a
real match afterwards:

`↑`/`↓` pick a value · `←`/`→` change it (hold `Shift` for ×5) · `Backspace`
reset all · `R` reset the arena · `F10` next level · `Esc` menu

It also shows what the numbers mean in play — jump apex and hang time, distance
covered in one execution window, time to reach top speed, best knife range at a
half draw — because those are what actually decide the feel, and working them
out from raw values by hand is the slow way to tune.

## The opponent

The AI plays by the same rules you do. It sees the world state and every knife
in flight, and it does **not** read your plan. Instead it guesses: each turn it
plays out three hypotheses for what your feet might do this window — hold, run
left, run right — and prefers the shot that covers the most of them. That is the
same prediction problem the game asks of a human.

Its plan is hidden from you (dashes in its panel, no ghost or trajectory drawn),
because it plans blind and showing you its intent would be a one-way giveaway.

It drives the ordinary piloting API, so its movement is recorded, costs stamina
and replays exactly like yours. The search runs in ~3ms slices across frames
during its think delay — a full sweep costs ~35ms, which would otherwise be a
visible hitch at the top of every planning phase. Measured over 5000 frames of
live play: **worst frame 7.9ms, zero frames over budget.**

Difficulty knobs on the `Main` node: `ai_aim_jitter` (degrees of slop, default
2.0), `ai_think_min` / `ai_think_max`, `ai_slice_usec`.

## The loop

```
PLANNING (5s, frozen)  ->  COMMITTING (0.25s, locked)  ->  EXECUTING (0.75s, physics)  ->  PLANNING ...
```

* Execution begins when both players confirm (after a 0.25s commit beat that
  absorbs late input) **or** when the timer hits zero.
* Nothing is cleared at a phase boundary. Knives are only removed when they hit
  terrain, hit a player, or leave the world.

## Match structure

**First to 3 hits takes the match.** A hit does not end the round — it costs a
point and takes the victim off the board for the remainder of that window only.
Everything else carries on untouched: knives stay in flight, platform damage
stands, the other player keeps their exact position and velocity.

The victim respawns at the start of the next planning phase with **one turn of
invulnerability** (a white ring; knives pass straight through). A banner names
who was hit and shows the score for a couple of seconds.

To keep a cautious match from lasting forever, each player also has a late-match
**SUPER** meter. It takes fourteen qualifying knife clashes to fill from empty.
A gold ring around the fighter marks a full meter. Once full, press the player's
SUPER toggle (`T`, `P`, or gamepad `Y`) to arm or disarm the upgrade, then draw
the shot normally. The meter is only spent when the first super wave actually
leaves the player. Immediately before that first wave, combat hard-freezes for
a short illustrated manga portrait cut-in with **IT'S ALL USELESS** and a rapid
synthetic **muda** chant. The portrait mirrors with the attacking side while the
panel inherits that player's color. If both supers share a tick, both
introductions play before the simulation advances.

A hitless exchange also advances the **Temporal Core** clock. After two
consecutive hitless execution windows, one of the level's authored Core sockets
is marked for a full turn. If the following window is also hitless, the Core
materializes there for two execution windows. Touching it with the real player
(not merely the planning ghost) fills that player's SUPER meter. If both players
touch it on the same physics tick, both earn the reward. A hit during the warning
turn cancels the incoming Core; once materialized, it persists for its full
lifetime unless collected.

For quick playtesting, `F8` fills Player 1's meter immediately; `Shift+F8` fills
Player 2's. This shortcut does not change the normal clash/Core charge rules.

Score pips sit under the timer. `F10` cycles levels and resets the score.

## Movement: pilot the ghost on a stamina budget

Movement is **not** a set of toggles — it is a recording.

During planning you drive your **ghost** with ordinary platformer controls.
Every tick of input is captured, and a **stamina bar** drains as the ghost
advances. When the stamina runs out the ghost stops steering; the rest of the
window is simulated with no input (momentum and gravity), drawn dotted, so you
always see where you truly end up. Execution then replays your recording
tick-for-tick.

Design lineage: the simultaneous plan-commit-watch structure comes from
[Frozen Synapse](https://en.wikipedia.org/wiki/Frozen_Synapse), which resolves
both sides' orders together over a fixed slice of simulated time. The movement
itself is closer to Worms/Gunbound — free real-time platforming metered by a
budget you spend down — rather than Frozen Synapse's waypoint drawing.

Key properties:

* **Time only moves while you do — on the ground and in the air alike.** Release
  everything and the ghost freezes, wherever it is. Hold a direction and it
  walks; hold jump and it climbs; hold the wait key (`S` / `↓`) and time runs
  with no steering, for falling or for lining a shot up at a precise moment.
  *(This used to be inconsistent: airborne ghosts advanced on their own, so the
  control rule silently changed the instant you left the ground — and since a
  full jump outlasts the window, that was every jump.)*
* **Variable jump height.** Let go while still climbing and the rise is capped
  at `jump_cut` of the impulse. A tap clears ~45px and lands inside one window;
  holding clears 211px and deliberately overruns it. Whether your jump fits in
  the turn is now your decision.
* **Charging freezes the ghost.** Hold the shoot button mid-run — even mid-jump
  — and everything stops while you aim. Release and piloting resumes.
* **The shot is pinned to a point on the path.** Fire at the top of a jump and
  the knife fan leaves from the top of that jump, at that tick, even if you keep
  walking afterwards. Its angle and power are locked at that moment; only the
  launch point moves if you re-pilot.
* **One volley per turn.** Once you release the charge the reticle disappears.
  Rollback brings it back.

## Controls

| | Player 1 — keyboard + mouse | Player 2 — keyboard | Either — gamepad |
|---|---|---|---|
| Walk the ghost | hold `A` / `D` | hold `←` / `→` | Left stick / D-pad |
| Jump (hold = higher) | `W` | `↑` | `A` |
| Let time run | `S` | `↓` | Left stick down |
| Aim | **Mouse** — free 360° | `.` / `,` (or `Num 6` / `Num 4`) | **Right stick** |
| Power | **Hold LMB** (or `Space`) | Hold `Enter` | **Hold R2** |
| Fire | release the button | release the key | release the trigger |
| Toggle SUPER | `T` | `P` | `Y` |
| Confirm | `Left Shift` | `Right Shift` | `Start` |
| Rollback shot | `R` or `RMB` | `Backspace` | `B` or `Select` |
| Reset path | `F` | `/` | `X` |

Global: `F9` restart · `F10` next level · `M` mute · `H` hide the control bar ·
`Esc` back to the menu · `Enter` rematch from the match-over screen.

In Vs AI the Player 2 column is inert — the AI ignores it.

In Online both computers use the **Player 1 — keyboard + mouse** column. The
server-assigned P1/P2 side changes the fighter and HUD label, not the local
bindings.

**Rollback** un-fires the shot and drops your confirmation but *keeps* the
movement you piloted, so you can re-aim without rebuilding the run.
**Reset path** throws the recording away and refills stamina (the shot goes with
it, since its tick indexes into the path that just vanished).

Rebind by editing the `K_P1` / `K_P2` dictionaries in `scripts/GameManager.gd`.

### Gamepads

The first connected pad goes to **Player 2** by default, so the out-of-the-box
setup is keyboard+mouse vs. gamepad. Flip it with `first_gamepad_to` on the
`Main` node. Aim source follows whatever a player touched last — mouse, stick,
or aim keys.

## Levels

Two focused arenas, cycled with `F10`. Layouts live in `scripts/Levels.gd`, and the HUD
names the wrap mode next to the level.

| # | Name | Wrap | Character |
|---|---|---|---|
| 1 | **Sacred Duel** | walled | Sacred Ground compressed for 1v1: side rooms frame a very large central flight chamber. |
| 2 | **Flight** | ↔ ↕ | Islands over a hole in the world, with horizontal portals and a vertical loop. |

The layouts borrow TowerFall's readable side architecture, but are compressed
for two players and deliberately use fewer internal walls. Obstacles shape
player routes while broad air chambers let persistent knives accumulate. Tests
verify supported spawns, usable wrap portals and a minimum open-volume budget.

### Wrapping

TowerFall-style: anything leaving a wrapping edge re-enters the opposite one,
**knives and players alike**. Two consequences worth knowing:

* On a wrapping arena there are multiple routes to your opponent, including
  attacks through the rear and vertical loop. Spawns are placed so none is a free hit.
* Collision uses seam copies of any platform or body near an edge, so standing
  on the edge works from either side.

Vertical wrapping uses a band starting at `y = 216` so nothing re-enters behind
the HUD. A `wrap_y` level therefore needs a solid ceiling with a gap in the
middle third, and its floor gap must sit inside that ceiling gap.

Flipping a level is one line: add `"wrap_x": true` to its dictionary. Side walls
are omitted automatically.

### Destructible cover

Terrain **never damages a player** — only knives do.

Platforms carry hit points and chip away as knives strike them, so cover is
temporary and the arena reshapes over a match. Remaining hits show as pips above
each piece, and it cracks and reddens as it takes damage. Indestructible
geometry is cool grey-blue; breakable geometry is warm brown. That colour split
is the only thing you have to learn to read an arena.

| Piece | HP |
|---|---|
| Ground, walls, spawn perches | indestructible |
| Centre pillar / plinth | 4 |
| Low steps | 3 |
| Mid steps, galleries, canopy, plateau | 2 |

A jump clears 211px. Breakables sit **outside** the lobbing corridor, so
destroying one opens new firing lines rather than closing the game down.

**One caveat worth knowing:** if a knife destroys a platform mid-window, anyone
standing on it falls, and the ghost that promised solid ground was drawn before
the floor went away. That is the one case where the preview can be wrong, and
it is deliberate — breaking the floor under an opponent is a legitimate play.

## Sound

Gameplay impacts remain procedurally synthesised, including a double-transient
knife `clink–clink`. The imported title voice plays at natural pitch when a
match starts. The SUPER cut-in uses a procedurally synthesised voice-like chant;
ordinary phase freeze and resume use very short, low-volume cues so they mark
the rhythm without dominating it. Everything shares an 8-voice pool. `M` mutes.

## Reading the preview

* **Solid line from your feet** — the stretch you piloted.
* **Dot where it changes to dotted** — where your stamina ran out.
* **Dotted tail** — uncontrolled coast to the end of the window.
* **Ring labelled `END`** — where you finish the execution window.
* **Green→red bar over the ghost** — stamina left.
* **Two notched knife rays** — the real fan direction and draw strength. Low
  power opens the fan; full power pulls the pair almost parallel. They show
  where you are *pointing*, **not where the knives land** — you still estimate
  the ballistic arc yourself.
* **Ringed dot labelled `FIRE`** — where and when along your path the volley releases.
* **Red `THREAT` ring** — a known knife crosses the visible plan during the next
  execution window. It is a warning, not a guarantee: the rival can still alter
  the shared world.
* **Rings labelled `+1`, `+2`, `+3`** — where a knife will be at the end of
  each future execution phase. A shot loosed mid-window reaches `+1` after less
  than a full window of flight, and the labels account for that.
* **White vector with a number** — a frozen knife's current velocity.
* **White ring around a player** — invulnerable this turn; knives pass through.
* **Violet grade, clock marks, and suspended gold motes** — the world is frozen.
  A violet/gold shock ring announces each freeze and a horizontal flash releases
  the next execution window.

All of it disappears during execution; you just watch.

## Tuning

Exported on the `Main` node in `scenes/Main.tscn`:

```
hits_to_win              3
respawn_invuln_turns     1
banner_duration          2.4

planning_duration        5.0
execution_duration       0.75
commit_delay             0.25

movement_budget          0.50    seconds of piloted control per turn
pilot_time_scale         0.5     ghost piloting runs at half real time
player_move_speed        260
player_acceleration      1800
player_air_acceleration  900
jump_impulse             780     full hold: 211px rise, 1.10s air
jump_cut                 0.40    tap: ~45px, ~0.5s — fits inside one window
gravity                  1400
max_fall_speed           1200

arrow_speed_min          300     (0% charge)
arrow_speed_max          720     (100% charge)
arrow_gravity            220
charge_time              1.1     seconds from 0% to 100%
knives_per_shot          2
knife_spread_max         26      degrees at 0% charge
knife_spread_min         4       degrees at 100% charge
knife_clash_radius       13
knife_clash_restitution  0.35
knife_clash_damping      0.55
knife_clash_spin         9       rad/sec after deflection
knife_reclash_damping_bonus 0.12 per previous impact
knife_reclash_damping_cap   0.82
knife_reclash_scatter       11   deterministic degrees

super_charge_per_clash   0.075   fourteen moving, clean clashes to fill
super_move_speed_min     80      owner speed required when the clash happens
super_waves              5
super_knives_per_wave    3
super_wave_interval_ticks 8      0.133s between waves at 60Hz
super_spread             10      narrow degrees per three-knife wave
super_speed_multiplier   1.08    relative to maximum normal knife speed

core_hitless_turns_to_announce 2 hitless executions before the one-turn warning
core_active_turns        2       execution windows available to collect it
core_collect_radius      22      pickup reach beyond the player body
ai_core_collect_value    280     less than the AI's lethal-path penalty
ai_core_approach_value   150     capped value for closing 200px toward the Core

aim_min_angle            -90     full 360°: straight down to straight up,
aim_max_angle            90        either facing covers the rest
aim_rate                 70      deg/sec, keyboard aiming only
trajectory_preview_time  4.5
first_gamepad_to         Player 2
```

`pilot_time_scale` is the main feel knob: 1.0 pilots in real time (0.75s of
movement takes 0.75s), 0.5 gives you twice as long to steer the same window.

A full jump (1.10s) deliberately **outlasts** the 0.50s movement budget. You
spend your controlled portion getting airborne, then momentum and gravity own
the remaining 0.25s of the execution window.

### Testing planning and execution durations

Hotkeys change them live, mid-match; current values show along the bottom:

* Planning: `F1` = 5s, `F2` = 8s, `F3` = 10s
* Execution: `F5` = 0.40s, `F6` = 0.75s, `F7` = 1.20s

### Shot windows

Per-level windows are in the Levels table above. The shape is consistent: flat
shots are denied by centre cover, low power gives wide forgiving arcs, and high
power buys a near-vertical mortar that hangs in the air for six-plus planning
phases. Both extremes keep knives frozen mid-flight across many turns, which is
the thing this prototype exists to test.

## Structure

| File | Responsibility |
|---|---|
| `scripts/GameManager.gd` | Phase machine, timers, ghost piloting + stamina, confirm/rollback, all input, platform damage, all tuning exports. Steps every entity explicitly — "frozen" is the default state and an execution window is an exact tick count. |
| `scripts/PlayerPlan.gd` | The recording: per-tick direction and jump, the tick the shot is pinned to, aim angle, power, and whether the committed shot is a super. Owns the aim vector / elevation math. |
| `scripts/Player.gd` | Player state, rendering, and `sim_step(dt, tick)` which replays one tick of the recording. Motion lives in a static, side-effect-free `step_state()`. |
| `scripts/Arrow.gd` | Knife integration, terrain/player hits, synchronised swept clash math, deflection and tumbling. The legacy class name remains internal. |
| `scripts/PredictionSystem.gd` | Knife trajectories and the uncontrolled `coast()` tail. Uses the *same* static step functions as the real simulation. |
| `scripts/PreviewLayer.gd` | Ghost path, stamina, two-ray knife fan, existing-knife trajectories, phase markers. |
| `scripts/TemporalCore.gd` | Visual telegraph and active-world rendering for the full-SUPER movement objective. |
| `scripts/UI.gd` | Compact central match HUD, optional control reference, banners and game over. |
| `scripts/Ai.gd` | The AI opponent. Ranks movements by safety, then searches shots coarse-to-fine against three hypotheses of what you might do. Sliced across frames. |
| `scripts/MenuLayer.gd` | Title screen: mode and starting level. |
| `scripts/OnlineLobby.gd` | Private-room create/join screen and room-code status. |
| `scripts/OnlineClient.gd` | Cloudflare HTTP/WebSocket client, heartbeat, reconnect and lockstep messages. |
| `backend/src/room.ts` | Hibernating Durable Object room: player slots, plan relay, state-hash barrier, rematches and expiry. |
| `scripts/Levels.gd` | The six arena layouts, wrap rules, platform hit points and authored Temporal Core sockets. |
| `scripts/Arena.gd` | Platform rendering, including damage state. |
| `scripts/Backdrop.gd` | Sky, stars and silhouette ridges. Deliberately low-contrast — the preview lines drawn on top are the information that matters. |
| `scripts/Effects.gd` | Impact sparks, platform shatters, hit bursts. Cosmetic only; runs on real time so it never consumes execution ticks. |
| `scripts/Sfx.gd` | Procedurally synthesised 8-bit sound effects and the voice pool. |
| `scripts/TimeStopLayer.gd` | Violet/gold frozen-world grade, clock motif, suspended motes, and freeze/release pulses. |
| `scripts/SuperFreezeFrame.gd` | Full-screen SUPER portrait composition, manga panel animation and real-time duration while combat ticks are paused. |
| `scripts/Phase.gd` | The phase enum, shared without a cyclic preload. |

Prediction only ever uses the current world state, existing projectile
velocities, and the asking player's own plan. The opponent's plan is never
simulated.
