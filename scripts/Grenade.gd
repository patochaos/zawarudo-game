extends Node2D
class_name Grenade

## A persistent, deterministic timed projectile. Planning freezes it along with
## every other threat because GameManager is the only thing that calls sim_step.

const RADIUS := 11.0
const SHOOTER_GRACE_TICKS := 8

var cfg
var vel := Vector2.ZERO
var shooter: int = -1
var network_id: int = -1
var volley: int = -1
var color := Color.WHITE
var prev_pos := Vector2.ZERO
var fuse_ticks_left: int = 120
var fuse_ticks_total: int = 120
var age_ticks: int = 0
var bounce_count: int = 0
var blast_radius_scale: float = 1.0
var cluster_fragment: bool = false
var trail := PackedVector2Array()


func collision_radius() -> float:
	return RADIUS * (0.68 if cluster_fragment else 1.0)


## Returns whether the grenade remains in the world and whether its fuse ended.
## Terrain contacts bounce. Touching a vulnerable fighter detonates immediately.
func sim_step(dt: float, players: Array) -> Dictionary:
	prev_pos = position
	age_ticks += 1
	fuse_ticks_left -= 1
	vel.x *= maxf(0.0, 1.0 - cfg.grenade_drag * dt)
	vel.y = minf(vel.y + cfg.grenade_gravity * dt, cfg.max_fall_speed)
	var raw := position + vel * dt
	var first_hit: Array = []
	var hit_player := false
	var radius := collision_radius()

	for p in players:
		if not p.alive or p.is_invulnerable():
			continue
		if p.index == shooter and age_ticks <= SHOOTER_GRACE_TICKS:
			continue
		for body: Rect2 in cfg.body_rects(p):
			var impact := Arrow.segment_rect_impact(position, raw, body.grow(radius))
			if not impact.is_empty() and (first_hit.is_empty() or impact[0] < first_hit[0]):
				first_hit = impact
				hit_player = true

	for pf: Dictionary in cfg.platforms:
		for platform_rect: Rect2 in pf["rects"]:
			var impact := Arrow.segment_rect_impact(position, raw, platform_rect.grow(radius))
			if not impact.is_empty() and (first_hit.is_empty() or impact[0] < first_hit[0]):
				first_hit = impact
				hit_player = false

	if not first_hit.is_empty():
		var normal: Vector2 = first_hit[1]
		if normal.is_zero_approx():
			normal = -vel.normalized() if not vel.is_zero_approx() else Vector2.UP
		position = position.lerp(raw, float(first_hit[0])) + normal * 1.5
		if hit_player:
			blast_radius_scale = minf(blast_radius_scale, cfg.grenade_direct_blast_scale)
		else:
			vel = vel.bounce(normal) * cfg.grenade_bounce_retention
			if normal.y < -0.7 and absf(vel.y) < cfg.grenade_rest_speed:
				vel.y = 0.0
				vel.x *= cfg.grenade_ground_friction
			bounce_count += 1
	else:
		var wrapped: Vector2 = cfg.wrap_point(raw)
		if not wrapped.is_equal_approx(raw):
			trail.clear()
			prev_pos = wrapped
		position = wrapped

	if not cfg.world_bounds.grow(radius * 2.0).has_point(position):
		return {"alive": false, "detonate": false}

	rotation += (vel.x / radius) * dt
	trail.append(position)
	if trail.size() > 9:
		trail.remove_at(0)
	queue_redraw()
	return {"alive": true, "detonate": hit_player or fuse_ticks_left <= 0}


func lockstep_digest_fragment() -> String:
	return "%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d" % [
		network_id, shooter, volley, age_ticks, fuse_ticks_left, bounce_count,
		int(round(position.x * 10000.0)), int(round(position.y * 10000.0)),
		int(round(vel.x * 10000.0)), int(round(vel.y * 10000.0)),
		int(round(blast_radius_scale * 10000.0)), 1 if cluster_fragment else 0,
	]


func _draw() -> void:
	var radius := collision_radius()
	for i in trail.size():
		var local: Vector2 = to_local(trail[i])
		var alpha: float = 0.05 + 0.18 * float(i + 1) / float(trail.size())
		draw_circle(local, 1.4 if cluster_fragment else 2.0,
			Color(color.r, color.g, color.b, alpha))

	# Frozen grenades show both their danger radius and exact remaining fuse.
	if cfg != null and cfg.state == Phase.PLANNING:
		var blast_radius: float = cfg.grenade_blast_radius * blast_radius_scale
		draw_circle(Vector2.ZERO, blast_radius,
			Color(color.r, color.g, color.b, 0.055), false, 2.0)
		draw_arc(Vector2.ZERO, blast_radius, 0.0, TAU, 48,
			Color(color.r, color.g, color.b, 0.52), 2.0)
		var seconds := int(ceil(float(maxi(fuse_ticks_left, 0)) /
			float(Engine.physics_ticks_per_second)))
		var fuse_label := color.lightened(0.45)
		draw_string(ThemeDB.fallback_font, Vector2(-16.0, -18.0), "%ds" % seconds,
			HORIZONTAL_ALIGNMENT_CENTER, 32.0, 12, fuse_label)

	var shell_color := color.darkened(0.55)
	draw_circle(Vector2(2.5, 3.0), radius + 1.5, Color(0.025, 0.02, 0.035, 0.92))
	draw_circle(Vector2.ZERO, radius, shell_color)
	draw_arc(Vector2.ZERO, radius - 2.0, -2.7, -0.3, 12, color.lightened(0.25), 2.4)
	draw_line(Vector2(-radius + 2.0, 0.0), Vector2(radius - 2.0, 0.0),
		Color(0.04, 0.035, 0.05), 2.5)
	draw_line(Vector2(0.0, -radius + 2.0), Vector2(0.0, radius - 2.0),
		Color(0.04, 0.035, 0.05), 2.5)
	draw_line(Vector2(3.0, -radius + 1.0), Vector2(7.0, -radius - 5.0),
		color.lightened(0.28), 2.0)
	var pulse := 2.0 + float(age_ticks % 8) * 0.28
	var spark_color := color.lightened(0.55)
	spark_color.a = 0.95
	draw_circle(Vector2(8.0, -radius - 6.0), pulse, spark_color)
