# Kenney asset subset

This directory contains only the Kenney assets used by ZAWARUDO. They were
selected from `Kenney Game Assets All-in-1 3.7.0`; the complete bundle is not
vendored into the project.

The included fonts, input prompts, audio, particles, light mask, and mobile
control artwork are Creative Commons Zero (CC0). Attribution is optional. The
original per-pack license files are preserved in `licenses/`.

Integration rules:

- Keep original Kenney files here and apply Za Warudo palette changes at draw
  time, rather than overwriting source art.
- Add only assets referenced by the game or a test.
- Imported effects are cosmetic and must not change collision, simulation,
  replay state, or online digests.
- Prompt icons remain neutral outlines so their tint communicates player or
  action ownership.
