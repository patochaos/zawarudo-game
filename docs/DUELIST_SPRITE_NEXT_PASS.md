# Duelist sprite, next pass — prompts

The current frames (`art_source/sprites/duelist-polished-v2`) were generated with
an image tool that is no longer available. These prompts target the same packer
(`python tools/art/build_duelist_polished.py`): one sheet per state, figures
facing RIGHT, transparent background, equal cells, generous gutters, same head
size and costume construction as the reference. Attach
`art_source/sprites/duelist-polished-v2/action-source.png` as the identity
reference when the tool accepts one. After generating, add the sheet to `SHEETS`
in the packer with its column/row count and body anchors, run it, then run
`DuelistPolishTest` and `DuelistSpritePolishVisualTest`.

Identity block, prepend to every prompt:

> Preserve this exact male character: swept angular black hair, ivory long
> split-tail coat with high collar, black fitted suit, black gloves, gold cuffs,
> one gold circular clock brooch on the chest with a tapered downward point,
> gold boot accents. Production-quality 2D hand-drawn cel animation sprite,
> bold readable shapes, confident line weight, two-tone cool shadow planes on
> the ivory cloth, restrained gold highlights. Not photoreal, not 3D, not chibi,
> no intricate ornament. Transparent background with real alpha, no drawn
> checkerboard, no ground shadow, no text, no borders.

## Victory (2 frames, 2 columns by 1 row)

Needed by the result tableau; the winner currently holds the lock stance.

> Left: a held victory pose, weight settled on the rear foot, chest open, one
> gloved hand closing a small gold dagger at hip height, chin slightly raised,
> coat tails settling. Right: the same pose one beat later, coat tails at rest,
> hand fully closed, eyes toward the viewer's right.

## Hit reaction (2 frames, 2 columns by 1 row)

Shown for the hit flash before the defeat sequence.

> Left: struck from the right, torso snapped back, head turned away, both arms
> thrown open, coat flaring toward the left. Right: the recoil one beat later,
> torso still twisted, one foot lifted, coat overshooting.

## SUPER anticipation (3 frames, 3 columns by 1 row)

Plays under the cut-in's first beat.

> Left: a low coiled crouch, both daggers drawn and crossed before the chest,
> coat gathered. Middle: rising, daggers uncrossing outward, coat beginning to
> lift. Right: full height, arms wide, five daggers fanned between the fingers
> of the right hand, coat fully lifted behind.

## Lock refinement (2 frames, 2 columns by 1 row)

Optional replacement for the current lock frames with a stronger asymmetric
silhouette.

> Left: a held asymmetric stance, feet planted wide, torso turned three-quarter
> toward the viewer, one hand near the chest brooch, the other arm low and
> extended behind. Right: the same stance with the coat tails settled one beat
> later and the head turned a few degrees further right.
