# Runtime atlas — Gilded Executor animated arena prototype v1

Generated from `art_source/sprites/gilded-executor-animated-v1` by
`tools/art/build_executor_animated_proof.py`.

- cell: 384x256
- baseline: y=238
- target upright source height: 224 px
- game draw rectangle: 87x58 px
- states: IDLE 4, WALK 6, RUN 6, RISE 2, FALL 2, LOCK 2, SHOT 4, DEFEAT 4
- `ghost-*.png`: alpha-matched monochrome atlases for animated planning ghosts

The 87x58 draw rectangle preserves the accepted ~51 px visible body height; its
extra width only accommodates the cape and broad action poses. Do not normalize
individual pose bounds independently, because that makes crouched and prone
frames grow larger than standing frames.
