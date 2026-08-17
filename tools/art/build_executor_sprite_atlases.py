from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw


STATES = {
    "idle": 6,
    "run": 8,
    "rise": 4,
    "fall": 4,
    "shoot": 6,
    "lock": 2,
}
CELL_SIZE = (256, 256)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build deterministic Executor sprite atlases.")
    parser.add_argument("--frames", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--preview", required=True, type=Path)
    return parser.parse_args()


def load_frame(path: Path) -> Image.Image:
    image = Image.open(path).convert("RGBA")
    if image.size != CELL_SIZE:
        raise ValueError(f"{path} has size {image.size}, expected {CELL_SIZE}")
    return image


def main() -> None:
    args = parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    args.preview.parent.mkdir(parents=True, exist_ok=True)
    atlases: dict[str, Image.Image] = {}

    for state, count in STATES.items():
        atlas = Image.new("RGBA", (CELL_SIZE[0] * count, CELL_SIZE[1]), (0, 0, 0, 0))
        for index in range(count):
            frame_path = args.frames / f"{state}_{index:02d}.png"
            if not frame_path.exists():
                raise FileNotFoundError(frame_path)
            atlas.alpha_composite(load_frame(frame_path), (index * CELL_SIZE[0], 0))
        atlas_path = args.output / f"{state}.png"
        atlas.save(atlas_path, optimize=True)
        atlases[state] = atlas
        print(f"Saved {atlas_path}")

    manifest = {
        "version": 1,
        "cell_size": list(CELL_SIZE),
        "fps": 12,
        "render_rect": [-64.0, -97.0, 128.0, 128.0],
        "states": STATES,
    }
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    preview_scale = 0.5
    cell_w = int(CELL_SIZE[0] * preview_scale)
    cell_h = int(CELL_SIZE[1] * preview_scale)
    label_h = 24
    preview = Image.new("RGB", (cell_w * max(STATES.values()), (cell_h + label_h) * len(STATES)), (12, 9, 22))
    draw = ImageDraw.Draw(preview)
    for row, (state, count) in enumerate(STATES.items()):
        y = row * (cell_h + label_h)
        draw.text((8, y + 5), state.upper(), fill=(235, 205, 130))
        strip = atlases[state].resize((cell_w * count, cell_h), Image.Resampling.LANCZOS).convert("RGB")
        preview.paste(strip, (0, y + label_h))
    preview.save(args.preview, optimize=True)
    print(f"Saved {args.preview}")


if __name__ == "__main__":
    main()
