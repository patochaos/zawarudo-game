# Class Lab: interception prototypes

Open **CLASS LAB** from the main menu. It starts with Eclipse versus a Duelist CPU in planning mode.

- **1 / 2 / 3 / 4:** select Duelist / Rook / Pulse / Eclipse for P1.
- **5 / 6 / 7 / 8:** select those same fighters for the CPU.
- **T:** switch between planning and real time.
- Selection and mode changes restart the encounter.
- Usual movement and hold/release throw controls apply. In planning, Shift commits; Backspace rewinds, Alt re-aims, comma/period adjust throw timing.
- In real time, H toggles the subtle aim guide and R resets. Esc returns to the menu.

This is an offline keyboard-accessible experiment. The normal local and online roster remains Duelist-only. Original Rook, Pulse and Eclipse implementations and assets are retained. All four lab fighters use Duelist movement; supers and the temporal core are disabled here so comparisons focus on ordinary throws. Planning uses the normal match rules; real time uses immediate respawns.

## Attacks

| Fighter | Commitment | Charge | Counterplay |
| --- | --- | --- | --- |
| Duelist | Two ballistic daggers | Narrows spread and increases speed | Dodge their routes, clash, use cover |
| Rook | One straight lance | Speed from 400 to 650 px/s | Vacate the lane or intercept it |
| Pulse | Harmless 180 px/s carrier; two daggers split at ±9 degrees | Fuse from 0.25 to 0.90 seconds of simulation | Intercept the carrier or cross before/after its split |
| Eclipse | One corona, decelerating outbound, holding, then retracing the original line | Range from 180 to 330 px | Intercept either pass or exploit its weapon cycle |

Rook pierces one fragile (one-hit) cover piece, retaining 55% speed. Permanent terrain stops it; another cover piece ends the throw. No body dash, guard, or Lost Frames.

Pulse's split daggers travel initially at 540 px/s and use normal dagger gravity, clashes and ricochets. The carrier does no contact damage and is destroyed by terrain. Its shrinking ring displays the fuse. No persistent orb field, radial blast, or secondary attack.

Eclipse travels outbound for 0.60 seconds, holds for 0.15, and returns over 0.60 seconds. The route is anchored to its original launch point, independent of the owner's movement. Terrain and body hits end the cycle. Only one corona can be active; another throw during its cycle does nothing. No manual recall or homing, and no unbreakable return.

All three special projectiles trade one-for-one with an intercepting projectile. Duelist dagger-versus-dagger physics remain unchanged. Clocks freeze during planning and advance continuously in real time.

## Test arena and previews

The lab uses static Crosshair Court with a fragile central pillar, providing a repeatable cover comparison. It does not expose wrapping or moving arenas. Planning forecasts use the prototype simulation and show Pulse's split paths. CPU attack evaluation and threat avoidance use those forecasts. Forecasts assume no intervening player/projectile collisions; they are conditional, just like Duelist forecasts.

The old character-specific supers, alternate attacks and movement do not run in the lab. These prototypes are not yet promoted into the main roster or online protocol.

## What to judge while playing

1. Can you explain a hit as a correct prediction of a route and time?
2. Can the opponent recognize and counter the threat before contact?
3. Does each weapon leave an opening after a bad read?
4. Does Pulse's delay add useful timing choices, and is its ring readable without a trajectory?
5. Does Eclipse's second pass reward planning without automatically covering every escape?
6. Does Rook gain enough from its single lane and cover penetration to compete with two daggers?

Automated checks cover mode entry/switching, movement parity, anchored return and forecast agreement, fuse timing, harmless carriers, splitting, cover penetration, projectile interception, and Eclipse's active-weapon limit. Visual captures cover the menu, three planning previews and continuous CPU execution. Human balance and feel are still to be evaluated.
