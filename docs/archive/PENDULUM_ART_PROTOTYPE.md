# Pendulum observatory art prototype

Implemented September 4, 2026, on the current source project.

The environment pipeline has since been extended to the other six arenas;
see [Arena art polish](ARENA_ART_POLISH.md) for the current full-set treatment.

## In game

- Pendulum has a Blender-rendered astronomical chamber: recessed dial,
  armillary rings, gears, stone buttresses and suspended counterweights.
- September 6 machinery pass: two escapement gears and both clock hands rotate;
  paired counterweights travel in opposite directions. Six transparent Blender
  layers replace those shapes in the baked wall. Suspension cables follow the
  weights. Everything remains behind the playable platforms and fighters.
- Machinery samples `world_tick * tick_dt()` in combat and replay, so planning,
  confirmation, online waiting, hit pauses and SUPER preserve its exact pose.
  Replay seeks reconstruct it without extra snapshot state. Free play uses the
  existing cosmetic atmosphere clock; rematches reset the pose.
- Solid, moving and breakable ledges use three original rendered materials.
  Fixed-width brass caps, precise top edges and subdued masonry bases preserve
  platform readability. Violet chevrons still identify movers; amber cover
  retains damage cracks, red wear and remaining-hit pips.
- Quiet dust drifts during execution/freeplay and stays at its current position
  during planning, confirmation and waiting. It is cosmetic and does not affect
  the simulation or online digest. The redundant decorative freeze dial and
  separate static motes are suppressed on Pendulum; entry/release pulses remain.
- The active Duelist uses the existing wind-up before launch, the extended arm
  at launch, and the recovery afterwards. Replay reconstructs the same sequence.
  Planning never displays an opponent's wind-up. No new sprite drawings were
  generated in this pass.

The level layout, camera, collisions and attack timing are unchanged. Other
arenas keep their existing artwork. This is a playable visual prototype, not a
full character animation replacement or a measured human-readability study.

## Art source

- `art_source/blender/pendulum-observatory-v1.blend`
- `tools/blender/build_pendulum_art.py`
- `assets/art/arenas/pendulum/{observatory,solid,moving,breakable}.png`

The source is original procedural geometry with named materials. It uses no
external textures or add-ons. The game loads ten PNGs, including
`gear-{left,right}`, `hand-{long,short}` and `weight-{left,right}` machinery layers;
Blender is only needed to edit/regenerate the assets. The source opens on the
architecture; platform objects are in `PLATFORM_KIT_exact_collision_faces` and
hidden from rendering after their individual sprite captures.

Machinery lives in six named `MACHINERY_*` collections. The generator renders
the wall with those collections hidden, then each transparent layer separately.
The front orthographic camera uses 100 pixels per metre: 192×192 gears,
336×336 hands centred on the dial pivot, and 96×112 weights. Lighting preserves
the original cool area key (650 W) and warm fill (170 W), with 24 Cycles samples.
There is no random animation or baked frame range: Godot rotates/translates the
six renders analytically. Weights travel ±28 pixels over an eight-second cycle;
gears turn at +0.30/−0.26 radians per second and hands at +0.14/+0.045.

Regenerate from the repository root:

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --python tools/blender/build_pendulum_art.py
```

## Verification

September 6: `PendulumMachineryTest`, `ArenaArtTest` and `LevelLayoutTest` passed.
They cover execution, frozen phases, SUPER, replay restoration, free play,
rematch reset, unchanged gameplay digest and arena geometry. The existing
visual capture suite was inspected at 1280×720 and 1024×576, including planning,
release, high contrast and four players. Add `-- --machinery` to its normal
command to save 36 motion frames: execution, planning freeze, then resume.
`previews/pendulum-machinery.gif` combines these at 12 fps for review. This is a
controlled presentation sample; it is not a recorded human playtest. No Web
export or performance measurement was performed for this pass.

Seven focused suites passed: PendulumArtTest, SimplifiedFighterPlayableTest,
FighterVisualTest, KineticArenaTest, LevelLayoutTest, DuelistPolishTest and
KenneyPolishTest. The new test checks dust freeze/resume, unchanged lockstep
state, launch-pose alignment, replay alignment and planning privacy.

`tests/PendulumArtVisualTest.gd` captures 1280×720 and 1024×576 planning,
high-contrast previews, simulated release and four-player breakable geometry.
Outputs are `previews/pendulum-art-*-after.png` (local ignored review artifacts).
Run it with a rendered Godot window, not headless:

```powershell
.\Play.bat --rendering-method gl_compatibility --audio-driver Dummy --script tests/PendulumArtVisualTest.gd
```

For ordinary play, run `Play.bat` and select Pendulum in match setup.
