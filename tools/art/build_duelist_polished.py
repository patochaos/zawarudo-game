"""Pack the authored Duelist v2 sheets using explicit body anchors.

Art is generated with imagegen; this reuses the project's foreground extraction
and atlas/ghost writer. Anchors are in source pixels, not silhouette centers:
changing the coat outline must not move the fighter's body. No new dependencies.
"""
from __future__ import annotations

import json
from collections import deque
from pathlib import Path

from PIL import Image

from build_executor_animated_proof import CELL_SIZE, save_atlas, save_contact_sheet
from build_simplified_executor_proof import extract_foreground

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art_source/sprites/duelist-polished-v2"
OUTPUT = ROOT / "assets/art/fighters/duelist-polished-v2"

# (columns, rows, common scale, body anchors, output states)
# Ground anchors share a baseline; airborne anchors retain tucked-leg clearance.
SHEETS = {
    "idle": (4, 1, 224 / 514, [(266, 706), (691, 706), (1113, 706), (1538, 706)],
             {"idle": [0, 1, 2, 3]}),
    "walk": (3, 2, .50, [(321, 455), (790, 455), (1236, 455),
                        (320, 933), (794, 933), (1230, 933)],
             {"walk": [0, 1, 2, 3, 4, 5]}),
    "run": (3, 2, .49, [(324, 459), (785, 459), (1249, 459),
                       (321, 918), (780, 918), (1238, 918)],
            {"run": [0, 1, 2, 3, 4, 5]}),
    "air": (2, 2, .40, [(409, 570), (908, 570), (367, 1160), (950, 1160)],
            {"rise": [0, 1], "fall": [2, 3]}),
    "action": (3, 2, .50, [(305, 458), (744, 458), (1240, 458),
                          (320, 914), (805, 914), (1240, 914)],
               {"lock": [0, 1], "shoot": [2, 3, 4, 5]}),
    "defeat": (2, 2, .44, [(311, 540), (955, 540), (347, 1056), (966, 1056)],
               {"defeat": [0, 1, 2, 3]}),
}


def figures(source: Image.Image, count: int, rows: int) -> list[tuple[Image.Image, tuple]]:
    """Separate complete silhouettes, including hands extending across grid lines.

    A rectangular grid cut would amputate the release hand. Retain components
    by connectivity instead, then order by source row and horizontal position.
    """
    alpha = source.getchannel("A")
    width, height = source.size
    pixels = alpha.load()
    seen = bytearray(width * height)
    found = []
    for y in range(height):
        for x in range(width):
            flat = y * width + x
            if seen[flat] or pixels[x, y] < 48:
                continue
            seen[flat] = 1
            queue = deque([(x, y)])
            points = []
            while queue:
                px, py = queue.popleft()
                points.append((px, py))
                for nx, ny in ((px-1, py), (px+1, py), (px, py-1), (px, py+1)):
                    if 0 <= nx < width and 0 <= ny < height:
                        at = ny * width + nx
                        if not seen[at] and pixels[nx, ny] >= 48:
                            seen[at] = 1
                            queue.append((nx, ny))
            if len(points) < 1000:
                continue
            box = (min(p[0] for p in points), min(p[1] for p in points),
                   max(p[0] for p in points) + 1, max(p[1] for p in points) + 1)
            mask = Image.new("L", (box[2]-box[0], box[3]-box[1]))
            mask_pixels = mask.load()
            for px, py in points:
                mask_pixels[px-box[0], py-box[1]] = pixels[px, py]
            frame = source.crop(box)
            frame.putalpha(mask)
            found.append((frame, box))
    if len(found) != count:
        raise ValueError(f"Expected {count} complete figures, found {len(found)}")
    found.sort(key=lambda item: (int((item[1][1]+item[1][3]) / 2 / height * rows), item[1][0]))
    return found


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    atlases = {}
    metrics = {}
    for name, (columns, rows, scale, anchors, states) in SHEETS.items():
        with Image.open(SOURCE / f"{name}-source.png") as raw:
            # Preserve genuine alpha when present; older generated sheets contain
            # a pale checkerboard and use the established project extractor.
            rgba = raw.convert("RGBA")
            source = rgba if rgba.getchannel("A").getextrema()[0] == 0 else extract_foreground(raw)
        extracted = figures(source, columns * rows, rows)
        packed = []
        for (frame, box), (anchor_x, anchor_y) in zip(extracted, anchors):
            size = (round(frame.width * scale), round(frame.height * scale))
            at = (round(192 + (box[0] - anchor_x) * scale),
                  round(238 + (box[1] - anchor_y) * scale))
            if at[0] < 4 or at[1] < 4 or at[0]+size[0] > 380 or at[1]+size[1] > 252:
                raise ValueError(f"{name}: authored anchor clips frame {box}, at {at}, size {size}")
            cell = Image.new("RGBA", CELL_SIZE)
            cell.alpha_composite(frame.resize(size, Image.Resampling.LANCZOS), at)
            packed.append(cell)
        metrics[name] = [list(box) for _, box in extracted]
        for state, indices in states.items():
            atlases[state] = [packed[index] for index in indices]
    ordered = {state: atlases[state] for state in
               ("idle", "walk", "run", "rise", "fall", "lock", "shoot", "defeat")}
    for state, frames in ordered.items():
        save_atlas(OUTPUT, state, frames)
    ghost = Image.new("RGBA", CELL_SIZE, (255, 255, 255, 0))
    ghost.putalpha(ordered["idle"][0].getchannel("A"))
    ghost.save(OUTPUT / "ghost.png")
    save_contact_sheet(OUTPUT, ordered)
    manifest = {"cell_size": list(CELL_SIZE), "baseline_y": 238,
                "target_upright_height": 224,
                "states": {name.upper(): len(frames) for name, frames in ordered.items()},
                "source_bounds": metrics, "packing": "authored body anchors"}
    (OUTPUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Packed {sum(map(len, ordered.values()))} frames and matching ghosts: {OUTPUT}")


if __name__ == "__main__":
    main()
