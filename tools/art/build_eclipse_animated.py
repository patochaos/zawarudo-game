from __future__ import annotations

"""Build the simplified Eclipse sheets with the shared fighter-atlas pipeline."""

import build_pulse_animated as shared


# Eclipse uses the same 30-frame state contract and 384x256 runtime cells as
# Duelist, Rook and Pulse. Each reference height is the tallest full silhouette
# (including the permanent aureole) in that generated source sheet, so all six
# sheets normalize to one consistent 224 px source envelope.
SHEETS = (
    shared.SheetSpec("idle-source.png", 4, 1, 731, (("idle", (0, 1, 2, 3)),)),
    shared.SheetSpec("walk-source.png", 3, 2, 440, (("walk", (0, 1, 2, 3, 4, 5)),)),
    shared.SheetSpec("run-source.png", 3, 2, 389, (("run", (0, 1, 2, 3, 4, 5)),)),
    shared.SheetSpec(
        "air-source.png",
        2,
        2,
        542,
        (("rise", (0, 1)), ("fall", (2, 3))),
    ),
    shared.SheetSpec(
        "action-source.png",
        3,
        2,
        439,
        (("lock", (0, 1)), ("shot", (2, 3, 4, 5))),
    ),
    shared.SheetSpec("defeat-source.png", 4, 1, 618, (("defeat", (0, 1, 2, 3)),)),
)


def main() -> None:
    shared.SHEETS = SHEETS
    shared.main()


if __name__ == "__main__":
    main()
