# Za Warudo project rules

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
