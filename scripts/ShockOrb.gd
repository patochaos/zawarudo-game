extends Node2D
class_name ShockOrb

## Slow persistent secondary fire for the Shock character. It becomes a shared
## piece of arena state: ordinary projectiles can cash it out for a small blast,
## while ShockPlasma requests the large combo. GameManager applies blast damage
## and calls Arrow.relaunch (or the equivalent) to revector nearby weapons.

const PROJECTILE_KIND := "shock_orb"
const HIT_REGULAR := "regular_projectile"
const HIT_PLASMA := "shock_plasma"
const BLAST_NONE := "none"
const BLAST_SMALL := "small"
const BLAST_COMBO := "combo"
const COLLISION_RADIUS := 12.0

var cfg
var vel := Vector2.ZERO
var shooter: int = -1
var network_id: int = -1
var age_ticks: int = 0
var arm_ticks: int = 30
var lifetime_ticks: int = 360
var gravity: float = 92.0
var drag: float = 0.32
var bounce_retention: float = 0.48
var ground_friction: float = 0.72
var rest_speed: float = 34.0
var max_fall_speed: float = 260.0
var prev_pos := Vector2.ZERO
var resting: bool = false
var support_platform: int = -1
var color := Color(0.98, 0.31, 0.92)
var trail := PackedVector2Array()


func configure_lob(direction: Vector2, speed: float = 330.0) -> void:
	vel = direction.normalized() * maxf(speed, 0.0)
	prev_pos = position
	resting = false
	support_platform = -1


func is_armed() -> bool:
	return age_ticks >= arm_ticks


func ticks_until_armed() -> int:
	return maxi(arm_ticks - age_ticks, 0)


## Advances only physical/lifetime state. It never applies damage itself.
## Returns {alive, detonate:false, expired, armed, resting, support_platform}.
func sim_step(dt: float) -> Dictionary:
	prev_pos = position
	age_ticks += 1
	if age_ticks >= lifetime_ticks:
		return _step_result(false, true)

	if resting and not _still_supported():
		resting = false
		support_platform = -1

	if resting:
		vel = Vector2.ZERO
		queue_redraw()
		return _step_result(true, false)

	vel.x *= maxf(0.0, 1.0 - drag * dt)
	vel.y = minf(vel.y + gravity * dt, max_fall_speed)
	var raw := position + vel * dt
	var first_hit: Array = []
	var first_platform := -1

	for platform_index in cfg.platforms.size():
		for platform_rect: Rect2 in _platform_rects(cfg.platforms[platform_index]):
			var impact := Arrow.segment_rect_impact(
				position, raw, platform_rect.grow(COLLISION_RADIUS))
			if not impact.is_empty() and (first_hit.is_empty() or impact[0] < first_hit[0]):
				first_hit = impact
				first_platform = platform_index

	if not first_hit.is_empty():
		var normal: Vector2 = first_hit[1]
		if normal.is_zero_approx():
			normal = -vel.normalized() if not vel.is_zero_approx() else Vector2.UP
		position = position.lerp(raw, float(first_hit[0])) + normal * 1.25
		vel = vel.bounce(normal) * bounce_retention
		if normal.y < -0.7:
			vel.x *= ground_friction
			if vel.length() <= rest_speed:
				vel = Vector2.ZERO
				resting = true
				support_platform = first_platform
	else:
		var wrapped: Vector2 = cfg.wrap_point(raw)
		if not wrapped.is_equal_approx(raw):
			trail.clear()
			prev_pos = wrapped
		position = wrapped

	if not cfg.world_bounds.grow(COLLISION_RADIUS * 2.0).has_point(position):
		return _step_result(false, true)

	trail.append(position)
	if trail.size() > 12:
		trail.remove_at(0)
	queue_redraw()
	return _step_result(true, false)


## Called by the integration layer after a swept projectile/orb contact.
## The request is intentionally declarative: the caller owns blast geometry,
## cover tests, damage/credit, VFX and revectoring live weapons.
func request_projectile_hit(hit_kind: String, trigger_shooter: int = -1) -> Dictionary:
	if not is_armed():
		return _detonation_result(false, BLAST_NONE, trigger_shooter, "unarmed")
	if hit_kind == HIT_PLASMA or hit_kind == ShockPlasma.PROJECTILE_KIND:
		return _detonation_result(true, BLAST_COMBO, trigger_shooter, "plasma_combo")
	return _detonation_result(true, BLAST_SMALL, trigger_shooter, "regular_hit")


func request_regular_hit(trigger_shooter: int = -1) -> Dictionary:
	return request_projectile_hit(HIT_REGULAR, trigger_shooter)


func request_plasma_hit(trigger_shooter: int = -1) -> Dictionary:
	return request_projectile_hit(HIT_PLASMA, trigger_shooter)


## Shared radial impulse helper for arrows, chakrams and other future weapons.
## Use the result with that weapon's relaunch/revector API; never delete it just
## because it lies inside the blast. At the exact origin, RIGHT is chosen so
## lockstep peers cannot disagree about a random direction.
static func revector_velocity(origin: Vector2, weapon_position: Vector2,
		old_velocity: Vector2, impulse: float, radius: float,
		velocity_carry: float = 0.32) -> Vector2:
	var offset := weapon_position - origin
	var distance := offset.length()
	if distance > radius or radius <= 0.0:
		return old_velocity
	var direction := offset / distance if distance > 0.000001 else Vector2.RIGHT
	var falloff := 1.0 - distance / radius
	return old_velocity * clampf(velocity_carry, 0.0, 1.0) \
		+ direction * impulse * falloff


func lockstep_digest_fragment() -> String:
	return "%d,%d,%d,%d,%d,%d,%d,%d,%d" % [
		network_id, shooter, age_ticks,
		int(round(position.x * 10000.0)), int(round(position.y * 10000.0)),
		int(round(vel.x * 10000.0)), int(round(vel.y * 10000.0)),
		1 if resting else 0, support_platform,
	]


func _step_result(alive: bool, expired: bool) -> Dictionary:
	return {
		"alive": alive,
		"detonate": false,
		"expired": expired,
		"armed": is_armed(),
		"resting": resting,
		"support_platform": support_platform,
		"projectile_kind": PROJECTILE_KIND,
	}


func _detonation_result(detonate: bool, blast: String,
		trigger_shooter: int, reason: String) -> Dictionary:
	return {
		"accepted": detonate,
		"detonate": detonate,
		"blast": blast,
		"position": position,
		"orb_owner": shooter,
		"trigger_shooter": trigger_shooter,
		"reason": reason,
		"revector_weapons": detonate,
		"consume_weapons": false,
	}


func _still_supported() -> bool:
	if support_platform < 0 or support_platform >= cfg.platforms.size():
		return false
	var foot := position + Vector2(0.0, COLLISION_RADIUS + 2.5)
	for platform_rect: Rect2 in _platform_rects(cfg.platforms[support_platform]):
		if platform_rect.grow(2.0).has_point(foot):
			return true
	return false


func _platform_rects(platform: Dictionary) -> Array:
	if platform.has("rects"):
		return platform["rects"]
	if platform.has("rect"):
		return [platform["rect"]]
	return []


func _draw() -> void:
	for i in trail.size():
		var local: Vector2 = to_local(trail[i])
		var alpha := 0.04 + 0.18 * float(i + 1) / float(maxi(trail.size(), 1))
		draw_circle(local, 2.0 + float(i) * 0.12,
			Color(color.r, color.g, color.b, alpha))

	var pulse := 1.0 + 0.08 * float(age_ticks % 10)
	var shell := color if is_armed() else color.darkened(0.42)
	draw_circle(Vector2.ZERO, COLLISION_RADIUS + 5.0 * pulse,
		Color(shell.r, shell.g, shell.b, 0.08))
	draw_arc(Vector2.ZERO, COLLISION_RADIUS + 3.0, 0.0, TAU, 24,
		Color(shell.r, shell.g, shell.b, 0.58), 2.0)
	draw_circle(Vector2.ZERO, COLLISION_RADIUS, Color(0.12, 0.025, 0.18, 0.94))
	draw_circle(Vector2(-2.0, -2.0), COLLISION_RADIUS * 0.62, shell)
	draw_circle(Vector2(-4.0, -4.0), 3.0, shell.lightened(0.75))

	if not is_armed():
		var progress := 1.0 - float(ticks_until_armed()) / float(maxi(arm_ticks, 1))
		draw_arc(Vector2.ZERO, COLLISION_RADIUS + 6.0, -PI * 0.5,
			-PI * 0.5 + TAU * progress, 24, Color(0.7, 0.95, 1.0, 0.86), 2.2)
