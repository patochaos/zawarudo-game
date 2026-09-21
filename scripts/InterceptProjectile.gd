extends Arrow
class_name InterceptProjectile

## Offline Class Lab projectile. All clocks advance only through sim_step.
var kind: int = Roster.DASHBLADE
var direction := Vector2.RIGHT
var origin := Vector2.ZERO
var power := 0.0
var speed := 480.0
var delay_ticks := 30
var pierced := false
var broken := false
var pierced_rect := Rect2()

func setup(weapon: int, at: Vector2, aim: Vector2, charge: float) -> void:
	kind = weapon
	origin = at
	position = at
	prev_pos = at
	direction = aim.normalized()
	power = clampf(charge, 0.0, 1.0)
	speed = lerpf(400.0, 650.0, power) if kind == Roster.DASHBLADE else 480.0
	delay_ticks = roundi(lerpf(15.0, 54.0, power))
	vel = direction * (180.0 if kind == Roster.SHOCK else speed)
	rotation = direction.angle()

func sim_step(dt: float, players: Array) -> Dictionary:
	var result := {"alive": not broken, "hit_player": -1, "hit_platform": -1, "burst": false}
	if broken:
		return result
	prev_pos = position
	age_ticks += 1
	if kind == Roster.CHAKRAM:
		# Decelerate to the fixed endpoint, hold, then retrace to the launch point.
		var outbound := 36
		var hold := 9
		var distance := lerpf(180.0, 330.0, power)
		var fraction := 0.0
		if age_ticks <= outbound:
			var t := float(age_ticks) / outbound
			fraction = 2.0 * t - t * t
		elif age_ticks <= outbound + hold:
			fraction = 1.0
		else:
			fraction = maxf(0.0, 1.0 - float(age_ticks - outbound - hold) / outbound)
		position = origin + direction * distance * fraction
		vel = (position - prev_pos) / dt
		result.alive = age_ticks < outbound * 2 + hold
	else:
		position += vel * dt
		result.alive = age_ticks < (delay_ticks if kind == Roster.SHOCK else 90)
		result.burst = kind == Roster.SHOCK and age_ticks == delay_ticks
	# Resolve the nearest wall first; a body behind it cannot be hit this tick.
	var nearest := 2.0
	var wall := -1
	for idx in cfg.platforms.size():
		for rect in cfg.platforms[idx]["rects"]:
			if pierced and rect == pierced_rect and int(cfg.platforms[idx]["hp"]) == 1:
				continue
			var hit := Arrow.segment_rect_impact(prev_pos, position, rect)
			if not hit.is_empty() and float(hit[0]) < nearest:
				nearest = float(hit[0])
				wall = idx
				if kind == Roster.DASHBLADE and not pierced:
					pierced_rect = rect
	if wall >= 0:
		position = prev_pos.lerp(position, nearest)
		result.burst = false
		result.alive = false
		if kind == Roster.DASHBLADE and not pierced and int(cfg.platforms[wall]["hp"]) == 1:
			pierced = true
			vel *= 0.55
			result.hit_platform = wall
			result.alive = true
		elif kind == Roster.DASHBLADE:
			result.hit_platform = wall
	if kind != Roster.SHOCK:
		for p in players:
			if not p.alive or p.is_invulnerable() or (p.index == shooter and age_ticks <= SELF_HIT_GRACE_TICKS):
				continue
			for rect in cfg.body_rects(p):
				if Arrow.seg_hits_rect(prev_pos, position, rect):
					result.hit_player = p.index
					result.alive = false
					return result
	if not cfg.world_bounds.has_point(position):
		result.alive = false
		result.burst = false
	queue_redraw()
	return result

func copy_for_prediction():
	var copy = get_script().new()
	for field in ["cfg", "kind", "direction", "origin", "power", "speed", "delay_ticks", "pierced", "pierced_rect", "broken", "position", "prev_pos", "vel", "age_ticks", "shooter"]:
		copy.set(field, get(field))
	return copy

func prediction(ticks: int) -> PackedVector2Array:
	var copy = copy_for_prediction()
	var path := PackedVector2Array([position])
	for tick in ticks:
		var result: Dictionary = copy.sim_step(cfg.tick_dt(), [])
		path.append(copy.position)
		if not result.alive:
			break
	copy.free()
	return path

func lockstep_digest_fragment() -> String:
	return super.lockstep_digest_fragment() + ":lab:%d:%s:%s:%f:%d:%s:%s" % [kind, origin, direction, power, delay_ticks, pierced, broken]

func lab_state() -> Dictionary:
	var data := {}
	for field in ["kind", "direction", "origin", "power", "speed", "delay_ticks", "pierced", "pierced_rect", "broken"]:
		data[field] = get(field)
	return data

func _draw() -> void:
	var edge := color.lightened(0.5)
	match kind:
		Roster.DASHBLADE:
			draw_line(Vector2(-20, 0), Vector2(20, 0), edge, 3.0)
			draw_colored_polygon(PackedVector2Array([Vector2(24, 0), Vector2(11, -5), Vector2(11, 5)]), color)
		Roster.CHAKRAM:
			draw_arc(Vector2.ZERO, 9, 0, TAU, 24, edge, 3.0)
			draw_line(Vector2(-5, 0), Vector2(5, 0), color, 2.0)
		Roster.SHOCK:
			draw_circle(Vector2.ZERO, 4, color)
			draw_arc(Vector2.ZERO, 11, -PI / 2, -PI / 2 + TAU * maxf(0.0, 1.0 - float(age_ticks) / delay_ticks), 24, edge, 2.0)
