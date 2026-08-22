# Simplified Executor arena proof V1

Status: isolated art-direction prototype. Not wired into normal matches.

## Thesis

Arena fighters are animated combat icons, not miniature versions of the HUD
portraits. Identity must survive through a few large shapes at roughly 112 px:

- angular hair wedge;
- oversized high collar;
- one large gold clock disk;
- ivory torso and two blade-like coat tails;
- blocky gold forearms;
- pointed black boots.

Every fighter must own at least two outer-silhouette anchors that no other
fighter shares. The Executor's approved pair is the angular/spiky hair wedge
plus the long blade-like cape tails. Color, face, weapon and UI must not be
required for recognition, including under combat effects and partial occlusion.

The source is intentionally reduced to five flat color families. Facial anatomy,
fingers, fabric folds, seams, texture, gradients and realistic lighting belong
in portraits and cut-ins, not in the arena sprite.

## Source and processing

- Generated source: `simplified-source-sheet.png`.
- Runtime review atlas: `../../../assets/art/fighters/gilded-executor-simplified-proof-v1/poses.png`.
- Build script: `../../../tools/art/build_simplified_executor_proof.py`.
- Real-scale capture: `../../../previews/gilded-executor-simplified-arena-proof-v1.png`.

Rebuild from the repository root:

```powershell
py -3 tools/art/build_simplified_executor_proof.py `
  art_source/sprites/gilded-executor-proof-v1/simplified-source-sheet.png `
  assets/art/fighters/gilded-executor-simplified-proof-v1/poses.png
```

The generated source contained a baked pale checkerboard. The build step removes
only that neutral background, reconstructs alpha, extracts the four poses and
normalizes them into 256 px cells. Godot displays each cell at 0.5 scale.

## Final generation prompt

```text
Use case: stylized-concept
Asset type: ultra-simplified 2D arena-fighter sprite prototype sheet
Input images: the visual-direction sheet is the identity and gesture reference;
the model sheet is the costume reference. Simplify them radically for tiny
gameplay display instead of reproducing their illustration detail.
Primary request: exactly four full-body sprites of the same Gilded Executor:
calm idle, extreme run contact, asymmetric lock/aim pose, compact airborne rise;
all facing screen right.
Design principle: each fighter is an animated combat icon, built from roughly
8–12 large graphic shapes. Prioritize silhouette, pose and negative space above
anatomy or costume detail.
Style: extremely simplified flat vector-like sprite art readable at 80–100 px;
chunky tapered limbs; slightly oversized head, hands, boots, collar, chest disk
and coat tails; thick near-black contour; hard edges; no texture.
Composition: four poses in one horizontal row at the same scale and baseline.
Palette: exactly five flat color families—near-black, warm ivory, antique gold,
skin tan and black hair. No gradients or soft shading.
Keep only the angular hair wedge, huge collar, large circular chest clock, ivory
coat mass, two long blade-like coat tails, gold forearm blocks and pointed boots.
Constraints: transparent background; exactly four consistent figures; radically
different readable silhouettes; no weapons, floor, shadows, text or watermark.
Avoid: facial detail beyond one eye/brow slash, fingers, folds, seams, tiny trim,
muscles, realistic anatomy or lighting, 3D rendering, painterly detail, neutral
mannequin poses, intricate costume construction, pixel noise and extra limbs.
```
