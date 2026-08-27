# Pulse simplified animated arena sprite v2

This is the Duelist-style readability pass for The Pulse. It preserves her bob
and acid forelock, white torso shard, burgundy costume masses, four rigid moth
wings, platform boots and tuning-fork baton while removing facets, wing veins,
trim and other noise that disappeared at Arena scale.

The six selected source sheets were generated with Codex built-in image
generation on 2026-08-26. Each prompt used the v1 Pulse identity as canon and the
approved animated Duelist as the arena-readability target. The shared instruction
was: use roughly 10–14 large graphic shapes, flat fills, no gradients or material
texture, solid blade-like wing polygons, and make the X-wing silhouette, white
torso and oversized boot wedges readable at the final 58 px draw height.

- `idle-source.png`: four contained wing pulses
- `walk-source.png`: six deliberate steps
- `run-source.png`: six forward drives
- `air-source.png`: two rise and two fall poses
- `action-source.png`: two lock poses and four conductor-cut poses
- `defeat-source.png`: four recoil-to-slump poses

Build with:

```powershell
py -3 tools/art/build_pulse_animated.py `
  art_source/sprites/pulse-animated-v2 `
  assets/art/fighters/pulse-animated-v2
```

The build emits 30 runtime frames in 384x256 cells plus alpha-matched planning
ghosts and a contact sheet.
