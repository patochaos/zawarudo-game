# Character balance iteration — 2026-08-19

> Historical baseline. The later class-speed, compact-dash, and multi-orb
> changes are documented in `CHARACTER_KIT_FOLLOWUP_2026-08-19.md` and
> supersede affected tuning here. These results predate Broodtail's promotion;
> the current tournament harness includes Broodtail as the fourth kit.

## Scope

This pass covers the selectable prototype roster:

- Dagger Duelist (control character)
- The Velocity
- The Static Witch

The repeatable tournament lives in `tests/CharacterBalanceSimulation.gd`. It
drives every slot with the production planner, rotates roster order, uses the
real first-to-five match length, caps a stalled match at 60 turns, and reports
wins, hits, duration, unresolved matches, slot results, head-to-head results,
and per-level winners.

Run the full seven-level matrix:

```powershell
& 'D:\Godot\godot.cmd' --headless --path . `
  --script res://tests/CharacterBalanceSimulation.gd -- --samples=1
```

Use `--players=2`, `--players=3`, or `--players=4` for a focused pass. Increase
`--samples=2` to reverse/rotate roster slots with a second deterministic seed.

## Initial finding

The first 49-match screening pass (first-to-three, one seed rotation, all seven
levels) produced:

| Kit | Wins | Appearances | Hits / appearance |
|---|---:|---:|---:|
| Dagger | 18 | 49 | 1.51 |
| Velocity | 27 | 49 | 2.24 |
| Static Witch | 2 | 49 | 0.80 |

This result was not used as a raw-stat verdict. Code inspection showed that the
AI evaluated both new kits as imaginary ballistic dagger throws. Static Witch
also detonated her own orb before it reached a target, and Velocity's guard did
not process plasma despite plasma being described as interceptible.

## Retained changes

### Production AI and tournament validity

- Added kit-aware decision scoring instead of tracing a dagger trajectory for
  Velocity and Static Witch.
- Velocity closes distance, aims at a predicted body position, and selects a
  charge whose authored dash reach matches the target distance.
- Static Witch establishes an orb, waits until an armed orb is within a real
  covered blast opportunity, then aims plasma at it. In 3P/4P she immediately
  re-establishes a denied orb and selects clustered setup targets.
- Symmetric nearest-target ties rotate by turn instead of favouring the lowest
  player index.
- In 3P/4P, nearby score leaders receive a bounded target-pressure bonus. This
  limits bot-fed snowballs without changing any 2P decision.

### Velocity

- The moving front guard can spend one durability to intercept plasma. The
  collision uses the same relative swept-space contract as dagger guarding and
  produces a visible `PLASMA PARRY` clash.
- One committed dash can score at most one fighter, preventing a single action
  from awarding several points through a crowded lineup.
- Launch speed, duration, reach, damage, and normal two-point guard durability
  were left unchanged.

### Static Witch

- Small orb pop radius increased from 72 px to 84 px; the 190 px plasma combo
  radius is unchanged.
- A regular deny-pop is credited to the orb owner and does not damage that
  owner. The large plasma combo remains dangerous to everyone and is credited
  to the plasma shooter.
- A dagger interception spends the dagger and attenuates plasma to 45% speed
  instead of deleting the entire lance. A later intercept can still stop the
  slowed shot.
- Orb arming remains at the original 30 ticks. A tested 24-tick arming window
  did not improve results cleanly and was reverted.

### Visual communication

- Character selection now describes Velocity as `PARRY · COMMIT · BREACH` and
  Static Witch as `LMB PLASMA · RMB SAFE ORB`.
- Planning tags read `FRONT PARRY` and `ORB · SAFE POP`, exposing the retained
  interaction rules in the arena.
- Updated 2P selection, 4P roster, and match HUD captures were rendered and
  visually inspected at 3840×2160. Copy remains inside its panels and the new
  tags do not overlap the fighters or central HUD.

## Rejected experiment

Ending Velocity's dash and guard on a successful body hit did not reduce its
42-match 4P win count and reduced Static Witch's result instead. The experiment
was reverted; successful dashes retain their authored follow-through.

## Final acceptance results

All results below use first-to-five, the 60-turn cap, deterministic production
AI, and all seven authored levels.

### 2 players — 21 matches

| Result | Wins |
|---|---:|
| Dagger | 7 |
| Velocity | 6 |
| Static Witch | 7 |
| Unresolved | 1 |

Head-to-head:

- Dagger 4–3 Velocity
- Dagger 3–3 Static Witch, one Shattered Sanctum draw
- Static Witch 4–3 Velocity

### 3 players — 7 matches

| Kit | Wins | Hits / appearance |
|---|---:|---:|
| Dagger | 2 | 3.29 |
| Velocity | 2 | 3.86 |
| Static Witch | 3 | 2.43 |

All matches resolved; average length was 21.29 turns.

### 4 players — 21 matches

| Kit | Wins | Hits / appearance |
|---|---:|---:|
| Dagger | 6 | 2.54 |
| Velocity | 8 | 3.64 |
| Static Witch | 7 | 2.54 |

All matches resolved; average length was 18.33 turns. Dagger and Static Witch
both recorded 71 hits. Velocity remains the highest-throughput kit, but leader
pressure and the one-score-per-dash rule keep that throughput from becoming a
runaway match-win advantage.

### Combined acceptance set

Across 49 matches and 48 resolved winners:

- Dagger: 15 wins
- Velocity: 16 wins
- Static Witch: 17 wins
- Unresolved: 1

Every level produced wins for at least two kits across the 2P/3P/4P matrix. The
remaining draw is Shattered Sanctum's cover-heavy Dagger–Static Witch duel and
is retained as a level pacing observation rather than forced into a tiebreak.
