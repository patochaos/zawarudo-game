# Eclipse simplified animated arena sprite v1

This is The Eclipse's first authored Arena set. It begins at the same strict
shape budget as the simplified Duelist, Rook and Pulse rather than carrying the
detail of the character master sheet into a 58 px figure.

The six selected source sheets were generated with Codex built-in image
generation on 2026-08-26. The canonical master sheet controlled identity while
the approved Duelist runtime set controlled simplification: roughly 10–14 broad
flat shapes, thick near-black contour, no material texture, no small costume
construction and no facial detail.

The permanent silhouette anchors are one smooth four-clasp aureole, the shaved
head, a bold white crescent mantle, one wine-red vertical body column, exactly
two long white ribbons and flared near-black legs. Dangerous twelve-bladed
coronas are deliberately absent from the body sheets because the live projectile
system owns them independently.

- `idle-source.png`: four contained liturgical weight shifts
- `walk-source.png`: six measured processional steps
- `run-source.png`: six long smooth gliding strides
- `air-source.png`: two ascents and two controlled descents
- `action-source.png`: two lock poses and four empty-hand DECREE gestures
- `defeat-source.png`: four recoil-to-kneel poses

Build with:

```powershell
py -3 tools/art/build_eclipse_animated.py `
  art_source/sprites/eclipse-animated-v1 `
  assets/art/fighters/eclipse-animated-v1
```

The build emits 30 runtime frames in 384x256 cells plus alpha-matched planning
ghosts and a contact sheet.
