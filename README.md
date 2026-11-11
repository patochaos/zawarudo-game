# ZAWARUDO: Tactical Knife Duel

A 2D side-view knife duel built in Godot 4.7. Both players plan in a frozen
world, then a short burst of real-time physics resolves both plans at once.
Players and knives keep their position and velocity across each freeze, so a
knife thrown now can still be a threat several turns later.

The Duelist is the only fighter. Current version: `0.4.2-pacing.1`
(`config/version` in `project.godot`).

## Run it

Install Godot 4.7 and double-click one of these:

| File | What it does |
|---|---|
| **`Play.bat`** | Canonical local launcher. Runs the latest working tree without an export step. |
| **`Play-1v3-CPU.bat`** | Skips the menus into a four-fighter free-for-all: you (keyboard) against three STANDARD CPUs. Same as `Play.bat -- --vs-3-cpu`. |
| **`Play-Source.bat`** | Source-launch implementation used by `Play.bat`. Set `GODOT_DIR` at the top if Godot isn't in `D:\Godot`. |
| **`Build.bat`** | Exports unpacked Windows + Web folders. It never creates ZIP archives. |
| **`Build-Web.bat`** | Generates and validates the browser build in `build/web`. |
| **`Deploy-Web.bat`** | Generates the browser build and publishes it to Vercel production. |

Or from a shell in the project folder:

```bash
godot --path .
```

## Modes

- **START DUEL**: the opponent ladder. Five named CPUs in order, each in its own
  arena, first to three hits.
- **LEARN TO PLAY**: three playable lessons, then the first ladder duel.
- **CUSTOM MATCH**: any of the five arenas, 2 to 4 fighters, each CPU's skill,
  free-for-all or team battle, first to 3, 5 or 7 hits.
- **INTERCEPTION**: a fixed-rule duel against a Standard CPU on a compact court.
- **ONLINE**: private rooms for 2 or 4 players.
- **GAME TUNING**: offline tuning sliders and presets.
- **Experiments**: `Play.bat -- --dev-tools` adds FATE TRIAL and SANDBOX to the
  title screen and enables the F1-F10 developer shortcuts.

Rules, controls, arenas and every system are described in
[docs/REFERENCE.md](docs/REFERENCE.md).

## Play online

Play the current production build at **https://zawarudo-pi.vercel.app**.

The web client is hosted on Vercel. Private rooms run through the Cloudflare
Worker in `backend/`. One player creates a room and shares its six-character
code; the others join with it. Everyone needs the same build. See
[Online](docs/REFERENCE.md#online) and
[four-player verification](docs/FOUR_PLAYER_ONLINE.md).

## Tests

`tests/` contains only test suites, and every one of them runs in CI.

```powershell
.\scripts\Test-Godot.ps1                      # every suite
.\scripts\Test-Godot.ps1 -Suite CoreDemoTest  # one suite
```

The room service has its own checks:

```powershell
cd backend
npm test
npm run typecheck
```

Screenshot capture scripts live in `tools/captures/` and long simulations in
`tools/sims/`. They are run by hand and are not part of the suite run.

## Releases

`.github/workflows/publish.yml` runs the Godot suites and the room service
checks on every push to `main` and every pull request. It publishes only when
a `v*` tag is pushed or the workflow is started by hand. A publish exports the
Web and Windows presets with Godot 4.7.1 and pushes them to the itch.io project
`patochaos/zawarudo` (channels `html5` and `windows`).

The Vercel web client is deployed separately with `Deploy-Web.bat`. The room
service is deployed with `npx wrangler deploy` from `backend/`.

Windows and Web ZIP archives are created only on explicit request.

## Documentation

| Document | Contents |
|---|---|
| [docs/REFERENCE.md](docs/REFERENCE.md) | Mechanics and systems: loop, movement, controls, arenas, knives, super, AI, online, tuning, file responsibilities, developer tools |
| [docs/GAME_DESIGN.md](docs/GAME_DESIGN.md) | Diseño de juego: visión, pilares, contratos de experiencia y marco para futuras decisiones |
| [docs/CORE_PLAYTEST.md](docs/CORE_PLAYTEST.md) | Scope of the public demo and the observation gates |
| [docs/PLAYTEST_GUIDE.md](docs/PLAYTEST_GUIDE.md) | Guide for testers |
| [docs/PRODUCTION_ROADMAP.md](docs/PRODUCTION_ROADMAP.md) | Production gates and art pipeline |
| [docs/FOUR_PLAYER_ONLINE.md](docs/FOUR_PLAYER_ONLINE.md) | Four-player online verification and rollout |
| [docs/DUELIST_POLISH.md](docs/DUELIST_POLISH.md) | Planning and readability pass, benchmark playtests |
| [docs/characters/duelist.md](docs/characters/duelist.md) | The Duelist's canonical specification |
| [docs/archive/](docs/archive/) | Dated handoffs and the specifications of the removed fighters |

Art direction and polish notes for arenas, combat and sprites are the remaining
files in [docs/](docs/).

The Rook, The Pulse and The Eclipse, with the Close Camera, Real Time and Class
Lab experiments, were removed from the tree on 2026-11-10. Their last state is
preserved at git tag `archive/pre-prune-2026-11-10`.
