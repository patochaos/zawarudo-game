extends Node2D

const DISPLAY_FONT := preload("res://assets/kenney/fonts/kenney-future.ttf")

## Procedural phase punctuation. Planning is the stopped world: a restrained
## violet grade, clock marks and suspended gold motes remain visible. Entering
## either phase adds a short, much stronger pulse so freeze/release reads before
## the HUD label does. This is cosmetic and never touches simulation time.

const W := 1280.0
const H := 720.0
const CLOCK_CENTRE := Vector2(640.0, 438.0)
const CLOCK_RADIUS := 286.0

var gm
var reduced_flashes: bool = false
var _phase: int = -1
var _freeze_flash: float = 0.0
var _resume_flash: float = 0.0
var _impact_flash: float = 0.0
var _impact_at: Vector2 = Vector2.ZERO
var _impact_color: Color = Color.WHITE
var _motes: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	var seeded := RandomNumberGenerator.new()
	seeded.seed = 19780607
	for i in 28:
		_motes.append(Vector2(seeded.randf_range(28.0, W - 28.0),
			seeded.randf_range(270.0, H - 105.0)))
	set_process(true)


func phase_changed(next_phase: int) -> void:
	_phase = next_phase
	if next_phase == Phase.PLANNING:
		_freeze_flash = 0.35 if reduced_flashes else 1.0
		_resume_flash = 0.0
	elif next_phase == Phase.EXECUTING:
		_resume_flash = 0.35 if reduced_flashes else 1.0
		_freeze_flash = 0.0
	queue_redraw()


func impact_flash(at: Vector2, color: Color) -> void:
	_impact_at = at
	_impact_color = color
	_impact_flash = 0.45 if reduced_flashes else 1.0
	queue_redraw()


func _process(delta: float) -> void:
	if gm == null:
		return
	visible = gm.state in [Phase.PLANNING, Phase.COMMITTING, Phase.EXECUTING] \
		or _impact_flash > 0.0
	if not visible:
		return
	_freeze_flash = maxf(0.0, _freeze_flash - delta / 0.62)
	_resume_flash = maxf(0.0, _resume_flash - delta / 0.24)
	_impact_flash = maxf(0.0, _impact_flash - delta / 0.16)
	queue_redraw()


func _draw() -> void:
	if gm == null:
		return
	if gm.state == Phase.PLANNING or gm.state == Phase.COMMITTING:
		_draw_frozen_world()
	if _resume_flash > 0.0:
		_draw_release_pulse(_resume_flash)
	if _impact_flash > 0.0:
		_draw_impact(_impact_flash)


func _draw_frozen_world() -> void:
	# A low-opacity grade keeps previews fully legible while making the frozen
	# phase visibly different even after the entry pulse is gone.
	draw_rect(Rect2(0.0, 0.0, W, H), Color(0.16, 0.035, 0.25, 0.055))

	# Soft stepped vignette: dramatic edges without requiring a shader or asset.
	for i in 9:
		var inset: float = float(i) * 10.0
		var alpha: float = 0.018 * (1.0 - float(i) / 9.0)
		draw_rect(Rect2(inset, inset, W - inset * 2.0, H - inset * 2.0),
			Color(0.04, 0.0, 0.08, alpha), false, 10.0)

	# An incomplete clock face sits behind the arena action. It is a motif, not
	# a timer: the actual countdown remains in the HUD.
	for hour in 12:
		var angle: float = -PI * 0.5 + TAU * float(hour) / 12.0
		var d := Vector2.from_angle(angle)
		var long_tick: float = 17.0 if hour % 3 == 0 else 10.0
		draw_line(CLOCK_CENTRE + d * (CLOCK_RADIUS - long_tick),
			CLOCK_CENTRE + d * CLOCK_RADIUS,
			Color(1.0, 0.76, 0.24, 0.13 if hour % 3 == 0 else 0.075),
			2.0 if hour % 3 == 0 else 1.0)
	draw_arc(CLOCK_CENTRE, CLOCK_RADIUS, PI * 0.08, PI * 0.78, 48,
		Color(0.88, 0.64, 0.23, 0.07), 1.0)
	draw_arc(CLOCK_CENTRE, CLOCK_RADIUS, PI * 1.08, PI * 1.78, 48,
		Color(0.88, 0.64, 0.23, 0.07), 1.0)

	# Gold particles held perfectly still sell the frozen air.
	for i in _motes.size():
		var p: Vector2 = _motes[i]
		var radius: float = 1.0 + float(i % 3) * 0.45
		var c := Color(1.0, 0.80, 0.32, 0.12 + float(i % 4) * 0.025)
		draw_circle(p, radius, c)
		if i % 5 == 0:
			draw_line(p - Vector2(4.0, 0.0), p + Vector2(4.0, 0.0), c, 1.0)

	if _freeze_flash <= 0.0:
		return
	var u: float = _freeze_flash
	var travelled: float = 1.0 - u
	var radius: float = 42.0 + travelled * 590.0
	draw_rect(Rect2(0.0, 0.0, W, H), Color(0.30, 0.06, 0.48, 0.11 * u))
	draw_arc(CLOCK_CENTRE, radius, 0.0, TAU, 96, Color(1.0, 0.83, 0.34, 0.75 * u), 3.0)
	draw_arc(CLOCK_CENTRE, radius + 10.0, 0.0, TAU, 96, Color(0.75, 0.34, 1.0, 0.35 * u), 1.5)
	for ray in 18:
		var angle: float = float(ray) * TAU / 18.0 + sin(float(ray) * 2.17) * 0.10
		var d := Vector2.from_angle(angle)
		var inner: float = maxf(0.0, radius - 46.0 - float(ray % 4) * 12.0)
		draw_line(CLOCK_CENTRE + d * inner, CLOCK_CENTRE + d * radius,
			Color(1.0, 0.86, 0.46, 0.35 * u), 1.0)
	var text_col := Color(1.0, 0.86, 0.42, minf(1.0, u * 1.8))
	draw_string(DISPLAY_FONT, Vector2(390.0, 304.0), "TIME // SUSPENDED",
		HORIZONTAL_ALIGNMENT_CENTER, 500.0, 28, text_col)


func _draw_release_pulse(u: float) -> void:
	var width: float = W * (1.0 - pow(u, 2.0))
	draw_rect(Rect2(0.0, 0.0, W, H), Color(1.0, 0.68, 0.16, 0.10 * u))
	draw_line(Vector2((W - width) * 0.5, CLOCK_CENTRE.y),
		Vector2((W + width) * 0.5, CLOCK_CENTRE.y),
		Color(1.0, 0.92, 0.62, 0.9 * u), 4.0)
	draw_line(Vector2((W - width * 0.72) * 0.5, CLOCK_CENTRE.y - 9.0),
		Vector2((W + width * 0.72) * 0.5, CLOCK_CENTRE.y - 9.0),
		Color(0.80, 0.42, 1.0, 0.55 * u), 2.0)
	draw_string(DISPLAY_FONT, Vector2(440.0, 304.0), "TIME FLOWS",
		HORIZONTAL_ALIGNMENT_CENTER, 400.0, 25, Color(1.0, 0.92, 0.66, u))


func _draw_impact(u: float) -> void:
	var strength := 0.32 if reduced_flashes else 1.0
	draw_rect(Rect2(0.0, 0.0, W, H), Color(1.0, 0.94, 0.82, 0.18 * u * strength))
	var reach: float = 42.0 + (1.0 - u) * 96.0
	draw_arc(_impact_at, reach, 0.0, TAU, 36,
		Color(_impact_color.r, _impact_color.g, _impact_color.b, 0.95 * u), 4.0)
	for i in 8:
		var d := Vector2.from_angle(float(i) * TAU / 8.0 + PI * 0.125)
		draw_line(_impact_at + d * 12.0, _impact_at + d * reach,
			Color(1.0, 0.96, 0.72, 0.9 * u), 3.0)
