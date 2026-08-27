# Rook simplified animated arena sprite v2

This is the Duelist-style readability pass for The Rook. It preserves her crest,
braid, tower shield, lance, palette and heavyweight movement while reducing each
frame to a few broad flat masses with a heavy near-black contour.

The six selected source sheets were generated with Codex built-in image
generation on 2026-08-26. Each prompt used the v1 Rook identity as canon and the
approved animated Duelist as the arena-readability target. The shared instruction
was: use roughly 10–14 large graphic shapes, flat fills, no gradients or material
texture, no small costume construction, and make the crest, crescent shield and
long lance readable at the final 58 px draw height.

- `idle-source.png`: four planted weight shifts
- `walk-source.png`: six broad shield-first steps
- `run-source.png`: six braced advances
- `air-source.png`: two rise and two fall poses
- `action-source-v2.png`: two lock poses and four BREAK LINE poses
- `defeat-source.png`: four recoil-to-kneel poses

`run-source-with-background.png` is a rejected generation retained for provenance;
the builder does not read it.

Build with:

```powershell
py -3 tools/art/build_rook_animated.py `
  art_source/sprites/rook-animated-v2 `
  assets/art/fighters/rook-animated-v2
```

The build emits 30 runtime frames in 384x256 cells plus alpha-matched planning
ghosts and a contact sheet.
