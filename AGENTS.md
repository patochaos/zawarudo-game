# Za Warudo project rules

## Git workflow

- Work directly on `main` by default.
- Do not create, switch to, or continue work on another branch unless the user
  explicitly asks for branch-based work in the current request.
- Before making changes, verify the active branch. If it is not `main` and the
  user did not request that branch, stop and explain the mismatch before editing.
- Keep `main` as the only long-lived branch after explicitly requested
  consolidation work.

## Local play

- Keep `Play.bat` working as the canonical way to launch the latest local
  working tree through Godot.
- `Play.bat` must not depend on an exported executable or require a build step.
- After changes that affect startup, verify that `Play.bat` still resolves Godot
  and launches the project from this repository.

## Builds and archives

- Never create or refresh a Windows ZIP or Web ZIP unless the user explicitly
  asks for that archive in the current request.
- Do not treat release packaging as an automatic verification step.
- Normal verification should run the source project and its tests. Unpacked
  exports may be produced only when they are relevant to the request; ZIP
  packaging always requires an explicit request.
