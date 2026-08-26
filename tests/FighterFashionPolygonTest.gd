extends SceneTree

## Renders every fighter kit through every pose branch, both facings, and the
## full aim sweep, so a costume polygon that folds across itself is caught here
## instead of in a playtest.
##
## THIS SUITE HAS NO ASSERTIONS BY DESIGN. Godot's triangulator refuses a
## non-simple polygon by logging
##
##     ERROR: Invalid polygon data, triangulation failed.
##
## and drawing nothing. There is no GDScript-visible signal for that — the frame
## simply comes out missing a piece of costume. CI's rule that a suite fails when
## Godot logs `ERROR:` even at exit 0 is what turns this run into a test, which
## is exactly the mechanism that caught the truncated lockstep digest. So this
## file's whole job is to make every fashion polygon actually get drawn.
##
## The same fault has now hit three kits: `_draw_velocity_fashion` built its coat
## from world-space offsets on a torso the dash can rotate, `_draw_pulse_fashion`
## had a six-point hem that folded in mirrored and movement poses, and
## `_draw_eclipse_fashion` anchored a crescent on two shoulder joints that swap
## order with facing. Each was found separately, by hand, after shipping. Adding
## a kit means adding it to KITS below; that is the entire maintenance cost.

const MAIN_SCENE := preload("res://scenes/Main.tscn")

## Weapon ids are append-only, so these are spelled out rather than ranged over.
const KITS := {
	0: "The Duelist",
	2: "The Rook",
	3: "The Eclipse",
	4: "The Pulse",
}

## Elevation steps across the full aim range. The pose reads the aim vector for
## the grip arm, and several costumes hang off joints that move with it.
const AIM_STEP_DEGREES := 10


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	# The legacy `_draw()` is what carries the costume polygons, so make sure the
	# sprite renderer is not standing in for it.
	game.fighter_visuals_enabled = false

	var subject: Player = game.players[0]
	subject.draw_legacy_visual = true

	var drawn := 0
	for style: int in KITS:
		subject.fighter_style = style
		for facing in [1, -1]:
			subject.facing = facing
			for elevation in range(-90, 91, AIM_STEP_DEGREES):
				var radians := deg_to_rad(float(elevation))
				subject.plan.set_aim_from_vector(
					Vector2(cos(radians) * float(facing), -sin(radians)),
					game.aim_min_angle, game.aim_max_angle)
				drawn += await _sweep_pose_branches(subject, facing)

	print("Fighter fashion: %d costume frames drawn across %d kits with no engine error"
		% [drawn, KITS.size()])
	quit()


## Walks the three branches of `Player._pose_points()`: grounded idle, airborne,
## and running. Running is swept in both travel directions because the run pose
## slides chest and neck by velocity sign while the free shoulder mirrors by
## facing — running backwards is a distinct pose, and it is the one that broke.
func _sweep_pose_branches(subject: Player, facing: int) -> int:
	var drawn := 0

	subject.on_ground = true
	subject.vel = Vector2.ZERO
	drawn += await _draw_at(subject, [0.0, 0.9, 1.8, 2.6])

	subject.on_ground = false
	subject.vel = Vector2(120.0 * float(facing), -260.0)
	drawn += await _draw_at(subject, [0.0, 1.3])
	subject.vel = Vector2(120.0 * float(facing), 340.0)
	drawn += await _draw_at(subject, [0.0, 1.3])

	subject.on_ground = true
	for travel in [1.0, -1.0]:
		subject.vel = Vector2(240.0 * travel, 0.0)
		drawn += await _draw_at(subject, [0.0, 0.35, 0.7, 1.05, 1.4, 1.75, 2.1, 2.45])

	return drawn


## Stamps the animation clock and forces one real frame per sample. The stride
## and breath terms are sine functions of `_anim_time`, so sampling it is how the
## sweep reaches the mid-stride poses rather than only the extremes.
func _draw_at(subject: Player, anim_times: Array) -> int:
	for t: float in anim_times:
		subject._anim_time = t
		subject.queue_redraw()
		await process_frame
	return anim_times.size()
