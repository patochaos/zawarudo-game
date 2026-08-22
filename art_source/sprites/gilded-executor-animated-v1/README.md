# Gilded Executor animated arena prototype v1

Built with Codex's built-in image-generation mode on 2026-08-21. The generated
images are source sheets, not runtime-ready assets: the pale checkerboard is
baked into the RGB pixels and is removed by
`tools/art/build_executor_animated_proof.py`.

## Shared art direction

Every prompt used the accepted simplified source sheet, the accepted four-pose
atlas, and the in-game scale capture as references. Shared constraints:

- small 2D arena-fighter sprite sheet; right-facing side view
- preserve the exact black spiky hair, angular profile, ivory split blade-cape,
  black bodysuit and boots, gold cuffs/ankle chevrons, and circular gold shoulder
  brooch
- flat five-color vector/cel treatment with thick black contour and no texture
- readable as a tiny silhouette during explosions; no background, labels,
  shadows, effects, weapon, extra limbs, or costume redesign
- transparent background requested (the generator returned a light checkerboard)

## Prompt set and frame order

- `idle-source.png`: exactly four horizontal frames — neutral, inhale, subtle
  weight shift with cape lag, settle.
- `walk-source.png`: exactly six frames in a 3x2 grid, row-major — a deliberate
  swagger walk based on the linked gameplay reference: upright chest, head
  slightly back, one hand locked at the waist, opposite arm hanging loose, and
  long heel-to-toe strides with restrained cape lag.
- `run-source.png`: exactly six frames in a 3x2 grid, row-major — right contact,
  recoil, passing, left contact, recoil, passing; forward torso lean,
  counter-swinging arms, delayed cape motion.
- `air-source.png`: exactly four frames in a 2x2 grid, row-major — compact rise,
  extended rise, apex/fall, landing brace.
- `action-source.png`: exactly six frames in a 3x2 grid, row-major — lock
  anticipation, lock hold, shot wind-up, open-hand release, follow-through,
  recovery. No weapon was requested because the projectile is authored by the
  game.
- `defeat-source.png`: exactly four horizontal frames — hit recoil, stagger,
  kneel/collapse, prone; no gore.

## Build

```powershell
python tools/art/build_executor_animated_proof.py `
  art_source/sprites/gilded-executor-animated-v1 `
  assets/art/fighters/gilded-executor-animated-v1
```

The runtime build contains 30 frames across `IDLE`, `WALK`, `RUN`, `RISE`, `FALL`,
`LOCK`, `SHOT`, and `DEFEAT`, plus parallel monochrome planning-ghost atlases
and a contact sheet. All frames use a 384x256 cell and one scale per generated
sheet so pose changes do not make the fighter breathe in size.
