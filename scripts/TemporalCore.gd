extends Node2D
class_name TemporalCore

## The late-match movement objective. GameManager owns every rule and collision;
## this node only makes the announced/active states readable in the world.

const GOLD := Color(1.0, 0.78, 0.22)
const VIOLET := Color(0.72, 0.35, 1.0)

var announced: bool = false
var active: bool = false
var _time: float = 0.0


func show_announcement(at: Vector2) -> void:
	position = at
	announced = true
	active = false
	visible = true
	queue_redraw()


func activate(at: Vector2) -> void:
	position = at
	announced = false
	active = true
	visible = true
	queue_redraw()


func hide_core() -> void:
	announced = false
	active = false
	visible = false
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	queue_redraw()


func _draw() -> void:
	if not announced and not active:
		return
	var pulse := 0.5 + 0.5 * sin(_time * (4.5 if active else 2.4))
	if announced:
		_draw_announcement(pulse)
	else:
		_draw_active(pulse)


func _draw_announcement(pulse: float) -> void:
	var faint := Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.20 + pulse * 0.16)
	draw_circle(Vector2.ZERO, 19.0 + pulse * 3.0, faint)
	for i in 8:
		var a0: float = float(i) * TAU / 8.0 + _time * 0.18
		draw_arc(Vector2.ZERO, 27.0, a0, a0 + 0.32, 5,
			Color(GOLD.r, GOLD.g, GOLD.b, 0.48 + pulse * 0.22), 2.0, true)
	_draw_diamond(Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.45), 10.0)
	_draw_caption("NEXT TURN", Color(0.86, 0.72, 1.0, 0.92))


func _draw_active(pulse: float) -> void:
	var halo := Color(GOLD.r, GOLD.g, GOLD.b, 0.14 + pulse * 0.16)
	draw_circle(Vector2.ZERO, 25.0 + pulse * 5.0, halo)
	draw_arc(Vector2.ZERO, 31.0 + pulse * 2.0, _time, _time + PI * 1.45, 28,
		Color(GOLD.r, GOLD.g, GOLD.b, 0.78), 3.0, true)
	draw_arc(Vector2.ZERO, 36.0 - pulse * 2.0, -_time * 0.7, -_time * 0.7 + PI,
		24, Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.70), 2.0, true)
	_draw_diamond(Color(1.0, 0.93, 0.48), 13.0 + pulse * 2.0)
	draw_circle(Vector2.ZERO, 5.0 + pulse * 1.5, Color(1.0, 1.0, 0.88))
	_draw_caption("FULL SUPER", Color(1.0, 0.88, 0.42))


func _draw_diamond(color: Color, radius: float) -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(0.0, -radius), Vector2(radius * 0.72, 0.0),
		Vector2(0.0, radius), Vector2(-radius * 0.72, 0.0),
	]), color)


func _draw_caption(text: String, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(font, Vector2(-width * 0.5, -44.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, color)
