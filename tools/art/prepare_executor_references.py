from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


PANELS = {
    "front": (70, 18, 480, 840),
    "left": (430, 18, 780, 840),
    "back": (690, 18, 1090, 840),
    "three-quarter": (1050, 18, 1510, 840),
}
CANVAS_SIZE = (460, 850)
BACKGROUND = (238, 238, 238, 255)


def prepare_panel(source: Image.Image, bounds: tuple[int, int, int, int]) -> Image.Image:
    panel = source.crop(bounds).convert("RGBA")
    canvas = Image.new("RGBA", CANVAS_SIZE, BACKGROUND)
    x = (CANVAS_SIZE[0] - panel.width) // 2
    canvas.alpha_composite(panel, (x, 0))
    return canvas


def main() -> None:
    parser = argparse.ArgumentParser(description="Split the Executor model sheet into Blender references.")
    parser.add_argument("source", type=Path)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    with Image.open(args.source) as source:
        for name, bounds in PANELS.items():
            output = args.output_dir / f"gilded-executor-{name}-reference-v1.png"
            prepare_panel(source, bounds).save(output)
            print(output)


if __name__ == "__main__":
    main()
