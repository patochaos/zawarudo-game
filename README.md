# ZAWARUDO — Tactical Knife Duel

> Diseño de juego: [`docs/GAME_DESIGN.md`](docs/GAME_DESIGN.md) — visión,
> pilares, contratos de experiencia y marco para futuras decisiones.

2D side-view 1v1 duel. Simultaneous planning, then a short burst of real-time
physics. Everything — players and knives — keeps its position and velocity
across the freeze, so a dangerous knife can hang in mid-air for several planning
phases while both players decide what to do about it.

Each Duelist throw releases a two-knife fan. Low charge is slow and wide for space
control; full charge is fast and nearly parallel. Knives from different throws
can collide in flight, ricochet, lose force, tumble, and remain lethal as they
fall through later execution windows.

A deflected knife can be struck again. Re-clashes retain progressively more
energy, accumulate tumble, and add a small deterministic glancing angle. The
result looks chaotic but replays exactly, preserving the planning contract.

### Knife feel: drag and debris

A knife bleeds forward speed but never fall speed. Gravity keeps pulling at full
strength while the throw runs out of steam, so the arc does not flatten into a
glide — it **collapses**: the knife stops advancing and drops. At `arrow_drag`
0.45 a knife keeps ~71% of its forward speed through one execution window, and a
flat full-draw throw reaches about two thirds of the arena before meeting the
floor instead of almost all of it.

Once a knife has been struck it falls under `arrow_clashed_gravity_scale` times
gravity. Nobody aimed it any more, so it behaves like debris and leaves the board
in about a second instead of drifting for the fifteen seconds its age cap allows.
This is what keeps a long exchange from silting up with stray knives — deflected
threats stay lethal on the way down, but they do come down.

Neither knob touches persistence in kind. A slow, falling knife is still a knife,
and still crosses planning phases; it simply stops being a flat line that owns
the whole arena. Both are live in the Free Play tuning panel, alongside a derived
readout of the flat full-draw reach and the forward speed kept per window.

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
| **`Play.bat`** | Canonical local launcher. Runs the latest working tree through Godot without an export step. |
| **`Play-Source.bat`** | Source-launch implementation used by `Play.bat`. Set `GODOT_DIR` at the top if Godot isn't in `D:\Godot`. |
| **`Build.bat`** | Exports unpacked Windows + Web folders. It never creates ZIP archives. |
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

1. Each player chooses their fighter in the Online lobby. Player 1 also chooses
   the arena, selects **CREATE PRIVATE ROOM**, then sends the
   six-character code to Player 2.
2. Player 2 chooses **ONLINE**, enters that code, and presses **JOIN**.
3. Both players use their own keyboard and mouse. Online, the controls on both
   computers are `A`/`D`, `W`, `S`, mouse aim, hold/release `LMB`, `Left Shift`
   to confirm, `R`/`RMB` to roll back, `F` to reset the path, and `T` for SUPER.
   Static Witch reserves `RMB` for her orb, so use `R` to roll her shot back.

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

The title screen keeps six primary choices: **PLAY**, **HOW TO PLAY**, **ONLINE**,
**CONTROLS**, **OPTIONS**, and **QUIT**. Every row is clickable; keyboard
navigation remains available (`W`/`S` select, `Enter` activate). The redesigned
command-dossier layout keeps navigation on the left and explains the selected
fate in a persistent field-note panel on the right.
**CONTROLS** opens a full reference sheet for the local device split, SUPER
activation, and playtest shortcuts.

**PLAY** groups the local variants in a second page:

* **VS AI — WIDE** — Player 2 is driven by `Ai.gd`; choose an authored arena,
  then configure both the human fighter and AI rival from the full roster.
* **VS AI — GRENADIER** — Player 1 replaces the normal knife fan with one
  bouncing timed grenade. The opponent remains the established knife-only AI.
  Choose an authored arena from the same submenu.
* **VS HUMAN** — opens character selection first. P1 and P2 independently pick
  **Dagger Duelist**, **The Velocity** (Dashblade), **The Static Witch**
  (Shock), or **Broodtail** (Chakram), then play with **open information**:
  both players see each other's plans and compose them simultaneously on the
  same machine.
* **TEAM BATTLE — 2 VS 2** — opens a FIFA-style formation screen. Keyboard and
  mouse plus up to three gamepads explicitly join, move to Team Crimson or Team
  Azure, select an arena, and lock their fate. Empty positions become CPU
  allies. Teams share the selected hit target; friendly fire still removes an
  ally for the execution window but awards no point.
* **3 PLAYERS** — Player 1 human against two independent AIs, using each
  arena's intermediate platform layout.
* **4 PLAYERS** — local free-for-all with Player 1 human and Players 2–4 driven
  by independent AIs. Each AI chooses a nearby living rival, so they fight one
  another as well as the human. The first player to reach the hit limit wins.
* **FREE PLAY** — see below.

**HOW TO PLAY** is a six-screen illustrated combat briefing. It explains the
plan/lock/execute loop, movement stamina, jumping and waiting, attack placement,
undo/reset/lock, and the win condition. The simulation is fully paused while it
is open, so every page can be read and navigated without completing a live input
challenge. Keyboard, gamepad, and touch equivalents appear beside every action.
**ONLINE** creates or joins a private six-character room; plans remain hidden
until both players lock. **OPTIONS** has its own page for sound level, hit
freeze, reduced flashes, high-contrast planning previews, and the
privacy-friendly local playtest log. High contrast gives preview paths and
labels dark keylines while separating players with yellow/cyan planning colors;
it does not alter collision, aim, timing, or fighter identity.

The playtest log makes no network request. It stores one JSON object per match
in `user://playtest-telemetry.jsonl` and overwrites
`user://latest-match-report.json` with the latest result. The result screen's
**COPY MATCH REPORT** action puts that compact report on the clipboard so a
tester can paste it into a bug report. Options can disable the log entirely.

## Free play — judging the feel

Turn structure makes movement hard to evaluate: you only ever see 0.75s of it at
a time. **FREE PLAY** drops the freeze entirely — continuous real-time control of
one player, no turns, no timer, no score, with Player 2 as an inert target to
shoot at. Platform destruction still works; the dummy just gets back up.

`A`/`D` run · `Space`/`W`/`↑` jump · mouse aim · hold `LMB` to draw, release to fire.

The left panel edits the tuning **live**, and whatever you set carries into a
real match afterwards:

`↑`/`↓` pick a value · `←`/`→` change it (hold `Shift` for ×5) · `Backspace`
reset all · `R` reset the arena · `F10` next level · `Esc` menu

It also shows what the numbers mean in play — jump apex and hang time, distance
covered in one execution window, time to reach top speed, best knife range at a
half draw — because those are what actually decide the feel, and working them
out from raw values by hand is the slow way to tune.

## The opponent

Each AI plays by the same rules you do. It sees the world state and every knife
in flight, and it does **not** read your plan. Instead it guesses: each turn it
plays out three hypotheses for what your feet might do this window — hold, run
left, run right — and prefers the shot that covers the most of them. That is the
same prediction problem the game asks of a human. In four-player mode, each AI
independently targets a nearby living rival and can choose another AI.

Its plan is hidden from you (dashes in its panel, no ghost or trajectory drawn),
because it plans blind and showing you its intent would be a one-way giveaway.

It drives the ordinary piloting API, so its movement is recorded, costs stamina
and replays exactly like yours. The search runs in ~3ms slices across frames
during its think delay — a full sweep costs ~35ms, which would otherwise be a
visible hitch at the top of every planning phase. Measured over 5000 frames of
live play: **worst frame 7.9ms, zero frames over budget.**

Against Velocity, the AI remains blind to the committed plan but tests a small
envelope of possible early/middle/late dash releases. Routes which escape that
body line score higher. A close projectile fired directly into the possible
front guard is treated as parry fuel, so the bot may reposition without firing
or choose a real over/under angle instead.

Difficulty knobs on the `Main` node: `ai_aim_jitter` (degrees of slop, default
2.0), `ai_think_min` / `ai_think_max`, `ai_slice_usec`.

## The loop

```
PLANNING (5s, frozen; shrinks after turn 3)  ->  COMMITTING (0.25s, locked)  ->  EXECUTING (0.75s, physics)  ->  PLANNING ...
```

* Execution begins when both players confirm (after a 0.25s commit beat that
  absorbs late input) **or** when the timer hits zero.
* Turns 1–3 retain the full 5-second planning window. Turns 4 and 5 fall to
  4.5s and 4.0s; turn 6 onward uses the 3.5-second floor. AI searches are sliced
  across frames and lock their best evaluated candidate if that clock expires.
* Nothing is cleared at a phase boundary. Knives are only removed when they hit
  terrain, hit a player, or leave the world.

## Match structure

**First to 5 hits takes the default match.** Local setup can select 3, 5, or 7
match lives before play. A hit does not end the round — it costs a
point and takes the victim off the board for the remainder of that window only.
Everything else carries on untouched: knives stay in flight, platform damage
stands, the other player keeps their exact position and velocity.

The victim respawns at the start of the next planning phase with **one turn of
invulnerability** (a white ring; knives pass straight through). A banner names
who was hit and shows the score for a couple of seconds.

When the match ends, the result screen stays on the winner. Press `R`, gamepad
`Y`, or **WATCH REPLAY** on touch to replay the latest **30 seconds** of execution
ticks at **1.5×**. Planning and commit pauses are not recorded.
Planning, commit delays, and SUPER freeze-frame introductions are omitted, so
the whole match plays back as one continuous action sequence. Offline, choose
the next rematch arena with `←`/`→`, the D-pad, or the result-screen arrows.
Online, Player 1 is the room host and chooses the shared rematch arena.

To keep a cautious match from lasting forever, each player also has a late-match
**SUPER** meter. It takes fourteen qualifying knife clashes to fill from empty.
A gold ring around the fighter marks a full meter. Once full, press the player's
SUPER toggle (`T` for P1 or gamepad `Y` for P2) to arm or disarm the upgrade, then draw
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

Score pips sit under the timer. `F10` cycles levels and resets the score. The
close-camera prototype remains available to internal tests but is hidden from
the player-facing mode menu.

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
* **Double jump.** Release and press jump again while airborne to spend one
  mid-air jump. Landing restores it; the ghost preview and execution replay the
  second impulse on the exact recorded tick.
* **Charging freezes the ghost.** Hold the shoot button mid-run — even mid-jump
  — and everything stops while you aim. Release and piloting resumes.
* **The shot is pinned to a point on the path.** Fire at the top of a jump and
  the knife fan leaves from the top of that jump, at that tick, even if you keep
  walking afterwards. Its angle and power are locked at that moment; only the
  launch point moves if you re-pilot.
* **One volley per turn.** Once you release the charge the reticle disappears.
  Rollback brings it back.

## Controls

| | Keyboard + mouse fighter | Any joined gamepad fighter |
|---|---|---|
| Walk the ghost | hold `A` / `D` | Left stick / D-pad |
| Jump / double jump (hold = higher) | `Space` / `W` / `↑` | `A` |
| Let time run | `S` | Left stick down |
| Aim | **Mouse** — free 360° | **Right stick** |
| Power | **Hold LMB** | **Hold R2** |
| Fire | release the button | release the trigger |
| Grenadier fuse | `1`, `2`, or `3` during planning | `L1` / `R1` |
| Toggle SUPER | `T` | `Y` |
| Confirm | `Left Shift` | `Start` |
| Rollback shot | `R`, or `RMB` except as Static Witch | `B` or `Select` |
| Reset path | `F` | `X` |

Playtest: `F8` fills P1 SUPER · `Shift+F8` fills P2 SUPER · `F7` enables
three-knife throws for the current local match.

Global: `F9` restart · `F10` next level · `M` mute · `H` hide the control bar ·
`Esc` back to the menu · `Enter`/`R` skip the replay. On the result screen:
`R` watch replay · `C` copy the match report · `←`/`→` choose the rematch level
· `Enter` rematch.

In local Vs Human, a Player 2 Grenadier cycles the 1/2/3-second fuse with
`L1`/`R1`. In Vs AI the Player 2 column is inert — the AI ignores it.

The Grenadier is retained only as its explicit **VS AI — GRENADIER** legacy
playtest; it is no longer part of character selection. Each normal throw
launches one grenade; its selected 1/2/3-second fuse
counts execution time from launch and pauses whenever time is frozen. A dagger
hit or a collision with another grenade detonates it immediately. Explosions
damage fighters in the visible blast radius, consume nearby daggers, respect
hard cover, and can chain into other grenades. A Grenadier SUPER still uses the
existing knife barrage for this first balance slice.

### Character prototype roster

**The Velocity** deletes one frame from every four steps: her horizontal
locomotion is 75% of the shared baseline, while the denied distance accumulates
as up to three **LOST FRAME** cells. Standing still or pressing into a wall earns
nothing. Her planned body dash—**CUT TO END**—automatically cashes the completed
cells into one extra route tick each; committing all three also adds one point
of front guard. The narrow blade remains a real moving collision surface which
can deflect daggers or intercept plasma, while attacks reaching the body from
above, below or behind still hit. The planning route is divided into manga
panels and shows the exact endpoint, stored-cell count and resulting guard.
A dash that meets a vertical border turns its remaining cut upward. Her SUPER
performs a full three-frame cut before applying its greater speed, duration and
guard life. Finishing a cut retains only 28% of its attack velocity, preventing
an upward dash from donating near-projectile momentum to the next movement plan.
Movement after CUT TO END cannot reload LOST FRAME cells until the next
execution window.

**The Static Witch** charges **PLASMA** with left mouse and **ORB** with right
mouse. Her horizontal locomotion is 110% of the shared baseline. Plasma gains
speed, range and visual weight with charge; partial shots fade before crossing
the full screen, while only a completed draw spans the arena. It remains a very
fast straight simulated projectile which can be
intercepted and heavily attenuated by a spent dagger. Each cast adds another
long-range, low-gravity persistent orb without dismissing her existing field. Orbs arm after a
short delay and can rest on platforms. Ordinary weapons trigger a small,
owner-safe pop, including when an orb's lifetime ends; plasma triggers the
large, fully dangerous shock combo, whose lethal radius grows with plasma charge.
Both blasts revector nearby weapons
instead of erasing them. Her SUPER launches an armed orb ahead of a plasma shot,
preserving an interceptible combo line.

**Broodtail**, the fourth selectable fighter, throws one **LIVING CHAKRAM** at
half the former launch speed. It follows the committed aim exactly. A wall or
hard platform pins it in place without stopping its spin; at the end of its
launch window, a midair chakram also holds at its exact position. It remains a
stationary threat through the following turn and begins returning on its third
turn. Chakrams launched on different turns recall independently. Any opposing
projectile impact destroys one immediately. Its SUPER retains the three-disc
forward spread under the same hold-and-return lifecycle.

The separate **critter summoner** concept is reserved for a later character.
Those summons would walk and climb platforms, acquire a fighter within a clear
reach radius, telegraph briefly, then pounce. Keeping that territorial,
delayed-pressure kit separate preserves Broodtail's returning-weapon identity
and gives the summons room for their own counterplay and limits.

In Online both computers use the **Player 1 — keyboard + mouse** column. The
server-assigned P1/P2 side changes the fighter and HUD label, not the local
bindings.

### Touch controls (mobile MVP)

On a touchscreen the Web build automatically shows a compact landscape overlay
during planning and hides it while time is executing. The floating bottom-left
joystick walks horizontally and lets time run when pushed down. The separate
**JUMP** button handles both jumps; pushing the joystick upward never jumps.
Drag in the right half of the arena to aim; hold
**DRAW** to charge and release it to fire. **UNDO**, **RESET**, **SUPER**, and
**LOCK** mirror the desktop actions. The top-left menu button and the touch
result card expose replay, rematch, menu, report-copy, and arena navigation
without requiring a keyboard.

Touch controls drive Player 1 in Vs AI and local modes, and the server-assigned
local fighter Online. Local two-player touch is intentionally not part of this
MVP. Set `force_touch_controls` on the `Main` node to test the overlay with a
mouse on a desktop; production detection uses the display's touchscreen flag.

**Rollback** un-fires the shot and drops your confirmation but *keeps* the
movement you piloted, so you can re-aim without rebuilding the run.
**Reset path** throws the recording away and refills stamina (the shot goes with
it, since its tick indexes into the path that just vanished).

Rebind the keyboard fighter by editing `K_P1` in `scripts/GameManager.gd`;
other local human slots are deliberately gamepad-only.

### Gamepads

In a local duel the first connected pad goes to **Player 2**, giving the
intended keyboard+mouse vs. gamepad setup. In Team Battle, each pad joins and
chooses a side independently; its ownership follows that fighter through
character selection and gameplay. Online, the first pad controls the
server-assigned local fighter. Aim source follows the local device in use.

### Descending: down + jump

Walking off an edge is not the only way down. **Down + jump** drops the fighter
through the ledge it is standing on, so changing level is a move you place in a
plan rather than a detour you walk.

Thickness is the rule, and it is one a player can read straight off the
silhouette: anything thinner than 30px is a ledge you can drop through, and
anything thicker — the floor, the walls, the roof of a tower — is not. Nothing
has to be marked.

A drop only opens the ledge you left. Ledges below stay solid, so you land on
the very next surface down instead of tunnelling past several; and because the
drop is recorded on its own channel of the plan, the ghost and the executed body
agree about it like they do about every other input. The AI does not use it —
it is a deliberate human verb, and the search has no way to value it yet.

## Levels

Seven arenas, cycled with `F10`. Layouts live in `scripts/Levels.gd`, and the HUD
names the wrap mode next to the level.

| # | Name | Wrap | Character |
|---|---|---|---|
| 1 | **Crosshair Court** | walled | Static permanent cover: the clean baseline for reading knife collisions and delayed danger. |
| 2 | **Endless Descent** | ↔ ↕ | Four-corner spawns, permanent side climbs and two vertical loops split by a hanging central pillar. |
| 3 | **Pendulum** | walled | Two wide lifts rise and fall in opposite phase either side of a permanent spine, with no second mechanic competing for attention. |
| 4 | **Pulse Chamber** | ↔ | Triggerable orbs bend fighters and persistent knives, then advertise a safe cooldown. |
| 5 | **Shattered Sanctum** | ↔ upper gate | Breakable stairs let players author the firing lanes of later turns. |
| 6 | **Foundry** | ↔ | One long shutter slides the whole width of the mid-field, sealing one half at a time. |
| 7 | **Collision Course** | walled | Converging ferries and a crossing pulse orb combine the earlier reads into one deterministic timing puzzle. |

The layouts borrow TowerFall's readable side architecture. Each is authored in
nested 2P, 3P and 4P variants: the trio adds one tactical shelf and the full
crowd adds another, preserving the arena's thesis while increasing safe landing
choices as simultaneous threats increase. P1/P2 start in the lower corners and P3/P4
in opposite upper corners, with permanent routes joining every height. Obstacles
shape player routes while broad air chambers let persistent knives accumulate.
Breakable shortcuts progressively expose new diagonal shots without deleting
the vertical traversal skeleton. Tests verify separated four-corner spawns,
reachable tiers, usable wrap portals and a minimum open-volume budget.

### Moving geometry

A platform may carry a `motion` block: an axis, a peak-to-peak distance and a
period in ticks. It then sweeps between its authored home and the far end of
that travel.

The position is a **pure function of the absolute simulation tick** (see
`scripts/Mover.gd`), never an accumulated velocity. Three things follow:

* It is frozen during planning and moves only while time runs, exactly like
  everything else in the world.
* Planning can project it. The ghost path, the coasted tail, existing-knife
  trajectories and the AI search all resolve against the geometry as it will
  stand on each tick of the coming window — not against the frozen snapshot. A
  plan that steps onto a lift that is about to rise is a plan you authored, and
  `KineticArenaTest` asserts the executed path matches the previewed one to
  within a thousandth of a pixel.
* Two browsers in a lockstep room cannot drift: the wave is a triangle built
  from integer arithmetic, and mover state enters the turn hash.

A body standing on a moving lip inherits its displacement, so a rising lift
carries its rider instead of clipping through them. Moving pieces wear a violet
cap and travel chevrons rather than the permanent gold, because that read has to
survive execution, when every planning overlay is stripped away.

`LevelLayoutTest` samples each arena across the full combined cycle of its
movers and re-checks every layout constraint at each pose, so an arena has to be
legal in every configuration it can actually reach.

### Pulse orbs

Orbs drift on their own rails. They are inert until a knife reaches one: the
orb detonates a radial forcefield, preserves the triggering knife, and relaunches
every knife inside its radius directly outward at full player-throw speed.
Fighter push keeps a linear falloff so the rim can be judged by eye. The orb
then goes dark for two execution windows, showing its recharge as pips.

Nothing is damaged — knives remain the only source of damage — but position,
momentum and every firing line inside the ring change, and the knives blown
outward stay in the world on ordinary throw gravity. Outward arrowheads and the
`DAGGERS OUT` label make that consequence public during planning.

### Close Camera mode

Disposable. It tests one coherent variant:

* a camera that pushes in while time is stopped and pulls out when it runs
* **Knife Court V3**, raised side shelves that leave the lower middle open, one
  high platform that moves only during execution, a jumpable centre blocker,
  low physical edge gates and horizontal wrap for fighters and knives
* a fixed two-knife throw: one follows the chosen aim exactly and the second
  leaves at the same speed with a small upward angle
* a lower ~129px jump, retaining the authored speed, air control and double jump
* a faster knife catching a slower one from behind transfers momentum into it
  and restores one spent ricochet
* the global HARD-surface ricochet rule remains active
* a 3.5s planning window instead of 5s, with the AI's deliberation scaled to fit
* **auto-ready**: finishing your action is the commitment, with no separate
  confirm press. A green `READY` badge appears over the fighter, drawn in world
  space so it survives the pushed-in camera. Execution begins as soon as
  everyone is ready, so a turn lasts as long as the slower player takes rather
  than as long as the timer allows.

  "Finished" deliberately means *the shot is placed and you have stopped
  driving for `prototype_ready_grace` seconds*, not *you have thrown*. Piloting
  after the shot — firing early, then running for cover behind your own knife —
  is one of the better moves in the game, and a confirmed plan stops accepting
  pilot input, so readying on the throw itself would silently delete it.
  Rollback still works and still un-readies: it un-fires the shot, so the plan
  stops being finished and the badge goes with it.

Select **RULESET · CLOSE CAMERA** from the main menu. Auto-ready deliberately
softens the explicit commitment beat that
§4.3 of the design document calls for; the short `prototype_commit_delay` is what
is left of it.

Delete `prototype_mode`, `scripts/DuelCamera.gd` and `Levels._proving_ground()`
together once it has answered its question, whichever way it answers.

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
are omitted automatically. Open seams carry cyan `WRAP` chevrons only where
collision is actually passable. Non-wrapping sides instead draw full-height
striped `NO PASS // HARD WALL` bulkheads. A vertical portal is marked at both
its ceiling and floor aperture; an unmarked open sky is not a portal, so knives
simply rise and return under gravity.

### Destructible cover

Terrain **never damages a player** — only knives do.

Platforms carry hit points and chip away as knives strike them, so cover is
temporary and the arena reshapes over a match. Remaining hits show as pips above
each piece, and it cracks and reddens as it takes damage. HARD geometry is cold
steel with rivets, a bright level accent and an explicit `HARD` label. BREAK
geometry is orange, diagonally striped, labelled `BREAK`, and carries HP pips.

A knife at or above `knife_ricochet_min_speed` bounces from HARD geometry at
any impact angle, retaining a tunable fraction of its speed for at most two
banks. The same knife embeds in BREAK geometry and damages it. The known-path
preview uses the identical material and force rule, so planned banks are shown.

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

Gameplay impacts keep their sharp procedural transients, including a
double-transient knife `clink–clink`, and now layer in quiet CC0 Kenney material
sounds for more body and variation. The imported title voice plays at natural
pitch when a match starts. The SUPER cut-in keeps its procedurally synthesised
voice-like chant; phase freeze, resume, orb blasts, and Temporal Core pickups
use distinct restrained layers so they mark the rhythm without dominating it.
Everything shares a 16-voice pool. `M` mutes.

## Reading the preview

* **Solid line from your feet** — the stretch you piloted.
* **Dot where it changes to dotted** — where your stamina ran out.
* **Dotted tail** — uncontrolled coast to the end of the window.
* **Ring labelled `END`** — where you finish the execution window.
* **Green→red bar over the ghost** — stamina left.
* **Two notched dagger arcs** — the real fan direction and draw strength. Low
  power opens the fan and droops early; full power reaches farther and pulls the
  pair almost parallel. The compact arc uses live dagger drag and gravity without
  revealing the complete landing point.
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
hits_to_win              5
respawn_invuln_turns     1
banner_duration          2.4

planning_duration        5.0
planning_shrink_after_rounds  3
planning_shrink_per_round     0.5
minimum_planning_duration    3.5
execution_duration       0.75
commit_delay             0.25

movement_budget          0.50    seconds of piloted control per turn
pilot_time_scale         0.5     ghost piloting runs at half real time
player_move_speed        260
velocity_move_speed_scale 0.75  horizontal target speed: 195 px/s
dash_exit_momentum_retention 0.28 inherited speed after CUT TO END completes
frame_debt_max_cells      3     completed LOST FRAME cells retained between turns
frame_debt_distance_per_cell 8  denied horizontal pixels required per cell
frame_debt_dash_ticks_per_cell 1 extra CUT TO END tick per committed cell
frame_debt_full_guard_bonus 1  extra front guard when all cells are committed
shock_move_speed_scale   1.10   horizontal target speed: 286 px/s
player_acceleration      1800
player_air_acceleration  900
jump_impulse             780     full hold: 211px rise, 1.10s air
jump_cut                 0.40    tap: ~45px, ~0.5s — fits inside one window
gravity                  1400
max_fall_speed           1200

arrow_speed_min          300     (0% charge)
arrow_speed_max          720     (100% charge)
arrow_gravity            220
arrow_drag               0.45    forward speed shed per second; never vertical
arrow_clashed_gravity_scale 2.2  a struck knife falls as debris
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
aim_rate                 70      deg/sec, reserved keyboard aiming rate
trajectory_preview_time  4.5
```

`pilot_time_scale` is the main feel knob: 1.0 pilots in real time (0.75s of
movement takes 0.75s), 0.5 gives you twice as long to steer the same window.

A full jump (1.10s) deliberately **outlasts** the 0.50s movement budget. You
spend your controlled portion getting airborne, then momentum and gravity own
the remaining 0.25s of the execution window.

### Testing planning and execution durations

Hotkeys change them live, mid-match; current values show along the bottom:

* Planning: `F1` = 5s, `F2` = 8s, `F3` = 10s
* Execution: `F5` = 0.40s, `F6` = 0.75s

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
| `scripts/Player.gd` | Player state, rendering, and `sim_step(dt, tick, from_tick)` which replays one tick of the recording. Motion lives in a static, side-effect-free `step_state()` that resolves against the geometry as it will stand at the end of the tick. |
| `scripts/Arrow.gd` | Knife integration, terrain/player hits, synchronised swept clash math, deflection and tumbling. The legacy class name remains internal. |
| `scripts/PredictionSystem.gd` | Knife trajectories and the uncontrolled `coast()` tail. Uses the *same* static step functions as the real simulation. |
| `scripts/PreviewLayer.gd` | Ghost path, stamina, charge-aware dagger arc reticle, existing-knife trajectories, phase markers, and optional high-contrast planning treatment. |
| `scripts/TemporalCore.gd` | Visual telegraph and active-world rendering for the full-SUPER movement objective. |
| `scripts/UI.gd` | Compact central match HUD, phase progress, portrait seals, banners, and the desktop result action panel. |
| `scripts/Ai.gd` | The AI opponent. Ranks movements by safety, then searches shots coarse-to-fine against three hypotheses of what you might do. Sliced across frames. |
| `scripts/MenuLayer.gd` | Title screen, local-mode/arena routing, controls reference, accessibility options, and contextual descriptions. |
| `scripts/TeamSelectLayer.gd` | Local device joining, Crimson/Azure side assignment, CPU formation fill, and Team Battle arena selection. |
| `scripts/OnlineLobby.gd` | Private-room create/join screen and room-code status. |
| `scripts/OnlineClient.gd` | Cloudflare HTTP/WebSocket client, heartbeat, reconnect and lockstep messages. |
| `backend/src/room.ts` | Hibernating Durable Object room: player slots, plan relay, state-hash barrier, rematches and expiry. |
| `scripts/Levels.gd` | The seven arena layouts and their 2P/3P/4P platform variants, wrap rules, platform hit points, mover motion data, orb placements and authored Temporal Core sockets. |
| `scripts/Mover.gd` | Tick-indexed motion for moving geometry and orbs. A pure triangle wave: position is a function of the absolute tick, never an accumulated velocity. |
| `scripts/Hazard.gd` | The pulse orb — drift, charge state, recharge countdown and the blast footprint drawn while time is stopped. |
| `scripts/DuelCamera.gd` | PROTOTYPE. Pushes in during planning and pulls out for execution. Disposable with the rest of `prototype_mode`. |
| `scripts/Arena.gd` | Platform rendering: gold caps for permanent, warm and cracked for breakable, violet caps and travel chevrons for moving. |
| `scripts/Backdrop.gd` | Low-contrast procedural scenery families assigned across all seven arenas: ruins, descent shafts, clockwork observatory, pulse cyan and foundry heat stacks. |
| `scripts/Effects.gd` | Impact sparks, platform shatters, hit bursts. Cosmetic only; runs on real time so it never consumes execution ticks. |
| `scripts/Sfx.gd` | Procedurally synthesised 8-bit sound effects and the voice pool. |
| `scripts/TimeStopLayer.gd` | Violet/gold frozen-world grade, clock motif, suspended motes, and freeze/release pulses. |
| `scripts/TransitionLayer.gd` | Reduced-flash-aware angular ink shutter used when entering modes and arenas. |
| `scripts/SuperFreezeFrame.gd` | Full-screen SUPER portrait composition, manga panel animation and real-time duration while combat ticks are paused. |
| `scripts/Phase.gd` | The phase enum, shared without a cyclic preload. |

Prediction only ever uses the current world state, existing projectile
velocities, and the asking player's own plan. The opponent's plan is never
simulated.
