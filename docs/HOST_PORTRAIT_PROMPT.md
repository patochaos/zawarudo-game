# Host portrait prompt

The LEARN TO PLAY briefing shows a host portrait at the left of the panel
(`scripts/GuidedPractice.gd`, drawn by `scripts/HostPortrait.gd`). Until a painted
portrait exists, the bust is drawn in-engine. Drop the generated image at
`assets/art/portraits/host-portrait-v1.png` and it replaces the drawn figure
automatically; the gold time-stop rings and plate stay behind it.

## File contract

- PNG, 1254 x 1254, transparent background (same as the roster portraits in
  `assets/art/portraits/`).
- Head and shoulders only, cropped below the collar line. Head centred, filling
  about 60 percent of the height. No hands, no weapons, no text, no watermark.
- Three-quarter view, facing the viewer's right, so he looks toward the briefing text.
- Keep the figure inside the frame: hair spikes may touch the top edge but nothing
  else is cut off.

## Prompt (Google Gemini)

```text
Anime character portrait, head and shoulders, three-quarter view facing slightly to the right, looking at the viewer with a smug, superior half-smile that shows one small fang. Cel-shaded illustration with clean black lineart, flat colors and two-tone shading, in the style of a 1990s-2010s shonen fighting anime. Square image, transparent background, no text, no watermark.

The character: a tall, aristocratic vampire lord who can stop time. Pale skin. Thick swept-back golden-blond hair in large sharp spikes that flare up and back. Narrow crimson eyes with small pupils, heavy angled eyebrows. On his forehead a dark green headband with a small red heart-shaped ornament at the centre. He wears an orange-yellow high-collared jacket with the collar flared open, a black tank top underneath, and a small green heart-shaped clasp at the chest. Earrings shaped like small hearts. Confident, theatrical, villainous, charismatic.

Lighting: strong gold key light from the upper left, deep violet rim light from the right, dark violet shadows. Palette: gold #F5B02E, violet #B861F2, near-black #050209, pale skin, crimson eyes.

Framing: head centred, filling about 60 percent of the frame height, cropped just below the collar. Nothing outside the figure.
```

If Gemini flags the description, drop the words "vampire" and "villainous" and
keep the rest; the look carries the character.

## Negative cues

```text
no full body, no hands, no weapons, no background scenery, no text, no logo, no
photorealism, no soft painterly blur, no muted colours, no extra characters
```

## Provenance

- Generator: Google Gemini, run by the user on 2026-10-14 with the prompt above.
  Gemini returned a 2048 x 2048 JPG with the checkerboard painted into the
  pixels instead of a real alpha channel.
- Conversion: a one-off Godot script flood-filled light, unsaturated pixels
  inward from the image border (the black outline stops the fill), eroded one
  pixel of grey fringe, resized to 1254 x 1254 with Lanczos and saved the PNG.
  Regenerate the same way if the source changes; ask Gemini for a solid
  `#050209` background instead of transparency to skip the keying step.
- Original download: `Gemini_Generated_Image_naooocnaooocnaoo.jpg` (not in the
  repository).
