extends "res://scripts/PreviewLayer.gd"

## Planning ghosts are translucent panes held together by the player's accent
## color. Paths and timing remain inherited from PreviewLayer.


func _draw_ghost_figure(at: Vector2, p: Player, alpha: float) -> void:
	var pose := Player.idle_pose_points(p.facing, p.aim_dir())
	var base: Color = _player_preview_color(p)
	var lead := Color(0.012, 0.016, 0.035, minf(0.92, alpha + 0.12))
	var glass := Color(base.r, base.g, base.b, alpha * (0.30 if high_contrast else 0.22))
	var glow := Color(base.r, base.g, base.b, minf(1.0, alpha + 0.16))

	var torso := PackedVector2Array([
		at + pose["free_shoulder"] + Vector2(-4.0 * float(p.facing), -2.0),
		at + pose["shoulder"] + Vector2(5.0 * float(p.facing), -1.0),
		at + pose["hip"] + Vector2(8.0 * float(p.facing), 3.0),
		at + pose["hip"] + Vector2(-8.0 * float(p.facing), 3.0),
	])
	draw_colored_polygon(torso, glass)
	draw_polyline(torso + PackedVector2Array([torso[0]]), lead, 5.0 if high_contrast else 3.5, true)
	draw_polyline(torso + PackedVector2Array([torso[0]]), glow, 1.6, true)

	var segments := [
		[pose["hip"], pose["knee_a"]], [pose["knee_a"], pose["foot_a"]],
		[pose["hip"], pose["knee_b"]], [pose["knee_b"], pose["foot_b"]],
		[pose["free_shoulder"], pose["free_elbow"]], [pose["free_elbow"], pose["free_hand"]],
		[pose["shoulder"], pose["aim_elbow"]], [pose["aim_elbow"], pose["grip"]],
	]
	for segment in segments:
		draw_line(at + segment[0], at + segment[1], lead, 5.0 if high_contrast else 4.0, true)
		draw_line(at + segment[0], at + segment[1], glow, 1.8, true)

	draw_circle(at + pose["head"], 9.0, lead)
	draw_circle(at + pose["head"], 6.5, glass)
	draw_arc(at + pose["head"], 6.5, 0.0, TAU, 16, glow, 1.8, true)
	draw_line(at + pose["head"] + Vector2(-5.0, 0.0), at + pose["head"] + Vector2(5.0, 0.0),
		lead, 1.2)
