# Kenney asset subset

This directory contains only the Kenney assets used by ZAWARUDO. They were
selected from `Kenney Game Assets All-in-1 3.7.0`; the complete bundle is not
vendored into the project.

The included fonts, input prompts, audio, arena patterns, cursors, class
reticles, particles, light mask, and mobile control artwork are Creative
Commons Zero (CC0). Attribution is optional. The original per-pack license
files are preserved in `licenses/`.

The audio subset covers UI navigation, temporal transitions, varied impacts,
distinct launch/recall cues for every fighter weapon, SUPER readiness, and
match-start/winner announcements. No music loop is used, keeping the planning
silence and sub-second execution burst as the game's central audio rhythm.

Audio source map for the fighter-identity pass:

- Duelist uses Foley `woosh1`, `woosh6`–`woosh8`, `swordStone2`, `sword1`,
  `swordMetal1`–`swordMetal2`, plus Impact Sounds light-metal variants. These
  cover throw, SUPER waves, ricochet, fighter contact, clashes, and misses.
- Rook uses Digital `phaseJump3` and `phaseJump5`, Foley `swordMetal5`, and
  Impact Sounds `impactMetal_heavy_004` / `impactPunch_heavy_004`. These cover
  ordinary/empowered dashes, guard contact, hard stops, and fighter contact.
- Eclipse uses RPG `knifeSlice2` / `metalClick`, Digital `phaserUp4` /
  `phaserUp7`, Foley `swordSlide1` / `sword4`, and distinct Impact Sounds
  medium-metal variants. These cover throw, recall, bounce, stick, projectile
  clash, break, fighter contact, and SUPER.
- Pulse uses Sci-Fi Sounds `laserSmall_001`, `impactMetal_003`,
  `laserLarge_002`, `forceField_002`–`forceField_003`,
  `lowFrequency_explosion_001`, `explosionCrunch_002`, and `laserLarge_004`.
  These cover plasma, orb, contact, denial, small/combo detonation, and SUPER.
- `Digital Audio` `powerUp7` supplies SUPER-ready; `Voiceover Pack Fighter`
  `prepare_yourself` and `winner` supply the announcer cues. Global UI,
  time-state, fighter-damage, arena, and temporal-core cues keep their own
  dedicated assets.

Visual source map:

- `Pattern Pack Lines` supplies a different low-opacity geometric motif for
  each arena. Backdrop code applies the level palette and keeps the motif below
  gameplay contrast.
- `Crosshair Pack` supplies distinct silhouettes for Duelist, Rook, Eclipse,
  and Pulse planning reticles. Existing trajectory simulation remains the
  aiming authority; these icons only reinforce fighter identity at its tip.
- `Cursor Pack` supplies the neutral outline pointer, pointing hand, busy, and
  unavailable cursors used across menus.
- `Splat Pack` and `Explosion Pack` supply monochrome kill and sonic-ring
  masks. Effects code tints and fades them, including reduced-flash scaling.

Integration rules:

- Keep original Kenney files here and apply Za Warudo palette changes at draw
  time, rather than overwriting source art.
- Add only assets referenced by the game or a test.
- Imported effects are cosmetic and must not change collision, simulation,
  replay state, or online digests.
- Prompt icons remain neutral outlines so their tint communicates player or
  action ownership.
