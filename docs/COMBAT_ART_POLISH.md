# SUPER and impact art — September 4, 2026 (copy revised October 14, 2026)

SUPER uses an original Blender-rendered temporal dial with five blade facets,
followed by the existing fighter portrait and, since the Gate 3 pass, the
original title THE WORLD HOLDS ITS BREATH / STAND STILL in place of the former
borrowed chant. Five accents build toward release, then the panel tears away
along the thrower's facing. The pause remains 1.45 seconds and is now a
GameManager timer (`super_cutin_duration`); the cut-in animates for the same
length. Portraits and fighter animations are unchanged.

Shared SPARK and CLASH feedback now uses four rendered metallic shard poses.
Wall contacts stay smaller than clashes; a short contact glint and a partial
clash ring give way to a quiet falloff. Existing event positions, colors,
lifetimes, projectile geometry and collision behavior are preserved. Because
these effect kinds are shared, ricochets and other CLASH callers also receive
the new treatment.

Reduced flashes is passed to SUPER when it begins. It removes entry glint,
shake and dial rotation; the portrait/title sequence remains legible. Impact
sprites and their procedural glint/ring also reduce their intensity.

## Sources

- `tools/blender/build_combat_art.py`: reproducible authoring and rendering.
- `art_source/blender/combat-art-v1.blend`: editable dial and impact geometry.
- `assets/art/combat/`: five runtime PNGs, approximately 292 KiB total.

Regenerate from the repository root:

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --python tools/blender/build_combat_art.py
```

Blender is only needed for authoring. Normal local play uses `Play.bat`.

## Verification

`SuperCutInTest` checks portrait routing, start/cancel, reduced-flash forwarding
and the unchanged deadline. `KnifeMechanicsTest` covers the first-wave gate and
knife mechanics. `CombatArtTest` checks cosmetic state-digest isolation and
impact cleanup. `CombatArtVisualTest` captures anticipation, portrait and release
for both players at 1280×720 and 1024×576, plus impact stages in normal and
reduced-flash modes. Captures are saved under `previews/combat-*.png`.

No Web export or human playtest is claimed by these source checks.

Validation completed: SuperCutInTest, KnifeMechanicsTest, CombatArtTest and
MatchReplayTest passed. The 16 visual captures completed without script errors;
review covered both player orientations, smaller resolution and reduced flashes.
