extends "res://scripts/UI.gd"

## Adds quiet leaded-glass architecture behind the existing compact HUD. The
## information layout and all interaction remain owned by UI.gd.

var _glass_frame: GlassHudFrame


class GlassHudFrame:
	extends Control

	var gm

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)
		queue_redraw()

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var gold := Color(0.96, 0.68, 0.18, 0.58)
		var violet := Color(0.72, 0.34, 1.0, 0.44)
		var ink := Color(0.008, 0.006, 0.020, 0.78)

		# Corner chapels sit behind the fighter seals.
		for mirrored in [false, true]:
			var panel := PackedVector2Array([
				Vector2(0.0, 0.0), Vector2(280.0, 0.0),
				Vector2(220.0, 118.0), Vector2(0.0, 154.0),
			]) if not mirrored else PackedVector2Array([
				Vector2(1000.0, 0.0), Vector2(1280.0, 0.0),
				Vector2(1280.0, 154.0), Vector2(1060.0, 118.0),
			])
			draw_colored_polygon(panel, Color(0.08, 0.035, 0.13, 0.30))
			draw_polyline(panel + PackedVector2Array([panel[0]]), ink, 5.0, true)
			if not mirrored:
				draw_line(Vector2(0.0, 118.0), Vector2(280.0, 42.0), gold, 1.2)
			else:
				draw_line(Vector2(1280.0, 118.0), Vector2(1000.0, 42.0), violet, 1.2)

		# Central timer is framed like the crown of a lancet window.
		draw_arc(Vector2(640.0, 132.0), 148.0, PI, TAU, 48, Color(0.96, 0.70, 0.20, 0.20), 2.0)
		draw_line(Vector2(490.0, 184.0), Vector2(790.0, 184.0), gold, 2.0)
		for x in [522.0, 640.0, 758.0]:
			draw_line(Vector2(x, 166.0), Vector2(x, 188.0), Color(0.72, 0.36, 1.0, 0.22), 1.0)

		# Floor frame anchors the game window without brightening the background.
		draw_rect(Rect2(0.0, 628.0, 1280.0, 5.0), ink)
		draw_line(Vector2(0.0, 630.0), Vector2(1280.0, 630.0), gold, 1.5)
		for x in range(40, 1280, 80):
			var c := Vector2(float(x), 630.0)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.0, -3.0), c + Vector2(3.0, 0.0),
				c + Vector2(0.0, 3.0), c + Vector2(-3.0, 0.0),
			]), Color(gold.r, gold.g, gold.b, 0.52))


func build(manager) -> void:
	_glass_frame = GlassHudFrame.new()
	_glass_frame.gm = manager
	_glass_frame.size = Vector2(1280.0, 720.0)
	_glass_frame.z_index = -2
	add_child(_glass_frame)
	super.build(manager)
	_level_label.add_theme_color_override("font_color", Color(0.58, 0.62, 0.76))
	_score_label.add_theme_color_override("font_color", Color(0.66, 0.70, 0.82))
