# Arena art polish

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
