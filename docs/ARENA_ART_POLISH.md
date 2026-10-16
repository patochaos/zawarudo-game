# Arena art polish

**October 16, 2026: rendered portal frames and mover rails.** The cyan dashes
along a wrap opening and the bare chevron read of a mover are replaced by
Blender pieces from `tools/blender/build_portal_rail_kit.py`, rendered with the
Pendulum kit's materials, camera and lighting into
`assets/art/arenas/pendulum/`:

- `portal-frame-v.png` and `portal-frame-h.png`: gunmetal rails with brass
  caps and a cyan lamp, one sheet per edge (left and right, ceiling and floor),
  each a 12 px cap, a 72 px repeatable segment and a cap. The 8 px channel
  between the rails is open; the backdrop shows through it.
- `portal-loop-v.png` and `portal-loop-h.png`: six frames of cyan bands
  sliding along the channel. The pattern repeats every 24 px, so the sixth
  frame returns to the first and the cells tile along any run. `Arena` steps
  the loop at 10 frames a second only while execution or free play runs, like
  the backdrop's air, and shows the first frame while time is stopped. The
  clock is cosmetic and never reaches the simulation or the digest.
- `rail-v.png` and `rail-h.png`: an 8 px gunmetal rail with the lift's violet
  enamel inlay and brass ties every 16 px, plus a 16 px stop at each end.

`Arena` draws a frame along every span that the same rect checks as before
leave open at both edges (both side probes for the horizontal wrap, the ceiling
and floor probes for the vertical one); the spans now come from the rect edges
themselves instead of a 12 px sample, so a frame ends exactly where the solid
architecture begins and solid walls still get no portal. Side frames sit in
the 12 px at each screen edge, the ceiling frame between the top gates and the
floor frame in the last 12 px above the bottom edge. A mover's rail is drawn
behind the platforms, from the piece's authored home to the far end of its
travel with a stop past each end, so the violet lip and the chevrons on the
face keep the moving read. No collision rectangle or timing changed.

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --python tools/blender/build_portal_rail_kit.py
```

The script saves `art_source/blender/portal-rail-kit-v1.blend`; the six PNGs
were imported with Godot headless and share the kit's lossless import settings.

Verification on October 16: `ArenaArtTest`, `KineticArenaTest`,
`LevelLayoutTest` and `PrototypeArenasTest` passed headless. The windowed
`ArenaArtVisualTest` ran and its captures were reviewed for Pulse Chamber (side
wrap, two framed runs per edge in the four-player layout where the perches
interrupt the seam) and Endless Descent (four-way wrap: side frames above the
lower bulkheads, the ceiling frame between the gates). The two fixtures that
carry a moving platform, Pendulum (lift on a vertical rail, vertical wrap) and
Knife Court (sideways mover, side wrap), were captured in planning and
mid-sweep execution with a scratch capture script outside the repository, and
the loop was confirmed to stay on frame 0 in planning and advance in execution.
Known limit: the floor frame of a vertical wrap sits under the HUD's bottom
band, as the former dashes did, so it reads only faintly in captures.

**October 16, 2026: layered backdrops, parallax and baked lighting states.**
Each of the five rotation arenas is now rendered as two Blender layers plus
their warm-light passes instead of one flat backdrop:

- `far.png` holds the rear chamber and new distant set dressing (a second row
  of arches, far capacitor banks, chimneys, the deeper Descent shaft tiers).
  `mid.png` holds the main architecture. The far layer slides up to about 11 px
  and the mid layer about 4 px as the fight's centre moves, read from the live
  fighters' positions, smoothed cosmetically and frozen whenever time is
  stopped. Both layers carry bleed so no edge is ever exposed.
- `far-warm.png` and `mid-warm.png` are the warm bounce light's contribution
  alone, rendered with the cool light, ambient and emissive surfaces switched
  off. `Backdrop` adds them while execution, free play or replay runs and
  fades them out for planning, so the room reads cold and still while plans
  are laid and lights up when time resumes. Planning is now the cool pass
  only; execution is the former look with the warm light at 1.35x.
- The far wall and the warm passes are soft gradients and render at half
  resolution; the runtime scales them. The five-arena PNG set is about
  7.6 MB on disk against 6.2 MB for the former five backdrops.
- `Backdrop` draws the architecture itself, adds the warm passes through an
  additive child node, and draws the motes, corner motifs and side trim on a
  second child so they stay above the lighting. Mote freezing, the Descent
  machinery clock and the state digest are unchanged; `ArenaArtTest` now also
  checks that planning stays cold and still, that execution lights and slides,
  that restart resets both, and that every layer keeps its bleed aspect.
- Collision Course was removed from `build_arena_art.py` along with the retired
  arena; its editable source remains in `art_source/blender/`.

Regenerate all five, or pass arena names after `--` for a subset:

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --python tools/blender/build_arena_art.py
```

Rendering picks OptiX or CUDA when available and falls back to the CPU.

Verification on October 16: `ArenaArtTest`, `KenneyPolishTest`,
`PrototypeArenasTest` and `KineticArenaTest` passed headless. The windowed
`ArenaArtVisualTest` captures were reviewed for all five arenas, and the new
`tests/ArenaParallaxVisualTest.gd` writes `previews/arena-parallax-*.png`: the
same arena in planning, then execution settled at the left and right edges.
Measured on Crosshair Court, the mid layer shifts 6 px between the two edges
and the far layer about 18 px, and the lit strip reads about 1.6x brighter in
execution than in planning. No human playtest or Web export is claimed.

**October 16, 2026: rendered cover damage, shards and the room behind the
plan.** Breakable cover no longer draws crack lines over the intact face.
`tools/blender/build_platform_damage.py` renders two damaged faces with the
Pendulum kit's ceramic, ink and brass materials, camera and lighting:
`breakable-cracked.png` (first hit: two cracks, a tilted face segment, a
chipped edge) and `breakable-broken.png` (last hit: four cracks, dropped and
scorched segments, chips at both ends, a sheared cap). `Arena.breakable_face`
picks intact at full hits, broken at one hit left and cracked between; the
pips and the reddening tint are unchanged, so the hit count still reads the
same way. The same script renders `debris.png`, four 32 px ceramic and brass
shards; `Effects` flings seven of them on a SHATTER along the burst's seeded
arcs, tumbling and fading before the burst ends. The intact face still comes
from `build_pendulum_art.py`, which also regenerates the retired observatory,
so the damage states have their own script and `platform-damage-v1.blend`.

The match setup plan now draws the chosen arena's far and mid layers at plan
scale, dimmed under the diagram, so the rules screen shows the room as well as
the layout. `tests/PlatformDamageVisualTest.gd` captures cracked, broken, the
shard burst a third of the way through its flight, and the setup screen for two
arenas under `previews/platform-damage-*.png`.

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --python tools/blender/build_platform_damage.py
```

**October 14, 2026:** the rotation is now five arenas. Pendulum, Shattered
Sanctum, Foundry and Collision Course were retired; Clockwork Gallery reuses the
Foundry scenery and Stilled Hall the Sanctum scenery. The Pendulum solid, moving
and breakable platform faces remain the shared platform material. The notes
below describe the original seven-arena pass.

The six remaining arenas now use original Blender scenery and platform faces,
following the Pendulum prototype. The current seven arena layouts are preserved,
including the recent Endless Descent and Pulse Chamber layout changes.

The September 6 [Endless Descent pass](ENDLESS_DESCENT_POLISH.md) supersedes
this initial treatment for that arena, including its tested 1v1 layout changes,
detailed shaft architecture and steel bulkheads.

| Arena | Architecture | Solid platform treatment |
|---|---|---|
| Crosshair Court | Ceremonial arches, wine banners, crossed-blade crest | Blue slate and bronze caps |
| Endless Descent | Nested lift shaft frames, cables and copper guide rails | Slate with oxidized copper |
| Pulse Chamber | Tall capacitor housings, glass panels and coolant pipes | Industrial slate and copper |
| Shattered Sanctum | Broken arches, oculus, fluted pillars and fallen masonry | Dressed limestone and bronze |
| Foundry | Banked furnaces, shutters, chimneys and crane hardware | Cast iron and bronze |
| Collision Course | Crossing conveyor rails, timing wheels and bearing plates | Cast iron and violet enamel |

Each backdrop is graded below the live players, platform edges and previews.
Sparse dust freezes in planning, confirmation and online waiting, then resumes
from the same position in execution. Foundry embers drift upward. The old
full-screen pattern wallpaper and duplicate freeze-only particles were removed;
small recessed corner motifs remain. Pendulum retains its accepted background.

Moving and breakable platform materials are shared across the set so their
meaning is consistent: violet chevrons for movers, amber faces with damage
cracks and remaining-hit pips for breakable cover. Tall moving shutters now have
metal slats, violet side rails and motion arrows along their height. All
platform decoration stays within its collision rectangle; portal openings still
come from the existing geometry checks.

## Sources and regeneration

`tools/blender/build_arena_art.py` generates six editable sources in
`art_source/blender/<arena-name>-v1.blend` and twelve runtime PNGs in
`assets/art/arenas/<arena-name>/`. Each source opens on its architecture; enable
the `PLATFORM_KIT_enable_for_editing` collection to edit its platform face.
No external textures, add-ons or runtime dependencies were added. The complete
seven-arena PNG set is approximately 7.2 MB on disk.

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --python tools/blender/build_arena_art.py
```

Normal play still uses `Play.bat`; Blender is needed only for asset authoring.

## Verification

Six focused suites passed: ArenaArtTest, PendulumArtTest, KenneyPolishTest,
KineticArenaTest, LevelLayoutTest and PrototypeArenasTest. The new atmosphere
checks exercise freeze/resume/reset and unchanged online state on all seven
arenas.

The source launcher ran `tests/ArenaArtVisualTest.gd` successfully. Its 24
captures cover all six arenas in planning, execution, 1024×576 high-contrast
planning, and four-player matches with damaged cover. Rendered review artifacts
are in `previews/arena-art-*.png`; the six-panel gallery is
`previews/arena-art-gallery.png`. Gallery order is the table order, left to
right, top to bottom. These local previews are ignored by Git.

```powershell
.\Play.bat --rendering-method gl_compatibility --audio-driver Dummy --script tests/ArenaArtVisualTest.gd
```

This verification establishes rendering and the affected source behavior; it
does not claim a measured improvement from a human playtest or a Web export.
