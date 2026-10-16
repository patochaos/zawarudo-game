# Duelist sprite polish

The default Duelist now uses `duelist_polished_v2`: 30 authored frames across
idle, walk, run, rise, fall, lock, throw and defeat. This is a sprite and
presentation pass on the existing ivory/black/gold design.

## Changes

- Cel shading separates cloth, suit and gold accents. A visible dagger wind-up,
  extended empty release hand, cross-body follow-through and recovery clarify
  the throw. The release remains synchronized to the authoritative shot tick.
- Explicit source body anchors replace silhouette-box centering. Coat and hand
  extensions no longer determine where the body is placed within the atlas.
- Launch/apex and descent/brace poses follow vertical speed instead of looping
  on the world clock. Live rendering, prediction and last-turn review share
  the frame selector. Other fighters retain their existing animation behavior.
- New atlas imports carry mipmaps; the Duelist visual uses linear mipmap
  filtering to reduce speckling at the original roughly 51-pixel standing height.
- Matching alpha silhouettes accompany all eight animation atlases.

## Sources and reproduction

- Art: `art_source/sprites/duelist-polished-v2/*-source.png`.
- Exact built-in imagegen prompts: `generation-prompts.json` in that directory.
- Runtime: `assets/art/fighters/duelist-polished-v2/`.
- Packing: `python tools/art/build_duelist_polished.py`.
- Keep the runtime `.png.import` files: these enable mipmap generation.

The generated sources contain a pale checkerboard matte; the packer reuses the
project's foreground extraction. Whole connected silhouettes preserve the
throwing hand where it extends past a nominal sheet-column boundary. All poses
have explicit, reviewable source anchors and a shared scale within each sheet.
The original v1 sheets remain available for comparison.

## Verification

Passed Godot 4.7.1 source suites: `FighterVisualTest`,
`SimplifiedFighterPlayableTest`, `AnimatedFighterPlayableTest`, and
`DuelistPolishTest`. Checks include atlas dimensions, filtering gutters, mipmaps,
matching ghost alpha, launch-frame synchronization, non-cycling airborne poses,
collision dimensions, player identity, replay and cosmetic digest isolation.

`tests/DuelistSpritePolishVisualTest.gd` captures actual Godot rendering at
1280x720 and 1024x576. Outputs are under `previews/duelist-sprite-polish-*.png`
(ignored local artifacts). Run windowed with a real render target:

```powershell
godot --path . --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/DuelistSpritePolishVisualTest.gd --quit-after 300
```

The visual pass was checked through these captures and deterministic frame
tests; subjective animation quality has not been established by a human playtest.
This does not certify an "AAA" quality bar. The six-frame locomotion cycles and
four-frame throw remain the current animation budget.
