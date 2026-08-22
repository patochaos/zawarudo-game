from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


CELL_SIZE = 256
POSE_NAMES = ("idle", "run", "lock", "rise")


def extract_foreground(source: Image.Image) -> Image.Image:
    """Remove the pale checkerboard baked into an image-generation draft."""
    rgb = source.convert("RGB")
    rgba = Image.new("RGBA", rgb.size)
    output = []
    for red, green, blue in rgb.get_flattened_data():
        darkest = min(red, green, blue)
        spread = max(red, green, blue) - darkest
        # The checkerboard is near-white neutral grey. Preserve warm ivory by
        # weighting channel spread as strongly as distance from white.
        alpha = max((255 - darkest - 18) * 8, (spread - 4) * 16)
        output.append((red, green, blue, max(0, min(255, alpha))))
    rgba.putdata(output)
    return rgba


def normalized_pose(source: Image.Image, left: int, right: int) -> Image.Image:
    pose = source.crop((left, 0, right, source.height))
    alpha = pose.getchannel("A")
    used = alpha.point(lambda value: 255 if value > 12 else 0).getbbox()
    if used is None:
        raise ValueError(f"No foreground found between x={left} and x={right}")
    pose = pose.crop(used)
    scale = min(224 / pose.width, 224 / pose.height)
    size = (max(1, round(pose.width * scale)), max(1, round(pose.height * scale)))
    pose = pose.resize(size, Image.Resampling.LANCZOS)

    cell = Image.new("RGBA", (CELL_SIZE, CELL_SIZE), (0, 0, 0, 0))
    x = (CELL_SIZE - pose.width) // 2
    # A shared baseline makes the atlas directly comparable at runtime scale.
    y = 238 - pose.height
    cell.alpha_composite(pose, (x, y))
    return cell


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build the four-pose simplified Executor review atlas."
    )
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    with Image.open(args.source) as raw:
        source = extract_foreground(raw)

    # The draft deliberately uses one horizontal row. These boundaries keep
    # pose extraction deterministic while leaving room for broad action poses.
    width = source.width
    boundaries = (0, round(width * 0.19), round(width * 0.50), round(width * 0.79), width)
    cells = [
        normalized_pose(source, boundaries[index], boundaries[index + 1])
        for index in range(4)
    ]

    atlas = Image.new("RGBA", (CELL_SIZE * len(cells), CELL_SIZE), (0, 0, 0, 0))
    for index, cell in enumerate(cells):
        atlas.alpha_composite(cell, (index * CELL_SIZE, 0))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(args.output)
    for name, cell in zip(POSE_NAMES, cells):
        cell.save(args.output.with_name(f"{name}.png"))
    print(args.output)


if __name__ == "__main__":
    main()
