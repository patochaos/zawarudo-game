from __future__ import annotations

import argparse
import json
from collections import deque
from pathlib import Path

from PIL import Image

from build_simplified_executor_proof import extract_foreground


CELL_SIZE = (384, 256)
BASELINE_Y = 238
TARGET_UPRIGHT_HEIGHT = 224
REFERENCE_BODY_HEIGHT = 586
ALPHA_CUTOFF = 48
POSE_NAMES = ("idle", "walk", "lock", "shot")


def connected_figures(source: Image.Image) -> list[Image.Image]:
    """Extract the four large pose components and order them left to right."""
    alpha = source.getchannel("A")
    width, height = alpha.size
    pixels = alpha.load()
    visited = bytearray(width * height)
    components: list[list[tuple[int, int]]] = []
    for y in range(height):
        for x in range(width):
            flat = y * width + x
            if visited[flat] or pixels[x, y] < ALPHA_CUTOFF:
                continue
            visited[flat] = 1
            component: list[tuple[int, int]] = []
            pending = deque(((x, y),))
            while pending:
                point_x, point_y = pending.popleft()
                component.append((point_x, point_y))
                for next_x, next_y in (
                    (point_x - 1, point_y),
                    (point_x + 1, point_y),
                    (point_x, point_y - 1),
                    (point_x, point_y + 1),
                ):
                    if next_x < 0 or next_y < 0 or next_x >= width or next_y >= height:
                        continue
                    next_flat = next_y * width + next_x
                    if visited[next_flat] or pixels[next_x, next_y] < ALPHA_CUTOFF:
                        continue
                    visited[next_flat] = 1
                    pending.append((next_x, next_y))
            if len(component) >= 1_000:
                components.append(component)

    if len(components) != 4:
        raise ValueError(f"Expected exactly four connected Rook poses, found {len(components)}")

    figures: list[tuple[int, Image.Image]] = []
    for component in components:
        left = min(point[0] for point in component)
        top = min(point[1] for point in component)
        right = max(point[0] for point in component) + 1
        bottom = max(point[1] for point in component) + 1
        keep = Image.new("L", source.size, 0)
        keep_pixels = keep.load()
        for point_x, point_y in component:
            keep_pixels[point_x, point_y] = pixels[point_x, point_y]
        figure = source.copy()
        figure.putalpha(keep)
        figures.append((left, figure.crop((left, top, right, bottom))))
    figures.sort(key=lambda item: item[0])
    return [figure for _, figure in figures]


def normalized_cell(frame: Image.Image, scale: float) -> Image.Image:
    width = max(1, round(frame.width * scale))
    height = max(1, round(frame.height * scale))
    if width > CELL_SIZE[0] - 12 or height > CELL_SIZE[1] - 12:
        raise ValueError(
            f"Pose {frame.size} does not fit a {CELL_SIZE} cell at shared scale {scale:.4f}"
        )
    frame = frame.resize((width, height), Image.Resampling.LANCZOS)
    cell = Image.new("RGBA", CELL_SIZE, (0, 0, 0, 0))
    cell.alpha_composite(frame, ((CELL_SIZE[0] - width) // 2, BASELINE_Y - height))
    return cell


def save_atlas(path: Path, frames: list[Image.Image], monochrome: bool = False) -> None:
    atlas = Image.new("RGBA", (CELL_SIZE[0] * len(frames), CELL_SIZE[1]), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        rendered = frame
        if monochrome:
            rendered = Image.new("RGBA", frame.size, (255, 255, 255, 0))
            rendered.putalpha(frame.getchannel("A"))
        atlas.alpha_composite(rendered, (index * CELL_SIZE[0], 0))
    atlas.save(path)


def main() -> None:
    parser = argparse.ArgumentParser(description="Build the four-pose Rook arena-scale proof.")
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    with Image.open(args.source) as raw:
        foreground = extract_foreground(raw)
    figures = connected_figures(foreground)
    # One shared scale governs every pose. The slight reduction from the ideal
    # 224 px body target keeps the tallest diagonal lance inside baseline y=238
    # without independently shrinking the WALK or LOCK cells.
    scale = min(
        TARGET_UPRIGHT_HEIGHT / REFERENCE_BODY_HEIGHT,
        BASELINE_Y / max(figure.height for figure in figures),
    )
    frames = [normalized_cell(figure, scale) for figure in figures]

    args.output.mkdir(parents=True, exist_ok=True)
    save_atlas(args.output / "arena-proof.png", frames)
    save_atlas(args.output / "ghost-arena-proof.png", frames, monochrome=True)
    manifest = {
        "cell_size": list(CELL_SIZE),
        "baseline_y": BASELINE_Y,
        "target_upright_height": TARGET_UPRIGHT_HEIGHT,
        "reference_body_height": REFERENCE_BODY_HEIGHT,
        "shared_source_scale": scale,
        "draw_rect": [-43.5, -29.921875, 87.0, 58.0],
        "poses": list(POSE_NAMES),
    }
    (args.output / "arena-proof-manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    print(args.output / "arena-proof.png")


if __name__ == "__main__":
    main()
