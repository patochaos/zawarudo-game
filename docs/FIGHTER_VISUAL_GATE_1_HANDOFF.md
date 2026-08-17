# Workstream handoff

## Identity

- Workstream: `vertical-slice-visual-architecture`
- Owner/task: delegated Gate 1 implementation task
- Starting branch: detached worktree HEAD; `codex/fighter-visual-slice` pointed
  at the starting commit
- Starting commit: `476977bde02af24182cddfdaacbc5bba2e0fdced`
- Production gate: Gate 1 — visual contract and silhouette proof
- Status: complete

## Required reading

- `docs/PRODUCTION_ROADMAP.md`
- `docs/character-and-freeze-frame-direction.md`
- `docs/WORKSTREAM_HANDOFF_TEMPLATE.md`

## Objective

Prove a cosmetic fighter seam, readable greybox scale, deterministic manual
state selection and exact visual aim without changing simulation behavior.

## Protected contracts

- Unchanged: `Player.step_state`, `Player.sim_step`, `Player.sim_free`,
  `PlayerPlan`, `PredictionSystem`, `Arrow`, collision constants, projectile
  launch origin/tick/direction, replay payloads and online digest construction.
- `Player.SIZE` remains `32x48`; visual bounds are `64x92` and foot-anchored.
- Visual code reads player/manager state and never writes simulation state.
- `PreviewLayer` and `SuperFreezeFrame` are unchanged.

## Allowed scope

- Edited: `scripts/GameManager.gd`, `scripts/Player.gd`.
- Added: `scripts/FighterSkin.gd`, `scripts/FighterVisual.gd`, script UIDs,
  `tests/FighterVisualTest.gd`, its UID and this handoff.
- No external art tools, generated character art or Blender dependencies.

## Deliverables

- `FighterSkin`: visual-only frame, pivot, portrait, palette, bounds,
  attachment and silhouette data.
- `FighterVisual`: cosmetic `Node2D` observer with `IDLE`, `RUN`, `RISE`,
  `FALL`, `LOCK` and `DEFEAT` state selection.
- Manual five-tick stepped frame selection from `world_tick`; no autonomous
  playback and no root motion.
- Dedicated `AimArm` child whose endpoints read `Player.shoulder()` and
  `Player.muzzle()` directly.
- `GameManager._add_player()` attachment behind
  `fighter_visuals_enabled`; false leaves a fully legacy manager-spawned player.
- Focused contract test covering attachment, fallback, collision dimensions,
  state coverage, planning freeze, aim updates, digest isolation, replay restore
  and eight principal aim directions within one pixel.

## Acceptance commands

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Godot.ps1
```

The runner first refreshes Godot's ignored global class cache. This matters
after switching branches or worktrees containing new `class_name` scripts;
otherwise direct script execution can read a stale cache even though an editor
launch or export would scan the new classes correctly.

Expected and observed: `Fighter visual: all tests passed` followed by the
complete suite result.

The established gameplay/journey set was run with the same command shape for:

```text
CloseCameraTest DoubleJumpTest FourPlayerModeTest KineticArenaTest
KnifeMechanicsTest LevelLayoutTest MatchReplayTest MenuInteractionTest
OnlineLockstepTest PlaytestReadinessTest SuperCutInTest TouchControlsTest
UserJourneyTest
```

Expected and observed: 13/13 passed.

```powershell
Set-Location backend
npm ci
npm test
npm run typecheck
Set-Location ..
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Export-Web.ps1
& 'D:\Godot\godot.cmd' --headless --path . --export-release 'Windows' `
  'build/windows/TacticalDuel.exe'
& '.\build\windows\TacticalDuel.exe' --headless --quit-after 180
```

Expected and observed: backend 3 files / 7 tests passed, TypeScript typecheck
passed, Web release export passed (39.2 MiB total; 37.7 MiB WASM), Windows
release export passed and the 180-frame headless startup exited cleanly.

## Decisions made

- The feature flag defaults on so Gate 1 is exercised in normal matches; false
  is the immediate stick-renderer fallback.
- Isolated `Player.new()` instances remain legacy. Only
  `GameManager._add_player()` may attach the observer.
- The temporary poses are dictionaries in `FighterSkin`, preserving a data seam
  for later imported sprite metadata without introducing final art now.
- Five simulation ticks per frame produces an apparent 12 fps at the protected
  60 Hz simulation rate.
- `LOCK` applies only during planning/commit/wait phases; execution and replay
  continue to derive locomotion from authoritative velocity and grounding.
- A normal-scale non-headless capture succeeded and was visually inspected, but
  the capture harness and artifact were removed because the dummy headless
  renderer cannot supply a viewport texture reliably. Focused and established
  automated suites remain the committed acceptance evidence.

## AI asset provenance

No generated art assets were added. The procedural greybox is source code and
uses only geometric primitives and existing runtime colors.

## Handoff result

- Final commit: this handoff's Gate 1 commit; exact hash is recorded in the
  completion report because a commit cannot contain its own hash.
- Changed files: listed in Allowed scope above.
- Verification performed: focused Godot contract test, all 13 established
  Godot suites, backend tests/typecheck, Web export, Windows export/startup.
- Known limitations: procedural poses are intentional greybox data, not final
  sprite frames; the legacy afterimage look is not reproduced by the new body;
  there is no retained automated screenshot artifact.
- Next recommended action: director silhouette review at normal match scale,
  then approve or revise the two profiles before Gate 2 art production.
- Items requiring director approval: accept the broad split-coat Executor and
  scarf/S-curve Witness as the Gate 1 identity anchors; confirm whether the
  feature flag should remain default-on for the next playtest build.
