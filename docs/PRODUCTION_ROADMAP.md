# ZAWARUDO — Production roadmap

## North star

Build a readable, original and theatrical 2D duel in Godot. Character poses,
controlled palette cuts and event composition should amplify the existing
plan → lock → execute rhythm without changing its deterministic simulation.

The production pipeline is hybrid: one canonical character model and rig in
Blender, rendered to layered 2D sprites, with a procedural aiming arm and
event-driven presentation in Godot.

## Direction decisions

- Stay in Godot. A Unity migration is out of scope.
- Use the standard match camera as the working target. The `Close Camera`
  experiment has been retired and removed.
- Keep `Player` authoritative for simulation, position, collision and aim.
- Treat every new character, shader and cut-in as a cosmetic observer.
- Use pre-rendered 3D for match characters. Do not use live 3D viewports in
  normal combat.
- Use apparent 8–12 fps stepped character animation over the 60 Hz simulation.
- Keep the stick renderer behind a feature flag until the first vertical slice
  passes gameplay, replay, online and Web verification.
- Build one complete fighter before producing the second.

## Protected gameplay contract

These rules cannot change as a side effect of the art pass:

- 60 simulation ticks per second.
- 32×48 player collision box.
- Existing prediction, replay snapshots and online lockstep digest.
- Authoritative shoulder, muzzle, launch tick and launch direction.
- No root motion, shared visual RNG, `Engine.time_scale` changes or visual code
  writing into `Player`, `PlayerPlan` or `GameManager` state.

## Gate 0 — Recoverable baseline

Goal: preserve a known-good version before changing the renderer.

- [ ] Review the current dirty worktree and separate intentional source changes
  from generated captures and previews.
- [ ] Create a recoverable checkpoint after explicit scope review.
- [x] Run all Godot suites, backend tests and typecheck.
- [x] Rebuild Web and run the Windows smoke test.
- [ ] Record reference screenshots and basic Web performance.
- [x] Use the standard camera as the provisional vertical-slice target.

Exit criteria: green verification, reference captures and a recoverable commit.
No final character production starts before this gate passes.

## Gate 1 — Visual contract and silhouette proof

Goal: prove scale, readability and integration with cheap greybox art.

- Add `FighterVisual`, a cosmetic child of `Player`.
- Add `FighterSkin`, a data resource for frames, pivots, portrait, palette,
  visual bounds and attachment metadata.
- Attach visuals only when players are spawned by `GameManager`; isolated
  `Player.new()` tests retain the legacy renderer.
- Implement `IDLE`, `RUN`, `RISE`, `FALL`, `LOCK` and `DEFEAT` greybox states.
- Read `world_tick` and simulation state to choose visual frames manually.
- Add a separate aim arm ending at the authoritative muzzle.
- Keep the current preview ghost during this gate.
- Add a feature flag that switches back to the stick renderer.

Exit criteria:

- Two fighters are distinguishable as black silhouettes at normal match scale.
- Art may occupy roughly 56×82–64×92 logical pixels while collision remains
  exactly 32×48.
- Hand/weapon and muzzle differ by at most 1 px in the eight principal aim
  sectors.
- Changing skin, palette or frame does not change the online digest.
- Planning freezes the body frame; aim can still update.
- Replay restores the same visual state.
- All existing tests remain green at 1280×720, 1024×576 and 1600×900, including
  touch and Web.

## Gate 2 — Fighter A vertical slice

Goal: prove the complete Blender → sprites → Godot production line with The
Gilded Executor.

- Approve front, side and back turnaround plus grayscale silhouette.
- Create one clean source mesh, rig, materials and orthographic camera setup.
- Separate body, aiming arm, face, coat and mask passes.
- Produce idle, run, rise, fall, charge, throw, hit, defeat, lock and victory.
- Render at 2× or 4× target resolution, downsample and manually retouch decisive
  frames.
- Generate atlases, contact sheets and Godot resources from a manifest.
- Add fighter portrait and one approved palette cut.

Exit criteria: every state works in a real match, with no foot sliding, root
motion, dishonest launch origin or visible Web performance regression.

## Gate 3 — Event direction

Goal: create one reusable theatrical grammar instead of isolated effects.

- Palette presets for lock, impact, SUPER and result.
- Lock-in pose and spotlight.
- Impact crop with one focal point and original typography.
- Three-beat SUPER: anticipation, portrait strike, release.
- Victory tableau using the real final world state.
- Reduced-flash variants preserving all gameplay information.
- Replace derivative portrait, copy and inherited catchphrases.

Do not refactor `SuperFreezeFrame` timing during Gate 1. It currently influences
when gameplay resumes; first make `GameManager` own that timing in a separate,
fully tested change, then turn the cut-in into a pure observer.

## Gate 4 — Fighter B and UI identity

Goal: reuse the proven contract for The Violet Witness.

- Produce a second silhouette and gesture language, not a recolor.
- Reuse exporter, atlas convention, shaders and `FighterSkin` contract.
- Add fighter-specific portrait, result pose, icons and tutorial references.
- Keep all visual differences in data/resources, not gameplay branches.

Exit criteria: both fighters remain distinct in grayscale, high contrast and
small-scale views while sharing one technical contract.

## Gate 5 — UX validation and candidate build

Run observed tests with players unfamiliar with the project.

- At least 4 of 5 understand plan → lock → execute from the onboarding.
- At least 4 of 5 can explain the cause of their last hit.
- Touch aiming does not hide the action.
- Repeated SUPERS remain exciting rather than disruptive.
- Accessibility variants preserve information.
- Replay, online lockstep and Web retain the Gate 0 baseline.

## AI automation policy

Use AI aggressively for breadth and mechanical repetition:

- silhouette, costume, palette and pose thumbnails;
- mocap blocking from recorded acting;
- retargeting and first-pass cleanup;
- Blender scripting for cameras, render layers and batch export;
- atlas packing and `.tres` generation;
- contact sheets, missing-frame detection, pivot/bounds checks;
- screenshot matrices, regression review and test scaffolding;
- UI layout exploration and portrait variants.

Human approval remains mandatory for identity, silhouette, key poses, timing,
hands, deformation, final cleanup, accessibility and similarity review. Never
generate final animation frames independently: the canonical Blender model,
rig and materials are the stable source of truth.

For every assisted asset, retain tool/model version, prompt, seed, date, source
files, license and human author/reviewer. Do not generate assets during gameplay.

## Task and context strategy

This task remains the direction room: scope, priorities, gate decisions and
acceptance. Use short-lived subagents for audits, research, QA and variants.

Open a separate user-visible task only when a workstream will span multiple
days or needs its own iterative history:

1. `vertical-slice-visual-architecture`
2. `fighter-a-art-pipeline`
3. `freeze-frame-direction`
4. `fighter-b-and-hud`
5. `ux-playtest-and-release-qa`

Every task starts from an exact commit and uses the handoff template in this
directory. Never run more than three implementation workstreams in parallel.

## Current sprint

1. Pass Gate 0 and establish a clean checkpoint.
2. Implement only the Gate 1 `FighterVisual`/`FighterSkin` seam.
3. Generate two cheap silhouette candidates at real gameplay scale.
4. Run digest, replay, aim-origin, resolution, touch and Web tests.
5. Approve or reject the camera/scale/pipeline before installing a full art
   toolchain or commissioning finished character work.

Current environment audit: Godot 4.7.1 is available. Blender, Krita/Aseprite and
FFmpeg were not found on `PATH`; installation and version pinning belong after
the recoverable baseline is established.

## Baseline verification log

2026-08-17:

- 13/13 Godot gameplay and journey suites passed on Godot 4.7.1.
- Backend: 3 test files and 7 tests passed.
- Backend TypeScript typecheck passed.
- Web release export passed: 40.8 MiB total, including 37.7 MiB WASM.
- Windows release export and three-second headless startup smoke passed.
- No source commit was created; the pre-existing worktree still needs scope
  review and a recoverable checkpoint.

## Gate 1 verification log

2026-08-17:

- Added the feature-flagged `FighterVisual`/`FighterSkin` cosmetic seam and two
  procedural greybox profiles at `64x92` visual bounds.
- Focused attachment, fallback, collision, digest, planning-freeze, replay and
  eight-direction aim-origin coverage passed.
- All 13 established Godot gameplay/journey suites passed.
- Backend 3 files / 7 tests and TypeScript typecheck passed.
- Web release export passed at 39.2 MiB total (37.7 MiB WASM); Windows release
  export and 180-frame headless startup passed.
- See `docs/FIGHTER_VISUAL_GATE_1_HANDOFF.md` for scope and director decisions.
