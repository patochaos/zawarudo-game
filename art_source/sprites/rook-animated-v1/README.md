# Rook animated arena sprite v1

Status: complete 30-frame animated arena set, wired to `Weapon.DASHBLADE` only.

## Canon and silhouette anchors

The identity references are `docs/concepts/velocity-rework/rook-master-sheet-v1.png`
and `docs/concepts/velocity-rework/velocity-heavy-shield-lancer-mockup-v1.png`.
Commit `c179bad` is used only for normalization, atlas, ghost-mask and Godot
integration technique. Its Executor artwork and movement are not references.

The two strongest character-exclusive outer-contour anchors are:

1. the enormous sculptural vertical auburn crest with the thick left-shoulder braid;
2. the asymmetrical body-tall tower shield with its crescent-blade upper rim.

The long impact lance with exactly three stabilizer rings is the third combat
anchor. The runtime character ID is currently `Weapon.DASHBLADE` (`2`).

## Movement thesis

Idle and walking perform weight: shield first, wide deliberate steps, minimal
bounce and clean held footfalls. Lock-in is a severe asymmetric fashion pose.
The signature release drops her behind the shield and collapses shoulder,
shield center, hips and lance into one catastrophic horizontal wedge.

## Built-in image-generation prompt set

Generated with Codex's built-in image-generation mode on 2026-08-22. The first
draft is `arena-proof-source.png`. The cell-safe revision selected for the proof
is `arena-proof-source-v2.png`.

### Primary proof prompt

```text
Use case: stylized-concept
Asset type: small arena-fighter sprite proof source sheet for a Godot game
Input images: Image 1 is the canonical Rook master sheet and controls exact identity, heroic heavyweight proportions, costume asymmetry, palette, shield, lance, crest and braid. Image 2 is an approved character-direction reference for attitude and equipment scale only. Do not use any Gilded Executor image, pose, swagger, coat, cape, or animation as a visual reference.
Primary request: Create exactly FOUR clearly separated full-body, screen-right-facing 2D sprite poses of the same character THE ROOK in one horizontal row, all at the exact same body scale and proportions: (1) IDLE—huge tower shield planted beside her left foot as a vertical wall, long lance upright or resting across shoulder, weight settled into one hip, chin high; (2) WALK—one wide deliberate shield-first step with minimal bounce, torso and lance following, heavy clean footfall; (3) LOCK—an asymmetric high-fashion commitment pose, shield planted, torso twisted away, lance forming one severe exact diagonal, right hand briefly open above eye level; (4) SIGNATURE ATTACK RELEASE / BREAK LINE—body dropped low behind the shield, left shoulder, shield center and hips forming one horizontal driving line, lance projecting screen-right beside the shield as the lethal point, a single compressed siege-engine wedge.
Subject identity: tall powerfully built adult woman, broad shoulders, muscular upper arms and back, sturdy waist, large athletic thighs and calves, warm medium skin. Dark auburn hair forms one enormous sculptural vertical swept crest and one thick braid over her left shoulder. Cropped midnight-navy jacket with large burnt-orange split collar; muscular RIGHT arm mostly bare; LEFT arm armored and shield-bearing; near-black left trouser leg; midnight-navy open drape on right leg; pointed stable boots. Exactly one asymmetrical near-black/navy tower shield, ground-to-above-shoulder height and wider than torso, one bold antique-gold crescent upper outer rim, one burnt-orange lower inset, exactly THREE diagonal cyan vents. Exactly one thick impact lance at least 1.6 times her body height, near-black shaft, angular gold diamond tip, and exactly THREE large cyan-lit stabilizer rings near the butt.
Style/medium: extremely simplified clean 2D vector/cel arena sprite source art, 10–14 large flat graphic shapes per figure plus equipment, thick near-black outer contour, hard clean edges, flat fills only. No gradients, texture, realistic material rendering, tiny trim, folds, chains, buttons, abdominal detail, or internal noise. Must remain immediately recognizable as a solid black silhouette at approximately 51 pixels body height. Preserve the vertical crest-plus-braid, crescent-rim shield, and long three-ring lance in every pose.
Composition/framing: transparent background; four equal conceptual cells in a single horizontal row; entire figure, shield, and lance contained in each cell with generous transparent gutters and no overlap. All ground poses share one foot baseline. Every pose faces screen-right and must mirror cleanly later. No labels, guides, borders, floor shadows, VFX, scenery, or UI.
Color palette: midnight navy #101B3D, near-black #111117, burnt orange #C45128, antique gold #C79B3B, controlled cyan #49DCE7, warm skin #A96F52, dark auburn #6F2D21. Cyan only in the three shield vents and three lance rings; gold structural only.
Movement personality: slow, glamorous, immovable and physically effortless. Ordinary motion performs weight. No hurry, bounce, nimble footwork, dance, brawling, or burden. The attack is all stored force arriving at once in one straight line.
Constraints: Preserve exact same identity, muscular proportions, left/right asymmetry, equipment ratios, and palette across all four poses. Shield always belongs to armored left arm. Bare right arm controls/braces lance. Keep exactly one shield, one lance, three shield vents, and three lance rings. No text or watermark.
Avoid: slender model body, tiny waist, dainty limbs, pin-up posing, medieval knight, military tank, armor suit, helmet, cape, skirt, generic rectangle shield, round shield, small shield, ordinary spear, shortened lance, extra weapon, extra shield, reversed arm or leg asymmetry, missing crest or braid, mohawk, ponytail, loose fluffy hair, more or fewer than three vents or rings, chess motifs, rook icon, castle battlements, lightning, fire, speed clouds, photorealism, 3D rendering, chibi anatomy, checkerboard background.
```

### Cell-safe idle revision

```text
Use case: precise-object-edit
Asset type: Rook arena-fighter four-pose proof source sheet
Primary request: Change ONLY the FIRST / LEFTMOST IDLE pose so her long lance is laid diagonally across or just behind her shoulders, entirely contained inside that first pose's existing horizontal cell and not extending above the enormous hair crest or below the feet. Keep the spear at least 1.6 times her body height, with the angular gold diamond tip, small butt point, and exactly three cyan-lit stabilizer rings near the butt. Keep her tower shield planted beside her left foot.
Invariants: Preserve the other three poses pixel-for-pixel in concept, placement, size, action, character identity, costume, colors, shield, weapons, proportions, right-facing direction, baked transparent checkerboard backdrop, and spacing. Preserve the first pose's exact body identity, muscular proportions, vertical auburn crest, left-shoulder braid, orange collar, armored left arm, bare right arm, planted crescent-rim tower shield with exactly three cyan vents, stance, baseline, and scale. Do not resize any body or any pose. Keep exactly four non-overlapping figures in one horizontal row.
Constraints: The revised idle lance must fit within the 384x256 runtime-cell proportions after the upright body is normalized to 224 source pixels high; therefore its long axis should be mostly horizontal or diagonal, never vertical. No text, labels, VFX, shadows, scenery, extra equipment, or watermark.
Avoid: changing any pose except the lance placement in the first pose; shortening the lance; losing or changing ring count; covering the hair crest or shield silhouette; adding limbs or weapons; redesigning costume or equipment.
```

## Proof build

```powershell
py -3 tools/art/build_rook_arena_proof.py `
  art_source/sprites/rook-animated-v1/arena-proof-source-v2.png `
  assets/art/fighters/rook-animated-v1
```

The proof uses 384x256 cells, baseline y=238, approximately 224 source pixels of
upright body height, one shared scale for all four poses, and the accepted 87x58
in-game draw rectangle. The common scale is reduced only enough to keep the
tallest diagonal lance inside the cell; no pose is normalized independently.
`ghost-arena-proof.png` is the parallel monochrome alpha-mask atlas.

## Production animation prompt set

All six production generations used `arena-proof-source-v2.png` as the approved
arena-style reference and `rook-master-sheet-v1.png` as the canonical identity
reference. Every prompt repeated these shared invariants:

```text
The same screen-right-facing Rook in every frame: tall heavyweight athletic
adult woman; enormous vertical dark-auburn sculptural crest and thick braid over
her left shoulder; broad shoulders, sturdy waist and powerful thighs; burnt-
orange collar; mostly bare muscular right arm; armored shield-bearing left arm;
exactly one asymmetrical body-tall tower shield with one gold crescent rim, one
orange inset and exactly three cyan vents; exactly one long thick impact lance
with a gold diamond tip and exactly three stabilizer rings. Match the approved
simplified flat 2D vector/cel combat icon: large flat regions, thick near-black
contour, solid-black silhouette readability at 51 px. Palette only #101B3D,
#111117, #C45128, #C79B3B, #49DCE7, #A96F52 and #6F2D21. Same body scale and
proportions throughout each sheet; transparent background and generous gutters;
no labels, grid lines, floor, shadow, VFX, text or watermark. Avoid gradients,
textures, tiny trim, buttons, chains, seams, folds, boot lattice, abdominal or
facial detail, Executor movement, cape, slender anatomy, generic/round shield,
short spear, reversed asymmetry, missing crest/braid, extra limbs or equipment,
and ring/vent count drift.
```

The per-sheet production requests were:

- `idle-source.png`, four horizontal frames: planted neutral; tiny shoulder
  inhale; subtle hip settle with shield absorbing motion first; return/hold.
  Lance remains mostly horizontal across or behind the shoulders.
- `walk-source.png`, 3x2 row-major: right contact; heavy settle; passing; left
  contact; heavy settle; passing. Wide shield-first steps, minimal bounce,
  clean held footfalls; crest and right-leg drape settle one frame late.
- `run-source.png`, 3x2 row-major: right contact; compression; passing; left
  contact; compression; passing. Heavy braced fast advance with shield ahead
  and lance pulled back; explicitly not the signature attack release.
- `air-source.png`, 2x2 row-major: compact shield-driven rise; extended upward
  redirect; controlled shield-first fall; heavy landing approach. No ordinary
  graceful jump or acrobatics.
- `action-source-v2.png`, 3x2 row-major: lock anticipation with contained severe
  lance diagonal; confirmed runway lock with raised open hand and visible
  diagonal lance; shot wind-up; low horizontal BREAK LINE release; committed
  follow-through; shield-scrape brake. `action-source.png` is the rejected first
  pass whose second lock key omitted the lance; the v2 identity-preserving edit
  restored it while holding the four release keys invariant.
- `defeat-source.png`, four horizontal frames at one fixed scale: sharp recoil;
  heavy stagger; one knee behind the planted shield with lance on the ground;
  final protected kneel/slump. The short keys are never enlarged independently.

## Production build

```powershell
py -3 tools/art/build_rook_animated.py `
  art_source/sprites/rook-animated-v1 `
  assets/art/fighters/rook-animated-v1
```

The runtime build contains IDLE 4, WALK 6, RUN 6, RISE 2, FALL 2, LOCK 2,
SHOT 4 and DEFEAT 4. Every atlas uses 384x256 cells, baseline y=238 and the
accepted 87x58 draw rectangle. Each source sheet has one shared normalization
scale, and every color atlas has an alpha-identical monochrome ghost atlas.
