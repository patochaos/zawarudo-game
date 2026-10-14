# ZAWARUDO itch.io upload

Project: https://patochaos.itch.io/zawarudo

Current release: **0.3.0-tuning.1**. Web and Windows use the existing
`html5` and `windows` channels. The release adds 75 offline tuning settings and
four presets: Tactical duel, Clear read, Crossfire, and Quick verdict.
Online matches, tutorials, and INTERCEPTION keep their own rules.

Published exports and their file hashes are in `build/itch/0.3.0-tuning.1/`.

`Build.bat` creates unpacked exports in `build/itch/web` and `build/itch/windows`.
When ZIPs are requested, package each directory's contents as:

- `ZAWARUDO-web.zip` — browser build. `index.html` is at the ZIP root.
- `ZAWARUDO-windows.zip` — portable Windows download.

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
butler push "build/itch/0.3.0-tuning.1/web" patochaos/zawarudo:html5 --userversion 0.3.0-tuning.1
butler push "build/itch/0.3.0-tuning.1/windows" patochaos/zawarudo:windows --userversion 0.3.0-tuning.1
```

On the itch.io edit page, mark the `html5` channel as playable in the browser.
