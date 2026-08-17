# Gilded Executor idle pose V1

## Status

Art-direction proof only. This asset is not wired into normal matches and is
not an animation source of truth. The legacy stick renderer remains the default
until this pose passes human review at real match scale.

## Files

- Chroma master: `docs/concepts/gilded-executor-idle-v1-chroma.png`
- Transparent runtime candidate: `assets/art/fighters/gilded-executor-idle-v1.png`
- In-game review harness: `tests/ExecutorIdlePoseVisualTest.gd`
- Local review capture: `previews/executor-idle-pose-v1.png`

## Provenance

- Tool: Codex built-in image generation.
- Date: 2026-08-17.
- Human direction: project owner plus Codex direction pass.
- Reference: `docs/concepts/duelist-visual-direction-v1.png`, using only the
  left-side original Gilded Executor design.
- Processing: generated on a flat chroma background, then converted locally to
  alpha with the installed imagegen `remove_chroma_key.py` helper.
- Blender: 5.2 detected locally, not used for V1.

## Final generation prompt

```text
Create one isolated, full-body, polished idle pose of The Gilded Executor from
the supplied original direction sheet. Preserve the white, black and muted-gold
split coat, clock-like chest clasp, gold forearm armor, angular formal boots,
dark swept hair and sharp aristocratic face. Use believable tall anatomy and a
calm theatrical asymmetrical contrapposto facing screen right. Keep the future
throwing arm close to the torso and empty. Render as premium cel-shaded 3D/2D
game key art with crisp contour and two-to-three value shading. Exactly one
complete character on a perfectly uniform #00ff00 chroma background, with no
floor, shadow, weapon, text, scenery or watermark. Avoid placeholder geometry,
circular joints, chibi proportions, bulky armor and generic superhero posing.
```

## Approval questions

- Does the silhouette read at the revised 128 logical-pixel art height?
- Are the long legs and split coat the right proportion for gameplay?
- Is the idle sufficiently theatrical without becoming an impact pose?
- Should the final 3D model preserve this face and collar shape?
