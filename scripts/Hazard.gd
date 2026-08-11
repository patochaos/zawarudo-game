extends Node2D
class_name Hazard

## A pulse orb: arena furniture that is only a hazard because someone chose to
## make it one.
##
## It drifts along a [Mover] rail, so it is stationary while time is stopped and
## only travels during an execution window. Striking it with a knife spends that
## knife and detonates a radial forcefield which shoves every fighter and every
## knife inside the blast outward. Nobody is damaged — knives remain the only
## source of damage — but positions, velocities and firing lines all change, and
## the knives thrown outward stay in the world afterwards.
##
## The orb then goes dark and recharges over a fixed number of execution
## windows, so it is a contested resource on a visible timer rather than a
## permanent trap.

const RADIUS := 15.0
const CHARGE_RING := 21.0

var cfg
## Authored rest position. The live position is home + Mover.offset(motion, t).
var home: Vector2 = Vector2.ZERO
var motion: Dictionary = {}
var blast_radius: float = 190.0
## Speed added to a body at the centre of the blast, falling to zero at its rim.
var blast_impulse: float = 620.0
var recharge_windows: int = 2

var charged: bool = true
var windows_left: int = 0
## Seconds of expanding shockwave still being drawn. Cosmetic only.
var flash: float = 0.0
var _time: float = 0.0


func _process(delta: float) -> void:
	# The idle shimmer is allowed to breathe while the world is stopped; the
	# shockwave is not, because it is the record of something that happened.
	_time += delta
	if flash > 0.0 and cfg != null and cfg.state == Phase.EXECUTING:
		flash = maxf(0.0, flash - delta * 2.2)
	queue_redraw()


## Where the orb sits at an absolute simulation tick. Frozen geometry and the
## planning preview both read this, so the drawn orb and the collidable orb are
## never two different objects.
func centre_at(abs_tick: int) -> Vector2:
	if motion.is_empty():
		return home
	return home + Mover.offset(motion, abs_tick)


func sync_to_tick(abs_tick: int) -> void:
	position = centre_at(abs_tick)


## Consumed by whoever strikes it; recharges after `recharge_windows` further
## execution windows, counted at the end of each one.
func discharge() -> void:
	charged = false
	windows_left = recharge_windows
	flash = 1.0


func end_of_window() -> void:
	if charged:
		return
	windows_left -= 1
	if windows_left <= 0:
		charged = true
		windows_left = 0


func lockstep_digest_fragment() -> String:
	return "%d,%d,%d,%d" % [
		1 if charged else 0, windows_left,
		int(round(position.x * 10000.0)), int(round(position.y * 10000.0)),
	]


# ------------------------------------------------------------------ drawing --

func _draw() -> void:
	var live := Color(0.55, 0.92, 1.0)
	var dead := Color(0.36, 0.33, 0.44)
	var body: Color = live if charged else dead

	if flash > 0.0:
		# The shockwave expands as it fades, so a player reading the aftermath
		# frame can still tell how far the push reached.
		var grow: float = blast_radius * (1.25 - flash * 0.85)
		draw_arc(Vector2.ZERO, grow, 0.0, TAU, 48, Color(0.72, 0.95, 1.0, flash * 0.85), 3.0)
		draw_arc(Vector2.ZERO, grow * 0.72, 0.0, TAU, 40, Color(1.0, 1.0, 1.0, flash * 0.35), 1.5)

	if charged:
		# The blast footprint is public information: it is the whole decision.
		var pulse: float = 0.5 + 0.5 * sin(_time * 1.8)
		draw_arc(Vector2.ZERO, blast_radius, 0.0, TAU, 56,
			Color(0.55, 0.92, 1.0, 0.10 + 0.06 * pulse), 1.5)
		for i in 24:
			var a: float = TAU * float(i) / 24.0
			var from: Vector2 = Vector2(cos(a), sin(a)) * blast_radius
			draw_line(from, from * 0.965, Color(0.62, 0.95, 1.0, 0.30), 1.5)
		draw_circle(Vector2.ZERO, CHARGE_RING + 3.0 * pulse, Color(0.45, 0.85, 1.0, 0.14))

	draw_circle(Vector2.ZERO, RADIUS + 2.5, Color(0.03, 0.03, 0.06, 0.92))
	draw_circle(Vector2.ZERO, RADIUS, body.darkened(0.45))
	draw_circle(Vector2(-3.5, -3.5), RADIUS * 0.42, body.lightened(0.35))
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 28, body.lightened(0.15), 2.0)

	if charged:
		# Three orbiting sparks read as "loaded" at a glance and at sprite scale.
		for i in 3:
			var a: float = _time * 1.1 + TAU * float(i) / 3.0
			draw_circle(Vector2(cos(a), sin(a)) * CHARGE_RING, 2.4, Color(0.85, 0.99, 1.0))
	else:
		# Dark orbs show the windows left as pips, matching breakable platforms.
		var pip := 5.0
		var gap := 3.0
		var count: int = maxi(recharge_windows, 1)
		var total: float = float(count) * pip + float(count - 1) * gap
		var x: float = -total * 0.5
		for i in count:
			draw_rect(Rect2(Vector2(x, -RADIUS - 13.0), Vector2(pip, 3.0)),
				Color(0.55, 0.92, 1.0, 0.85) if i >= windows_left else Color(0.36, 0.33, 0.44, 0.7))
			x += pip + gap
