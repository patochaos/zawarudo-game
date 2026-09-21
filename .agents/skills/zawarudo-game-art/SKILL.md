---
name: zawarudo-game-art
description: Create, integrate or review Za Warudo game art in Blender and Godot.
---

# Za Warudo game art

Use the relevant `docs/GAME_DESIGN.md` sections and character contracts in
`docs/characters/`. Current runtime references govern integration; prototypes and
art handoffs do not authorize changing production behavior.

## Reuse and reproduce

- Use `tools/blender/` and `tools/art/` for existing authoring and packing workflows.
  Keep editable Blender sources under `art_source/blender/`, source sprites under
  `art_source/sprites/`, runtime art under `assets/art/`, and captures under `previews/`.
  Preserve `art_source/.gdignore` so source files do not enter Godot imports.
- Reuse the relevant script and record the command, inputs, output paths, camera,
  lighting, frame range and seed when applicable. Preserve editable sources and asset
  provenance. Avoid a new generator or dependency when the existing pipeline suffices.
- Read `docs/DUELIST_SPRITE_POLISH.md` for the current Duelist packing/import workflow,
  `docs/COMBAT_ART_POLISH.md` for SUPER and impact art, and
  `docs/ARENA_ART_POLISH.md` for arena art when those surfaces are affected.
  `art_source/blender/README.md` describes Executor experiments; it is not blanket
  authorization to activate experimental geometry or animation.

## Integrate without changing mechanics

- Keep sprite scale and ground/pivot anchors consistent across poses and facing directions.
  Check alpha edges, atlas gutters, import filtering/mipmaps and matching ghost silhouettes
  against the existing asset pipeline; do not impose one filtering mode on every asset.
- Godot's simulation owns movement, collisions, aiming, projectile origin and release,
  time-stop phases, SUPER timing and replay. Visual animation follows those values;
  it must not introduce root motion or change gameplay timing to fit new artwork.
- Check fighters, platforms, knives, ownership colors and impact cues at actual match
  scale. Decorative detail must preserve their readability in planning and execution.
  Keep reduced-flash behavior effective for affected flashes, shake and effects.

## Verify the affected presentation

Use current relevant tests and a rendered capture or play check. For sprites, inspect
alignment, both facings and affected poses at native match scale; include prediction
and replay when frame selection changes. For combat effects, inspect key stages and
reduced flashes. For arenas, inspect platform edges and projectile visibility.

Select existing suites under `tests/` for the changed surface: fighter visual/playable,
Duelist polish, combat art/SUPER/knife mechanics, or arena art. Run only relevant suites
and current required checks. Reuse visual capture scripts at the affected screen sizes;
current art captures commonly use 1280x720 and 1024x576. A headless test or successful
import alone does not establish rendered quality.

Report what changed, source/reproduction locations, checks performed and remaining
gaps. Distinguish rendered inspection from human playtesting and desktop evidence from
Web verification. Follow the project's `Play.bat` and explicit archive rules.
