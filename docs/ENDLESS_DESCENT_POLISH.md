# Endless Descent: 1v1 layout and art, September 6, 2026

The layout was tested before editing using the production AI planner, actual
execution ticks, rendered early exchanges and targeted movement probes. These
are automated playtests, not human observations or proof of an optimal map.

## Confirmed opening problem

Both original spawns stood directly under solid 220-pixel-wide ledges. Straight
and outward held jumps hit the underside after 86 pixels of rise and landed
back on the floor. The permanent climb existed but required a detour before the
first useful jump. The new outward jump rises 210.83 pixels, hits no ceiling
and lands on the permanent first step on either side.

## Layout decisions

- Starting separation drops from 720 to 580 pixels. Both spawns remain on the
  split floor, with access to the inner shaft and the outward climbing route.
- Lower permanent steps move outward and narrow to 170 pixels. Upper perches
  narrow to 160 pixels, leaving space beside their underside for the next jump.
- Both climbing routes survive complete destruction of temporary cover.
- The central hanging divider is retained for three/four-player games only;
  duels have an open upper crossing and symmetric wrap access.
- Side Core sockets move from x=290/990 to x=490/790, closer to contested space.
  The lower central socket remains. This is a design hypothesis to validate with
  people, not a measured increase in Core contest quality.
- Respawn sockets follow the revised permanent landings. Upper side passages,
  lower bulkheads, floor/ceiling wrap gaps, controls and knife physics remain.

## Reproduce the playtest

`tests/EndlessDescentPlaytest.gd` runs four seeded Duelist mirrors, with the
production planner for both players. Each match has a 24-turn observation cap
and uses the current custom-match hit target (five in this run). SUPER cut-ins
are cleared without consuming a simulation tick. Seeds: 90210, 90347, 90484,
90621. Use the same settings for comparisons; bot preferences limit conclusions.

```powershell
& 'D:/Godot/Godot_v4.7.1-stable_win64_console.exe' --path . --rendering-method gl_compatibility --audio-driver Dummy --script tests/EndlessDescentPlaytest.gd -- --label=polished --visual
```

Reports: `previews/descent-{baseline,candidate,polished}.json`. Early execution
captures: `previews/descent-<label>-turn<1..4>.png`. First-hit turn in this harness
is sampled after the turn transition; compare consistently instead of treating
it as an exact event tick. Wrap counters are large position-displacement samples.
`EndlessDescentRoutes.gd` measures the actual opening jump with `Player.step_state`.
The saved comparison reports were reconstructed from each run's per-match
`DESCENT SAMPLE` output after correcting shared score-array references in the
JSON writer; no matches or scores were inferred or replaced.

### Observed comparison

| Measure across the four seeds | Original | Final |
|---|---:|---:|
| Hits scored within the observation cap | 16 | 24 |
| Mean longest scoreless stretch, turns | 7.75 | 5.5 |
| Fighter samples in the central x=430..850 band | 21.5% | 28.0% |
| Fighter samples above y=330 | 33.5% | 24.2% |
| Matches reaching five hits before the cap | 0/4 | 0/4 |

More exchanges and more central activity support the new layout. Upper-area
use fell despite the clearer physical climb, and first-hit timing did not
improve consistently. Those remain explicit human-playtest questions, not
reasons to claim optimal balance. The intermediate candidate scored 24 hits
but used the upper tier even less; narrowing the upper perch improved that
route while retaining the final hit count.

## Art source and presentation

The existing generator now accepts arena names after `--`, so this pass renders
only Endless Descent. Its Blender source contains receding chamfered shaft
frames, hoist sheaves, cable runs, copper rails, service hatches, vent louvres,
bolts, cantilever braces and distant cage silhouettes. Details concentrate on
the wings; the central projectile field stays dark.

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --python tools/blender/build_arena_art.py -- endless-descent
```

- Source: `art_source/blender/endless-descent-v1.blend`.
- Runtime: `assets/art/arenas/endless-descent/{backdrop,solid}.png`.
- Camera: front orthographic, 12.8-metre width; backdrop 1920×1080, platform
  face 256×32. Cycles 48 samples; original 650 W cool key and 150 W warm fill.
- Original procedural materials, with subtle noise bump on the metal surfaces;
  no external textures, add-ons or dependencies. No random geometry seed.
- Godot gives thick solids riveted steel panels instead of brick courses.
  Subtle recessed light shafts and falling streaks follow the existing machinery
  clock. Geometry owns portal markers and every visible platform edge.

## Review limits

Passed: EndlessDescentRoutes, PrototypeArenasTest, LevelLayoutTest,
CoreDemoTest, OnlineLockstepTest, MatchReplayTest and ArenaArtTest. The final
`EndlessDescentVisualTest.gd` was launched through `Play.bat` and produced seven
captures without script errors: planning in both contrast modes at 1280×720
and 1024×576, execution, all cover destroyed, and four players. Initial and
revised bot playtests additionally captured four actual early exchanges each.

Suggested human comparison: two players swap sides, first using the outward
climb and then the drop/re-entry route. Repeat after breaking all temporary
cover. Observe whether each can contest the Core, escape a held firing lane,
and explain incoming knives from either wrap. Include new players because
Endless Descent is also the demo's entry arena.

Normal local play remains `Play.bat`. No archives, deployment or Web export were
made. Online peers must use matching source/build geometry; the local lockstep
suite is not a two-device test against an older published client.
