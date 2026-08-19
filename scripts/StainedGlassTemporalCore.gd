extends "res://scripts/TemporalCore.gd"

## The Core is the missing jewel in a tiny rose window: announcement shows the
## empty socket; activation fills it with transmitted gold light.


func _draw_announcement(pulse: float) -> void:
	var alpha := 0.34 + pulse * 0.18
	_draw_rose_socket(27.0 + pulse * 2.0, Color(0.68, 0.35, 1.0, alpha), false)
	_draw_caption("EMPTY SOCKET", Color(0.82, 0.70, 1.0, 0.92))


func _draw_active(pulse: float) -> void:
	var radius := 30.0 + pulse * 4.0
	draw_circle(Vector2.ZERO, radius + 7.0, Color(1.0, 0.72, 0.20, 0.10 + pulse * 0.08))
	_draw_rose_socket(radius, Color(1.0, 0.78, 0.22, 0.88), true)
	draw_circle(Vector2.ZERO, 5.0 + pulse * 1.5, Color(1.0, 0.98, 0.68))
	_draw_caption("FULL SUPER", Color(1.0, 0.88, 0.42))


func _draw_rose_socket(radius: float, color: Color, filled: bool) -> void:
	for spoke in 8:
		var a := PI * 0.125 + TAU * float(spoke) / 8.0 + _time * (0.08 if filled else 0.02)
		var d := Vector2.from_angle(a)
		var side := d.orthogonal()
		var pane := PackedVector2Array([
			d * 7.0, d * radius + side * 5.0, d * radius - side * 5.0,
		])
		if filled:
			draw_colored_polygon(pane, Color(color.r, color.g, color.b, color.a * 0.42))
		draw_polyline(pane + PackedVector2Array([pane[0]]), color, 1.8, true)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, color, 2.2)
	draw_arc(Vector2.ZERO, 9.0, 0.0, TAU, 16, color, 1.6)
