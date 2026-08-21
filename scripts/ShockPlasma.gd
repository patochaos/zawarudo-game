extends Node2D
class_name ShockPlasma

## Fast, deterministic primary fire for the Shock character. GameManager owns
## spawning, orb-vs-plasma checks and damage; this node only advances the bolt
## and reports swept contacts so a fast shot cannot tunnel through a target.

const PROJECTILE_KIND := "shock_plasma"
const COLLISION_RADIUS := 4.0
## A bolt starts beside the shooter's shoulder. Ignore that same body briefly so
## the swept test cannot mistake its launch volume for an immediate self-hit.
## The grace is short enough that a wrapping bolt can still threaten its owner.
const OWNER_GRACE_TICKS := 8

var cfg
var vel := Vector2.ZERO
var shooter: int = -1
var network_id: int = -1
var age_ticks: int = 0
var max_ticks: int = 120
## Captured at fire time. The manager uses it to scale an orb combo, while the
## projectile also renders hotter and heavier at a full draw.
var charge_power: float = 0.0
var distance_travelled: float = 0.0
var max_distance: float = 1400.0
var fade_fraction: float = 0.28
var prev_pos := Vector2.ZERO
var color := Color(0.35, 0.95, 1.0)
var trail := PackedVector2Array()


func configure_launch(direction: Vector2, speed: float = 1120.0,
		power: float = 1.0, travel_range: float = 1400.0) -> void:
	charge_power = clampf(power, 0.0, 1.0)
	distance_travelled = 0.0
	max_distance = maxf(travel_range, 1.0)
	vel = direction.normalized() * maxf(speed, 0.0)
	rotation = vel.angle() if not vel.is_zero_approx() else 0.0
	prev_pos = position


## Returns:
## {alive, hit_player, hit_platform, contact_position, projectile_kind}.
## A -1 target means no contact. Orb contact is deliberately resolved by the
## integration layer, alongside the other projectile/projectile interactions.
func sim_step(dt: float, players: Array) -> Dictionary:
	prev_pos = position
	age_ticks += 1
	var result := _empty_result()
	var full_step_distance := vel.length() * dt
	var distance_left := maxf(max_distance - distance_travelled, 0.0)
	if distance_left <= 0.0001:
		result["alive"] = false
		result["range_expired"] = true
		return result
	var step_fraction := minf(1.0, distance_left / maxf(full_step_distance, 0.000001))
	var travelled_this_step := full_step_distance * step_fraction
	var raw := position + vel * dt * step_fraction
	var first_hit: Array = []
	var hit_player := -1
	var hit_platform := -1

	for player in players:
		if not player.alive or player.is_invulnerable():
			continue
		if player.index == shooter and age_ticks <= OWNER_GRACE_TICKS:
			continue
		for body: Rect2 in cfg.body_rects(player):
			var impact := Arrow.segment_rect_impact(position, raw, body.grow(COLLISION_RADIUS))
			if not impact.is_empty() and (first_hit.is_empty() or impact[0] < first_hit[0]):
				first_hit = impact
				hit_player = player.index
				hit_platform = -1

	for platform_index in cfg.platforms.size():
		for platform_rect: Rect2 in _platform_rects(cfg.platforms[platform_index]):
			var impact := Arrow.segment_rect_impact(
				position, raw, platform_rect.grow(COLLISION_RADIUS))
			if not impact.is_empty() and (first_hit.is_empty() or impact[0] < first_hit[0]):
				first_hit = impact
				hit_player = -1
				hit_platform = platform_index

	if not first_hit.is_empty():
		var impact_fraction := float(first_hit[0])
		position = position.lerp(raw, impact_fraction)
		distance_travelled += travelled_this_step * impact_fraction
		result["alive"] = false
		result["hit_player"] = hit_player
		result["hit_platform"] = hit_platform
		result["contact_position"] = position
		queue_redraw()
		return result

	var wrapped: Vector2 = cfg.wrap_point(raw)
	if not wrapped.is_equal_approx(raw):
		trail.clear()
		prev_pos = wrapped
	position = wrapped
	distance_travelled += travelled_this_step
	if distance_travelled >= max_distance - 0.0001:
		result["alive"] = false
		result["range_expired"] = true
		queue_redraw()
		return result
	if age_ticks >= max_ticks or not cfg.world_bounds.grow(COLLISION_RADIUS).has_point(position):
		result["alive"] = false
		return result

	trail.append(position)
	if trail.size() > 8:
		trail.remove_at(0)
	rotation = vel.angle() if not vel.is_zero_approx() else rotation
	queue_redraw()
	return result


func overlaps_circle(center: Vector2, radius: float) -> bool:
	return swept_circle_contact(prev_pos, position, center, radius + COLLISION_RADIUS)


static func swept_circle_contact(from: Vector2, to: Vector2,
		center: Vector2, combined_radius: float) -> bool:
	var travel := to - from
	var length_sq := travel.length_squared()
	var fraction := 0.0
	if length_sq > 0.000001:
		fraction = clampf((center - from).dot(travel) / length_sq, 0.0, 1.0)
	return from.lerp(to, fraction).distance_squared_to(center) \
		<= combined_radius * combined_radius


func fade_alpha() -> float:
	var fade_distance := maxf(max_distance * clampf(fade_fraction, 0.01, 1.0), 1.0)
	return clampf((max_distance - distance_travelled) / fade_distance, 0.0, 1.0)


func lockstep_digest_fragment() -> String:
	return "%d,%d,%d,%d,%d,%d,%d,%d,%d,%d" % [
		network_id, shooter, age_ticks,
		int(round(position.x * 10000.0)), int(round(position.y * 10000.0)),
		int(round(vel.x * 10000.0)), int(round(vel.y * 10000.0)),
		int(round(charge_power * 10000.0)),
		int(round(distance_travelled * 10000.0)),
		int(round(max_distance * 10000.0)),
	]


func _empty_result() -> Dictionary:
	return {
		"alive": true,
		"hit_player": -1,
		"hit_platform": -1,
		"contact_position": position,
		"projectile_kind": PROJECTILE_KIND,
		"range_expired": false,
	}


func _platform_rects(platform: Dictionary) -> Array:
	if platform.has("rects"):
		return platform["rects"]
	if platform.has("rect"):
		return [platform["rect"]]
	return []


func _draw() -> void:
	var inv := Transform2D(rotation, position).affine_inverse()
	var fade := fade_alpha()
	for i in trail.size() - 1:
		var alpha := (0.12 + 0.45 * float(i + 1) / float(maxi(trail.size(), 1))) * fade
		draw_line(inv * trail[i], inv * trail[i + 1],
			Color(color.r, color.g, color.b, alpha), 2.0 + float(i) * 0.28)

	var white_hot := color.lightened(0.72)
	white_hot.a *= fade
	var bolt_color := color
	bolt_color.a *= fade
	var thickness := lerpf(3.2, 6.2, charge_power)
	draw_line(Vector2(-13.0, 0.0), Vector2(9.0, 0.0),
		Color(color.r, color.g, color.b, 0.32 * fade), thickness * 2.0)
	draw_line(Vector2(-9.0, 0.0), Vector2(10.0, 0.0), bolt_color, thickness)
	draw_circle(Vector2(9.0, 0.0), thickness * 0.72, white_hot)
	draw_circle(Vector2(-5.0, 0.0), 2.0, white_hot)
