# Runtime atlas — Eclipse simplified animated arena fighter v1

Generated from `art_source/sprites/eclipse-animated-v1` by
`tools/art/build_eclipse_animated.py`.

- cell: 384x256
- baseline: y=238
- game draw rectangle: 87x58 px
- states: IDLE 4, WALK 6, RUN 6, RISE 2, FALL 2, LOCK 2, SHOT 4, DEFEAT 4
- `ghost-*.png`: alpha-identical monochrome atlases for planning ghosts
- `contact-sheet.png`: all 30 color frames at runtime-relative scale

The smooth permanent aureole is part of every body silhouette. Twelve-bladed
coronas remain separate live projectiles and are never baked into these atlases.
