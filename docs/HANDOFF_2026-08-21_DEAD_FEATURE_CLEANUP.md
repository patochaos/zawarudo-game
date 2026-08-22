# Workstream handoff — dead-feature cleanup and verification hardening

## Identity

- Workstream: remove retired features, close correctness gaps, make CI real
- Owner/task: full-project review (gameplay, code, UI/UX) and its first
  implementation pass
- Starting branch: `main` at `3508807`
- Starting commit: `904ddbe` (checkpoint of the previously uncommitted worktree)
- Working branch: `remove-dead-features`, head `e0a686e` — **not merged, not deployed**
- Production gate: none; this is maintenance ahead of Gate 2
- Status: **complete for its scope.** The remaining backlog below is untouched.

## Required reading

- `docs/PRODUCTION_ROADMAP.md` — gates and the protected gameplay contract
- `docs/GAME_DESIGN.md` — pillars and experience contracts (Spanish)
- `docs/CHARACTER_MOVEMENT_BALANCE_2026-08-21.md` — the live balance problem
- `README.md` — player-facing rules; kept in sync with this branch

---

## What this branch did

Twelve commits on top of `904ddbe`. Net **+1,437 / −2,131** across 61 files.

| Commit | Change |
|---|---|
| `904ddbe` | Checkpoint. Also committed `assets/art/tutorial/`, which `TutorialLayer` preloads — a clean clone did not run before this. |
| `957c7f4` | `.gitattributes`. Repo already stored LF; this pins the worktree so the Linux CI stops warning on all 50 text files. `.bat`/`.ps1` keep CRLF. |
| `180c27e` | **Close-camera prototype deleted** (−828). |
| `8386cd8` | **Velocity coat polygons fixed.** |
| `6b1babe` | **Backend: protocol 2 pinned, plan budget enforced, lockstep covered.** |
| `2b7e4b8` | **Grenadier deleted** (−887). |
| `ac007cb` | Client's last two lockstep compatibility shims removed. |
| `4a80663` | Digest format-string fix (see "Bug introduced and caught" below). |
| `d1dd0c2` | README and roadmap de-staled. |
| `ed32932` | **CI runs every suite and fails on engine errors**; capture scripts fixed. |
| `86d6547` | Three latent plan/execution divergences. |
| `e0a686e` | **Forfeit path for abandoned online matches.** |

### Deletions in detail

**Close camera** — `prototype_mode` and its 8 exports, `_apply_ruleset`,
`_sync_prototype_tuning/_timings/_camera`, `_auto_ready_finished_plans`,
`DuelCamera.gd`, `Levels._proving_ground()` + `build_prototype()`, MenuLayer's
`Ruleset` enum, the trailing-boost knife vocabulary (`knife_boost_*`,
`_try_trailing_boost`) that only close camera reached, and both CloseCamera
tests. `Telemetry.begin_match` lost its `ruleset` parameter — there is only one
ruleset now.

**Grenadier** — the Grenades tuning group, `Grenade.gd`, `grenades` /
`_next_grenade_id`, `_step_grenades`, `_detonate_grenades`,
`_resolve_grenade_knife_contacts`, `_spawn_cluster_fragments`, `_spawn_grenade`,
`grenade_launch_velocity`, `uses_grenade`, `_set_grenade_fuse`, the
chakram-versus-grenade contact, the shock orb's grenade revector, grenade replay
capture/restore, the AI's whole ballistic planner (`_fire_grenade`,
`_choose_grenade_fuse`), the preview reticle, the HUD fuse readouts and hints,
and the SUPER portrait.

Two things survived rather than dying:

- `_grenade_blast_reaches` → **`_blast_reaches`**. It is the shared hard-cover
  line-of-sight test and the shock orb needs it.
- `_cycle_grenade_fuse` → **`_cycle_attack_mode`**. Only its Static Witch branch
  was ever live.

`Weapon` ids are **append-only**: id 1 is left vacant rather than renumbered, so
existing captures and telemetry cannot silently reinterpret a kit.

```gdscript
enum Weapon { KNIVES = 0, DASHBLADE = 2, CHAKRAM = 3, SHOCK = 4 }
```

### Correctness fixes

1. **`_draw_velocity_fashion` self-intersecting polygons** (`scripts/Player.gd`).
   The `jacket` and `lapel` quads were built from torso joints plus world-space
   x/y offsets, which only describe a coat while the torso is upright.
   `_dashblade_pose` restrings those joints along the aim vector, so during a
   dash the torso can be horizontal or inverted and both quads folded across
   themselves. Godot's triangulator rejects a non-simple polygon, draws nothing,
   and logs `Invalid polygon data, triangulation failed` **every frame** — the
   Velocity lost her coat exactly when the dash made her the focus.
   Measured: `lapel` 60/144 dash orientations non-simple, `jacket` 20/144.
   Both are now cut in the torso's own basis (the pattern the trouser flare
   already used). Exhaustive probe over 3312 pose cases: **0** failures. Idle
   silhouette preserved to within 0.06 px per vertex.

2. **`restart()` leaked drop-through state.** It reset everything except
   `drop_ticks` / `drop_from_y` — the only reset path that missed them. A
   restart or rematch mid-drop carried ledge immunity into the next match, so
   thin platforms stayed transparent for up to 18 ticks of turn 1. `drop_ticks`
   is in the lockstep digest, making it a desync surface too.

3. **`_sim_tick` took the frame delta.** The planning ghost integrates with
   `tick_dt()`. Equal today only by coincidence; anything touching
   `Engine.time_scale` or the physics rate separates them, and the moment they
   separate, the plan the player committed to stops being the plan that runs.
   Now takes the fixed tick explicitly.

4. **`Ai.begin` sized its budget with `round()`** while `_pilot_step` enforces
   `ceil()` via `movement_tick_budget()`. Off by one whenever the budget is not
   an exact multiple of a tick, and the AI would then arm its shot from a tick it
   had never evaluated. Now asks for the same budget the recorder enforces.

5. **Denial-of-match.** The server allowed `MAX_PLAN_TICKS = 180` while the
   client rejects anything over ~30 and *stops the match on sight*. A modified
   peer could end an honest player's game at will. The cap is now derived from
   the real movement budget on both ends.

### Bug introduced and caught — read this one

Removing the Grenadier's fuse from `_online_state_digest()` dropped the argument
but left its `%d`. `String.format` failed and **every player fragment was
silently truncated**, so online desync detection would have compared a broken
digest on both sides.

It was caught by the CI rule added in the same branch (`ed32932`): fail a suite
when Godot logs `ERROR:` even at exit 0. Three suites were exiting 0 while
spewing that error. **Do not weaken that rule.** It is the only thing standing
between this codebase and silent engine-level faults; a self-intersecting
polygon had already survived in `Player.gd` for the same reason.

### New online capability — forfeit

A player whose browser reloads mid-match cannot rejoin (`_start_online_match`
returns early when `turn != 1`; an in-progress simulation cannot be rebuilt from
one turn of state). The survivor previously waited until the room expired 24 h
later.

Deliberately **timer-free** — no second Durable Object alarm. The survivor asks,
and the room grants only while the peer is genuinely disconnected:

```
client -> room   {"type": "forfeit"}
room -> both     {"type": "opponent_left", "winner": <slot>, "turn": <n>}
errors           wrong_phase   (not planning/executing)
                 peer_present  (opponent still connected — anti rage-quit)
```

Desync stays **unclaimable on purpose**: when neither side can be trusted as the
winner there is no honest victor, so that path offers the menu instead. Both dead
ends now name the key that leaves, on a HUD line that persists rather than a
banner that expires (`online_peer_lost` / `online_match_broken` latches).

---

## Protected contracts

Do not break these without an explicit decision.

- **60 simulation ticks/sec; 32×48 collision box.** From the roadmap.
- **One integration path.** `Player.step_state()` is shared by the planning
  ghost, execution, the AI search and replay. Any change to movement physics
  must go through it or the planning contract breaks.
- **`solids_at(tick)` is the single "where is the world at tick N" oracle.**
- **The lockstep digest** (`_online_state_digest`) must stay in sync with what
  the simulation actually carries. Quantisation is `* 10000.0` then `round`.
- **No `Engine.time_scale` changes**, no visual code writing into `Player`,
  `PlayerPlan` or `GameManager` state.
- **No backward compatibility.** Project rule, and this branch acted on it: five
  shims removed and the protocol pinned to exactly 2. Do not add fallbacks,
  migrations or `?? default` shims. Bump the version and reject instead.
- **Plans stay private until both are in.** The core competitive guarantee;
  there is a backend test asserting it.

---

## Acceptance commands

Godot lives at `D:/Godot/Godot_v4.7.1-stable_win64_console.exe`.
This is the exact logic CI runs:

```bash
status=0; pass=0; count=0
for t in tests/*.gd; do
  case "$t" in *CharacterBalanceSimulation.gd|*VisualCaptureHelper.gd) continue;; esac
  grep -q "VisualCaptureHelper" "$t" && continue
  count=$((count+1))
  out=$(timeout 300 "D:/Godot/Godot_v4.7.1-stable_win64_console.exe" --headless --path . --script "$t" 2>&1)
  rc=$?
  if [ $rc -ne 0 ] || echo "$out" | grep -q "ERROR:"; then echo "FAIL $t"; status=1; else pass=$((pass+1)); fi
done
echo "$pass/$count green, status=$status"
```

```bash
cd backend && npm test && npm run typecheck
```

**Expected at `e0a686e`: 20/20 Godot suites green with zero engine errors,
34 backend tests passing, typecheck clean.**

---

## Traps this session hit — save yourself the time

- **`tests/` contains three different kinds of file.** 20 are real assertion
  suites. 19 are screenshot capture scripts (identified by preloading
  `tests/VisualCaptureHelper.gd`, *not* by filename).
  `tests/CharacterBalanceSimulation.gd` is a multi-minute AI tournament research
  tool, not a test — never put it in a normal run.
- **Do not filter suites with `grep -v Visual`.** `tests/FighterVisualTest.gd`
  is a real headless suite. Filter by the helper preload, as CI does.
- **Capture scripts cannot run `--headless`** — the viewport texture is null.
  They now fail loudly and exit non-zero instead of hanging forever. Run them
  windowed (omit `--headless`).
- **`--script` does not step physics.** A SceneTree script can drive menus and
  call `_sim_tick` manually, but `_physics_process` never fires, so `world_tick`
  stays 0 and turns never advance on their own. Loop coverage comes from
  `MatchReplayTest`, `KineticArenaTest` and `UserJourneyTest`, which drive the
  tick functions directly.
- **A GDScript runtime error kills the suite coroutine before `quit()`**, leaving
  Godot running forever. Always wrap in `timeout`.
- **Tabs do not survive a bash heredoc.** Multi-line GDScript edits done with
  `python - <<'EOF'` silently fail to match on indentation. Write the script to a
  file and run it, or build indentation with explicit `"\t"` concatenation.
  Continuation lines in this codebase are often 4–5 tabs deep — verify with
  `repr()` before trusting a match.
- **Working tree had mixed CRLF/LF** before `957c7f4`. Normalise in-script
  (`.replace("\r\n", "\n")`) and write back with `newline="\n"`.

---

## Pending decisions — needs a human

1. **The protocol change is breaking and nothing is deployed.** The Godot client
   and the Cloudflare Worker must ship together; either alone breaks online play.
   `Deploy-Web.bat` (or `scripts/Deploy-Web.ps1`) for the client,
   `cd backend && npx wrangler deploy` for the room service.

2. **`sprite-scale-proof.patch` in the repo root (untracked).** A coherent but
   *unrequested* change scaling the Executor proof sprite from 112 px to ~56 px
   to match the stick fighter's footprint — `scripts/FighterSkin.gd`, two docs,
   and one assertion in `tests/SimplifiedFighterPlayableTest.gd` (the four are
   coupled; applying a subset breaks that suite). Parked rather than committed or
   discarded. It is relevant to backlog item **22**. `git apply` it or delete it.

3. **Tutorial screenshots** (`assets/art/tutorial/*.png`) were left at their
   committed versions. Agents regenerated them as a side effect of running the
   capture tests; re-shooting tutorial art is an art decision, not a refactor.
   Note the current images still carry the `TIME // SUSPENDED` transition title
   across the illustration, which is worth a deliberate re-capture.

---

## Remaining backlog

Ordered as recommended. Nothing here is blocked. Numbering matches the original
review so earlier discussion still maps.

### Gameplay

- **18 — Balance.** The headline problem, already documented in
  `docs/CHARACTER_MOVEMENT_BALANCE_2026-08-21.md`: Static Witch **71.4 %** win
  rate; Broodtail beats Velocity **7–0** while losing to the other two. The doc's
  own conclusion is that it is the kit, not locomotion. Start at
  `shock_plasma_range_full` (1440 px — wider than the 1280 px arena) and
  `shock_combo_radius` (280 px). Needs playtesting between changes;
  `CharacterBalanceSimulation.gd` gives directional evidence only.
- **19 — Difficulty selection.** Highest value per hour on this list, and
  self-contained. Three presets over constants that already exist:
  `ai_aim_jitter` (fixed 2.0), `Ai.MOVES_SEARCHED` (fixed 2, out of 11 movement
  candidates), `ai_think_min` / `ai_think_max`. Today there is one fixed skill
  level and it bounces new players straight off.
- **20 — Unresolved matches.** 7/84 and 4/42 of the project's own simulations hit
  `TURN_CAP = 60` with no winner — a five-minute draw. SUPER and the Temporal
  Core are not closing it.
- **21 — The 5 s : 0.75 s planning-to-execution ratio.** Nearly 7:1 and the
  defining rhythm of the game. The turn-3 shrink treats the symptom; the ratio
  deserves a deliberate test at 3.5 s planning and 1.0 s execution.
- **22 — Fighter scale.** 32×48 fighters in a 1280×720 arena read as small stick
  figures. Close Camera was the previous answer and is now retired, so the answer
  has to come from arena dimensions or a fixed camera zoom. See pending decision 2.

### UI/UX

- **23 — Key rebinding.** `K_P1` is hardcoded keycodes with a comment saying
  "rebind by editing the keycodes below". Hostile to AZERTY and to anyone with a
  mobility need. Moving to a Godot input map also fixes **32**.
- **24** — The right-hand menu panel is ~45 % of every screen for one sentence,
  and still reads `FIGHT DOSSIER // CONTEXT` on the Options page.
- **25** — The `SUPER` label sits inside its meter and is covered by the fill.
- **26** — `T1` / `PLAN` are the smallest text on screen while `3.0` is the
  largest; "am I planning or watching?" is the more important state.
- **27** — `HARD` is stamped on all nine platforms plus two wall labels,
  duplicating what the colour system already carries.
- **28** — `MenuLayer._label` uses `shadow_offset (3, 4)` on 11–16 px text —
  ~35 % of glyph height, so it reads as a second copy of the word. Drop to
  `(1, 2)`; keep the large offset for the 31 px title only.
- **29** — Options has five entries: no fullscreen, no resolution, no music/SFX
  split, no language (the design doc is Spanish; the UI is English-only, with all
  strings hardcoded in GDScript).
- **30** — The tutorial is a passive six-page slideshow. One guided turn against
  a scripted opponent would teach more than all six pages. Pairs with **19**.

### Structure

- **31 — Split `GameManager.gd`.** Now **4,596 lines** (was 5,093). The next
  clean seam is the remaining `_step_*` / `_spawn_*` weapon blocks into a
  `Weapons` module.
- **32 — Replace `_unhandled_key_input`.** ~211 lines of near-duplicate
  per-mode keycode branches. Both the maintenance hazard and the reason **23**
  does not exist.
- **33 — Rate-limit `POST /rooms`.** Joins and socket messages are throttled;
  room *creation* is not.

---

## Handoff result

- Final commit: `e0a686e` on `remove-dead-features` (not merged, not deployed)
- Verification performed: 20/20 Godot suites with zero engine errors; 34/34
  backend tests; backend typecheck clean; all four kits confirmed to start a
  match; HUD reference capture regenerated and visually confirmed
- Known limitations: the branch is unmerged and the protocol change is breaking
  (see pending decision 1); backlog items 18–33 untouched
- Next recommended action: **item 19 (difficulty selection)** — self-contained,
  testable without playtesting, and the largest single improvement to the new
  player experience. Item 18 is more valuable but needs human playtesting between
  iterations.
- Items requiring director approval: pending decisions 1–3 above
