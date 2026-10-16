# SUPER and impact art, September 4, 2026 (copy revised October 14, 2026)

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

# Thrown knife sprites, October 16, 2026

The thrown knife is now a Blender-rendered sprite of the Duelist's hourglass
dagger (`docs/characters/duelist.md`): a symmetrical end-to-end diamond with a
waist, antique-gold edge, near-black body and a small centre diamond. The
procedural polygon knife in `Arrow._draw()` is gone; the planning halo and
velocity chevron, the boost streak, the clash rings and the trail are unchanged.

Nothing in the simulation moved. `Arrow` keeps its position, rotation, speed,
collision segment, release tick and digest exactly as before; the sprite is
drawn at the node's position, 30 px tip to tip like the former polygon, pointed
along the real velocity (or tumbling, once clashed). `KnifeMechanicsTest` and
`MatchReplayTest` cover that, and `CombatArtTest` still checks that cosmetic
state never enters the lockstep digest.

## How the sprite is drawn

- `assets/art/combat/knife.png`: 512x512 atlas, 16 cells of 128 px, cell i
  holding the dagger at i x 22.5 degrees clockwise. The node is already rotated
  to the flight angle, so the nearest cell is drawn turned back by its own
  angle: the knife points exactly along the velocity while the baked lighting
  stays within 11.25 degrees of the scene's fixed lights.
- `knife-tint.png`: the same cells holding only the waist wrap and centre
  diamond, rendered white and drawn in the owner's colour.
- `knife-glow.png`: the same cells as a flat white silhouette, drawn at 1.3x
  under the dagger in the owner's colour at 62% alpha. This is what keeps a
  near-black blade readable on the dark backdrops and keeps ownership legible
  at a glance, which the old fully coloured polygon gave for free.
- `knife-streak.png`: 256x384, one motion-stretched frame (blades 1.45x longer
  with two fading echoes behind) in three rows: body, tint, glow. It replaces
  the still cell while a knife flies at 90% or more of `arrow_speed_max` and
  is not tumbling, so boosted and SUPER knives read as a streak.
- Each cell spans 4 scene units and the dagger 3.5 of them, so the cell is
  drawn 34.3 px wide. The atlas is minified about 3.7x at match scale, so the
  knife imports generate mipmaps (unlike `impact-*.png`, which are drawn near
  native size) and `Arrow` uses linear-with-mipmaps filtering; lossless
  compression and alpha border fixing match the impact sprites.

## Sources

- `tools/blender/build_combat_art.py`: the knife section at the bottom builds
  the dagger from ridged outlines, renders the cells with the existing dial and
  impact lighting, and composites the atlases with Blender's bundled numpy.
- `art_source/blender/combat-art-v1.blend`: now also holds the knife and streak
  geometry, hidden, next to the dial and impact facets.

Regenerate from the repository root (renders the dial, the impacts and the
knife set; about a minute on OptiX):

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --python tools/blender/build_combat_art.py
```

Only the four knife PNGs were kept from this run; the dial and impact PNGs were
restored to their committed versions because Cycles noise differs run to run.
If the dial or impacts are ever meant to change, keep them deliberately.

## Verification

`CombatArtVisualTest` gained a knife section: on each of the five arenas it
places a ring of still knives at every 22.5 degrees, two streaking knives, a
tumbling clashed knife and a trailing knife for both players, as cosmetic
nodes outside `arrows`, and saves `previews/combat-knives-<arena>.png` at
1280x720, plus `combat-knives-planning-1024.png` for the last arena in planning
at 1024x576.

Checked on October 16: CombatArtTest, KnifeMechanicsTest and MatchReplayTest
passed headless. The 22 visual captures completed without script errors.
Reviewed: every cell points along its velocity and tumbling cells follow the
spin; the owner halo separates P1 from P2 on Crosshair Court, Clockwork
Gallery, Stilled Hall, Pulse Chamber and Endless Descent; the planning halo and
chevron still frame the smaller sprite at 1024x576; the streak reads as motion
without covering the chevron. `ArenaArtVisualTest` execution captures were also
regenerated to see knives launched by the real throw path one tick after
release.

Reduced flashes is untouched: the knife never flashed, and the halo is a static
layer, not a pulse. No Web export or human playtest is claimed by these checks.

# Dial sheet and surface shards, October 16, 2026

Two more combat effects now come from `combat-art-v1.blend` through the same
script. Neither touches the simulation: the 1.45 s SUPER pause
(`super_cutin_duration`) and the cut-in timing stay GameManager's, and the
sprites only follow the values they already published. `SuperCutInTest` still
checks the unchanged deadline and `CombatArtTest` that cosmetic state stays out
of the lockstep digest.

## Time-stop shatter (cut the same day)

A third effect, eight rendered glass-crack frames spreading from the clock
centre when the world froze, shipped in the working tree for a few hours and
was cut after the first playtest reported visual clutter. Even thinned to 1150
px and 0.58 alpha it landed on the ghosts and aim fans at the exact moment
planning begins, together with the freeze ring, its rays, the TIME //
SUSPENDED title and the aftermath echoes. The crack, the rays, the second
ring and both centred phase titles are gone; the freeze is now one expanding
gold ring over a faint violet wash, and release stays the horizontal sweep.

The runtime atlas and its captures were deleted. The authoring stays in
`build_combat_art.py` under the `shatter` target (the seeded crack tree,
`crack_tree(1409)`), in case the motif returns for a one-off beat such as the
match-deciding hit, where nothing has to be read afterwards.

The same pass removed two other duplicates of information the HUD already
carries: the second impact ring with rays that `TimeStopLayer` drew on top of
the kill burst, and the world-space word (`P2 DOWN`, `TIME // CUT`) that
`EventDirection` struck beside the impact crop while the HUD banner said the
same thing. The LOCK beat (spotlight plus `DECIDED`) went too: it darkened the
whole screen while the opponent was still planning, and the READY badge and
HUD status already show readiness.

## SUPER dial sheet and accents

`super-dial.png` is now a 24-frame rotation sheet (6x4, 384 px cells) rendered
0.011 rad apart with frame 12 upright. `SuperFreezeFrame` keeps its drift angle
(-0.12 to +0.06 rad along the thrower's facing) and picks the nearest frame
instead of rotating one render, so the blade facets and index chips catch the
fixed lights as the dial turns. Reduced flashes holds frame 12 flat, as it
disabled the drawn rotation before.

The five accents under the title are rendered too: `super-accents.png` is a
5x1 strip of 64 px cells, one blade chip per wave pointing up-right like the
former stroke, with one more splinter flung off the tip per wave. Each grows
from 82% to full size as it lights on the same 0.44 + 0.065 x wave beat;
without reduced flashes the strike adds a brief white pop that peaks halfway
through the 0.06 s beat.

## Impact shards per surface

The four shared shard poses became three 4x1 atlases of 128 px cells:
`impact-stone.png` (short, wide, matte chips with dust motes), `impact-metal.png`
(the original silver spears) and `impact-glass.png` (long translucent slivers
with a lit edge). The old `impact-0..3.png` are gone. `Effects.set_level_theme`
maps `Arena.level_theme` to the set when a level loads: Crosshair Court and
Stilled Hall are stone, Clockwork Gallery and Endless Descent metal, Pulse
Chamber glass. SPARK and CLASH keep their positions, lifetimes, diameters,
glint and ring; only the sheet changes.

## Sources

- `tools/blender/build_combat_art.py`: dial pivot and frame loop, accent strip,
  per-surface impact materials, the seeded crack tree (`crack_tree(1409)`), and
  `--only` to limit a run. `save_atlas` now clears colour under fully
  transparent pixels, which is what keeps the sheets small (the dial sheet is
  about 1.7 MiB, the shatter about 190 KiB, the three impact atlases 7 to 8 KiB
  each).
- `art_source/blender/combat-art-v1.blend`: re-saved by the script; holds the
  dial under its pivot, the knife geometry and the impact materials.

Regenerate from the repository root (about three minutes on OptiX for these four
sets; add `knife` to re-render the knife atlases too):

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --python tools/blender/build_combat_art.py -- --only dial,accents,impacts,shatter
```

New PNGs were imported with `Godot --headless --import`; all use the default
lossless import without mipmaps, since each sheet is drawn near or above its
native size.

## Verification

`CombatArtVisualTest` now captures impacts on the arena that selects each
surface (Crosshair Court, Clockwork Gallery, Pulse Chamber) in normal and
reduced-flash modes, with Pulse Chamber also at 1024x576. The shatter section
it briefly had was removed with the effect. The SUPER captures are unchanged
(both players, both resolutions; player 2 runs with reduced flashes).

Checked on October 16: SuperCutInTest, CombatArtTest, KnifeMechanicsTest and
MatchReplayTest passed headless. The visual captures completed without
script errors. Reviewed: the dial frames sit where the single render did for both
players and the five accent chips light in turn with their splinters visible
at 1280 and 1024. Stone shards read as chunky chips on Crosshair Court, metal
as spears on Clockwork Gallery and glass as thin slivers on Pulse Chamber, and
reduced flashes halves all three as before. No Web export or human playtest is
claimed by these checks.
