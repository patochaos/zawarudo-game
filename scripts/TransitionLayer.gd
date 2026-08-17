extends CanvasLayer
class_name TransitionLayer

## Presentation-only scene reveal. It never delays or mutates simulation state:
## two angular ink shutters briefly frame the destination, then clear the arena.

const VIEW := Vector2(1280.0, 720.0)
const DURATION := 0.68

var _surface: Control
var _elapsed: float = DURATION
var _kicker: String = ""
var _title: String = ""
var _accent: Color = Color(0.96, 0.69, 0.18)
var _reduced: bool = false


func _ready() -> void:
	layer = 40
	_surface = Control.new()
	_surface.size = VIEW
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.draw.connect(_draw_transition)
	add_child(_surface)
	visible = false


func play(kicker: String, title: String, accent: Color, reduced_motion: bool = false) -> void:
	_kicker = kicker
	_title = title
	_accent = accent
	_reduced = reduced_motion
	_elapsed = 0.0
	visible = true
	_surface.queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_elapsed += delta * (1.65 if _reduced else 1.0)
	if _elapsed >= DURATION:
		visible = false
		return
	_surface.queue_redraw()


func progress() -> float:
	return clampf(_elapsed / DURATION, 0.0, 1.0)


func _draw_transition() -> void:
	var u := progress()
	var release := clampf((u - 0.20) / 0.80, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - release, 3.0)
	var travel := 760.0 * eased
	var ink := Color(0.012, 0.006, 0.026, 1.0)
	var left := PackedVector2Array([
		Vector2(-travel, 0.0), Vector2(735.0 - travel, 0.0),
		Vector2(585.0 - travel, 720.0), Vector2(-travel, 720.0),
	])
	var right := PackedVector2Array([
		Vector2(735.0 + travel, 0.0), Vector2(1280.0 + travel, 0.0),
		Vector2(1280.0 + travel, 720.0), Vector2(585.0 + travel, 720.0),
	])
	_surface.draw_colored_polygon(left, ink)
	_surface.draw_colored_polygon(right, ink)
	_surface.draw_line(Vector2(735.0 - travel, 0.0), Vector2(585.0 - travel, 720.0),
		Color(_accent.r, _accent.g, _accent.b, 0.88), 3.0)
	_surface.draw_line(Vector2(735.0 + travel, 0.0), Vector2(585.0 + travel, 720.0),
		Color(_accent.r, _accent.g, _accent.b, 0.48), 2.0)
	if release >= 0.62:
		return
	var text_alpha := 1.0 - clampf(release / 0.62, 0.0, 1.0)
	var font := ThemeDB.fallback_font
	_surface.draw_string(font, Vector2(390.0, 326.0), _kicker,
		HORIZONTAL_ALIGNMENT_CENTER, 500.0, 13,
		Color(_accent.r, _accent.g, _accent.b, 0.76 * text_alpha))
	_surface.draw_string(font, Vector2(240.0, 382.0), _title,
		HORIZONTAL_ALIGNMENT_CENTER, 800.0, 34,
		Color(0.96, 0.97, 1.0, text_alpha))
	_surface.draw_line(Vector2(470.0, 409.0), Vector2(810.0, 409.0),
		Color(_accent.r, _accent.g, _accent.b, 0.62 * text_alpha), 2.0)
