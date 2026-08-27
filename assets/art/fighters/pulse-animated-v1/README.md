# Runtime atlas — The Pulse animated arena fighter v1

Generated from `art_source/sprites/pulse-animated-v1` by
`tools/art/build_pulse_animated.py`.

- cell: 384x256
- baseline: y=238
- target upright body height: approximately 224 px
- game draw rectangle: 87x58 px
- states: IDLE 4, WALK 6, RUN 6, RISE 2, FALL 2, LOCK 2, SHOT 4, DEFEAT 4
- `ghost-*.png`: alpha-identical monochrome atlases for adaptive planning ghosts

Every generated sheet uses one shared scale so pose changes do not enlarge short
keys. Runtime player identity remains in the existing tint, label and world
markers; the personal cherry, ultraviolet, acid, bone and chrome palette remains
recognizably Pulse.
