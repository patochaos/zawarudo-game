# Velocity — Lost Frames prototype — 2026-08-20

## Rule

Velocity moves at 75% of the shared horizontal baseline because every fourth
frame is withheld. Only real horizontal displacement made while directional
input is active creates Frame Debt; idle time, coasting and pushing into a wall
create none.

Denied distance persists between execution windows as three completed LOST
FRAME cells plus deterministic sub-cell progress. CUT TO END automatically
commits every completed cell available on its release tick.

## First-pass tuning

- 8 denied horizontal pixels complete one cell.
- Each committed cell adds one simulated dash tick.
- Committing all three cells adds one front-guard durability.
- An ordinary empty dash retains the previous speed, duration and two-point
  guard. The normal one-fighter score cap remains.
- A completed dash retains 28% of its attack velocity. At maximum normal charge
  this leaves 274 px/s instead of 980 px/s, close to ordinary run speed.
- Once a dash fires, movement during the remainder of that execution cannot
  generate new cells. The next execution clears the earning lock.
- SUPER behaves as a full three-cell cut, clears partial progress, then applies
  its existing speed, duration and guard bonuses.

## Planning contract

The release tick matters. Movement before release can complete another cell;
an early dash trades that future reach for immediate pressure. The preview
replays the real ghost path, projects the cells available at release, and draws
the resulting endpoint, guard count and storyboard panels. AI candidates use
the same path projection.

The rival AI does not inspect Velocity's private plan. It evaluates a bounded
threat envelope consisting of full-power dashes from early, middle and late
release moments across the existing left/hold/right footwork hypotheses. It
prefers movement routes which leave those lines. A direct dagger or plasma shot
within closing range is discounted as probable front-guard fuel; movement
without firing remains a legal fallback if every available shot is worse.

## Presentation

- The duel HUD renders three FRAME cells beside Velocity's identity.
- Slow-motion afterimages are enclosed by broken manga panels.
- The dash route uses storyboard cells instead of generic speed dots.
- Live dashes collapse one additional trailing panel per committed cell.

## Evaluation questions

1. Does moving before firing feel like loading an attack rather than paying a
   movement penalty?
2. Is three extra ticks enough to notice without invalidating spacing knowledge?
3. Is the full-debt guard bonus readable when projectiles cross the route?
4. Does automatic full spending create interesting timing decisions, or should
   charge later select how many cells to commit?

## Initial deterministic duel audit (before exit-momentum nerf)

One production-AI seed across all seven arenas produced 21 resolved duels:

- Dagger 3–4 Velocity.
- Static Witch 4–3 Velocity.
- Static Witch 5–2 Dagger.
- Velocity won 7 of 14 appearances and averaged 3.93 hits.

The slice is intentionally too small and one-sided to establish final balance,
but the new reach did not create an immediate matchup runaway or stalemate. A
two-sided multi-seed matrix remains appropriate after human feel testing.

Focused Dashblade, character-kit, online-lockstep and replay tests pass.

## Post-counterplay duel audit

The same one-seed, seven-arena matrix was rerun after adding dash-aware AI
counterplay, 28% dash-exit momentum retention, and the post-dash debt lock:

- Dagger 3–4 Velocity.
- Static Witch 4–3 Velocity.
- Static Witch 5–2 Dagger.
- Velocity won 7 of 14 appearances and averaged 4.00 hits.
- All 21 duels resolved, averaging 31.14 turns instead of 28.29.

The matchup splits remained stable in this small sample. Duels became roughly
10% longer because opponents now evade dangerous dash lanes and sometimes
withhold a frontal projectile, but the audit produced no stalemates. This is a
useful regression result, not sufficient evidence that the final tuning is
solved.
