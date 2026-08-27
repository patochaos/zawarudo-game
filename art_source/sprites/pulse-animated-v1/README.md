# The Pulse animated arena sprite v1

Built with Codex's built-in image-generation mode on 2026-08-26. The six
generated source sheets use the canonical master sheet at
`docs/concepts/shock-rework/pulse-master-sheet-v1.png` for identity and the
accepted arena-sprite workflow for layout and scale.

Every frame preserves the short black-violet bob, single acid forelock, pointed
black-cherry bolero, white torso shard, massive chrome-soled boots, four rigid
ultraviolet wing blades and one open tuning-fork baton. Movement stays controlled
and beat-driven; the wings rotate as hard panels and never imply free flight.

Frame order:

- `idle-source.png`: four horizontal frames — neutral, inhale, hip/wrist settle,
  return.
- `walk-source.png`: six frames in a 3x2 grid — contact, transfer, passing for
  each foot.
- `run-source.png`: six frames in a 3x2 grid — contact, compression, passing for
  each foot.
- `air-source.png`: four frames in a 2x2 grid — compact rise, extended rise,
  controlled fall, landing approach.
- `action-source.png`: six frames in a 3x2 grid — two lock keys followed by
  wind-up, conductor-cut release, follow-through and recovery.
- `defeat-source.png`: four horizontal frames — recoil, stagger, collapse and
  seated slump.

The generator returned a pale baked checkerboard. Build the transparent runtime
atlases, planning-ghost masks and contact sheet with:

```powershell
py -3 tools/art/build_pulse_animated.py `
  art_source/sprites/pulse-animated-v1 `
  assets/art/fighters/pulse-animated-v1
```
