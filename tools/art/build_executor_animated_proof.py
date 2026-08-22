from __future__ import annotations

import argparse
import json
from collections import deque
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw

from build_simplified_executor_proof import extract_foreground


CELL_SIZE = (384, 256)
BASELINE_Y = 238
TARGET_UPRIGHT_HEIGHT = 224
ALPHA_CUTOFF = 48


@dataclass(frozen=True)
class SheetSpec:
    source_name: str
    columns: int
    rows: int
    reference_height: int
    outputs: tuple[tuple[str, tuple[int, ...]], ...]


SHEETS = (
    SheetSpec("idle-source.png", 4, 1, 667, (("idle", (0, 1, 2, 3)),)),
    SheetSpec("walk-source.png", 3, 2, 452, (("walk", (0, 1, 2, 3, 4, 5)),)),
    SheetSpec("run-source.png", 3, 2, 387, (("run", (0, 1, 2, 3, 4, 5)),)),
    SheetSpec(
        "air-source.png",
        2,
        2,
        439,
        (("rise", (0, 1)), ("fall", (2, 3))),
    ),
    SheetSpec(
        "action-source.png",
        3,
        2,
        373,
        (("lock", (0, 1)), ("shoot", (2, 3, 4, 5))),
    ),
    # One shared scale is especially important here: the prone frame should
    # become shorter because of the pose, not grow to fill the cell.
    SheetSpec("defeat-source.png", 4, 1, 427, (("defeat", (0, 1, 2, 3)),)),
)


def trim_foreground(cell: Image.Image) -> Image.Image:
    alpha = cell.getchannel("A")
    width, height = alpha.size
    pixels = alpha.load()
    visited = bytearray(width * height)
    largest: list[tuple[int, int]] = []
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
                    (point_x - 1, point_y), (point_x + 1, point_y),
                    (point_x, point_y - 1), (point_x, point_y + 1),
                ):
                    if next_x < 0 or next_y < 0 or next_x >= width or next_y >= height:
                        continue
                    next_flat = next_y * width + next_x
                    if visited[next_flat] or pixels[next_x, next_y] < ALPHA_CUTOFF:
                        continue
                    visited[next_flat] = 1
                    pending.append((next_x, next_y))
            if len(component) > len(largest):
                largest = component

    if not largest:
        raise ValueError("Generated cell contains no usable foreground")
    keep = Image.new("L", cell.size, 0)
    keep_pixels = keep.load()
    for x, y in largest:
        keep_pixels[x, y] = pixels[x, y]
    cleaned = cell.copy()
    cleaned.putalpha(keep)
    used = keep.getbbox()
    if used is None:
        raise ValueError("Generated cell contains no usable foreground")
    return cleaned.crop(used)


def sheet_cells(source: Image.Image, spec: SheetSpec) -> list[Image.Image]:
    cells: list[Image.Image] = []
    for row in range(spec.rows):
        top = round(source.height * row / spec.rows)
        bottom = round(source.height * (row + 1) / spec.rows)
        for column in range(spec.columns):
            left = round(source.width * column / spec.columns)
            right = round(source.width * (column + 1) / spec.columns)
            cells.append(trim_foreground(source.crop((left, top, right, bottom))))
    return cells


def normalized_cell(frame: Image.Image, scale: float) -> Image.Image:
    width = max(1, round(frame.width * scale))
    height = max(1, round(frame.height * scale))
    # Leave a small safety gutter for filtering at the edge of broad poses.
    fit = min(1.0, (CELL_SIZE[0] - 16) / width, (CELL_SIZE[1] - 12) / height)
    width = max(1, round(width * fit))
    height = max(1, round(height * fit))
    frame = frame.resize((width, height), Image.Resampling.LANCZOS)

    cell = Image.new("RGBA", CELL_SIZE, (0, 0, 0, 0))
    x = (CELL_SIZE[0] - width) // 2
    y = BASELINE_Y - height
    cell.alpha_composite(frame, (x, y))
    return cell


def save_atlas(output: Path, name: str, frames: list[Image.Image]) -> None:
    atlas = Image.new("RGBA", (CELL_SIZE[0] * len(frames), CELL_SIZE[1]), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        atlas.alpha_composite(frame, (index * CELL_SIZE[0], 0))
    atlas.save(output / f"{name}.png")

    ghost_atlas = Image.new("RGBA", atlas.size, (255, 255, 255, 0))
    ghost_atlas.putalpha(atlas.getchannel("A"))
    ghost_atlas.save(output / f"ghost-{name}.png")


def save_contact_sheet(output: Path, atlases: dict[str, list[Image.Image]]) -> None:
    preview_cell = (192, 128)
    label_width = 116
    margin = 14
    row_height = preview_cell[1] + 18
    width = label_width + max(len(frames) for frames in atlases.values()) * preview_cell[0] + margin * 2
    height = margin * 2 + len(atlases) * row_height
    sheet = Image.new("RGBA", (width, height), (12, 11, 19, 255))
    draw = ImageDraw.Draw(sheet)
    for row, (name, frames) in enumerate(atlases.items()):
        y = margin + row * row_height
        draw.text((margin, y + 50), name.upper(), fill=(239, 205, 91, 255))
        for index, frame in enumerate(frames):
            preview = frame.resize(preview_cell, Image.Resampling.LANCZOS)
            x = label_width + index * preview_cell[0]
            if (index + row) % 2 == 0:
                draw.rectangle((x, y, x + preview_cell[0], y + preview_cell[1]), fill=(27, 23, 39, 255))
            else:
                draw.rectangle((x, y, x + preview_cell[0], y + preview_cell[1]), fill=(34, 29, 47, 255))
            sheet.alpha_composite(preview, (x, y))
            draw.text((x + 6, y + 5), str(index + 1), fill=(180, 171, 198, 255))
    sheet.save(output / "contact-sheet.png")


def main() -> None:
    parser = argparse.ArgumentParser(description="Normalize generated Executor animation sheets.")
    parser.add_argument("source", type=Path, help="Folder containing the five generated source sheets")
    parser.add_argument("output", type=Path, help="Versioned runtime-art output folder")
    args = parser.parse_args()

    args.output.mkdir(parents=True, exist_ok=True)
    atlases: dict[str, list[Image.Image]] = {}
    for spec in SHEETS:
        with Image.open(args.source / spec.source_name) as raw:
            foreground = extract_foreground(raw)
        cells = sheet_cells(foreground, spec)
        scale = TARGET_UPRIGHT_HEIGHT / spec.reference_height
        normalized = [normalized_cell(frame, scale) for frame in cells]
        for name, indices in spec.outputs:
            selected = [normalized[index] for index in indices]
            atlases[name] = selected
            save_atlas(args.output, name, selected)

    ghost = Image.new("RGBA", CELL_SIZE, (255, 255, 255, 0))
    ghost.putalpha(atlases["idle"][0].getchannel("A"))
    ghost.save(args.output / "ghost.png")
    save_contact_sheet(args.output, atlases)

    manifest = {
        "cell_size": list(CELL_SIZE),
        "baseline_y": BASELINE_Y,
        "target_upright_height": TARGET_UPRIGHT_HEIGHT,
        "states": {name.upper(): len(frames) for name, frames in atlases.items()},
        "source_order": [spec.source_name for spec in SHEETS],
    }
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(args.output)


if __name__ == "__main__":
    main()
