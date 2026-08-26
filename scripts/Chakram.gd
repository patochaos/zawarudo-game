extends Node2D
class_name Chakram

## Persistent outbound/holding/returning combat primitive. Despite the class name, the
## prototype silhouette is a tiny flying squirrel: the giant-squirrel fighter
## throws one of its glider companions and calls it home again.
##
## There is deliberately no `_process` or `_physics_process`. GameManager owns
## time and calls `sim_step` only during execution, so a chakram automatically
## remains frozen and visible throughout planning.

const ARROW_SCRIPT := preload("res://scripts/Arrow.gd")

enum FlightState { OUTBOUND, HOLDING, RETURNING }
enum ClashKind { REJECTED, DEFLECTED, BROKEN }

const COLLISION_RADIUS := 9.0
const OWNER_CATCH_RADIUS := 25.0
const OWNER_HIT_GRACE_TICKS := 8
const PLAYER_REHIT_GRACE_TICKS := 12

## Lockstep identity/ownership, matching Arrow's integration vocabulary.
var cfg
var shooter: int = -1
var network_id: int = -1
var volley: int = -1
var color := Color(0.92, 0.62, 0.22)

var vel := Vector2.ZERO
var prev_pos := Vector2.ZERO
var age_ticks: int = 0
var flight_state: FlightState = FlightState.OUTBOUND
var launch_turn: int = -1
var return_started: bool = false
## Free Play has no turn changes, so one execution window is approximated with
## this many live ticks: outbound, one window holding, then return.
var freeplay_window_ticks: int = 45
var max_lifetime_ticks: int = 600

## Per-instance tuning lets a character kit author a heavy flat throw, a high
## lob, or a fast recall without adding shared GameManager configuration first.
var outbound_gravity: float = 310.0
var outbound_drag: float = 0.08
var return_speed: float = 760.0
var return_acceleration: float = 2400.0
var return_gravity_scale: float = 0.0
var stationary_spin_speed: float = TAU * 1.8
var destroy_on_player_hit: bool = false
## One bank off permanent HARD geometry gives Eclipse a route around a Duelist's
## approach without letting a persistent corona pinball around the arena.
var bounce_limit: int = 1
var bounce_retention: float = 0.82
var bounce_count: int = 0

var _player_hit_cooldowns: Dictionary = {}
var _stuck_platform_index: int = -1
var _stuck_rect_index: int = -1
var _stuck_rect_offset := Vector2.ZERO
var trail := PackedVector2Array()


## Optional dictionary configuration for spawn code and tests. Unknown keys are
## ignored so kit data can contain visual/character fields beside physics.
func configure(options: Dictionary) -> void:
	for key in options:
		if key in [
			"freeplay_window_ticks", "max_lifetime_ticks", "outbound_gravity",
			"outbound_drag", "return_speed", "return_acceleration",
			"return_gravity_scale", "stationary_spin_speed", "destroy_on_player_hit",
			"bounce_limit", "bounce_retention",
		]:
			set(key, options[key])
	freeplay_window_ticks = maxi(1, freeplay_window_ticks)
	max_lifetime_ticks = maxi(1, max_lifetime_ticks)
	return_speed = maxf(0.0, return_speed)
	return_acceleration = maxf(0.0, return_acceleration)
	bounce_limit = maxi(0, bounce_limit)
	bounce_retention = clampf(bounce_retention, 0.0, 1.0)


func is_returning() -> bool:
	return flight_state == FlightState.RETURNING


func is_holding() -> bool:
	return flight_state == FlightState.HOLDING


func begin_lifecycle(current_turn: int) -> void:
	launch_turn = current_turn
	return_started = false
	flight_state = FlightState.OUTBOUND


## Called when planning advances. Launch turn moves normally; the following
## turn is held in place; the third turn recalls; the fourth removes any disc
## whose return was obstructed or whose owner was too far away.
func advance_to_turn(current_turn: int) -> bool:
	if launch_turn < 0:
		return true
	var elapsed := current_turn - launch_turn
	if elapsed >= 3:
		return false
	if elapsed >= 2 and not return_started:
		force_recall()
	elif elapsed >= 1 and not return_started and flight_state == FlightState.OUTBOUND:
		hold_position()
	return true


func hold_position(platform_index: int = -1, rect_index: int = -1) -> void:
	flight_state = FlightState.HOLDING
	vel = Vector2.ZERO
	trail.clear()
	_stuck_platform_index = platform_index
	_stuck_rect_index = rect_index
	_stuck_rect_offset = Vector2.ZERO
	if platform_index >= 0 and platform_index < cfg.platforms.size():
		var rects: Array = cfg.platforms[platform_index].get("rects", [])
		if rect_index >= 0 and rect_index < rects.size():
			_stuck_rect_offset = position - (rects[rect_index] as Rect2).position
	queue_redraw()


func force_recall() -> void:
	if return_started and flight_state == FlightState.RETURNING:
		return
	return_started = true
	flight_state = FlightState.RETURNING
	vel = Vector2.ZERO
	_stuck_platform_index = -1
	_stuck_rect_index = -1
	trail.clear()
	queue_redraw()


## Advances one deterministic simulation tick.
##
## Result keys are intentionally manager-friendly:
##   alive: retain this node in the projectile array
##   caught: owner completed the return (alive is false)
##   hit_player: opponent index, or -1
##   hit_platform: platform index, or -1
##   stuck: terrain contact pinned the spinning chakram in place
##   bounced: the outbound chakram ricocheted from HARD terrain
##   recalled: this tick changed OUTBOUND -> RETURNING
func sim_step(dt: float, players: Array, current_turn: int = -1) -> Dictionary:
	prev_pos = position
	age_ticks += 1
	_tick_cooldowns(_player_hit_cooldowns)

	var result := {
		"alive": true,
		"caught": false,
		"hit_player": -1,
		"hit_platform": -1,
		"stuck": false,
		"bounced": false,
		"recalled": false,
	}
	var was_returning := is_returning()
	if current_turn >= 0:
		if not advance_to_turn(current_turn):
			result["alive"] = false
			return result
	else:
		if age_ticks >= freeplay_window_ticks * 3:
			result["alive"] = false
			return result
		if age_ticks >= freeplay_window_ticks * 2 and not return_started:
			force_recall()
		elif age_ticks >= freeplay_window_ticks and flight_state == FlightState.OUTBOUND:
			hold_position()
	result["recalled"] = not was_returning and is_returning()

	if flight_state == FlightState.HOLDING:
		var held_from := position
		_follow_stuck_platform()
		prev_pos = held_from
		var held_contact := _first_player_contact(held_from, position, players)
		if not held_contact.is_empty():
			var held_player = held_contact[2]
			position = held_from.lerp(position, float(held_contact[0]))
			result["hit_player"] = held_player.index
			_player_hit_cooldowns[held_player.index] = PLAYER_REHIT_GRACE_TICKS
		rotation += stationary_spin_speed * dt
		queue_redraw()
		return result

	var owner = _find_player(players, shooter)
	if flight_state == FlightState.OUTBOUND:
		vel.x *= maxf(0.0, 1.0 - outbound_drag * dt)
		vel.y += outbound_gravity * dt
	elif owner != null and owner.alive:
		var home: Vector2 = owner.position
		var desired := position.direction_to(home) * return_speed
		vel = vel.move_toward(desired, return_acceleration * dt)
		vel.y += outbound_gravity * return_gravity_scale * dt

	var raw := position + vel * dt
	var player_contact := _first_player_contact(position, raw, players)
	var terrain_contact := _first_terrain_contact(position, raw)

	# Resolve the earliest swept contact. Catching uses the same sweep so a fast
	# return cannot tunnel through its owner between ticks.
	if not player_contact.is_empty() and (terrain_contact.is_empty() \
			or float(player_contact[0]) <= float(terrain_contact[0])):
		var player = player_contact[2]
		position = position.lerp(raw, float(player_contact[0]))
		if player.index == shooter and flight_state == FlightState.RETURNING:
			result["alive"] = false
			result["caught"] = true
			queue_redraw()
			return result
		result["hit_player"] = player.index
		_player_hit_cooldowns[player.index] = PLAYER_REHIT_GRACE_TICKS
		if destroy_on_player_hit:
			result["alive"] = false
		elif flight_state == FlightState.OUTBOUND:
			hold_position()
		queue_redraw()
		return result

	if not terrain_contact.is_empty():
		var hit_fraction: float = terrain_contact[0]
		var normal: Vector2 = terrain_contact[1]
		var platform_index: int = terrain_contact[2]
		var rect_index: int = terrain_contact[3]
		position = position.lerp(raw, hit_fraction) + normal * 1.5
		result["hit_platform"] = platform_index
		if _can_bounce(normal, cfg.platforms[platform_index]):
			vel = vel.bounce(normal) * bounce_retention
			bounce_count += 1
			prev_pos = position
			trail.clear()
			result["bounced"] = true
			queue_redraw()
			return result
		result["stuck"] = true
		hold_position(platform_index, rect_index)
		queue_redraw()
		return result

	position = cfg.wrap_point(raw)
	if not position.is_equal_approx(raw):
		prev_pos = position
		trail.clear()
	if age_ticks >= max_lifetime_ticks \
			or not cfg.world_bounds.grow(COLLISION_RADIUS * 2.0).has_point(position):
		result["alive"] = false
		return result

	trail.append(position)
	if trail.size() > 12:
		trail.remove_at(0)
	rotation += (vel.length() / 32.0) * dt * (-1.0 if vel.x < 0.0 else 1.0)
	queue_redraw()
	return result


## Manager clash hook. The caller owns swept contact detection and applies the
## returned `other_velocity` to the other projectile (usually via Arrow.deflect).
## A projectile impact always breaks the chakram. The striking projectile keeps
## its incoming velocity and continues through the clash.
func resolve_projectile_clash(other_velocity: Vector2, other_id: int = -1) -> Dictionary:
	return _clash_result(ClashKind.BROKEN, false, other_velocity)


func can_clash_with_projectile(other_id: int) -> bool:
	return true


func stable_id() -> int:
	return network_id if network_id >= 0 else get_instance_id()


func lockstep_digest_fragment() -> String:
	return "%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d" % [
		network_id, shooter, volley, age_ticks, int(flight_state),
		int(round(position.x * 10000.0)), int(round(position.y * 10000.0)),
		int(round(vel.x * 10000.0)), int(round(vel.y * 10000.0)),
		launch_turn, 1 if return_started else 0, _stuck_platform_index,
		_stuck_rect_index, bounce_count,
	]


func _can_bounce(normal: Vector2, platform: Dictionary) -> bool:
	return flight_state == FlightState.OUTBOUND \
		and int(platform.get("hp", -1)) == -1 \
		and bounce_count < bounce_limit \
		and not normal.is_zero_approx()


func _first_player_contact(from: Vector2, to: Vector2, players: Array) -> Array:
	var first: Array = []
	for player in players:
		if not player.alive or player.is_invulnerable():
			continue
		if _player_hit_cooldowns.has(player.index):
			continue
		if player.index == shooter:
			if flight_state != FlightState.RETURNING or age_ticks <= OWNER_HIT_GRACE_TICKS:
				continue
			var catch_rect := Rect2(player.position - Vector2.ONE * OWNER_CATCH_RADIUS,
				Vector2.ONE * OWNER_CATCH_RADIUS * 2.0)
			var catch_impact := ARROW_SCRIPT.segment_rect_impact(from, to, catch_rect)
			if not catch_impact.is_empty() and (first.is_empty() \
					or float(catch_impact[0]) < float(first[0])):
				first = [catch_impact[0], catch_impact[1], player]
			continue
		for body: Rect2 in cfg.body_rects(player):
			var impact := ARROW_SCRIPT.segment_rect_impact(
				from, to, body.grow(COLLISION_RADIUS))
			if not impact.is_empty() and (first.is_empty() \
					or float(impact[0]) < float(first[0])):
				first = [impact[0], impact[1], player]
	return first


func _first_terrain_contact(from: Vector2, to: Vector2) -> Array:
	var first: Array = []
	for platform_index in cfg.platforms.size():
		var platform: Dictionary = cfg.platforms[platform_index]
		var platform_rects: Array = platform["rects"]
		for rect_index in platform_rects.size():
			var platform_rect: Rect2 = platform_rects[rect_index]
			var impact := ARROW_SCRIPT.segment_rect_impact(
				from, to, platform_rect.grow(COLLISION_RADIUS))
			if not impact.is_empty() and (first.is_empty() \
					or float(impact[0]) < float(first[0])):
				first = [impact[0], impact[1], platform_index, rect_index]
	return first


func _follow_stuck_platform() -> void:
	if _stuck_platform_index < 0 or _stuck_platform_index >= cfg.platforms.size():
		return
	var rects: Array = cfg.platforms[_stuck_platform_index].get("rects", [])
	if _stuck_rect_index < 0 or _stuck_rect_index >= rects.size():
		return
	position = (rects[_stuck_rect_index] as Rect2).position + _stuck_rect_offset


func _find_player(players: Array, index: int):
	for player in players:
		if player.index == index:
			return player
	return null


func _tick_cooldowns(cooldowns: Dictionary) -> void:
	for key in cooldowns.keys():
		var remaining: int = int(cooldowns[key]) - 1
		if remaining <= 0:
			cooldowns.erase(key)
		else:
			cooldowns[key] = remaining


func _clash_result(kind: ClashKind, alive: bool, other_velocity: Vector2) -> Dictionary:
	return {
		"accepted": kind != ClashKind.REJECTED,
		"kind": kind,
		"alive": alive,
		"destroy_other": false,
		"other_velocity": other_velocity,
		"position": position,
	}


func _draw() -> void:
	# World-space trail, transformed back to local space because the node spins.
	for i in trail.size() - 1:
		var strength: float = float(i + 1) / float(maxi(1, trail.size() - 1))
		draw_line(to_local(trail[i]), to_local(trail[i + 1]),
			Color(color.r, color.g, color.b, strength * 0.28), 1.0 + strength * 2.0)

	if flight_state == FlightState.RETURNING:
		draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 24,
			Color(1.0, 0.86, 0.35, 0.62), 2.0)
		# Recall chevrons remain readable while time is stopped.
		draw_line(Vector2(-21.0, -5.0), Vector2(-14.0, 0.0), color.lightened(0.45), 2.0)
		draw_line(Vector2(-21.0, 5.0), Vector2(-14.0, 0.0), color.lightened(0.45), 2.0)
	elif flight_state == FlightState.HOLDING:
		draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 24,
			Color(color.r, color.g, color.b, 0.48), 2.0)
		for spoke in 4:
			var angle := TAU * float(spoke) / 4.0 + rotation
			draw_line(Vector2.from_angle(angle) * 16.0,
				Vector2.from_angle(angle) * 21.0, color.lightened(0.35), 1.8)

	# Flying-squirrel glider: spread membrane, head/ears, feet, and absurdly long
	# curled tail. It reads as a creature at rest and a chakram-like disc in spin.
	var outline := Color(0.055, 0.035, 0.025, 0.96)
	var fur := color.darkened(0.22)
	var membrane := Color(color.r, color.g * 0.76, color.b * 0.42, 0.96)
	var body := PackedVector2Array([
		Vector2(-14.0, -3.0), Vector2(-5.0, -10.0), Vector2(0.0, -4.0),
		Vector2(9.0, -11.0), Vector2(13.0, -4.0), Vector2(7.0, 0.0),
		Vector2(13.0, 4.0), Vector2(9.0, 11.0), Vector2(0.0, 4.0),
		Vector2(-5.0, 10.0), Vector2(-14.0, 3.0),
	])
	draw_colored_polygon(body, outline)
	var inner := PackedVector2Array([
		Vector2(-11.5, -2.4), Vector2(-4.5, -7.8), Vector2(0.0, -2.5),
		Vector2(8.5, -8.5), Vector2(10.0, -3.2), Vector2(5.0, 0.0),
		Vector2(10.0, 3.2), Vector2(8.5, 8.5), Vector2(0.0, 2.5),
		Vector2(-4.5, 7.8), Vector2(-11.5, 2.4),
	])
	draw_colored_polygon(inner, membrane)
	_draw_fur_ellipse(Vector2(-1.0, 0.0), Vector2(6.3, 3.2), fur)
	draw_circle(Vector2(-8.0, 0.0), 4.2, fur)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-10.5, -2.5), Vector2(-10.0, -7.0), Vector2(-6.6, -3.6),
	]), fur.lightened(0.15))
	draw_circle(Vector2(-9.2, -1.0), 0.9, Color(0.95, 1.0, 0.72))
	draw_circle(Vector2(-9.4, -1.0), 0.38, Color(0.05, 0.025, 0.02))
	draw_arc(Vector2(3.0, 1.0), 9.5, -0.2, 4.3, 20, outline, 3.8)
	draw_arc(Vector2(3.0, 1.0), 9.5, -0.2, 4.3, 20, color.lightened(0.12), 2.0)


func _draw_fur_ellipse(center: Vector2, radii: Vector2, fill: Color) -> void:
	var points := PackedVector2Array()
	for i in 20:
		var angle := TAU * float(i) / 20.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, fill)
