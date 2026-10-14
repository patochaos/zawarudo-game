# ZAWARUDO — Tactical Knife Duel

**Core-loop demo:** launch `Play.bat` and choose **LEARN TO PLAY** for three playable lessons, or **START DUEL** for an immediate match against the opponent ladder: five named CPUs played in order, each in its own arena, first to three hits. Turns have an eight-second planning limit by default. See the [tester guide](docs/PLAYTEST_GUIDE.md) and [current demo scope](docs/CORE_PLAYTEST.md). **CUSTOM MATCH** picks any arena, the number of fighters, each CPU's skill and the match length. Experiments require `Play.bat -- --dev-tools`.

### Interception test

Choose **INTERCEPTION** from the main menu for a Duelist match against a Standard
CPU, first to three hits. The compact Interception Court has a low passage under
a central platform and an exposed upper route. The core is announced immediately
and can become active for turn two.

This mode uses one jump, 450 px/s² air acceleration, and airborne momentum that
continues after recorded input ends. Walking brakes automatically; landing also
restores ground braking. Record **WAIT** (S by default) to brake in the air.
The CPU contests the crossing and responds to visible projectile threats. Planning
lasts eight seconds, execution 0.75 seconds, and movement control 0.5 seconds.
The knife pair and ground jump retain their authored settings. Interception uses
fixed test rules; leaving it restores your saved offline tuning.

### Offline game tuning

Choose **GAME TUNING** from the main menu to adjust 75 settings across timing,
movement, projectiles, knife physics, supers, and character abilities. Drag a
slider, type a number and press Enter, or use the On/Off switches. Each control
shows its unit, explanation, and default. Reset a single value, category, or the
whole profile at any time.

Changes save automatically on this device and apply to ordinary offline matches. Online
matches and teaching lessons always use standard rules; your saved choices return
when you play offline again. Jump duration stretches air time while preserving
jump height. Projectile lifetime controls how long knives survive in moving time;
path preview duration controls how much future flight the aiming guide reveals.

#### Tuning presets

Open **GAME TUNING > Presets**, choose **Apply preset**, then return to **START
DUEL**. Applying a preset replaces all 75 tuning values with authored defaults
plus that preset's changes. Individual edits then show **Custom tuning**. Presets
save on this device; online, lessons, and the fixed Interception test keep their
own rules.

| Preset | Design intent | Freeze / action | Knives | Double jump | Knife lifetime |
|---|---|---|---|---|---|
| **Tactical duel** (recommended) | Predict committed jumps and intercept landings | 10 / 0.75 s | 2 | Off | 9 s |
| **Clear read** | Learn trajectories with fewer simultaneous threats | 14 / 0.65 s | 1 | Off | 6 s |
| **Crossfire** | Read several intersecting threats across successive freezes | 10 / 0.75 s | 3 | On | 6 s |
| **Quick verdict** | Make practiced reads in shorter planning turns | 6 / 0.60 s | 2 | Off | 6 s |

Knife lifetimes count moving time; freezes do not consume them.

- **Tactical duel:** 600 px/s² air acceleration lets a fighter brake from the
  260 px/s run speed in about 0.43 s, inside the 0.50 s movement budget. A full
  reversal needs about 0.87 s. Knives travel at 280 to 680 px/s, with the normal
  0.45 s opening guide. The goal is readable commitment and meaningful landing
  threats while keeping the two-knife charge tradeoff.
- **Clear read:** slower ghost piloting and a 0.60 s guide give more room to
  understand the attempt. One knife removes the usual low-charge fan coverage,
  so this is a trajectory-learning preset rather than an easier way to hit.
  Supers use three waves of two knives, and knives can bounce from a wall once.
- **Crossfire:** slower, wider three-knife fans encourage area denial and
  collisions. The six-second lifetime limits accumulation on wrapping arenas;
  stronger debris gravity changes how deflected knives fall. One wall bounce,
  three super waves, and lower super gain per clash contain the extra volume.
- **Quick verdict:** 0.80 s charging, 0.65x ghost speed, and a 0.15 s commit delay
  leave more of the six-second freeze for deciding where to shoot. Its 0.40 s
  movement budget and 0.60 s action window keep a committed tail. Faster knives
  do not imply longer travel per turn because each action window is shorter.

These are starting points for playtesting the documented design goals. Compare
whether players can explain a hit or miss, exploit an earlier knife, and finish
their plan before the clock expires. Automated checks verify the preset values
and rules; they do not establish which preset feels best.

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
| **`Play.bat`** | Canonical local launcher. Runs the latest working tree with the authored Duelist arena sprite, without an export step. |
| **`Play-1v3-CPU.bat`** | Skips the menus into a four-fighter free-for-all: you (keyboard) against three STANDARD CPUs. Same as `Play.bat -- --vs-3-cpu`. |
| **`Play-Source.bat`** | Source-launch implementation used by `Play.bat`. Set `GODOT_DIR` at the top if Godot isn't in `D:\Godot`. |
| **`Build.bat`** | Exports unpacked Windows + Web folders. It never creates ZIP archives. |

### Arenas in a duel

Choose **Custom Match**, keep two fighters, then select an arena. A duel plays
the same five arenas as a crowd, with the crowd shelves cut (see Levels).
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
The Worker coordinates the lobby and exchanges locked plans; all clients then
simulate the exact same deterministic turn and compare a state hash before the
next one begins.

To play online:

1. The host chooses **ONLINE**, selects **4 PLAYERS** (the default) or **2 PLAYERS**,
   chooses the arena, and selects **CREATE PRIVATE ROOM**. Share the six-character
   code with the other players.
2. Each other player chooses **ONLINE**, enters the code, and presses **JOIN**.
   The lobby displays connected seats and starts only when every seat is connected.
3. Each player uses their own keyboard and mouse. Online, the controls on all
   computers are `A`/`D`, `W`, `S`, mouse aim, hold/release `LMB`, `Left Shift`
   to confirm, `R`/`RMB` to roll back, `F` to reset the path, and `T` for SUPER.

Plans remain private until every player confirms. A disconnected client retries
the room socket automatically; a detected state mismatch stops the match
instead of allowing screens to silently diverge. Four-player matches wait for
disconnected players to reconnect; they do not award a disconnect victory.
If someone closes the game entirely, create a new room together.

Four-player support requires the protocol 3 room server and matching clients.
The room server was updated on September 19, 2026; use the updated source on
every PC. The hosted website client has not been updated for four-player play.
See [four-player verification and rollout](docs/FOUR_PLAYER_ONLINE.md).

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

The public title screen has seven choices: **START DUEL**, **LEARN TO PLAY**,
**ONLINE**, **CONTROLS**, **OPTIONS**, **SEND FEEDBACK**, and **QUIT** (Reload Demo
in a browser). Developer mode replaces Feedback with Experiments and adds
Custom Match. Escape returns from submenus; on the title it focuses Start Duel.
Every row is clickable; keyboard
navigation remains available (`W`/`S` select, `Enter` activate). The redesigned
command-dossier layout keeps navigation on the left and explains the selected
fate in a persistent field-note panel on the right.
**CONTROLS** opens a full reference sheet for the local device split, SUPER
activation, and match controls. Its Player 1 column reads the live bindings,
and **REBIND KEYS** opens the list: pick an action, press Enter, then press the
key you want. A key drives exactly one action, so taking it from another leaves
that one unbound until you set it too; Escape cancels a capture and is never
itself bindable. **RESET TO DEFAULTS** restores the shipped layout. Bindings are
stored per install and only override the actions they actually name, so an action
added later still arrives with its default.

**OPTIONS** carries display, sound and accessibility:

| Row | Choices |
|---|---|
| **DISPLAY** | window at 1280x720, 1600x900 or 1920x1080, maximized, or fullscreen |
| **EFFECTS VOLUME** | throws, impacts, breaking platforms, freeze cues |
| **VOICE VOLUME** | the match-opening shout and the SUPER chant |
| **HIT FREEZE** | the brief stop on a landed hit |
| **FLASHES** | full, or reduced while keeping gameplay information |
| **PREVIEW CONTRAST** | strengthens planning lines and player-colour separation |
| **PLAYTEST LOG** | local anonymous match events for bug reports |

There is no music bed in the build, so sound splits along the axis that actually
matters: the loud voice cues against everything else.

**START DUEL** launches the fixed playtest immediately. **CUSTOM MATCH**, available
in developer mode, opens the lineup and rules screens described below.

**The lineup screen** is four slots side by side. Player 1 holds the keyboard and
mouse, Player 2 starts as a CPU, and slots three and four start open. Nobody
picks a head count: the match is however many slots are filled, from two to four.

Every occupied slot plays **The Duelist**, including CPUs and training dummies.
The Rook, The Pulse and The Eclipse are benched while development focuses on
predicting movement and placing projectiles across an opponent’s route. Their
code and assets are retained. Under each slot, the **control tile** walks the seat
through PLAYER, the three CPU skills, and OPEN; two fighters is the floor, so the
open option is skipped rather than offered and refused.

`↑`/`↓` moves between the fighter, the control tile and the confirm bar, `Tab`
walks to the next slot, and `Enter` readies a human seat or drops a CPU into an
empty one. A pad presses `A` to take the seat waiting for it — or the first open
slot — moves its own fighter with the d-pad, readies with `A`, and gives the seat
back with `B`. A pad that disconnects leaves a CPU behind rather than a dead seat.

**The rules screen** takes the settled lineup and adds what the whole table
shares: mode, arena, and match length. The arena is chosen next to a scale
drawing of its actual layout — solid geometry, breakable cover, spawn sockets,
hazards and the ends of every moving ledge — so a level is picked on its shape
rather than on its name. `Esc` steps back to the lineup with every pick intact.

The three modes are:

* **VS** — every fighter scores for themselves. With two slots this is the duel,
  played with **open information**: both players see each other's plans and
  compose them simultaneously on the same machine. With three or four slots it
  is a free-for-all, and each CPU chooses a nearby living rival so they fight one
  another as well as the human.
* **TEAM BATTLE** — sides alternate by slot (Crimson, Azure, Crimson, Azure), so
  which side you fight for is decided by which slot your device claims. Unclaimed
  positions become CPU allies. Teams share the selected hit target; friendly fire
  still removes an ally for the execution window but awards no point.
* **FREE PLAY** — see below. Scoring is retired and unclaimed slots become
  training dummies.

**LEARN TO PLAY** teaches movement, interception and persistent threats through
three playable exercises. Instructions appear before the timed attempt; every
playable turn has eight seconds. Failed attempts can be retried. Completing the
lessons starts the ladder duel against the first opponent. The old illustrated briefing is retained
as a developer reference, not the public onboarding route.
**ONLINE** creates or joins a private six-character room; plans remain hidden
until both players lock. **OPTIONS** has its own page for sound level, hit
freeze, reduced flashes, high-contrast planning previews, and the
privacy-friendly local playtest log. High contrast gives preview paths and
labels dark keylines while separating players with yellow/cyan planning colors;
it does not alter collision, aim, timing, or fighter identity.

The playtest log makes no network request. It stores one JSON object per match
in `user://playtest-telemetry.jsonl` and overwrites
`user://latest-match-report.json` after events, including unfinished matches.
**SEND FEEDBACK** on the menu and results opens an editable email draft workflow
for patochaos@gmail.com. The player can copy the report with their notes and
choose whether to send it. Options can disable logging entirely.

## Single player prototype — Fate Trial 01

Choose **EXPERIMENTS → FATE TRIAL** to enter **The Crossfire** as the
Duelist. A hostile Duelist commits first and its complete movement and knife
trajectory remain visible during planning. One earlier knife is already entering
from behind; survive three execution windows to clear the trial. A hit ends the
attempt, while hitting the hostile echo only disrupts it for that window.

The prototype uses the ordinary deterministic match, persistent-projectile and
replay systems. `Enter` retries the authored opening after either result.

## Real Time — continuous Duelist experiment

Choose **EXPERIMENTS → REAL TIME** for an endless Duelist-versus-CPU
session in Crosshair Court. Movement and hold/release dagger throws happen
immediately. Hits respawn fighters immediately; there are no planning windows,
lock-ins, scores or round breaks. The CPU uses the existing live sandbox AI.

Full trajectory and landing hints are hidden. A faint short aim stroke and a
charge bar while drawing are the only aids; `H` toggles both off/on.
`A`/`D` moves, `Space` jumps, mouse aims, hold/release `LMB` throws, `R` resets,
`M` mutes and `Esc` returns to the menu. The normal Sandbox keeps its full
previews and tuning panel. This mode is an offline feel test, not online play.

## Sandbox / Free Play — judging the feel

Turn structure makes movement hard to evaluate: you only ever see 0.75s of it at
a time. **EXPERIMENTS → SANDBOX** drops the freeze entirely and enters
Arena 1 immediately as the Duelist: one player, no turns, no timer, no score,
and no setup screens. The rules screen's **FREE PLAY** route reaches the same
live tuning mode with its chosen lineup. Platform destruction still works and
hit fighters immediately get back up.

`A`/`D` run · `Space`/`W`/`↑` jump · mouse aim · hold `LMB` to draw, release to fire.

The top lab strip changes the running test without leaving the arena:

`F1` P1 class (Duelist only) · `F2` arena · `F3` add/remove CPU · `F4` CPU class (Duelist only) · `F5` CPU
skill · hold `Shift` with a cycle key to go backward · `R` reset the arena

The optional CPU uses the normal blind-planning opponent and its real skill
presets in rolling live windows, so class and AI changes can be tested in place.

The left panel edits physics tuning **live**, and whatever you set carries into
a real match afterwards:

`↑`/`↓` pick a value · `←`/`→` change it (hold `Shift` for ×5) · `Backspace`
reset all · `Esc` menu

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

In the retained, benched Rook prototype, the AI remains blind to the committed plan but tests a small
envelope of possible early/middle/late dash releases. Routes which escape that
body line score higher. A close projectile fired directly into the possible
front guard is treated as parry fuel, so the bot may reposition without firing
or choose a real over/under angle instead.

Each CPU fighter carries its own skill preset on its slot plate, so a
four-player match can mix them (for example, P3 NOVICE and P4 RUTHLESS).
Every preset plans blind by the same rules — none of them ever sees another
fighter's plan. What changes is how much of the search that CPU spends and how
straight it throws:

| Preset | Aim slop | Routes shot-searched | Deliberation |
|---|---:|---:|---|
| **NOVICE** | 7.0° | 1 of 11 | 1.4–3.0s |
| **STANDARD** | 2.0° | 2 of 11 | 0.8–2.2s |
| **RUTHLESS** | 0.6° | 5 of 11 | 0.5–1.2s |

STANDARD is the baseline every balance pass was tuned at. All eleven movement
candidates are still ranked for safety at every preset; the number above is how
many of them get a full shot search on top. Setting the preset writes
`ai_aim_jitter`, `ai_moves_searched` and `ai_think_min` / `ai_think_max` on the
`Main` node as the legacy/default tuning baseline. Live local matches resolve
those values per CPU slot; `ai_slice_usec` remains the shared frame budget.

### The opponent ladder

Start Duel plays five named opponents in order. Each is a skill preset plus a
style: a few weights the planner adds to its route and shot scores
(`scripts/Opponents.gd`). The planner still ranks routes for safety and guesses
the same three hypotheses; the style only changes what it wants beyond
surviving. Beating the opponent the ladder points at unlocks the next one and
saves `ladder_progress` in the options file. Rematch replays the same opponent,
**N** starts the next after a win, and the result-screen arrows revisit any
opponent already reached.

| # | Opponent | Skill | Arena | Style |
|---|---|---|---|---|
| 1 | **THE APPRENTICE** | Novice | Crosshair Court | Neutral. Wide aim, one route searched. |
| 2 | **THE HOUND** | Novice, tighter aim | Clockwork Gallery | Ends its route close to you, throws early, quick low draws, accepts more risk. |
| 3 | **THE WARDEN** | Standard | Stilled Hall | Doubles its caution, keeps a mid distance and holds the knife unless a throw squarely covers a hypothesis. |
| 4 | **THE SPIRE** | Standard, three routes | Pulse Chamber | Climbs above you, keeps long range and prefers full draws late in the window. |
| 5 | **THE PHANTOM** | Ruthless | Endless Descent | Throws away from you so the knife arrives through the wrap seam, and favours airborne routes. |

Named opponents only exist in Start Duel. Custom matches, Interception and the
four-fighter launcher keep the plain presets above.

## The loop

```
PLANNING (8s, frozen; fixed each turn)  ->  COMMITTING (0.25s, locked)  ->  EXECUTING (0.75s, physics)  ->  PLANNING ...
```

* Execution begins when both players confirm (after a 0.25s commit beat that
  absorbs late input) **or** when the timer hits zero.
* Standard matches retain an eight-second planning window throughout the match.
  Confirming early still starts execution immediately after the commit beat.
  The optional shrink tuning remains available with a default decrement of zero;
  Fate Trial and Close Camera retain their own authored clocks.
* Nothing is cleared at a phase boundary. Knives are only removed when they hit
  terrain, hit a player, or leave the world.

### Plan editing and review

The compact timeline shows recorded movement in player color, a white throw
marker, and the dashed momentum/gravity continuation to the next freeze.
The thin budget mark separates available recording time from compulsory coast.
Only locally controlled fighters appear; online plans remain private.

- `Backspace` / gamepad `L1`: rewind the last six movement ticks (0.10s at 60 Hz).
  Earlier input and any throw still within that input survive; later input and
  throws are removed. The removed movement budget is refunded.
- Hold `Alt` / gamepad `R1` while aiming: adjust a placed shot without recharging.
- `,` / `.`: move a placed throw one simulation tick earlier/later. It stays
  inside the recorded route, and SUPER retains room for its full volley.
- These edits require an unlocked plan. Online submissions cannot be edited.
- `V` during desktop offline planning: review the last execution at 35% speed.
  `Space` plays/pauses; `,` / `.` steps; `V` / `Esc` returns. Planning and AI
  pause while this read-only view is open. Online and touch review are unavailable.

Existing knife previews emphasize the next freeze (`NEXT`) and show only one
fainter later window. These are conditional projections, not guaranteed hits:
new shots and interactions can redirect them. Ricochet samples represent one
simulation tick each and use the knife's existing ricochet budget and lifetime.

See [Duelist polish and playtest matrix](docs/DUELIST_POLISH.md) for the current
changes, benchmark arenas and experiments that still require player evidence.

## Match structure

**First to 5 hits takes the default match.** The rules screen selects 3, 5, or 7
match lives, and every CPU carries an independent skill preset. A hit
does not end the round — it costs a point and takes the victim off the board for
the remainder of that window only.
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
a short illustrated portrait cut-in in three beats: the world collapses to two
values (anticipation), the portrait strikes with **THE WORLD HOLDS ITS BREATH**
and the **STAND STILL** title over a rapid synthetic chant, and the panel tears
away along the thrower's facing as combat resumes (release). GameManager owns
the pause (`super_cutin_duration`); the cut-in only animates for the same
length. The portrait mirrors with the attacking side while the panel inherits
that player's color. If both supers share a tick, both introductions play
before the simulation advances.

### Event direction

`scripts/EventDirection.gd` is one grammar for the match's theatrical beats,
drawn in world space above the fighters and below the HUD, on wall time, never
touching simulation, replay or the lockstep digest. Each beat is a palette
preset (a multiply tint plus an additive lift) with its own return to base:

- **Lock**: confirming a plan swells the fighter into its held stance, drops a
  short spotlight around it and strikes **DECIDED** beside the body.
- **Impact**: a hit crushes the frame warm, crops it with a diagonal band
  through the contact and one hard shadow, and strikes **SNAP** (or
  **TIME // CUT** on the match-deciding hit). The grade returns in three hard
  steps. There is no generic white flash.
- **SUPER**: the three beats above.
- **Result**: the final world state holds under a subdued grade. The winner
  takes the poised lock stance as a victory pose inside a spotlight; the loser
  keeps the real defeat silhouette under a dim halo. The result panel is a band
  for the verdict, so both bodies stay in view.

Reduced flashes keeps every tint but drops the additive lift, removes the
stepped return and shortens each transition, so the information survives
without high-luminance jumps. Fighters also carry a one-pixel ink outline, a
player-colour rim, a brief hit flash and landing dust, all observed from the
authoritative state.

A hitless exchange also advances the **Temporal Core** clock. After two
consecutive hitless execution windows, one of the level's authored Core sockets
is marked for a full turn. If the following window is also hitless, the Core
materializes there for two execution windows. Touching it with the real player
(not merely the planning ghost) fills that player's SUPER meter. If both players
touch it on the same physics tick, both earn the reward. A hit during the warning
turn cancels the incoming Core; once materialized, it persists for its full
lifetime unless collected.

Score pips sit under the timer. With developer tools enabled, `F10` cycles levels and resets the score.

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
| Toggle SUPER | `T` | `Y` |
| Confirm | `Left Shift` | `Start` |
| Rollback shot | `R` or `RMB` | `B` or `Select` |
| Reset path | `F` | `X` |

Developer tools only (`Play.bat -- --dev-tools`): `F8` fills P1 SUPER · `Shift+F8` fills P2 SUPER · `F7` enables
three-knife throws for the current local match.

Global: `M` mute · `H` hide the control bar ·
`Esc` back to the menu · `Enter`/`R` skip the replay. On the result screen:
`R` watch replay · `C` copy the match report · `←`/`→` choose the rematch level
· `Enter` rematch.

In Vs AI the Player 2 column is inert — the AI ignores it.

### Benched character prototypes (unavailable in play)

As of September 4, 2026, **The Duelist is the only active fighter** in local,
online, free play and sandbox. The following kits are retained for future
iteration; these descriptions are reference material, not available choices.
`Roster.ORDER` controls availability; match entry points enforce it. Online
rooms containing unavailable kits are rejected to avoid mismatched simulations.
The old `--rook-proto` launch option also falls back to Duelist.
Character-specific prototype tests, balance simulations and visual captures
use explicit fixture assignments to exercise retained mechanics outside the
active roster. These do not make the benched kits available in play.

**The Rook** deletes one frame from every four steps: her horizontal
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

**The Pulse** charges **PLASMA** with left mouse and **ORB** with right
mouse. Her horizontal locomotion is 110% of the shared baseline.

**The lance falls.** It is fast, but it is ballistic like every other projectile
in the game, so hitting a distant target means leading it and aiming above the
mark. Charge buys a flatter arc as well as more speed and range, which is what
makes waiting for a full draw a decision rather than a formality. The planning
preview draws the true arc — not a direction line — and rings the head in red
where cover stops it. A spent dagger can still intercept the bolt and heavily
attenuate it.

She may hold **two orbs at once**. Casting a third detonates her oldest rather
than refusing the throw, so the field is a resource with a ceiling instead of an
accumulation. An uncollected orb holds its square for four execution windows.
Orbs arm after a short delay and can rest on platforms. Ordinary weapons trigger
a small, owner-safe pop, including when an orb's lifetime ends; plasma triggers
the large, fully dangerous shock combo, whose lethal radius grows with plasma
charge. Both blasts revector nearby weapons instead of erasing them. Her SUPER
places an armed orb ahead of her and fires a lance, as two separate threats.

*Why she changed:* a flat lance crossed 870px of the 1280px arena inside one
execution window, while a fighter can move about 195px. It was the one attack
that asked no prediction of its owner in a game built on prediction, and it read
in the balance matrix as a kit that beat every other kit. Giving it an arc put
her back inside the game's own rule rather than nerfing a number.

**The Eclipse**, a benched prototype, throws one **CORONA** at a
deliberate 300–520 px/s. It follows the committed aim exactly. Its first impact
with permanent HARD terrain ricochets at 82% speed; breakable cover or a second
terrain impact pins it in place without stopping its spin. At the end of its
launch window, a midair chakram also holds at its exact position. It remains a
stationary threat through the following turn and begins returning on its third
turn. Holding and releasing **RMB** or **L2** instead performs **ABSOLUTION**:
every active corona recalls at that point in Eclipse's route, consuming the
turn's attack. Movement during execution bends the dangerous return formation.
Once a return begins, the corona cannot be broken or expire. A blocked corona
skids along platform edges until it finds a clear lane home.

A normal corona has two visible integrity vows. A dagger spends itself to strip
one; plasma spends itself to strip both; a guarded CUT TO END may also clear it
by spending guard, but only before the return begins. The three SUPER coronas
retain one integrity each during their outbound and holding states. Chakrams
launched on different turns still track their own lifecycle independently.

The separate **critter summoner** concept is reserved for a later character.
Those summons would walk and climb platforms, acquire a fighter within a clear
reach radius, telegraph briefly, then pounce. Keeping that territorial,
delayed-pressure kit separate preserves The Eclipse's returning-weapon identity
and gives the summons room for their own counterplay and limits.

In Online all computers use the **Player 1 — keyboard + mouse** column. The
server-assigned P1/P2/P3/P4 slot changes the fighter and HUD label, not the local
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

Rebind the keyboard fighter in **CONTROLS > REBIND KEYS**; `DEFAULT_BINDINGS`
in `scripts/GameManager.gd` is only the shipped layout. Other local human slots
are deliberately gamepad-only.

### Gamepads

On the lineup screen a pad takes a seat by pressing `A`: the first seat whose
control tile already says PLAYER, otherwise the first open slot. Set Player 2's
tile to PLAYER for the intended keyboard+mouse vs. gamepad duel. `B` hands the
seat back, and a pad that disconnects leaves a CPU behind rather than stranding
a cursor. Whatever a pad
claimed there is the fighter it drives in play, in every mode. Online, the first
pad controls the server-assigned local fighter. Aim source follows the local
device in use.

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

Five arenas, one rule each, selected in match setup or visited in order by the
opponent ladder. Layouts live in `scripts/Levels.gd`, and the HUD names the wrap
mode next to the level. Following TowerFall's towers, every arena is authored
for four fighters and the duel is that board cut down: pieces tagged
`min_players` leave when fewer play, spawn sockets stay on permanent geometry
in every count, and the first arena is the deliberately readable one.

| # | Name | Wrap | Character |
|---|---|---|---|
| 1 | **Crosshair Court** | walled | Static permanent cover: the clean baseline for reading knife collisions and delayed danger. |
| 2 | **Clockwork Gallery** | ↔ | Three bridge gates and two low gates open and close on staggered clocks. Stand on one when it opens and you fall. |
| 3 | **Stilled Hall** | walled | Two stasis fields flank the centre pillar. Bodies and knives inside run at 35 percent speed, so a knife thrown in stays a threat for turns. |
| 4 | **Pulse Chamber** | ↔ | Staggered islands and paired triggerable orbs turn the side seam into a slingshot loop. |
| 5 | **Endless Descent** | ↔ ↕ | Four-corner spawns, permanent side climbs and two vertical loops split by a hanging central pillar. |

Moving platforms and breakable cover remain supported rules (the kinetic
contract tests run on a lift fixture outside the rotation), but no arena is
built around them any more. Pendulum, Shattered Sanctum, Foundry, Collision
Course and Lodestone Reach were retired in October 2026; their layouts live in
git history.

The layouts borrow TowerFall's readable edge architecture. Each is authored as
the four-fighter board; the trio and the duel are that board with its crowd
shelves cut, preserving the arena's thesis while matching the landing choices
to the number of simultaneous threats. Opening spawns use permanent,
stationary supports at meaningfully different elevations, but they are not
forced into one four-corner template. Obstacles shape player routes while broad
air chambers let persistent knives accumulate. Tests verify separated spawns,
usable wrap portals, legal mover sweeps and a minimum open-volume budget.

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
outward stay in the world on ordinary throw gravity. Outward arrowheads around
the blast ring make that consequence visible during planning without text.

### Wrapping

TowerFall-style: anything leaving a wrapping edge re-enters the opposite one,
**knives and players alike**. Two consequences worth knowing:

* On a wrapping arena there are multiple routes to your opponent, including
  attacks through the rear and vertical loop. Spawns are placed so none is a free hit.
* Collision uses seam copies of any platform or body near an edge, so standing
  on the edge works from either side.

Vertical wrapping happens at the actual screen edges (`y = 0` and `y = 720`).
A `wrap_y` level therefore needs a visible top gate just below the compact HUD,
with a gap in the middle third; its floor gap must sit inside that top gap.

Flipping a level is one line: add `"wrap_x": true` to its dictionary. Side walls
are omitted automatically. Open seams carry cyan directional chevrons only
where collision is actually passable. Non-wrapping sides instead draw
full-height striped steel bulkheads. A vertical portal is marked at both its
ceiling and floor aperture; an unmarked open sky is not a portal, so knives
simply rise and return under gravity.

### Timed shutters

A platform may carry a `cycle` block: a period, how many ticks of it the piece
is solid, and a phase, all in ticks. Like a mover, the state is a **pure function
of the absolute tick** (`Mover.cycle_solid`), so it is frozen during planning,
projected by the ghost path, the knife preview and the AI, and identical in a
lockstep room. An open gate leaves the collision set entirely: bodies fall
through it and knives fly through it. Gates draw a green lip with a draining
clock bar while solid, and a dashed outline with a filling bar while open; the
planning overlay marks any gate that changes state inside the coming window
with OPENS or CLOSES. Gates are never spawn or respawn supports.

### Stasis fields

A level may list `zones`, rectangles with a `time_scale`. Inside one, bodies and
knives integrate their motion at that scale: the same recorded inputs cover
less ground, a jump hangs, and a knife crawls. The rule is read by position
inside the two shared step functions, so every prediction bends exactly where
execution does. A knife thrown into a field is a trap that lands several turns
later.

### Destructible cover

Terrain **never damages a player** — only knives do.

Platforms carry hit points and chip away as knives strike them, so cover is
temporary and the arena reshapes over a match. Remaining hits show as pips above
each piece, and it cracks and reddens as it takes damage. Permanent geometry is
cold steel with rivets and a bright level accent. Breakable geometry is orange,
diagonally striped and carries HP pips. Neither relies on an in-world label.

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

planning_duration        8.0
planning_shrink_after_rounds  3
planning_shrink_per_round     0.0
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

With developer tools enabled:

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
| `scripts/PredictionSystem.gd` | Knife and plasma trajectories. Uses the *same* static step functions as the real simulation; player ghost paths are rebuilt in `GameManager.gd`. |
| `scripts/PreviewLayer.gd` | Ghost path, stamina, charge-aware dagger arc reticle, existing-knife trajectories, phase markers, and optional high-contrast planning treatment. |
| `scripts/TemporalCore.gd` | Visual telegraph and active-world rendering for the full-SUPER movement objective. |
| `scripts/UI.gd` | Compact central match HUD, phase progress, portrait seals, banners, and the desktop result action panel. |
| `scripts/Ai.gd` | The AI opponent. Ranks movements by safety, then searches shots coarse-to-fine against three hypotheses of what you might do. Sliced across frames. |
| `scripts/MenuLayer.gd` | Title screen: destinations, controls reference, accessibility options, and contextual descriptions. It holds no match configuration. |
| `scripts/Roster.gd` | The cast: names, portraits, movement and ability copy. The roster screen and the online lobby both read it, so a fighter cannot be described two ways. |
| `scripts/RosterLayer.gd` | The lineup screen: four slots, a fighter carousel inside each, the control tile that makes a seat a player, a CPU or nothing, and device joining and leaving. |
| `scripts/MatchSetupLayer.gd` | The rules screen: mode, match length, and the arena chosen beside a scale drawing of its layout. It emits the one configuration a local match is built from. |
| `scripts/OnlineLobby.gd` | Private-room create/join screen: the fighter grid, host arena, room-code entry and status. |
| `scripts/OnlineClient.gd` | Cloudflare HTTP/WebSocket client, heartbeat, reconnect and lockstep messages. |
| `backend/src/room.ts` | Hibernating Durable Object room: player slots, plan relay, state-hash barrier, rematches and expiry. |
| `scripts/Levels.gd` | The seven arena layouts and their 2P/3P/4P platform variants, wrap rules, platform hit points, mover motion data, orb placements and authored Temporal Core sockets. |
| `scripts/Mover.gd` | Tick-indexed motion for moving geometry and orbs. A pure triangle wave: position is a function of the absolute tick, never an accumulated velocity. |
| `scripts/Hazard.gd` | The pulse orb — drift, charge state, recharge countdown and the blast footprint drawn while time is stopped. |
| `scripts/Arena.gd` | Platform rendering: gold caps for permanent, warm and cracked for breakable, violet caps and travel chevrons for moving. |
| `scripts/Backdrop.gd` | Low-contrast procedural scenery families assigned across the five arenas: ruins, foundry heat stacks, sanctum stone, pulse cyan and descent shafts. |
| `scripts/Effects.gd` | Impact sparks, platform shatters, hit bursts. Cosmetic only; runs on real time so it never consumes execution ticks. |
| `scripts/Sfx.gd` | Procedurally synthesised 8-bit sound effects and the voice pool, on separate volume channels. |
| `scripts/TimeStopLayer.gd` | Violet/gold frozen-world grade, clock motif, suspended motes, and freeze/release pulses. |
| `scripts/TransitionLayer.gd` | Reduced-flash-aware angular ink shutter used when entering modes and arenas. |
| `scripts/SuperFreezeFrame.gd` | Full-screen SUPER portrait composition, manga panel animation and real-time duration while combat ticks are paused. |
| `scripts/Phase.gd` | The phase enum, shared without a cyclic preload. |

Prediction only ever uses the current world state, existing projectile
velocities, and the asking player's own plan. The opponent's plan is never
simulated.

## Developer tools

Normal local matches ignore the F1–F10 timing, SUPER, secret-volley, restart
and arena-switch shortcuts. To opt into those tools, run `Play.bat -- --dev-tools`.
Sandbox retains its live tuning controls inside Experiments. Tests stay in
`tests/` for development and are excluded from both export presets.
The fixed public duel restores the authored tuning before starting. Older
mode and arena documentation below the main-menu section describes developer
routes unless identified as part of [the current demo](docs/CORE_PLAYTEST.md).
