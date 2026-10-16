# ZAWARUDO itch.io upload

Project: https://patochaos.itch.io/zawarudo

Current release: **0.4.2-pacing.1**. Web and Windows use the existing
`html5` and `windows` channels. This release answers the October playtest:
platforms are spaced 140px apart with three raised tiers on every arena,
planning turns last four seconds, the action phase plays at 0.35x speed, a kill
slows to 0.15x with a camera push-in and then eases back, versus openings are
dealt at random (a single human against one CPU always starts on the left), and
UNDO reports what it did. Online rooms add a selection phase where players pick
fighters and vote on the arena and match length; it needs the protocol 4
backend, which also still accepts older clients. 0.4.1-names.2 was a copy pass
over 0.4.1-names.1.

Published exports and their file hashes are in `build/itch/0.4.2-pacing.1/`.

`Build.bat` creates unpacked exports in `build/itch/web` and `build/itch/windows`.
When ZIPs are requested, package each directory's contents as:

- `ZAWARUDO-web.zip`: browser build. `index.html` is at the ZIP root.
- `ZAWARUDO-windows.zip`: portable Windows download.

## Page settings

1. Create or edit the project as **HTML Game**.
2. Upload `ZAWARUDO-web.zip` and select **This file will be played in the browser**.
3. Choose **Embed in page**, viewport **1280 × 720**.
4. Enable **Click to Play** and the fullscreen button.
5. Enable **Mobile friendly**; the Web build exposes landscape touch controls.
6. Upload `ZAWARUDO-windows.zip` as an additional downloadable file and mark it
   **Windows**.
7. Use **In development** while this remains a prototype.

## Optional butler upload

After creating the itch.io project page and installing/authenticating butler:

```powershell
butler push "build/itch/0.4.2-pacing.1/web" patochaos/zawarudo:html5 --userversion 0.4.2-pacing.1
butler push "build/itch/0.4.2-pacing.1/windows" patochaos/zawarudo:windows --userversion 0.4.2-pacing.1
```

On the itch.io edit page, mark the `html5` channel as playable in the browser.
