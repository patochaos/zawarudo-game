extends Node2D
class_name Player

## Physics-based duelist. All motion goes through the static `step_state()` below
## so that PredictionSystem can produce a ghost using the exact same integration.

const SIZE := Vector2(32.0, 48.0)
const HALF := Vector2(16.0, 24.0)
## A ground jump plus this one mid-air charge makes the movement a double jump.
const MAX_AIR_JUMPS := 1

## Down + jump drops the body through the ledge it is standing on, so descending
## a level is a deliberate move rather than a walk to the nearest edge.
##
## Only ledges thinner than this are doors. The floor, the walls and the roof of
## a tower are all far thicker, so they stay solid without needing to be marked:
## thickness IS the rule, and it is one a player can read off the silhouette.
const DROP_THROUGH_MAX_THICKNESS := 30.0
## Safety cap only. What actually ends a drop is geometry: the immunity applies
## to the ledge being left and to nothing below it, so a generous cap cannot
## carry the body through a second ledge on the way down.
const DROP_THROUGH_TICKS := 18
## A push-off, so the drop reads as a decision instead of a slow sag.
const DROP_THROUGH_NUDGE := 220.0

var cfg                      # GameManager, holds tuning values + solid_rects
var index: int = 0           # 0 = P1, 1 = P2
var color: Color = Color.WHITE
var vel: Vector2 = Vector2.ZERO
var on_ground: bool = false
var air_jumps_left: int = MAX_AIR_JUMPS
## Ticks of collision immunity to thin ledges left in the current drop-through.
var drop_ticks: int = 0
## Surface height the current drop started from. Only ledges at or above this
## line are transparent, so a drop passes through the ledge you left and lands
## on the next one down rather than tunnelling past both.
var drop_from_y: float = 0.0
var facing: int = 1
var alive: bool = true
## Execution windows this player still shrugs off arrows for, granted on
## respawn so nobody is shot the instant they come back.
var invuln_turns: int = 0
var plan: PlayerPlan
var _anim_time: float = 0.0


func _init() -> void:
	plan = PlayerPlan.new()


## The simulation remains deterministic; this clock only bends the drawn stick
## figure. During planning the pose freezes with the rest of the world.
func _process(delta: float) -> void:
	if alive and (cfg == null or cfg.state == Phase.EXECUTING or cfg.state == Phase.FREEPLAY):
		_anim_time += delta
	# Aim can change while the body is frozen, so refresh even when the animation
	# clock is stopped. There are only two fighters, making this effectively free.
	queue_redraw()


func rect() -> Rect2:
	return Rect2(position - HALF, SIZE)


func is_invulnerable() -> bool:
	return invuln_turns > 0


func aim_dir() -> Vector2:
	return plan.aim_vector()


## Where the bow sits. Aiming and the shot preview use the *ghost* position, so
## these take an explicit origin; the no-argument forms use the live body.
static func shoulder_at(pos: Vector2) -> Vector2:
	return pos + Vector2(0.0, -6.0)


func muzzle_at(pos: Vector2) -> Vector2:
	return shoulder_at(pos) + aim_dir() * 22.0


func shoulder() -> Vector2:
	return shoulder_at(position)


func muzzle() -> Vector2:
	return muzzle_at(position)


## Direct real-time control, for the free-play tuning sandbox. Same integration
## as everything else, just driven by live input instead of a recording.
func sim_free(dt: float, dir: int, jump: bool, jump_held: bool, drop: bool = false) -> void:
	if not alive:
		return
	var drop_result := Player.apply_drop(position.y, vel, on_ground, drop_ticks, drop_from_y, drop)
	vel = drop_result[0]
	on_ground = drop_result[1]
	drop_ticks = drop_result[2]
	drop_from_y = drop_result[3]
	var jump_result := Player.apply_jump(vel, on_ground, air_jumps_left, jump, cfg.jump_impulse)
	vel = jump_result[0]
	on_ground = jump_result[1]
	air_jumps_left = jump_result[2]
	var st := Player.step_state(position, vel, on_ground, dir, jump_held, dt, cfg, -1,
		drop_ticks, drop_from_y)
	position = st[0]
	vel = st[1]
	on_ground = st[2]
	if on_ground:
		air_jumps_left = MAX_AIR_JUMPS


## Replays tick `t` of the recorded plan. Past the end of the recording the
## player simply coasts — momentum and gravity, no input.
##
## `from_tick` is the absolute world tick this step departs from; it is what the
## moving geometry is projected against. -1 means "resolve against the world
## exactly as it stands", which is what free play and the static arenas want.
func sim_step(dt: float, t: int, from_tick: int = -1) -> void:
	if not alive:
		return
	var drop_result := Player.apply_drop(position.y, vel, on_ground, drop_ticks, drop_from_y,
		plan.drop_at(t))
	vel = drop_result[0]
	on_ground = drop_result[1]
	drop_ticks = drop_result[2]
	drop_from_y = drop_result[3]
	var jump_result := Player.apply_jump(vel, on_ground, air_jumps_left,
		plan.jump_at(t), cfg.jump_impulse)
	vel = jump_result[0]
	on_ground = jump_result[1]
	air_jumps_left = jump_result[2]
	var st := Player.step_state(position, vel, on_ground, plan.dir_at(t), plan.hold_at(t), dt,
		cfg, from_tick, drop_ticks, drop_from_y)
	position = st[0]
	vel = st[1]
	on_ground = st[2]
	if on_ground:
		air_jumps_left = MAX_AIR_JUMPS


## Returns [velocity, on_ground, drop_ticks, drop_from_y]. Opening a drop costs
## the ground contact immediately, so the same tick cannot also be spent on a
## jump — down and up are one button, and asking for both is asking for down.
##
## A drop can only be opened from a surface. Whether there is actually anything
## to fall through is settled by `step_state`: if the body is standing on
## something too thick to pass, the immunity never matches a rect and the body
## lands straight back where it was.
static func apply_drop(pos_y: float, vel: Vector2, on_ground: bool, drop_ticks: int,
		drop_from_y: float, requested: bool) -> Array:
	if requested and on_ground:
		return [Vector2(vel.x, maxf(vel.y, DROP_THROUGH_NUDGE)), false,
			DROP_THROUGH_TICKS, pos_y + HALF.y]
	return [vel, on_ground, maxi(0, drop_ticks - 1), drop_from_y]


## Returns [velocity, on_ground, air_jumps_left, jumped]. Keeping the rule here
## lets live play, ghost planning, AI previews and execution share one decision.
static func apply_jump(vel: Vector2, on_ground: bool, air_jumps_left: int,
		requested: bool, impulse: float) -> Array:
	var jumped := false
	if requested and (on_ground or air_jumps_left > 0):
		vel.y = -impulse
		if on_ground:
			air_jumps_left = MAX_AIR_JUMPS
		else:
			air_jumps_left -= 1
		on_ground = false
		jumped = true
	return [vel, on_ground, air_jumps_left, jumped]


## Returns [pos, vel, on_ground]. Static + side-effect free so the prediction
## system can run it on a copy of the state.
static func step_state(pos: Vector2, vel: Vector2, on_ground: bool, dir: int, jump_held: bool,
		dt: float, cfg, from_tick: int = -1, drop_ticks: int = 0,
		drop_from_y: float = 0.0) -> Array:
	# Ride whatever moving piece this body is standing on, then resolve against
	# the geometry as it stands at the END of the tick. Doing both from the same
	# pure tick function is what lets a planning ghost and the live execution
	# agree about a lift that is going to move underneath them.
	var rects: Array[Rect2]
	if from_tick >= 0:
		pos += cfg.mover_carry(pos, from_tick)
		rects = cfg.solids_at(from_tick + 1)
	else:
		rects = cfg.solid_rects

	# Variable jump height: let go while still climbing and the rise is capped,
	# so a tap is a hop that fits inside one execution window and a held jump is
	# the full floaty arc that deliberately overruns it.
	if vel.y < 0.0 and not jump_held:
		vel.y = maxf(vel.y, -cfg.jump_impulse * cfg.jump_cut)

	var target: float = float(dir) * cfg.player_move_speed
	var accel: float = cfg.player_acceleration if on_ground else cfg.player_air_acceleration
	vel.x = move_toward(vel.x, target, accel * dt)
	vel.y = minf(vel.y + cfg.gravity * dt, cfg.max_fall_speed)

	# A drop-through makes thin ledges transparent on BOTH axes for its duration.
	# Skipping only the vertical pass would let the horizontal one snap the body
	# sideways out of the ledge it is falling through.
	var passing: bool = drop_ticks > 0

	# --- horizontal ---
	pos.x += vel.x * dt
	for r in rects:
		if passing and _is_open_ledge(r, drop_from_y):
			continue
		if _overlaps(pos, r):
			if vel.x > 0.0:
				pos.x = r.position.x - HALF.x
			elif vel.x < 0.0:
				pos.x = r.end.x + HALF.x
			vel.x = 0.0

	# --- vertical ---
	pos.y += vel.y * dt
	on_ground = false
	for r in rects:
		if passing and _is_open_ledge(r, drop_from_y):
			continue
		if _overlaps(pos, r):
			if vel.y > 0.0:
				pos.y = r.position.y - HALF.y
				on_ground = true
			elif vel.y < 0.0:
				pos.y = r.end.y + HALF.y
			vel.y = 0.0

	# Wrapping happens after collision, and the solid set already carries seam
	# copies, so a body straddling an edge is resolved against the same piece
	# from either side before it is folded back into the arena.
	pos = cfg.wrap_point(pos)
	return [pos, vel, on_ground]


## Transparent to a drop in progress: thin enough to be a ledge rather than a
## floor, and sitting at or above the surface the drop started from. The height
## test is what keeps the immunity from carrying past a second ledge — anything
## below the one you left is still solid, so a drop always lands somewhere.
static func _is_open_ledge(r: Rect2, drop_from_y: float) -> bool:
	return r.size.y <= DROP_THROUGH_MAX_THICKNESS and r.position.y <= drop_from_y + 1.0


static func _overlaps(center: Vector2, r: Rect2) -> bool:
	return absf(center.x - (r.position.x + r.size.x * 0.5)) < HALF.x + r.size.x * 0.5 \
		and absf(center.y - (r.position.y + r.size.y * 0.5)) < HALF.y + r.size.y * 0.5


## Shared with PreviewLayer so the planning ghost has the same dramatic
## silhouette as the live fighter. The lean, crossed weight and hand framing
## the face evoke a theatrical manga pose without tracing a specific character.
static func idle_pose_points(face: int, aim: Vector2, breath: float = 0.0) -> Dictionary:
	var f := float(face)
	var d := aim.normalized() if not aim.is_zero_approx() else Vector2(f, 0.0)
	var hip := Vector2(3.0 * f, 6.0 + breath)
	var chest := Vector2(-2.5 * f, -6.0 + breath * 0.35)
	var neck := Vector2(-6.0 * f, -13.0 + breath * 0.15)
	var head := Vector2(-8.0 * f, -20.0 + breath * 0.1)
	var shoulder := Vector2(0.0, -6.0)
	var grip := shoulder + d * 11.0
	return {
		"hip": hip,
		"chest": chest,
		"neck": neck,
		"head": head,
		"shoulder": shoulder,
		"aim_elbow": shoulder.lerp(grip, 0.52) + d.orthogonal() * (1.8 * f),
		"grip": grip,
		"free_shoulder": chest + Vector2(-3.0 * f, 1.0),
		"free_elbow": Vector2(-15.0 * f, -5.0 + breath),
		"free_hand": Vector2(-11.0 * f, -17.0 + breath * 0.4),
		"knee_a": Vector2(10.0 * f, 14.0),
		"foot_a": Vector2(15.0 * f, 24.0),
		"knee_b": Vector2(-5.0 * f, 15.0),
		"foot_b": Vector2(-11.0 * f, 24.0),
	}


func _pose_points() -> Dictionary:
	var speed := absf(vel.x)
	var moving := on_ground and speed > 24.0
	var breath := sin(_anim_time * 2.4) * 0.8
	var pose := idle_pose_points(facing, aim_dir(), breath)

	if not on_ground:
		var f := float(facing)
		pose["hip"] = Vector2(0.0, 5.0)
		pose["chest"] = Vector2(-1.5 * f, -6.0)
		pose["neck"] = Vector2(-3.0 * f, -13.0)
		pose["head"] = Vector2(-4.0 * f, -20.0)
		pose["free_shoulder"] = pose["chest"] + Vector2(-3.0 * f, 1.0)
		pose["free_elbow"] = Vector2(-11.0 * f, -11.0)
		pose["free_hand"] = Vector2(-15.0 * f, -4.0)
		pose["knee_a"] = Vector2(9.0 * f, 12.0)
		pose["foot_a"] = Vector2(4.0 * f, 22.0)
		pose["knee_b"] = Vector2(-8.0 * f, 10.0)
		pose["foot_b"] = Vector2(-13.0 * f, 18.0)
	elif moving:
		var travel := signf(vel.x)
		var stride := sin(_anim_time * clampf(speed * 0.045, 7.5, 13.0))
		var lift_a := maxf(0.0, -stride) * 3.0
		var lift_b := maxf(0.0, stride) * 3.0
		pose["hip"] = Vector2(0.0, 5.0 + absf(stride) * 0.8)
		pose["chest"] = Vector2(2.5 * travel, -6.0)
		pose["neck"] = Vector2(3.5 * travel, -13.0)
		pose["head"] = Vector2(4.0 * travel, -20.0)
		pose["free_shoulder"] = pose["chest"] + Vector2(-3.0 * float(facing), 1.0)
		pose["free_elbow"] = Vector2(-10.0 * travel * stride, 0.0)
		pose["free_hand"] = Vector2(-14.0 * travel * stride, 8.0)
		pose["knee_a"] = Vector2(9.0 * travel * stride, 14.0 - lift_a)
		pose["foot_a"] = Vector2(14.0 * travel * stride, 24.0 - lift_a)
		pose["knee_b"] = Vector2(-9.0 * travel * stride, 14.0 - lift_b)
		pose["foot_b"] = Vector2(-14.0 * travel * stride, 24.0 - lift_b)

	return pose


func _draw_bone(a: Vector2, b: Vector2, width: float, body: Color) -> void:
	var ink := Color(0.035, 0.035, 0.055, 0.96)
	draw_line(a, b, ink, width + 3.0, true)
	draw_line(a, b, body, width, true)


func _draw_joint(at: Vector2, radius: float, body: Color) -> void:
	draw_circle(at, radius + 1.4, Color(0.035, 0.035, 0.055, 0.96))
	draw_circle(at, radius, body.lightened(0.18))


func _draw_knife_pair(grip: Vector2, d: Vector2) -> void:
	for launch in cfg.knife_launch_velocities(d, plan.power):
		var kd: Vector2 = launch.normalized()
		var side: Vector2 = kd.orthogonal()
		var base: Vector2 = grip + kd * 2.0
		var point: Vector2 = grip + kd * 18.0
		draw_colored_polygon(PackedVector2Array([
			point, base + side * 2.2, base - kd * 3.0, base - side * 2.2,
		]), Color(0.90, 0.93, 1.0, 0.96))
		draw_line(base - side * 3.2, base + side * 3.2, color.lightened(0.5), 1.4, true)


func _draw_pose_shadow(pose: Dictionary) -> void:
	# A hard offset shadow reads at sprite scale and matches the cel-shaded UI.
	# It is separate from the contact shadow: airborne fighters keep this one.
	var off := Vector2(4.0, 5.0)
	var shade := Color(0.01, 0.005, 0.025, 0.58)
	var segments := [
		[pose["hip"], pose["chest"], 7.5], [pose["chest"], pose["neck"], 7.0],
		[pose["hip"], pose["knee_a"], 6.2], [pose["knee_a"], pose["foot_a"], 6.2],
		[pose["hip"], pose["knee_b"], 6.0], [pose["knee_b"], pose["foot_b"], 6.0],
		[pose["free_shoulder"], pose["free_elbow"], 6.0],
		[pose["free_elbow"], pose["free_hand"], 6.0],
		[pose["shoulder"], pose["aim_elbow"], 6.2],
		[pose["aim_elbow"], pose["grip"], 6.2],
	]
	for segment in segments:
		draw_line(segment[0] + off, segment[1] + off, shade, segment[2], true)
	draw_circle(pose["head"] + off, 8.4, shade)
	for joint in [pose["hip"], pose["knee_a"], pose["knee_b"], pose["free_elbow"], pose["grip"]]:
		draw_circle(joint + off, 3.8, shade)


func _draw() -> void:
	if not alive:
		var fallen := Color(0.30, 0.30, 0.34, 0.72)
		_draw_bone(Vector2(-13.0, 18.0), Vector2(6.0, 17.0), 3.0, fallen)
		_draw_bone(Vector2(-2.0, 17.0), Vector2(-10.0, 7.0), 2.5, fallen)
		_draw_bone(Vector2(4.0, 17.0), Vector2(13.0, 23.0), 2.5, fallen)
		draw_circle(Vector2(-17.0, 17.0), 6.0, Color(0.035, 0.035, 0.055, 0.9))
		draw_circle(Vector2(-17.0, 17.0), 4.2, fallen)
		draw_line(Vector2(-22.0, 8.0), Vector2(18.0, 25.0), Color(1, 0.25, 0.25, 0.9), 2.5, true)
		return

	var f := float(facing)
	var pose := _pose_points()
	# A completed late-match meter should be legible on the fighter even when the
	# HUD is not where the player is looking. Arming it brightens and thickens the
	# ring, so the toggle has world-space feedback as well as a panel label.
	if index < cfg.super_meter.size() and cfg.super_meter[index] >= 1.0:
		var armed: bool = index < cfg.super_armed.size() and cfg.super_armed[index]
		draw_circle(Vector2.ZERO, 38.0, Color(1.0, 0.78, 0.18, 0.19 if armed else 0.08))
		draw_arc(Vector2.ZERO, 38.0, 0.0, TAU, 32,
			Color(1.0, 0.97, 0.64, 1.0) if armed else Color(1.0, 0.82, 0.36, 0.72),
			4.0 if armed else 2.0)
		for i in 4:
			var sa: float = TAU * float(i) / 4.0
			draw_circle(Vector2(cos(sa), sin(sa)) * 38.0, 3.5 if armed else 2.5,
				Color(1.0, 1.0, 0.78) if armed else Color(1.0, 0.86, 0.48))
	# contact shadow, so a player reads as standing on a surface rather than
	# floating in front of it
	if on_ground:
		draw_circle(Vector2(0.0, HALF.y + 2.0), 15.0, Color(0, 0, 0, 0.28))

	# invulnerability shield — arrows pass straight through this turn
	if is_invulnerable():
		var r := 34.0
		draw_circle(Vector2.ZERO, r, Color(color.r, color.g, color.b, 0.10))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(0.95, 0.97, 1.0, 0.75), 2.0)
		for i in 8:
			var a: float = TAU * float(i) / 8.0
			draw_line(Vector2(cos(a), sin(a)) * (r - 5.0), Vector2(cos(a), sin(a)) * (r + 4.0),
				Color(0.95, 0.97, 1.0, 0.35), 1.5)

	_draw_pose_shadow(pose)

	# Legs first, then the curved torso, so joints overlap like a tiny articulated
	# puppet. A dark under-stroke gives the thin figure manga-like ink weight.
	_draw_bone(pose["hip"], pose["knee_b"], 3.0, color.darkened(0.12))
	_draw_bone(pose["knee_b"], pose["foot_b"], 3.0, color.darkened(0.12))
	_draw_bone(pose["hip"], pose["knee_a"], 3.2, color)
	_draw_bone(pose["knee_a"], pose["foot_a"], 3.2, color)
	_draw_bone(pose["hip"], pose["chest"], 4.5, color)
	_draw_bone(pose["chest"], pose["neck"], 4.0, color.lightened(0.08))

	# The free arm frames the face in the idle stance; the throwing arm remains
	# mechanically honest and always reaches the actual launch shoulder.
	_draw_bone(pose["free_shoulder"], pose["free_elbow"], 3.0, color.darkened(0.05))
	_draw_bone(pose["free_elbow"], pose["free_hand"], 3.0, color)
	_draw_bone(pose["shoulder"], pose["aim_elbow"], 3.2, color.lightened(0.05))
	_draw_bone(pose["aim_elbow"], pose["grip"], 3.2, color)

	for joint in [pose["hip"], pose["knee_a"], pose["knee_b"], pose["free_elbow"], pose["grip"]]:
		_draw_joint(joint, 2.1, color)

	var head: Vector2 = pose["head"]
	var ink := Color(0.035, 0.035, 0.055, 0.98)
	# Angular collar and swept spikes add an aristocratic-vampire silhouette
	# without turning the tiny fighter into a detailed costume sprite.
	var collar := PackedVector2Array([
		pose["neck"] + Vector2(-1.0 * f, 1.0),
		pose["chest"] + Vector2(-7.0 * f, -1.0),
		pose["chest"] + Vector2(-2.0 * f, 5.0),
		pose["chest"] + Vector2(4.0 * f, 2.0),
	])
	draw_colored_polygon(collar, ink)
	draw_polyline(collar, color.lightened(0.12), 1.4, true)
	var hair := PackedVector2Array([
		head + Vector2(-3.0 * f, -5.0),
		head + Vector2(-9.0 * f, -7.0),
		head + Vector2(-6.0 * f, -1.0),
		head + Vector2(-11.0 * f, 2.0),
		head + Vector2(-4.0 * f, 4.0),
	])
	draw_colored_polygon(hair, ink)
	draw_polyline(hair, color.darkened(0.10), 2.0, true)
	draw_circle(head, 7.2, Color(0.035, 0.035, 0.055, 0.98))
	draw_circle(head, 5.1, color.lightened(0.18))
	draw_arc(head, 5.2, -0.9, 1.9, 10, color.lightened(0.55), 1.1, true)
	draw_circle(head + Vector2(3.0 * f, -0.8), 1.25, Color(0.03, 0.03, 0.05))
	# A tiny angular brow sells the stare even at the native 720p scale.
	draw_line(head + Vector2(0.7 * f, -2.5), head + Vector2(4.0 * f, -1.7),
		Color(0.03, 0.03, 0.05), 1.2, true)

	_draw_knife_pair(pose["grip"], aim_dir())

	draw_string(ThemeDB.fallback_font, Vector2(-10.0, -HALF.y - 12.0), "P%d" % (index + 1),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color.lightened(0.5))
