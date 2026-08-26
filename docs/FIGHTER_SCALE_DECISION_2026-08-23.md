# Fighter scale — decision and evidence

**Backlog item 22. Closed 2026-08-23. The framing was wrong: the fighters are
not too small.**

The backlog recorded item 22 as "32×48 fighters in a 1280×720 arena read as
small stick figures. Close Camera was the previous answer and is now retired, so
the answer has to come from arena dimensions or a fixed camera zoom."

Both of those levers are wrong, and a third one was already approved at Gate 0.

---

## What was measured

Character height as a fraction of frame height, taken from official gameplay
screenshots at their published resolution. ZAWARUDO's figure is exact, from
source; the peers are measured off pixels and carry the stated confidence.

| Game | Character height | Share of frame | Confidence |
|---|---|---|---|
| TowerFall Ascension | ~18 px of 240 | **7.6 %** | high — two archers measured independently, 7.6 % both times |
| **ZAWARUDO** | 48 of 720 | **6.7 %** | exact |
| Duck Game | ~43 px of 720 | ~6.0 % | medium |
| Samurai GUNN 2 | — | ~4 % | low — action-obscured crop |
| Nidhogg 2 | — | ~30 % | not a peer: camera-following side-scroller, not a single-screen arena |

**ZAWARUDO sits mid-band among single-screen arena fighters.** TowerFall's archer
is 12 % taller relative to the frame. Nobody perceives 12 % as "small".

Two further measurements, same screenshots:

- **Ink inside the footprint.** Opaque fraction of the character's own bounding
  box: TowerFall **45 %**, ZAWARUDO **28–30 %**.
- **Brightness rank.** The fighter's bright pixels out-shine 96–97 % of a
  ZAWARUDO frame, against 99 % of a TowerFall frame — roughly three times as
  much competing bright material on screen.

`previews/fighter-scale-peer-comparison.png` shows all three normalised to the
same on-screen height, so only drawn mass differs. `.gitignore` excludes
`/previews/*.png`, so that file needs `git add -f` if this evidence is to travel
with the document.

## What the comparison actually shows

Coverage is not the variable. The animated Executor measures 30 % ink — two
points above the stick figure's 28 % — and reads far better than either the
stick figure or TowerFall's archer. What separates them is **arrangement**: a
silhouette reads as a character, a wireframe with joint dots reads as a diagram.

So the problem is neither scale nor coverage. Two of the four fighters have the
treatment, and one of those only in Player 1's slot.

---

## Ruling

**1. Camera zoom is structurally unavailable, permanently.**

Not "expensive" — unavailable. This is a plan-the-whole-turn game. `PreviewLayer`
draws ghost paths and projected kinetics across the whole board during planning,
and several arenas wrap. You cannot zoom in *and* see the board you are planning
on. That is why Close Camera was retired, and it is why any successor would be
retired too. Do not reopen this line.

**2. Arena dimensions and the collision box stay as they are.**

Shrinking the world to 1024×576 would buy about 1.6 percentage points of apparent
size and cost every authored layout, every spawn socket, every movement and
stamina distance, the AI's search ranges, and every number in
`CHARACTER_MOVEMENT_BALANCE_2026-08-21.md`. It would land directly on top of the
open balance work (item 18). The 32×48 box is a protected contract besides.

**3. The lever already exists, and it is visual-only.**

`docs/PRODUCTION_ROADMAP.md`, Gate 0 exit criteria:

> Art may occupy roughly **56×82–64×92 logical pixels** while collision remains
> exactly 32×48.

`FighterSkin.visual_bounds` already defaults to `Rect2(-32, -68, 64, 92)` — the
top of that envelope. No shipped skin uses it:

| Skin | `visual_bounds` height | Used by |
|---|---:|---|
| `FighterSkin` default | **92** | nothing — the sanctioned envelope |
| `animated_rook` | 54 | The Rook, any slot |
| `animated_executor_proof` | 54 | The Duelist, **Player 1's slot only** |
| `simplified_executor_proof` | 54 | not wired into `_fighter_skin_for` |
| `executor_prototype` | 128 | only when `simplified_fighter_proto_enabled` is off |

`_fighter_skin_for()` returns `null` for everything else, which falls back to the
stick renderer. So today: **The Rook and a Player-1 Duelist are drawn; The Pulse,
The Eclipse, and a Duelist in any other slot are still sticks.** The same Duelist
is a character in P1 and a wireframe in P2.

The drawn fighters declare **54 px of visual bounds against a sanctioned 82–92**
— about 59 % of the height the roadmap already approved. `animated_executor_proof`
says why in its own comment: the 224 px authored body was mapped to "the same
~51 px perceived height as the accepted single-pose proof". The art was
calibrated **down**, to match the legacy stick figure it was replacing.

### Why this is an art task and not a number

`sprite_draw_rect` cannot simply be enlarged. The aim anchors do not come from
the sprite — `FighterVisual.aim_muzzle_global()` reads `Player.muzzle()`, and
those are simulation constants:

```gdscript
static func shoulder_at(pos: Vector2) -> Vector2:
	return pos + Vector2(0.0, -6.0)

func muzzle_at(pos: Vector2) -> Vector2:
	return shoulder_at(pos) + aim_dir() * 22.0
```

Knives launch from that point, the AI aims from it, and the lockstep digest
carries what it produces. It cannot move. Scaling the sprite by the 1.59× needed
to reach 92 px would leave the drawn hand about **13 px** from the authoritative
muzzle, against a Gate 0 budget of 1 px.

**So the constraint on the art is: a fighter standing 82–92 px tall must place its
hand 22 px from a point 6 px above its own origin — about 24 % of body height.**
The current 58 px art puts the hand at 22 px of a 58 px body, or 38 %, which is
close to natural human proportion. A taller figure at the same fixed reach has to
be stockier — proportionally shorter arms, a heavier torso — or drawn with the
weapon arm tucked so the visible hand falls inside that radius.

That is not a defect in the art already made; it is the brief nobody wrote down.
It also happens to describe how TowerFall's archers are proportioned, which is
why they carry so much more mass at the same screen height.

---

## What replaces item 22

All three of the following are **art-pipeline work, not code changes.** Nothing
in `FighterSkin.gd` or `FighterVisual.gd` was edited for this decision.

- **Re-render at the real envelope.** Author the fighters at 82–92 px with the
  hand at a 22 px reach, per the constraint above, instead of calibrating down to
  the legacy figure's ~51 px.
- **The Pulse and The Eclipse have no animated skin at all.** `_fighter_skin_for()`
  returns `null` for them, so they fall back to the stick renderer. There is no
  art to wire up.
- ~~**The Duelist's Player-1-only rule.**~~ **DONE 2026-08-24.** The rule existed
  because the animated skin had `sprite_tint = Color.WHITE` and a fixed palette,
  so a second slot would have put two identical gold figures on the board —
  `tests/SimplifiedFighterPlayableTest.gd` pinned exactly that. It is lifted now
  that `FighterSkin.apply_player_identity()` gives each slot its own accent: a
  34 % wash on `sprite_tint`, plus `palette.body` set to the player colour so the
  label, ground shadow, invulnerability ring and SUPER arc follow the player
  rather than the artwork. The Rook takes the same treatment, so two players who
  pick one fighter stay legible. `previews/identity-two-duelists.png` and
  `previews/identity-four-slots.png` are the reference shots.
- **Item 27 is the other half.** `HARD` is stamped on nine platforms plus two
  wall labels, and the platform rails, clock ring and `TIME // SUSPENDED`
  overlay all out-shine the fighters. That is the 3 % of the frame currently
  beating them on contrast. Quieting it is cheap and raises the fighter's rank
  without touching the fighter at all.

## Method, so this can be re-run

Peer screenshots were pulled from the Steam store API (`appdetails`) at
published resolution, characters located by eye, bounding boxes measured against
a pixel ruler, and ink coverage computed as the fraction of pixels inside the box
differing from the median colour of a 6 px ring outside it. Brightness rank is
the 80th-percentile luminance inside the box, expressed as a percentile of the
whole frame. Reported confidence reflects how cleanly the character separated
from its background, not the arithmetic.
