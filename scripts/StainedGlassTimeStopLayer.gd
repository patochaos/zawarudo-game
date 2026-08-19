extends "res://scripts/TimeStopLayer.gd"

## Phase punctuation becomes a pane being sealed and released. The persistent
## background stays subtle; these brighter lines appear only at phase changes.

const GLASS_CLOCK_CENTRE := Vector2(640.0, 432.0)
const GLASS_CLOCK_RADIUS := 282.0


func _draw_frozen_world() -> void:
	draw_rect(Rect2(0.0, 0.0, W, H), Color(0.10, 0.025, 0.20, 0.045))
	for i in 8:
		var inset := float(i) * 11.0
		draw_rect(Rect2(inset, inset, W - inset * 2.0, H - inset * 2.0),
			Color(0.01, 0.004, 0.025, 0.016 * (1.0 - float(i) / 8.0)), false, 9.0)

	for hour in 12:
		var angle := -PI * 0.5 + TAU * float(hour) / 12.0
		var d := Vector2.from_angle(angle)
		var inner := GLASS_CLOCK_RADIUS - (18.0 if hour % 3 == 0 else 10.0)
		draw_line(GLASS_CLOCK_CENTRE + d * inner, GLASS_CLOCK_CENTRE + d * GLASS_CLOCK_RADIUS,
			Color(1.0, 0.72, 0.20, 0.13 if hour % 3 == 0 else 0.07),
			2.2 if hour % 3 == 0 else 1.0)

	for i in _motes.size():
		var p: Vector2 = _motes[i]
		var c := Color(1.0, 0.78, 0.28, 0.12 + float(i % 3) * 0.025)
		_draw_diamond(p, 1.8 + float(i % 2), c)

	if _freeze_flash <= 0.0:
		return
	var u := _freeze_flash
	var travelled := 1.0 - u
	var radius := 46.0 + travelled * 590.0
	draw_rect(Rect2(0.0, 0.0, W, H), Color(0.24, 0.04, 0.38, 0.085 * u))
	draw_arc(GLASS_CLOCK_CENTRE, radius, 0.0, TAU, 96, Color(1.0, 0.79, 0.28, 0.78 * u), 4.0)
	for ray in 16:
		var d := Vector2.from_angle(TAU * float(ray) / 16.0)
		draw_line(GLASS_CLOCK_CENTRE + d * maxf(0.0, radius - 52.0),
			GLASS_CLOCK_CENTRE + d * radius, Color(0.72, 0.35, 1.0, 0.38 * u), 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(390.0, 303.0), "TIME // SEALED",
		HORIZONTAL_ALIGNMENT_CENTER, 500.0, 28, Color(1.0, 0.84, 0.38, minf(1.0, u * 1.8)))


func _draw_release_pulse(u: float) -> void:
	var width := W * (1.0 - pow(u, 2.0))
	draw_rect(Rect2(0.0, 0.0, W, H), Color(1.0, 0.58, 0.10, 0.075 * u))
	var left := (W - width) * 0.5
	var right := (W + width) * 0.5
	draw_line(Vector2(left, GLASS_CLOCK_CENTRE.y), Vector2(right, GLASS_CLOCK_CENTRE.y),
		Color(1.0, 0.92, 0.62, 0.92 * u), 4.0)
	for offset in [-18.0, 18.0]:
		draw_line(Vector2(left + 48.0, GLASS_CLOCK_CENTRE.y + offset),
			Vector2(right - 48.0, GLASS_CLOCK_CENTRE.y + offset),
			Color(0.72, 0.34, 1.0, 0.34 * u), 1.5)
	draw_string(ThemeDB.fallback_font, Vector2(440.0, 303.0), "THE WINDOW MOVES",
		HORIZONTAL_ALIGNMENT_CENTER, 400.0, 24, Color(1.0, 0.91, 0.60, u))


func _draw_impact(u: float) -> void:
	var strength := 0.34 if reduced_flashes else 1.0
	draw_rect(Rect2(0.0, 0.0, W, H), Color(1.0, 0.90, 0.70, 0.11 * u * strength))
	var reach := 34.0 + (1.0 - u) * 104.0
	for ray in 10:
		var d := Vector2.from_angle(PI * 0.10 + TAU * float(ray) / 10.0)
		draw_line(_impact_at + d * 8.0, _impact_at + d * reach,
			Color(_impact_color.r, _impact_color.g, _impact_color.b, 0.94 * u),
			3.0 if ray % 2 == 0 else 1.5)
	draw_arc(_impact_at, reach * 0.34, 0.0, TAU, 20, Color(1.0, 0.95, 0.70, 0.82 * u), 2.5)


func _draw_diamond(at: Vector2, radius: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(0.0, -radius), at + Vector2(radius, 0.0),
		at + Vector2(0.0, radius), at + Vector2(-radius, 0.0),
	]), col)
