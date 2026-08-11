# ZAWARUDO 0.2.0-playtest.1 — itch.io upload

The ready-to-upload files are generated in `build/itch/`:

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
butler push "build/itch/web" patochaos/za-warudo:html5 --userversion 0.2.0-playtest.1
butler push "build/itch/windows" patochaos/za-warudo:windows --userversion 0.2.0-playtest.1
```

On the itch.io edit page, mark the `html5` channel as playable in the browser.
