# Gilded Executor — 3D production contract

Status: model sheet V1 and Blender scene prepared. No 3D mesh is approved yet.

## Direction

The game remains 2D. Characters are authored as stylized 3D models in Blender, then rendered through an orthographic camera into deterministic 2D sprite atlases for Godot.

This gives us consistent identity, lighting, proportions and animation while preserving the graphic readability and freeze-frame palette changes of a 2D fighting game. Runtime 3D is not part of the first production gate.

## Approved visual source

- Character: Gilded Executor V1.
- Palette: ivory/white, gold and black.
- Hair: the original short angular hairstyle.
- Height guide: 1.86 m.
- Primary silhouette: high collar, circular clock ornament and four long coat-tail points.
- Model sheet: `docs/concepts/gilded-executor-model-sheet-v1.png`.
- Blender scene: `art_source/blender/gilded-executor-v1.blend`.

The generated turnaround is construction guidance, not permission to redesign the approved idle illustration. When there is a conflict, the approved V1 idle pose wins.

## Production gates

### Gate A — base model

- Clean full-body mesh in neutral A-pose.
- Correct silhouette from front, profile and gameplay camera.
- Separate editable objects for body, hair, coat, coat tails, gloves, boots and clock ornament.
- No final textures, rig or animation yet.

Approval test: the untextured silhouette must be recognizable at 128 px and must not look like the technical polygon prototype.

### Gate B — topology and materials

- Deformation-ready topology at shoulders, elbows, hips and knees.
- Coat tails have enough geometry for controlled secondary motion.
- Cel-shaded materials limited to ivory, black, gold, skin and hair families.
- Shared palette controls support freeze-frame hue changes without repainting textures.

### Gate C — rig

- Humanoid rig with IK/FK arms and legs.
- Dedicated controls for coat tails, collar, hair locks and clock ornament.
- Weapon hand and shoulder anchors exported as named markers.
- No root motion; gameplay position remains authoritative in Godot.

### Gate D — animation slice

First delivery contains only:

1. Idle loop.
2. Run loop.
3. Rise/fall poses.
4. Aim/lock pose with 360-degree arm targeting.
5. Hit, defeat and victory poses.

Animation is rendered at fixed frame indices. Godot selects frames from simulation state and `world_tick`; Blender animation playback never controls gameplay.

### Gate E — sprite export

- Orthographic render with transparent background.
- 128 px target fighter height for the first readability pass.
- Consistent pivot: logical feet at local `y = 24` relative to the existing 32 × 48 gameplay box.
- Atlas naming is deterministic and includes fighter, state, direction and frame.
- Web build uses atlases, not live Blender files or runtime 3D viewports.

## AI automation boundary

Automate:

- Turnaround exploration and reference preparation.
- Blender scene setup, naming, scale and collection structure.
- Repetitive material setup and palette variants.
- Sprite rendering, atlas packing and import metadata.
- Structural QA: missing frames, wrong pivots, inconsistent dimensions and export regressions.

Require artistic approval:

- Face and likeness.
- Silhouette and costume construction.
- Shoulder/hip deformation.
- Idle pose attitude and animation timing.
- Any change to hair, proportions or the white/gold/black design.

AI output is never promoted directly into the game. Each gate produces a visible review asset first.

## Current next action

Review the V1 model sheet. If its construction matches the approved character, create Gate A in the prepared `MODEL_EXECUTOR` collection. Do not integrate it into Godot until the 128 px silhouette review passes.
