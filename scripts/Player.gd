extends Node2D
class_name Player

## Physics-based fighter. All motion goes through the static `step_state()` below
## so that PredictionSystem can produce a ghost using the exact same integration.

const SIZE := Vector2(32.0, 48.0)
const HALF := Vector2(16.0, 24.0)
## A ground jump plus this one mid-air charge makes the movement a double jump.
const MAX_AIR_JUMPS := 1

## Cosmetic movement echoes. They are sampled only while time is running, so
## the last few poses remain pinned to the arena when planning freezes again.
## Keeping the count and opacity low gives the motion an anime accent without
## turning the fighter into a bright continuous smear.
const AFTERIMAGE_MAX := 5
const AFTERIMAGE_SAMPLE_INTERVAL := 0.055
const AFTERIMAGE_LIFETIME := 0.32
const AFTERIMAGE_MIN_SPEED := 105.0
const AFTERIMAGE_MIN_DISTANCE := 10.0

## Character-specific inks are deliberately few and bold. They change only the
## procedural silhouette; the player color still owns the articulated body.
const VELOCITY_ORANGE := Color(0.94, 0.37, 0.10, 0.98)
const VELOCITY_CYAN := Color(0.24, 0.96, 1.0, 0.98)
const VELOCITY_GOLD := Color(1.0, 0.76, 0.22, 0.98)
const ECLIPSE_WINE := Color(0.33, 0.11, 0.21, 0.98)
const ECLIPSE_PEARL := Color(0.91, 0.88, 0.82, 0.98)
const ECLIPSE_ROSE := Color(0.72, 0.48, 0.38, 0.98)
const PULSE_CHERRY := Color(0.23, 0.06, 0.16, 0.98)
const PULSE_VIOLET := Color(0.43, 0.24, 0.60, 0.92)
const PULSE_ACID := Color(0.78, 0.95, 0.36, 0.98)
const PULSE_BONE := Color(0.92, 0.89, 0.84, 0.98)
const PULSE_CHROME := Color(0.75, 0.78, 0.81, 0.98)

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
## Cosmetic roster id mirrored from GameManager. Physics never reads it here;
## it only gives every prototype a distinct procedural stick silhouette.
var fighter_style: int = 0
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
## Gate 1 renderer switch. This is cosmetic only: disabling it suppresses this
## node's legacy `_draw()` while every simulation method and constant stays live.
var draw_legacy_visual: bool = true
var _anim_time: float = 0.0
var _afterimages: Array[Dictionary] = []
var _afterimage_sample_time: float = 0.0
var _afterimage_last_position: Vector2 = Vector2.ZERO
var _afterimage_has_origin: bool = false


func _init() -> void:
	plan = PlayerPlan.new()


## The simulation remains deterministic; this clock only bends the drawn stick
## figure. During planning the pose freezes with the rest of the world.
func _process(delta: float) -> void:
	var time_running: bool = cfg == null or cfg.state == Phase.EXECUTING \
		or cfg.state == Phase.FREEPLAY
	if alive and time_running:
		_anim_time += delta
	_update_afterimages(delta, time_running)
	# Aim can change while the body is frozen, so refresh even when the animation
	# clock is stopped. There are only two fighters, making this effectively free.
	queue_redraw()


## The entries age only in live time. During planning/commit they keep their
## exact position and opacity, becoming a quiet record of the preceding burst.
func _update_afterimages(delta: float, time_running: bool) -> void:
	if not time_running:
		return

	for i in range(_afterimages.size() - 1, -1, -1):
		_afterimages[i]["age"] = float(_afterimages[i]["age"]) + delta
		if float(_afterimages[i]["age"]) >= AFTERIMAGE_LIFETIME:
			_afterimages.remove_at(i)

	if not alive:
		_afterimage_has_origin = false
		return

	var speed := vel.length()
	if speed < AFTERIMAGE_MIN_SPEED:
		_afterimage_sample_time = 0.0
		_afterimage_last_position = position
		_afterimage_has_origin = true
		return

	_afterimage_sample_time += delta
	if not _afterimage_has_origin:
		_afterimage_last_position = position
		_afterimage_has_origin = true
		return

	var travelled: Vector2 = cfg.wrap_delta(_afterimage_last_position, position) \
		if cfg != null and cfg.has_method("wrap_delta") \
		else position - _afterimage_last_position
	if _afterimage_sample_time < AFTERIMAGE_SAMPLE_INTERVAL \
		or travelled.length() < AFTERIMAGE_MIN_DISTANCE:
		return

	_afterimage_sample_time = 0.0
	_afterimage_last_position = position
	_afterimages.append({
		"position": position,
		"pose": _pose_points().duplicate(true),
		"age": 0.0,
	})
	while _afterimages.size() > AFTERIMAGE_MAX:
		_afterimages.pop_front()


func clear_afterimages() -> void:
	_afterimages.clear()
	_afterimage_sample_time = 0.0
	_afterimage_last_position = position
	_afterimage_has_origin = false
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
	var jump_result := Player.apply_jump(vel, on_ground, air_jumps_left, jump,
		cfg.jump_impulse_for(index), cfg.air_jump_impulse_for(index), cfg.air_jumps_for(index))
	vel = jump_result[0]
	on_ground = jump_result[1]
	air_jumps_left = jump_result[2]
	var st := Player.step_state(position, vel, on_ground, dir, jump_held, dt, cfg, -1,
		drop_ticks, drop_from_y, cfg.movement_speed_scale(index), cfg.jump_impulse_for(index),
		cfg.max_fall_speed_for(index))
	position = st[0]
	vel = st[1]
	on_ground = st[2]
	if on_ground:
		air_jumps_left = cfg.air_jumps_for(index)


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
		plan.jump_at(t), cfg.jump_impulse_for(index), cfg.air_jump_impulse_for(index),
		cfg.air_jumps_for(index))
	vel = jump_result[0]
	on_ground = jump_result[1]
	air_jumps_left = jump_result[2]
	var st := Player.step_state(position, vel, on_ground, plan.dir_at(t), plan.hold_at(t), dt,
		cfg, from_tick, drop_ticks, drop_from_y, cfg.movement_speed_scale(index),
		cfg.jump_impulse_for(index), cfg.max_fall_speed_for(index))
	position = st[0]
	vel = st[1]
	on_ground = st[2]
	if on_ground:
		air_jumps_left = cfg.air_jumps_for(index)


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
		requested: bool, ground_impulse: float, air_impulse: float = -1.0,
		max_air_jumps: int = MAX_AIR_JUMPS) -> Array:
	var jumped := false
	var impulse := ground_impulse if on_ground else \
		(ground_impulse if air_impulse < 0.0 else air_impulse)
	if requested and impulse > 0.0 and (on_ground or air_jumps_left > 0):
		vel.y = -impulse
		if on_ground:
			air_jumps_left = max_air_jumps
		else:
			air_jumps_left -= 1
		on_ground = false
		jumped = true
	return [vel, on_ground, air_jumps_left, jumped]


## Returns [pos, vel, on_ground]. Static + side-effect free so the prediction
## system can run it on a copy of the state.
static func step_state(pos: Vector2, vel: Vector2, on_ground: bool, dir: int, jump_held: bool,
		dt: float, cfg, from_tick: int = -1, drop_ticks: int = 0,
		drop_from_y: float = 0.0, move_speed_scale: float = 1.0,
		jump_cut_impulse: float = -1.0, fall_speed: float = -1.0) -> Array:
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
	var effective_jump_impulse: float = cfg.jump_impulse \
		if jump_cut_impulse < 0.0 else jump_cut_impulse
	if vel.y < 0.0 and not jump_held:
		vel.y = maxf(vel.y, -effective_jump_impulse * cfg.jump_cut)

	var target: float = float(dir) * cfg.player_move_speed * move_speed_scale
	var accel: float = cfg.player_acceleration if on_ground else cfg.player_air_acceleration
	vel.x = move_toward(vel.x, target, accel * dt)
	var effective_fall_speed: float = cfg.max_fall_speed if fall_speed < 0.0 else fall_speed
	vel.y = minf(vel.y + cfg.gravity * dt, effective_fall_speed)

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


func _draw_knife_fan(grip: Vector2, d: Vector2) -> void:
	for launch in cfg.knife_launch_velocities(d, plan.power):
		var kd: Vector2 = launch.normalized()
		var side: Vector2 = kd.orthogonal()
		var base: Vector2 = grip + kd * 2.0
		var point: Vector2 = grip + kd * 18.0
		draw_colored_polygon(PackedVector2Array([
			point, base + side * 2.2, base - kd * 3.0, base - side * 2.2,
		]), Color(0.90, 0.93, 1.0, 0.96))
		draw_line(base - side * 3.2, base + side * 3.2, color.lightened(0.5), 1.4, true)


func _is_dashblading() -> bool:
	return fighter_style == 2 and cfg != null and cfg.has_method("_player_is_dashing") \
		and cfg._player_is_dashing(index)


## The special pose follows the attack vector, but it is cosmetic: the Player
## position, 32x48 body and Dashblade guard rectangle remain authoritative.
func _dashblade_pose(base_pose: Dictionary) -> Dictionary:
	var pose := base_pose.duplicate(true)
	var d := aim_dir().normalized()
	if d.is_zero_approx():
		d = Vector2(float(facing), 0.0)
	var side := d.orthogonal()
	pose["hip"] = -d * 1.0
	pose["chest"] = -d * 7.0
	pose["neck"] = -d * 12.0
	pose["head"] = -d * 17.0 - side * 1.5
	pose["shoulder"] = -d * 5.0 + side * 4.0
	pose["aim_elbow"] = d * 1.0 + side * 2.5
	pose["grip"] = d * 8.0
	pose["free_shoulder"] = -d * 7.0 - side * 4.0
	pose["free_elbow"] = d * 3.0 - side * 7.0
	pose["free_hand"] = d * 15.0 - side * 4.0
	pose["knee_a"] = -d * 6.0 + side * 7.0
	pose["foot_a"] = -d * 17.0 + side * 10.0
	pose["knee_b"] = -d * 8.0 - side * 6.0
	pose["foot_b"] = -d * 20.0 - side * 8.0
	return pose


func _velocity_stored_frames() -> int:
	if cfg == null or index < 0 or index >= cfg.frame_debt_cells.size():
		return 0
	return clampi(int(cfg.frame_debt_cells[index]), 0, 3)


func _draw_velocity_lance(rear: Vector2, point: Vector2, d: Vector2,
		side: Vector2, ring_origin: Vector2, stored: int) -> void:
	var ink := Color(0.025, 0.02, 0.045, 0.99)
	draw_line(rear, point - d * 7.0, ink, 7.0, true)
	draw_line(rear, point - d * 7.0, VELOCITY_GOLD.darkened(0.48), 3.4, true)
	draw_line(rear + side * 0.8, point - d * 9.0 + side * 0.8,
		Color(0.22, 0.32, 0.48, 0.96), 1.3, true)
	# The three sliding rings are the character-readable version of LOST FRAME.
	for i in 3:
		var at := ring_origin - d * (float(i) * 7.0)
		var ring_color := VELOCITY_CYAN if i < stored else VELOCITY_GOLD
		draw_line(at - side * 5.0, at + side * 5.0, ink, 4.2, true)
		draw_line(at - side * 4.2, at + side * 4.2, ring_color, 2.0, true)
	var neck := point - d * 9.0
	var tip := PackedVector2Array([
		point, neck + side * 5.2, neck - d * 7.0, neck - side * 5.2,
	])
	draw_colored_polygon(tip, ink)
	draw_polyline(tip + PackedVector2Array([tip[0]]), VELOCITY_GOLD, 1.5, true)
	draw_line(neck - d * 4.0, point - d * 2.0, VELOCITY_CYAN, 1.3, true)


## Two shield halves leave a narrow central channel. The lance is drawn first,
## so the shield visibly leads while the point passes through that channel.
func _draw_velocity_shield(center: Vector2, d: Vector2, side: Vector2,
		half_span: float, half_depth: float) -> void:
	var ink := Color(0.025, 0.02, 0.045, 0.99)
	for raw_sign in [-1.0, 1.0]:
		var sign_value: float = float(raw_sign)
		var shield_half := PackedVector2Array([
			center + side * sign_value * 2.2 - d * half_depth,
			center + side * sign_value * half_span - d * (half_depth * 0.72),
			center + side * sign_value * (half_span + 3.0),
			center + side * sign_value * (half_span - 2.0) + d * half_depth,
			center + side * sign_value * 2.2 + d * (half_depth * 0.75),
		])
		draw_colored_polygon(shield_half, ink)
		draw_polyline(shield_half + PackedVector2Array([shield_half[0]]),
			VELOCITY_GOLD, 1.6, true)
		var slit_start: Vector2 = center + side * sign_value * 6.0 \
			- d * (half_depth * 0.38)
		var slit_end: Vector2 = center + side * sign_value * (half_span - 3.5) \
			+ d * (half_depth * 0.2)
		draw_line(slit_start, slit_end, VELOCITY_CYAN, 2.0, true)


func _draw_dashblade_kit(pose: Dictionary) -> void:
	var d := aim_dir().normalized()
	if d.is_zero_approx():
		d = Vector2(float(facing), 0.0)
	var side := d.orthogonal()
	if _is_dashblading():
		var committed: int = cfg.dash_frame_debt_spent(index) \
			if cfg.has_method("dash_frame_debt_spent") else 0
		# Weapon first, shield second: the charge is visually shield-led while the
		# lance emerges through its split centre and remains the striking point.
		_draw_velocity_lance(-d * 34.0, d * 62.0, d, side, -d * 7.0,
			clampi(committed, 0, 3))
		_draw_velocity_shield(d * 24.0, d, side, 26.0, 10.0)
		return

	var grip: Vector2 = pose["grip"]
	_draw_velocity_lance(grip - d * 15.0, grip + d * 45.0, d, side,
		grip - d * 1.0, _velocity_stored_frames())
	# At rest the shield hangs from the free arm like an extravagant piece of
	# runway hardware; it becomes the full leading slab only during the breach.
	var shield_center: Vector2 = pose["free_hand"] + d * 4.0
	_draw_velocity_shield(shield_center, d, side, 12.0, 6.0)


func _draw_chakram_kit(pose: Dictionary) -> void:
	# The Eclipse manufactures a separate twelve-bladed corona at the open hand;
	# the smooth permanent aureole is drawn by his costume and never leaves him.
	var d := aim_dir().normalized()
	if d.is_zero_approx():
		d = Vector2(float(facing), 0.0)
	var center: Vector2 = pose["grip"] + d * 8.0
	draw_circle(pose["grip"], 3.7, ECLIPSE_PEARL)
	draw_arc(center, 8.0, 0.0, TAU, 24, Color(0.04, 0.03, 0.05), 4.0, true)
	draw_arc(center, 7.2, 0.0, TAU, 24, ECLIPSE_WINE.lightened(0.12), 1.2, true)
	for i in 12:
		var a := TAU * float(i) / 12.0
		var outward := Vector2(cos(a), sin(a))
		var side := outward.orthogonal()
		var root := center + outward * 8.0
		draw_colored_polygon(PackedVector2Array([
			root - side * 1.5, root + outward * 4.5, root + side * 1.5,
		]), ECLIPSE_ROSE)


func _draw_shock_kit(pose: Dictionary) -> void:
	# The Pulse conducts through one open tuning-fork baton. It must never read as
	# the old firearm: a straight shaft, two clean prongs and one floating crystal.
	var d := aim_dir().normalized()
	if d.is_zero_approx():
		d = Vector2(float(facing), 0.0)
	var side := d.orthogonal()
	var grip: Vector2 = pose["grip"]
	var fork_base := grip + d * 18.0
	var fork_tip := grip + d * 29.0
	draw_line(grip - d * 9.0, fork_base, Color(0.055, 0.04, 0.07), 5.0, true)
	draw_line(grip - d * 8.0, fork_base, PULSE_CHROME, 1.6, true)
	draw_line(fork_base, fork_tip + side * 4.0, PULSE_CHROME, 2.4, true)
	draw_line(fork_base, fork_tip - side * 4.0, PULSE_CHROME, 2.4, true)
	if plan.attack_mode == 1:
		var orb_center := fork_tip + d * 7.0
		draw_circle(orb_center, 6.2, Color(0.08, 0.04, 0.11, 0.98))
		draw_arc(orb_center, 5.0, 0.0, TAU, 16, PULSE_CHROME, 1.2, true)
		draw_circle(orb_center, 2.4, PULSE_ACID)
		for tab_dir in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
			draw_circle(orb_center + tab_dir * 7.0, 1.2, PULSE_CHROME)
	else:
		var crystal_center := fork_tip + d * 1.5
		var crystal := PackedVector2Array([
			crystal_center + d * 3.0, crystal_center + side * 2.2,
			crystal_center - d * 3.0, crystal_center - side * 2.2,
		])
		draw_colored_polygon(crystal, PULSE_ACID)


func _draw_default_costume(pose: Dictionary, head: Vector2, f: float) -> void:
	var ink := Color(0.035, 0.035, 0.055, 0.98)
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


func _draw_velocity_fashion(pose: Dictionary, head: Vector2, f: float) -> void:
	var ink := Color(0.025, 0.02, 0.045, 0.99)
	# One trouser leg blooms into the portrait's runway flare. This stays outside
	# collision and is intentionally only a few pixels wider than the stick leg.
	var knee: Vector2 = pose["knee_b"]
	var foot: Vector2 = pose["foot_b"]
	var leg_axis := (foot - knee).normalized()
	var leg_side := leg_axis.orthogonal()
	var flare := PackedVector2Array([
		knee - leg_side * 3.2, knee + leg_side * 3.2,
		foot + leg_side * 6.5, foot + leg_axis * 2.0,
		foot - leg_side * 6.5,
	])
	draw_colored_polygon(flare, Color(0.035, 0.08, 0.22, 0.98))
	draw_polyline(flare + PackedVector2Array([flare[0]]), color.lightened(0.12), 1.2, true)
	# Cropped cavalry jacket and the single huge orange lapel carry most of the
	# fashion read; the body underneath remains the shared puppet. Both are cut
	# in the torso's own basis, the same way the flare follows the shin above.
	# The dash pose swings hip/chest/neck around the aim vector, so world-space
	# x/y offsets fold these quads onto themselves at most angles, and Godot's
	# triangulator drops a non-simple polygon instead of drawing it.
	var hip: Vector2 = pose["hip"]
	var chest: Vector2 = pose["chest"]
	var neck: Vector2 = pose["neck"]
	var torso_axis := (neck - hip).normalized()
	var torso_side := torso_axis.orthogonal() * f
	var jacket := PackedVector2Array([
		chest + torso_axis * 6.2 + torso_side * 3.7,
		chest - torso_axis * 0.5 - torso_side * 8.1,
		hip - torso_axis * 1.2 - torso_side * 4.9,
		hip + torso_axis * 0.8 + torso_side * 4.0,
	])
	draw_colored_polygon(jacket, Color(0.03, 0.07, 0.18, 0.98))
	draw_polyline(jacket + PackedVector2Array([jacket[0]]), VELOCITY_GOLD, 1.2, true)
	var lapel := PackedVector2Array([
		neck - torso_axis * 0.5 + torso_side * 1.3,
		neck + torso_axis * 1.9 + torso_side * 6.3,
		chest - torso_axis * 1.5 + torso_side * 6.2,
		hip - torso_side * 2.2,
	])
	draw_colored_polygon(lapel, VELOCITY_ORANGE)
	draw_polyline(lapel + PackedVector2Array([lapel[0]]), ink, 1.2, true)
	# The upward hair horn replaces a literal dragoon helmet.
	var hair_horn := PackedVector2Array([
		head + Vector2(-4.0 * f, 2.0),
		head + Vector2(-7.0 * f, -3.0),
		head + Vector2(-4.0 * f, -15.0),
		head + Vector2(1.0 * f, -8.0),
		head + Vector2(3.0 * f, -4.0),
	])
	draw_colored_polygon(hair_horn, Color(0.18, 0.055, 0.035, 0.99))
	draw_polyline(hair_horn + PackedVector2Array([hair_horn[0]]),
		VELOCITY_ORANGE.darkened(0.16), 1.4, true)
	draw_circle(pose["shoulder"], 4.2, ink)
	draw_arc(pose["shoulder"], 3.5, 0.0, TAU, 10, VELOCITY_GOLD, 1.3, true)


func _draw_eclipse_fashion(pose: Dictionary, head: Vector2, _f: float) -> void:
	var ink := Color(0.035, 0.025, 0.04, 0.99)
	# One smooth permanent aureole anchors the identity. It is intentionally
	# unbladed and stays attached even while a weapon corona is in flight.
	draw_arc(head, 15.5, 0.0, TAU, 30, ink, 3.2, true)
	draw_arc(head, 14.3, 0.0, TAU, 30, ECLIPSE_WINE.lightened(0.16), 1.0, true)
	for cardinal in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		draw_circle(head + cardinal * 15.0, 1.5, ECLIPSE_ROSE)
	# The pearl crescent mantle frames the head without becoming horns or armor.
	var mantle := PackedVector2Array([
		pose["free_shoulder"] + Vector2(-5.0, -4.0),
		pose["neck"] + Vector2(-7.0, -1.0),
		pose["neck"] + Vector2(0.0, 5.0),
		pose["neck"] + Vector2(7.0, -1.0),
		pose["shoulder"] + Vector2(5.0, -4.0),
		pose["chest"] + Vector2(6.0, 5.0),
		pose["chest"] + Vector2(-6.0, 5.0),
	])
	draw_colored_polygon(mantle, ECLIPSE_PEARL)
	draw_polyline(mantle + PackedVector2Array([mantle[0]]), ECLIPSE_ROSE, 1.2, true)
	var vest := PackedVector2Array([
		pose["chest"] + Vector2(-4.0, 0.0), pose["chest"] + Vector2(4.0, 0.0),
		pose["hip"] + Vector2(5.0, 5.0), pose["hip"] + Vector2(-5.0, 5.0),
	])
	draw_colored_polygon(vest, ECLIPSE_WINE)
	for shoulder in [pose["free_shoulder"], pose["shoulder"]]:
		draw_line(shoulder, pose["hip"] + Vector2(signf(shoulder.x - pose["hip"].x) * 8.0, 13.0),
			ECLIPSE_PEARL, 2.2, true)


func _draw_pulse_fashion(pose: Dictionary, head: Vector2, f: float) -> void:
	var ink := Color(0.035, 0.015, 0.055, 0.99)
	# Exactly four hard stained-glass moth panels form the serrated X behind her.
	var wing_root: Vector2 = pose["chest"] + Vector2(-2.0 * f, 2.0)
	for tip_offset: Vector2 in [Vector2(-18.0, -24.0), Vector2(18.0, -24.0),
			Vector2(-16.0, 20.0), Vector2(16.0, 20.0)]:
		var tip: Vector2 = wing_root + tip_offset
		var axis: Vector2 = (tip - wing_root).normalized()
		var side: Vector2 = axis.orthogonal()
		var wing := PackedVector2Array([
			wing_root - side * 2.2, tip, wing_root + side * 4.0,
		])
		draw_colored_polygon(wing, Color(PULSE_VIOLET.r, PULSE_VIOLET.g, PULSE_VIOLET.b, 0.46))
		draw_polyline(wing + PackedVector2Array([wing[0]]), PULSE_ACID, 1.2, true)
	var bodice := PackedVector2Array([
		pose["neck"] + Vector2(-3.0, 1.0), pose["neck"] + Vector2(3.0, 1.0),
		pose["hip"] + Vector2(4.0, 2.0), pose["hip"] + Vector2(-4.0, 2.0),
	])
	draw_colored_polygon(bodice, PULSE_BONE)
	draw_polyline(bodice + PackedVector2Array([bodice[0]]), PULSE_CHROME, 1.0, true)
	# Two simple panels keep the hem sharply pointed without creating the
	# self-intersecting six-point polygon that failed triangulation in mirrored
	# and movement poses.
	var jacket_left := PackedVector2Array([
		pose["chest"] + Vector2(-7.0, -3.0),
		pose["chest"] + Vector2(0.0, -2.0),
		pose["hip"] + Vector2(0.0, 3.0),
		pose["hip"] + Vector2(-6.0, 7.0),
	])
	var jacket_right := PackedVector2Array([
		pose["chest"] + Vector2(0.0, -2.0),
		pose["chest"] + Vector2(7.0, -3.0),
		pose["hip"] + Vector2(6.0, 7.0),
		pose["hip"] + Vector2(0.0, 3.0),
	])
	for panel: PackedVector2Array in [jacket_left, jacket_right]:
		draw_colored_polygon(panel, PULSE_CHERRY)
		draw_polyline(panel + PackedVector2Array([panel[0]]), PULSE_ACID, 1.2, true)
	draw_circle(pose["chest"], 2.2, PULSE_ACID)
	# Compact black-violet bob plus one acid lightning forelock; no twin tails.
	draw_circle(head + Vector2(-1.5 * f, -1.0), 8.2, ink)
	var bob := PackedVector2Array([
		head + Vector2(-7.0 * f, -5.0), head + Vector2(-2.0 * f, -9.0),
		head + Vector2(5.0 * f, -6.0), head + Vector2(7.0 * f, 2.0),
		head + Vector2(-4.0 * f, 6.0),
	])
	draw_colored_polygon(bob, Color(0.14, 0.09, 0.18, 0.99))
	draw_polyline(PackedVector2Array([
		head + Vector2(1.0 * f, -7.0), head + Vector2(4.0 * f, -3.0),
		head + Vector2(2.0 * f, -1.0), head + Vector2(5.0 * f, 2.0),
	]), PULSE_ACID, 2.0, true)


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


## A reduced version of the fighter silhouette: no label, weapon, shield or
## facial detail. That restraint is what keeps three echoes from reading as
## three additional players in a busy freeze-frame.
func _draw_afterimage(pose: Dictionary, offset: Vector2, strength: float) -> void:
	var echo := color.lightened(0.30)
	echo.a = strength
	var segments := [
		[pose["hip"], pose["chest"], 5.3], [pose["chest"], pose["neck"], 4.8],
		[pose["hip"], pose["knee_a"], 4.0], [pose["knee_a"], pose["foot_a"], 4.0],
		[pose["hip"], pose["knee_b"], 3.8], [pose["knee_b"], pose["foot_b"], 3.8],
		[pose["free_shoulder"], pose["free_elbow"], 3.7],
		[pose["free_elbow"], pose["free_hand"], 3.7],
		[pose["shoulder"], pose["aim_elbow"], 3.9],
		[pose["aim_elbow"], pose["grip"], 3.9],
	]
	for segment in segments:
		draw_line(segment[0] + offset, segment[1] + offset, echo, segment[2], true)
	for joint in [pose["hip"], pose["knee_a"], pose["knee_b"], pose["free_elbow"], pose["grip"]]:
		draw_circle(joint + offset, 2.6, echo)
	draw_circle(pose["head"] + offset, 7.0, echo)


func _draw_missing_frame(offset: Vector2, strength: float) -> void:
	var skew := 3.0 * signf(offset.x) if not is_zero_approx(offset.x) else 2.0
	var panel := PackedVector2Array([
		offset + Vector2(-18.0 + skew, -29.0),
		offset + Vector2(18.0 + skew, -27.0),
		offset + Vector2(17.0 - skew, 28.0),
		offset + Vector2(-19.0 - skew, 26.0),
	])
	draw_colored_polygon(panel, Color(0.08, 0.88, 1.0, 0.025 * strength))
	draw_polyline(panel + PackedVector2Array([panel[0]]),
		Color(0.50, 0.96, 1.0, 0.72 * strength), 1.2, true)


func _draw() -> void:
	_draw_team_marker()
	if not draw_legacy_visual:
		return
	if not alive:
		var fallen := Color(0.30, 0.30, 0.34, 0.72)
		_draw_bone(Vector2(-13.0, 18.0), Vector2(6.0, 17.0), 3.0, fallen)
		_draw_bone(Vector2(-2.0, 17.0), Vector2(-10.0, 7.0), 2.5, fallen)
		_draw_bone(Vector2(4.0, 17.0), Vector2(13.0, 23.0), 2.5, fallen)
		draw_circle(Vector2(-17.0, 17.0), 6.0, Color(0.035, 0.035, 0.055, 0.9))
		draw_circle(Vector2(-17.0, 17.0), 4.2, fallen)
		draw_line(Vector2(-22.0, 8.0), Vector2(18.0, 25.0), Color(1, 0.25, 0.25, 0.9), 2.5, true)
		return

	# Oldest first, all behind the live body. `wrap_delta` keeps an echo beside
	# its owner even when the movement crosses an arena seam.
	for snapshot in _afterimages:
		var offset: Vector2 = cfg.wrap_delta(position, snapshot["position"]) \
			if cfg != null and cfg.has_method("wrap_delta") \
			else snapshot["position"] - position
		var life: float = 1.0 - float(snapshot["age"]) / AFTERIMAGE_LIFETIME
		if fighter_style == 2:
			_draw_missing_frame(offset, life)
		_draw_afterimage(snapshot["pose"], offset, 0.14 * life * life)

	var f := float(facing)
	var pose := _pose_points()
	if _is_dashblading():
		pose = _dashblade_pose(pose)
		_draw_dash_aura()
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
	match fighter_style:
		2:
			_draw_velocity_fashion(pose, head, f)
		3:
			_draw_eclipse_fashion(pose, head, f)
		4:
			_draw_pulse_fashion(pose, head, f)
		_:
			# The dagger fallback keeps the aristocratic swept collar.
			_draw_default_costume(pose, head, f)
	draw_circle(head, 7.2, Color(0.035, 0.035, 0.055, 0.98))
	draw_circle(head, 5.1, color.lightened(0.18))
	draw_arc(head, 5.2, -0.9, 1.9, 10, color.lightened(0.55), 1.1, true)
	draw_circle(head + Vector2(3.0 * f, -0.8), 1.25, Color(0.03, 0.03, 0.05))
	# A tiny angular brow sells the stare even at the native 720p scale.
	draw_line(head + Vector2(0.7 * f, -2.5), head + Vector2(4.0 * f, -1.7),
		Color(0.03, 0.03, 0.05), 1.2, true)

	match fighter_style:
		2:
			_draw_dashblade_kit(pose)
		3:
			_draw_chakram_kit(pose)
		4:
			_draw_shock_kit(pose)
		_:
			_draw_knife_fan(pose["grip"], aim_dir())

	if cfg == null or not bool(cfg.team_mode):
		draw_string(ThemeDB.fallback_font, Vector2(-10.0, -HALF.y - 12.0), "P%d" % (index + 1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color.lightened(0.5))


func _draw_team_marker() -> void:
	if cfg == null or not bool(cfg.team_mode) or index >= cfg.player_teams.size():
		return
	var team: int = cfg.player_teams[index]
	if team < 0 or team >= cfg.TEAM_COLORS.size():
		return
	var team_color: Color = cfg.TEAM_COLORS[team]
	var marker_y := -HALF.y - 22.0
	var chevron := PackedVector2Array([
		Vector2(-14.0, marker_y - 8.0), Vector2(14.0, marker_y - 8.0),
		Vector2(9.0, marker_y + 7.0), Vector2(0.0, marker_y + 12.0),
		Vector2(-9.0, marker_y + 7.0),
	])
	draw_colored_polygon(chevron, Color(0.018, 0.012, 0.030, 0.94))
	draw_polyline(chevron + PackedVector2Array([chevron[0]]),
		Color(team_color.r, team_color.g, team_color.b, 0.96), 1.6, true)
	draw_string(ThemeDB.fallback_font, Vector2(-9.0, marker_y + 6.0), "P%d" % (index + 1),
		HORIZONTAL_ALIGNMENT_CENTER, 18.0, 11, team_color.lightened(0.28))


func _draw_dash_aura() -> void:
	var d := aim_dir().normalized()
	var side := d.orthogonal()
	draw_circle(Vector2.ZERO, 37.0, Color(0.18, 0.92, 1.0, 0.15))
	draw_arc(Vector2.ZERO, 36.0, 0.0, TAU, 30, Color(0.35, 0.96, 1.0, 0.72), 2.2)
	var committed: int = cfg.dash_frame_debt_spent(index) \
		if cfg != null and cfg.has_method("dash_frame_debt_spent") else 0
	for i in maxi(1, committed + 1):
		var centre := -d * (18.0 + float(i) * 11.0) \
			+ side * (float(i % 2) * 8.0 - 4.0)
		var half_forward := 6.0 + float(i) * 0.7
		var half_side := 17.0
		var panel := PackedVector2Array([
			centre - d * half_forward - side * half_side,
			centre + d * half_forward - side * half_side,
			centre + d * half_forward + side * half_side,
			centre - d * half_forward + side * half_side,
		])
		draw_polyline(panel + PackedVector2Array([panel[0]]),
			Color(0.42, 0.96, 1.0, 0.38 + 0.10 * float(i)), 1.8, true)
	var shield_center := d * 24.0
	draw_arc(shield_center, 29.0, d.angle() - 1.05, d.angle() + 1.05, 22,
		Color(VELOCITY_CYAN.r, VELOCITY_CYAN.g, VELOCITY_CYAN.b, 0.42), 2.0, true)
