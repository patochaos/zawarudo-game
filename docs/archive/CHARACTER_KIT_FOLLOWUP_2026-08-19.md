# Character kit follow-up — 2026-08-19

This follow-up supersedes the affected Velocity and Static Witch tuning notes in
`CHARACTER_BALANCE_ITERATION_2026-08-19.md`.

## Final identity changes

- Velocity can walk, jump, and drop during planning and Free Play again. Her
  horizontal target speed is 75% of the 260 px/s shared baseline, so the
  compact dash remains her decisive repositioning verb without making ordinary
  movement unavailable.
- Velocity's normal dash uses its original 8–15 tick duration and two-point
  front guard. One dash can still score at most one fighter.
- Static Witch's horizontal target speed is 110% of baseline.
- Static Witch casts no longer remove her previous orb. Every orb retains its
  own owner, arming timer, lifetime, collision, and combo state.
- Orb launch speed is 280–520 (previously 220–390). This preserves the requested
  longer field-building range while avoiding the first pass's 560 px/s extreme.
  The planning curve and live-orb HUD counter expose the larger field.

## AI support

- AI movement previews, planning ghosts, live planning, Free Play, and execution
  all use the same class speed multiplier. Velocity evaluates the full movement
  candidate set again, and its real dash path is scored against left, hold, and
  right opponent hypotheses.
- Static Witch selects the best combo opportunity across all owned orbs, mixes
  plasma between setup casts, and leads direct plasma against the same movement
  hypotheses. Lower AI charge is used for nearby orb placement so the new human
  maximum range does not make ordinary setups overshoot.

## Iteration

The initial locomotion pass used 60% Velocity speed, 120% Witch speed, one point
of dash guard, and a 560 px/s orb maximum. Its 49-match one-seed matrix was
aggregate-balanced (14 Dagger / 20 Velocity / 15 Witch), but a two-sided duel
audit exposed extreme matchups: Dagger–Velocity 14–0, Witch–Dagger 13–1, and
Velocity–Witch 10–4.

The retained second pass uses 75% / 110%, restores Velocity's two-point front
guard, and trims orb maximum speed to 520. On the same first seed block, duel
matchups improved from 7–0 / 7–0 / 6–1 to 5–2 / 5–2 / 4–3.

## Final deterministic matrix

First to five hits, 60-turn cap, all seven authored levels. Duels use two seed
rotations so both roster orders are represented; 3P and 4P use one rotation:

| Players | Dagger wins | Velocity wins | Witch wins | Unresolved |
|---|---:|---:|---:|---:|
| 2P (42 matches) | 11 | 12 | 18 | 1 |
| 3P (7 matches) | 3 | 4 | 0 | 0 |
| 4P (21 matches) | 3 | 11 | 7 | 0 |

Two-sided head-to-head results are Dagger 8–6 Velocity, Witch 8–6 Velocity,
and Witch 10–3 Dagger with one draw. Witch did not win this small 3P sample but
won seven 4P matches and led duels; Dagger trailed in 4P but won three matches
and produced 2.50 hits per appearance. Velocity is the crowd leader rather than
an exclusive winner. The acceptance target is distinct, viable kits—not equal
percentages—and no character is globally noncompetitive in this matrix.

## Verification

- `CharacterKitsTest`: restored Velocity movement, both locomotion profiles,
  simultaneous orbs, extended orb speed, safe pop, combo, and plasma interception.
- `DashbladeTest` and `ShockWeaponTest`: focused deterministic mechanics.
- `CharacterBalanceSimulation`: 2P, 3P, and 4P across all seven levels.
- `Test-Godot.ps1`: complete gameplay and journey regression suite.
