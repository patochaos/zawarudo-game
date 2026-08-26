# Runtime atlas — Rook animated arena fighter v1

Generated from `art_source/sprites/rook-animated-v1` by
`tools/art/build_rook_animated.py`.

- cell: 384x256
- baseline: y=238
- target upright source height: approximately 224 px
- game draw rectangle: 87x58 px
- states: IDLE 4, WALK 6, RUN 6, RISE 2, FALL 2, LOCK 2, SHOT 4, DEFEAT 4
- `ghost-*.png`: alpha-identical monochrome atlases for adaptive planning ghosts

Every generated source sheet uses one shared scale. Short, crouched and kneeling
poses are never enlarged independently. The Rook skin is canonical-color only;
team identity remains in existing markers and effects.
