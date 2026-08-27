# Runtime atlas — Rook simplified animated arena fighter v2

Generated from `art_source/sprites/rook-animated-v2` by
`tools/art/build_rook_animated.py`.

- cell: 384x256
- baseline: y=238
- game draw rectangle: 87x58 px
- states: IDLE 4, WALK 6, RUN 6, RISE 2, FALL 2, LOCK 2, SHOT 4, DEFEAT 4
- `ghost-*.png`: alpha-identical monochrome atlases for planning ghosts
- `contact-sheet.png`: all 30 color frames at runtime-relative scale

This v2 replaces v1 at runtime. The v1 directory remains as historical source.
