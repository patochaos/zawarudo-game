extends Node2D
class_name Dashblade

## Deterministic, integration-agnostic Dashblade action.
##
## GameManager owns the real fighter and calls `begin()` once, then `sim_step()`
## once per simulation tick. This node deliberately does not grant invulnerability:
## its narrow front guard physically deflects Arrow instances, while projectiles
## that reach the body are reported back to the caller.

const DEFAULT_BODY_HALF := Vector2(16.0, 24.0)
const DEFAULT_GUARD_OFFSET := 18.0
const DEFAULT_GUARD_DEPTH := 14.0
const DEFAULT_GUARD_HALF_LENGTH := 27.0
const DEFAULT_DEFLECT_RETENTION := 0.72
const DEFAULT_DEFLECT_SPIN := 16.0
const DEFAULT_DEFLECT_COOLDOWN := 4
const DEFAULT_WALL_SHIMMY_SPEED := 240.0
const DEFAULT_WALL_SHIMMY_TICKS := 6
## A cut ends near ordinary running speed instead of donating its full attack
## velocity to the next turn. The burst still crosses its authored route; only
## the momentum inherited after the final frame is damped.
const DEFAULT_EXIT_MOMENTUM_RETENTION := 0.28
const MAX_FIGHTER_HITS := 1

var owner_index: int = -1
var direction := Vector2.RIGHT
var velocity := Vector2.ZERO
var previous_position := Vector2.ZERO
var ticks_left: int = 0
var active: bool = false
var guard_durability: int = 0
## Number of stored Lost Frame cells committed to this dash. The dash parameters
## already contain their mechanical benefit; retaining the count here lets the
## fighter renderer show the same collapsing panels during live execution.
var frame_debt_spent: int = 0
var body_half := DEFAULT_BODY_HALF
var guard_offset: float = DEFAULT_GUARD_OFFSET
var guard_depth: float = DEFAULT_GUARD_DEPTH
var guard_half_length: float = DEFAULT_GUARD_HALF_LENGTH
var deflect_retention: float = DEFAULT_DEFLECT_RETENTION
var deflect_spin: float = DEFAULT_DEFLECT_SPIN
var deflect_cooldown: int = DEFAULT_DEFLECT_COOLDOWN
var wall_shimmy_speed: float = DEFAULT_WALL_SHIMMY_SPEED
var wall_shimmy_ticks: int = DEFAULT_WALL_SHIMMY_TICKS
var exit_momentum_retention: float = DEFAULT_EXIT_MOMENTUM_RETENTION
var shimmying: bool = false

var _hit_fighters: Dictionary = {}
var _handled_projectiles: Dictionary = {}


## Starts a planned dash. Duration is expressed in simulation ticks so the end
## does not depend on accumulated floating-point time.
func begin(origin: Vector2, planned_direction: Vector2, speed: float,
		duration_ticks: int, fighter_index: int, durability: int = 2,
		lost_frames: int = 0,
		exit_retention: float = DEFAULT_EXIT_MOMENTUM_RETENTION) -> void:
	position = origin
	previous_position = origin
	direction = planned_direction.normalized()
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	velocity = direction * maxf(0.0, speed)
	ticks_left = maxi(0, duration_ticks)
	owner_index = fighter_index
	guard_durability = maxi(0, durability)
	frame_debt_spent = maxi(0, lost_frames)
	exit_momentum_retention = clampf(exit_retention, 0.0, 1.0)
	active = ticks_left > 0 and not velocity.is_zero_approx()
	shimmying = false
	_hit_fighters.clear()
	_handled_projectiles.clear()


## Makes a combat-free copy for the planning ghost. Keeping this beside the
## authoritative dash state prevents previews from approximating a dash that is
## still in progress when the next time stop begins.
func prediction_copy() -> Dashblade:
	var copy := Dashblade.new()
	copy.position = position
	copy.previous_position = previous_position
	copy.direction = direction
	copy.velocity = velocity
	copy.ticks_left = ticks_left
	copy.active = active
	copy.guard_durability = guard_durability
	copy.frame_debt_spent = frame_debt_spent
	copy.body_half = body_half
	copy.guard_offset = guard_offset
	copy.guard_depth = guard_depth
	copy.guard_half_length = guard_half_length
	copy.deflect_retention = deflect_retention
	copy.deflect_spin = deflect_spin
	copy.deflect_cooldown = deflect_cooldown
	copy.wall_shimmy_speed = wall_shimmy_speed
	copy.wall_shimmy_ticks = wall_shimmy_ticks
	copy.exit_momentum_retention = exit_momentum_retention
	copy.shimmying = shimmying
	return copy


## Advances the dash and resolves only the interactions owned by this action.
## Arrow movement for the tick must already be represented by `prev_pos ->
## position`. Returned keys:
##
##   active, position, velocity, guard_durability
##   deflected             Array[Arrow]
##   hit_fighters          Array[int], newly struck this tick
##   owner_hit_projectiles Array[Arrow], projectiles that bypassed the guard
##   stopped_by_hard, hit_platform
##
## `platforms` accepts the project's normal {rects, hp} entries and the simpler
## {rect, hp} form used by level definitions and focused tests. Only hp == -1 is
## HARD; breakable terrain is intentionally left for the integrating system.
func sim_step(dt: float, arrows: Array = [], fighters: Array = [],
		platforms: Array = []) -> Dictionary:
	var result := {
		"active": active,
		"position": position,
		"velocity": velocity,
		"guard_durability": guard_durability,
		"deflected": [],
		"hit_fighters": [],
		"owner_hit_projectiles": [],
		"stopped_by_hard": false,
		"hit_platform": -1,
		"shimmy": shimmying,
	}
	if not active:
		previous_position = position
		return result

	var from := position
	previous_position = from
	var to := from + velocity * dt
	var terrain_hit := _first_hard_impact(from, to, platforms)
	if not terrain_hit.is_empty():
		var fraction: float = terrain_hit[0]
		var normal: Vector2 = terrain_hit[2]
		position = from.lerp(to, fraction) + normal * 0.05
		result["stopped_by_hard"] = true
		result["hit_platform"] = int(terrain_hit[1])
		# A head-on wall is not an invisible cancel. The fighter catches the edge
		# and rides upward for a few ticks, while the guard keeps facing forward.
		if not shimmying and absf(normal.x) > 0.7 and ticks_left > 1:
			shimmying = true
			ticks_left = mini(ticks_left - 1, maxi(1, wall_shimmy_ticks))
			velocity = Vector2(0.0, -absf(wall_shimmy_speed))
			active = true
			result["shimmy"] = true
		else:
			velocity = Vector2.ZERO
			ticks_left = 0
			active = false
			shimmying = false
	else:
		position = to
		ticks_left -= 1
		if ticks_left <= 0:
			ticks_left = 0
			active = false
			if shimmying:
				velocity = Vector2.ZERO
				shimmying = false
			else:
				velocity *= exit_momentum_retention

	_resolve_arrows(from, position, arrows, result)
	_resolve_fighters(from, position, fighters, result)
	result["active"] = active
	result["position"] = position
	result["velocity"] = velocity
	result["guard_durability"] = guard_durability
	return result


## Reports where an energy projectile crossed the moving front guard or body.
## GameManager uses this for plasma because plasma owns its own swept movement;
## keeping the relative-space test here guarantees it matches dagger guarding.
func swept_projectile_contact(projectile_from: Vector2, projectile_to: Vector2,
		radius: float = 0.0) -> Dictionary:
	var relative_from := _to_dash_space(projectile_from - previous_position)
	var relative_to := _to_dash_space(projectile_to - position)
	var guard_hit := Arrow.segment_rect_impact(relative_from, relative_to,
		_guard_rect().grow(maxf(0.0, radius)))
	var body_hit := Arrow.segment_rect_impact(relative_from, relative_to,
		Rect2(-body_half, body_half * 2.0).grow(maxf(0.0, radius)))
	return {
		"guard_time": float(guard_hit[0]) if not guard_hit.is_empty() else INF,
		"body_time": float(body_hit[0]) if not body_hit.is_empty() else INF,
	}


func spend_guard() -> bool:
	if guard_durability <= 0:
		return false
	guard_durability -= 1
	return true


## A compact deterministic fragment suitable for a lockstep digest. The hit
## dictionaries are history filters, so their sorted IDs are part of the state.
func lockstep_digest_fragment() -> String:
	var fighter_ids: Array = _hit_fighters.keys()
	fighter_ids.sort()
	var projectile_ids: Array = _handled_projectiles.keys()
	projectile_ids.sort()
	return "%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%s,%s" % [
		owner_index,
		int(round(position.x * 10000.0)), int(round(position.y * 10000.0)),
		int(round(velocity.x * 10000.0)), int(round(velocity.y * 10000.0)),
		ticks_left, guard_durability, frame_debt_spent,
		1 if active else 0, 1 if shimmying else 0,
		_join_ints(fighter_ids), _join_ints(projectile_ids),
	]


func _resolve_arrows(from: Vector2, to: Vector2, arrows: Array, result: Dictionary) -> void:
	var contacts: Array[Dictionary] = []
	for arrow in arrows:
		if arrow == null or not is_instance_valid(arrow):
			continue
		var projectile_id := _projectile_id(arrow)
		if _handled_projectiles.has(projectile_id):
			continue
		var arrow_from: Vector2 = arrow.prev_pos
		var arrow_to: Vector2 = arrow.position
		var relative_from := _to_dash_space(arrow_from - from)
		var relative_to := _to_dash_space(arrow_to - to)
		var guard_hit := Arrow.segment_rect_impact(relative_from, relative_to, _guard_rect())
		var body_hit := Arrow.segment_rect_impact(relative_from, relative_to,
			Rect2(-body_half, body_half * 2.0))
		if guard_hit.is_empty() and body_hit.is_empty():
			continue
		var guard_time := float(guard_hit[0]) if not guard_hit.is_empty() else INF
		var body_time := float(body_hit[0]) if not body_hit.is_empty() else INF
		contacts.append({
			"arrow": arrow,
			"id": projectile_id,
			"guard_time": guard_time,
			"body_time": body_time,
			"time": minf(guard_time, body_time),
		})

	contacts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["time"]), float(b["time"])):
			return float(a["time"]) < float(b["time"])
		return int(a["id"]) < int(b["id"])
	)

	for contact: Dictionary in contacts:
		var arrow = contact["arrow"]
		var projectile_id: int = contact["id"]
		var guard_first: bool = float(contact["guard_time"]) <= float(contact["body_time"])
		if guard_first and guard_durability > 0:
			_deflect_arrow(arrow, projectile_id)
			guard_durability -= 1
			_handled_projectiles[projectile_id] = true
			result["deflected"].append(arrow)
		elif float(contact["body_time"]) < INF:
			_handled_projectiles[projectile_id] = true
			result["owner_hit_projectiles"].append(arrow)


func _resolve_fighters(from: Vector2, to: Vector2, fighters: Array,
		result: Dictionary) -> void:
	if _hit_fighters.size() >= MAX_FIGHTER_HITS:
		return
	for fighter in fighters:
		if fighter == null or not is_instance_valid(fighter):
			continue
		var fighter_index: int = int(fighter.index)
		if fighter_index == owner_index or _hit_fighters.has(fighter_index) or not fighter.alive:
			continue
		var target_rect: Rect2 = fighter.rect()
		var target_half := target_rect.size * 0.5
		var target_center := target_rect.get_center()
		var projected_half := Vector2(
			absf(direction.x) * target_half.x + absf(direction.y) * target_half.y,
			absf(-direction.y) * target_half.x + absf(direction.x) * target_half.y)
		var relative_from := _to_dash_space(target_center - from)
		var relative_to := _to_dash_space(target_center - to)
		var expanded_guard := Rect2(_guard_rect().position - projected_half,
			_guard_rect().size + projected_half * 2.0)
		if not Arrow.segment_rect_impact(relative_from, relative_to, expanded_guard).is_empty():
			_hit_fighters[fighter_index] = true
			result["hit_fighters"].append(fighter_index)
			# The blade pierces the space and keeps moving, but one committed dash
			# cannot turn a crowded lineup into several score points.
			return


func _deflect_arrow(arrow, projectile_id: int) -> void:
	var relative_velocity: Vector2 = arrow.vel - velocity
	# The broad side of the blade is perpendicular to the dash. Reflecting the
	# projectile in the blade's moving frame preserves the collision's geometry;
	# adding the blade velocity back transfers dash momentum into the ricochet.
	var reflected := relative_velocity.bounce(direction) * clampf(deflect_retention, 0.0, 1.0)
	var new_velocity := velocity + reflected
	var side: float = signf((arrow.position - position).dot(direction.orthogonal()))
	if is_zero_approx(side):
		side = -1.0 if projectile_id % 2 == 0 else 1.0
	arrow.deflect(new_velocity, side * deflect_spin, deflect_cooldown)


func _first_hard_impact(from: Vector2, to: Vector2, platforms: Array) -> Array:
	var first: Array = []
	for platform_index in platforms.size():
		var platform: Dictionary = platforms[platform_index]
		if int(platform.get("hp", -1)) != -1:
			continue
		for rect: Rect2 in _platform_rects(platform):
			var expanded := Rect2(rect.position - body_half, rect.size + body_half * 2.0)
			var impact := Arrow.segment_rect_impact(from, to, expanded)
			# Standing on a floor means the body begins exactly on the expanded
			# boundary. Parallel or outward travel reports t=0 with no entering
			# normal; that is resting contact, not something the dash struck.
			if not impact.is_empty() and float(impact[0]) <= 0.000001 \
					and (impact[1] as Vector2).is_zero_approx():
				continue
			if not impact.is_empty() and (first.is_empty() or float(impact[0]) < float(first[0])):
				first = [float(impact[0]), platform_index, impact[1]]
	return first


func _guard_rect() -> Rect2:
	return Rect2(Vector2(guard_offset, -guard_half_length),
		Vector2(guard_depth, guard_half_length * 2.0))


func _to_dash_space(world_delta: Vector2) -> Vector2:
	return Vector2(world_delta.dot(direction), world_delta.dot(direction.orthogonal()))


static func _platform_rects(platform: Dictionary) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if platform.has("rects"):
		for rect in platform["rects"]:
			rects.append(rect as Rect2)
	elif platform.has("rect"):
		rects.append(platform["rect"] as Rect2)
	return rects


static func _projectile_id(arrow) -> int:
	return int(arrow.stable_id()) if arrow.has_method("stable_id") else int(arrow.get_instance_id())


static func _join_ints(values: Array) -> String:
	var parts := PackedStringArray()
	for value in values:
		parts.append(str(int(value)))
	return ":".join(parts)
