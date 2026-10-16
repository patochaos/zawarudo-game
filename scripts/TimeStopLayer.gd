extends Node2D

## Procedural phase punctuation. Planning is the stopped world: a restrained
## violet grade, clock marks and suspended gold motes remain visible. Entering
## either phase adds one short pulse so freeze/release reads before the HUD
## label does. The pulse never crosses the fighters' lanes with geometry or
## text: the HUD already names the phase, so the arena only needs a change of
## state, not a second announcement. Cosmetic; never touches simulation time.

const W := 1280.0
const H := 720.0
const CLOCK_CENTRE := Vector2(640.0, 438.0)
const CLOCK_RADIUS := 286.0

var gm
var reduced_flashes: bool = false
var _phase: int = -1
var _freeze_flash: float = 0.0
var _resume_flash: float = 0.0


func _ready() -> void:
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


func _process(delta: float) -> void:
	if gm == null:
		return
	visible = gm.state in [Phase.PLANNING, Phase.COMMITTING, Phase.EXECUTING]
	if not visible:
		return
	_freeze_flash = maxf(0.0, _freeze_flash - delta / 0.62)
	_resume_flash = maxf(0.0, _resume_flash - delta / 0.24)
	queue_redraw()


func _draw() -> void:
	if gm == null:
		return
	if gm.state == Phase.PLANNING or gm.state == Phase.COMMITTING:
		_draw_frozen_world()
	if _resume_flash > 0.0:
		_draw_release_pulse(_resume_flash)


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
	var show_clock: bool = true
	for hour in (12 if show_clock else 0):
		var angle: float = -PI * 0.5 + TAU * float(hour) / 12.0
		var d := Vector2.from_angle(angle)
		var long_tick: float = 17.0 if hour % 3 == 0 else 10.0
		draw_line(CLOCK_CENTRE + d * (CLOCK_RADIUS - long_tick),
			CLOCK_CENTRE + d * CLOCK_RADIUS,
			Color(1.0, 0.76, 0.24, 0.13 if hour % 3 == 0 else 0.075),
			2.0 if hour % 3 == 0 else 1.0)
	if show_clock:
		draw_arc(CLOCK_CENTRE, CLOCK_RADIUS, PI * 0.08, PI * 0.78, 48,
			Color(0.88, 0.64, 0.23, 0.07), 1.0)
		draw_arc(CLOCK_CENTRE, CLOCK_RADIUS, PI * 1.08, PI * 1.78, 48,
			Color(0.88, 0.64, 0.23, 0.07), 1.0)

	# All arena dust now exists in both phases and freezes in Backdrop.

	if _freeze_flash <= 0.0:
		return
	# The freeze is one expanding gold ring over a faint violet wash. The glass
	# crack, the radial rays, the second ring and the TIME // SUSPENDED title
	# that used to share this beat were cut after playtesting: they stacked on
	# the ghosts and aim fans at the exact moment planning begins.
	var u: float = _freeze_flash
	var travelled: float = 1.0 - u
	var radius: float = 42.0 + travelled * 590.0
	draw_rect(Rect2(0.0, 0.0, W, H), Color(0.30, 0.06, 0.48, 0.11 * u))
	draw_arc(CLOCK_CENTRE, radius, 0.0, TAU, 96, Color(1.0, 0.83, 0.34, 0.75 * u), 3.0)


## Release is a horizontal sweep from the clock centre over a faint warm wash.
func _draw_release_pulse(u: float) -> void:
	var width: float = W * (1.0 - pow(u, 2.0))
	draw_rect(Rect2(0.0, 0.0, W, H), Color(1.0, 0.68, 0.16, 0.10 * u))
	draw_line(Vector2((W - width) * 0.5, CLOCK_CENTRE.y),
		Vector2((W + width) * 0.5, CLOCK_CENTRE.y),
		Color(1.0, 0.92, 0.62, 0.9 * u), 4.0)
	draw_line(Vector2((W - width * 0.72) * 0.5, CLOCK_CENTRE.y - 9.0),
		Vector2((W + width * 0.72) * 0.5, CLOCK_CENTRE.y - 9.0),
		Color(0.80, 0.42, 1.0, 0.55 * u), 2.0)
