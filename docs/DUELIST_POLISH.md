# Duelist polish, September 4, 2026

## Intent

Win by predicting movement and placing a persistent projectile across a future
route. Improve authoring, readability and understanding before expanding the kit.

## Implemented

- Fixed eight-second standard planning window; early confirmation remains fast.
  Optional shrinking-clock tuning defaults to zero. Authored special-mode clocks
  retain their existing behavior.
- Compact local-player timelines: recorded movement, throw tick, movement budget
  boundary and the coast to the next freeze. No hidden opponent plan is exposed.
- Partial rewind with Backspace / L1, explicit re-aim with Alt / R1, and keyboard
  throw retiming with comma / period. Rewind resimulates the retained input prefix
  from the live body, preserving jump/drop behavior and refunding removed time.
  Confirmed plans and online submissions are protected from these edits.
- Two-window existing-projectile projections, with NEXT emphasizing the coming
  freeze and the later path subdued. These do not anticipate new collisions.
- Fixed ricochet preview indexing: one sample per simulation tick, with the
  existing knife's remaining ricochet allowance and lifetime respected.
- Three prioritized aftermath echoes: hits outrank destruction, which outranks
  incidental clashes. Echoes remain visible for 1.4 seconds.
- Offline desktop last-turn review at 35% speed, with pause and single-tick
  stepping. This simplified movement/knife view reads snapshots without applying
  them to the simulation. Opening it pauses planning and AI; online and touch
  review are unavailable. Full-match replay remains available after the result.
- Quieter permanent-platform rails and rivets, preserving material/mover cues.
- Arena selection now gives actionable interception exercises for Crosshair
  Court, Shattered Sanctum and Pendulum. Geometry and arena IDs are preserved.
- Tutorial copy explains the timeline, two-dagger charge tradeoff and editing.
- Local telemetry records planning timeouts, retained rewind ticks, and knife-hit
  age/clash/ricochet counts. These supplement existing lock/charge/core events.

## Benchmark playtests

Use two Duelists and the same match length and opponent difficulty for each
comparison. Change one variable at a time. These are proposed human playtests,
not claims of measured improvements.

| Arena | Exercise | Observe |
|---|---|---|
| Crosshair Court | Catch landings with slow fans; compare fast bank shots | Opening approach time, charge selection, understandable misses |
| Shattered Sanctum | Spend a throw opening cover, then exploit the lane | Whether destruction creates usable follow-up routes; safe camping |
| Pendulum | Intercept after a lift ride or vertical wrap | Whether landing timing and portal return are readable |

The latter two are existing advanced arenas, not newly simplified maps. Use the
static court as the control when judging projectile and movement changes.

For each match, record unfinished plans/timeouts, low-versus-high charge use,
hits from earlier windows, and whether players can explain each hit or miss.
The telemetry provides events; understanding and intention require asking players.

## Experiments still requiring evidence

- Compare the existing local F7 three-dagger variant against the two-dagger
  baseline. More hits alone are not evidence of better interception play.
- Test a recorded fast-fall only after the existing jump/wait/rewind controls
  have been evaluated. No fast-fall, air dash or divekick is added by this pass.
- Rework spawn separation or geometry only after measuring approach time,
  dominant routes and camping. Shared arena simulation changes need coordinated
  online compatibility work.
- Evaluate SUPER's five three-dagger waves and Core contest outcomes before
  changing coverage, resource rewards or timing.
- Additional Fate Trial lessons, new animations/audio, and camera changes remain
  follow-up production work. Existing attacks, movement and sound are retained.

## Verification

`tests/DuelistPolishTest.gd` covers retained airborne movement, stamina refund,
throw preservation/removal, timing clamps, submission protection, private
timeline visibility, ricochet timing/budget and aftermath prioritization. It also
checks that last-turn review pauses time without changing the live digest.

Use source Godot tests and visual captures. `Play.bat` remains the local launcher.
No release archive or deployment is part of this pass.
