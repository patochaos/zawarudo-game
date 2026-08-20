extends Node2D
class_name Arrow

## Persistent projectile — a thrown knife. Never destroyed at a phase boundary,
## only when it hits terrain, hits a player, or leaves the world bounds.
##
## A knife that has been struck by another knife mid-air (see
## GameManager._resolve_clashes) is marked `clashed`: it keeps flying and stays
## lethal, but it tumbles instead of pointing along its velocity, which is the
## read that it is no longer going where anyone aimed it.

const SELF_HIT_GRACE_TICKS := 8

var cfg
var vel: Vector2 = Vector2.ZERO
var shooter: int = -1
## Stable across lockstep clients. Instance IDs are process-local and therefore
## must never influence online simulation.
var network_id: int = -1
## Which throw this knife belongs to. Knives from the same fan leave the same
## point on the same tick, so they must never clash with each other.
var volley: int = -1
var color: Color = Color.WHITE
var age_ticks: int = 0
## Position at the start of the current tick. Clash resolution needs the swept
## segment, not just the endpoint — two knives closing head-on cover up to 24px
## in one tick and would tunnel through a point test.
var prev_pos: Vector2 = Vector2.ZERO
## Struck by another knife: tumbling, slowed, no longer on its aimed line.
var clashed: bool = false
var spin: float = 0.0          # rad/sec, only while tumbling
## Every later strike raises this count. GameManager uses it to retain more
## energy and introduce a deterministic glancing angle on re-clashes.
var clash_count: int = 0
## A boost is a trailing knife transferring momentum; ricochets are limited so
## a fast knife cannot pinball forever.
var boost_count: int = 0
var ricochet_count: int = 0
## Ticks before this knife may clash again, so a pair does not stick together
## and grind through the impulse every tick.
var clash_cooldown: int = 0
## Cooldown is tracked PER OTHER KNIFE. A fresh third knife may strike
## immediately; only the pair that just separated is temporarily suppressed.
var _clash_cooldowns: Dictionary = {}
## Recent world positions, newest last — drawn as a fading streak so a fast
## knife reads as motion during execution instead of a teleporting dash.
var trail: PackedVector2Array = PackedVector2Array()


## Advances one tick. Returns a dictionary describing what happened:
##   {"alive": bool, "hit_player": int, "hit_platform": int}   -1 when nothing.
func sim_step(dt: float, players: Array) -> Dictionary:
	var from := position
	prev_pos = from
	_tick_clash_cooldowns()
	var st := Arrow.step_state(from, vel, dt, cfg, clashed)
	var to: Vector2 = st[0]
	vel = st[1]
	var raw: Vector2 = st[2]
	age_ticks += 1

	var result := {"alive": true, "hit_player": -1, "hit_platform": -1,
		"ricochet": false, "ricochet_position": Vector2.ZERO}

	for p in players:
		if not p.alive or p.is_invulnerable():
			continue
		if p.index == shooter and age_ticks <= SELF_HIT_GRACE_TICKS:
			continue
		for pr in cfg.body_rects(p):
			if seg_hits_rect(from, raw, pr):
				position = to
				_face(dt)
				result["alive"] = false
				result["hit_player"] = p.index
				return result

	var first_hit: Array = []
	var first_platform := -1
	for idx in cfg.platforms.size():
		for r in cfg.platforms[idx]["rects"]:
			var impact := segment_rect_impact(from, raw, r)
			if not impact.is_empty() and (first_hit.is_empty() or impact[0] < first_hit[0]):
				first_hit = impact
				first_platform = idx
	if not first_hit.is_empty():
		var normal: Vector2 = first_hit[1]
		var impact_at: Vector2 = from.lerp(raw, first_hit[0])
		if _can_ricochet(normal):
			vel = vel.bounce(normal) * cfg.knife_ricochet_retention
			ricochet_count += 1
			position = impact_at + normal * 2.0
			prev_pos = position
			trail.clear()
			rotation = vel.angle()
			result["ricochet"] = true
			result["ricochet_position"] = position
			queue_redraw()
			return result
		result["alive"] = false
		result["hit_platform"] = first_platform
		return result

	# On a wrapping axis there is no edge to leave through, so a knife could
	# orbit forever; age it out instead.
	if age_ticks > cfg.arrow_max_ticks or not cfg.world_bounds.has_point(to):
		result["alive"] = false
		return result

	if not to.is_equal_approx(raw):
		trail.clear()          # do not streak the trail across the seam
		prev_pos = to          # nor test a clash across it
	position = to
	_face(dt)
	trail.append(to)
	if trail.size() > 10:
		trail.remove_at(0)
	queue_redraw()
	return result


## A thrown knife points where it is going; a deflected one tumbles.
func _face(dt: float) -> void:
	if clashed:
		rotation += spin * dt
	else:
		rotation = vel.angle()


## Applies a mid-air deflection. Called by GameManager once per clashing pair.
func deflect(new_vel: Vector2, new_spin: float, cooldown: int, other_id: int = -1) -> void:
	vel = new_vel
	clash_count += 1
	if clashed:
		# Do not erase the history of a tumbling knife. Successive blows add
		# angular momentum in its current tumble direction, capped so the
		# silhouette remains readable. A later contact changes the flight path,
		# not the already-established visual direction of rotation.
		var spin_sign: float = signf(spin) if absf(spin) > 0.01 else signf(new_spin)
		spin = spin_sign * minf(28.0, absf(spin) * 0.82 + absf(new_spin) * 0.90)
	else:
		spin = new_spin
	clashed = true
	clash_cooldown = cooldown
	if other_id >= 0:
		_clash_cooldowns[other_id] = cooldown
	trail.clear()


## A clean rear impact restores an aimed flight instead of turning the leading
## knife into heavy debris. Direction comes from the transferred momentum.
func boost(new_vel: Vector2, cooldown: int, other_id: int = -1) -> void:
	vel = new_vel
	boost_count += 1
	clashed = false
	spin = 0.0
	clash_cooldown = cooldown
	if other_id >= 0:
		_clash_cooldowns[other_id] = cooldown
	trail.clear()
	rotation = vel.angle()
	queue_redraw()


func _can_ricochet(normal: Vector2) -> bool:
	if not cfg.prototype_mode or ricochet_count >= cfg.knife_ricochet_limit:
		return false
	if normal.is_zero_approx():
		return false
	var speed: float = vel.length()
	if speed < cfg.knife_ricochet_min_speed or speed <= 0.001:
		return false
	# Only a grazing impact skips. A square hit still embeds or damages cover.
	return absf(vel.normalized().dot(normal.normalized())) \
		<= cfg.knife_ricochet_max_normal_ratio


func can_clash_with(other: Arrow) -> bool:
	return not _clash_cooldowns.has(other.stable_id())


func stable_id() -> int:
	# Tests and editor tools may construct a knife outside GameManager. Runtime
	# knives always receive a lockstep ID before their first simulation tick.
	return network_id if network_id >= 0 else get_instance_id()


func _tick_clash_cooldowns() -> void:
	var longest := 0
	for other_id in _clash_cooldowns.keys():
		var left: int = _clash_cooldowns[other_id] - 1
		if left <= 0:
			_clash_cooldowns.erase(other_id)
		else:
			_clash_cooldowns[other_id] = left
			longest = maxi(longest, left)
	clash_cooldown = longest


func lockstep_digest_fragment() -> String:
	var cooldown_ids: Array = _clash_cooldowns.keys()
	cooldown_ids.sort()
	var cooldown_parts := PackedStringArray()
	for other_id in cooldown_ids:
		cooldown_parts.append("%d:%d" % [int(other_id), int(_clash_cooldowns[other_id])])
	return "%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%s" % [
		network_id, shooter, volley, age_ticks,
		int(round(position.x * 10000.0)), int(round(position.y * 10000.0)),
		int(round(vel.x * 10000.0)), int(round(vel.y * 10000.0)),
		1 if clashed else 0, int(round(spin * 10000.0)), clash_count,
		boost_count, ricochet_count,
		clash_cooldown, ";".join(cooldown_parts),
	]


## Returns [wrapped_pos, vel, raw_pos]. Shared with PredictionSystem so previews
## match reality.
##
## Collision must be tested against `pos -> raw_pos`, the UNWRAPPED segment: the
## solid set carries seam copies of anything near an edge, so the overhanging
## segment meets the same geometry it would on the far side. Only after that is
## the position folded back into the arena.
##
## DRAG is applied to the FORWARD component only, and that asymmetry is the whole
## design. Gravity keeps pulling at full strength while the throw runs out of
## steam, so the arc does not merely widen — it collapses: the knife stops
## advancing and drops. Bleeding the vertical component too would cap the fall
## speed and produce the opposite read, a knife parachuting gently down.
##
## A knife that has been struck falls under heavier gravity. Nobody aimed it any
## more, so it should behave like debris and leave the board, rather than drift
## for the fifteen seconds its age cap allows.
static func step_state(pos: Vector2, vel: Vector2, dt: float, cfg, clashed: bool = false) -> Array:
	var drag: float = cfg.arrow_drag
	if drag > 0.0:
		vel.x *= maxf(0.0, 1.0 - drag * dt)
	var gravity: float = cfg.arrow_gravity
	if clashed:
		gravity *= cfg.arrow_clashed_gravity_scale
	vel.y += gravity * dt
	var raw: Vector2 = pos + vel * dt
	return [cfg.wrap_point(raw), vel, raw]


## Slab-method segment vs AABB test.
static func seg_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	return not segment_rect_impact(a, b, r).is_empty()


## First swept contact with an AABB as [tick_fraction, outward_normal]. Keeping
## the normal makes the same collision useful for deterministic ricochets.
static func segment_rect_impact(a: Vector2, b: Vector2, r: Rect2) -> Array:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	var enter_normal := Vector2.ZERO
	for axis in 2:
		var dd: float = d[axis]
		var lo: float = r.position[axis]
		var hi: float = r.end[axis]
		if absf(dd) < 0.000001:
			if a[axis] < lo or a[axis] > hi:
				return []
		else:
			var ta: float = (lo - a[axis]) / dd
			var tb: float = (hi - a[axis]) / dd
			var near_normal := Vector2.ZERO
			near_normal[axis] = -1.0 if dd > 0.0 else 1.0
			if ta > tb:
				var tmp := ta
				ta = tb
				tb = tmp
			if ta > t0:
				t0 = ta
				enter_normal = near_normal
			t1 = minf(t1, tb)
			if t0 > t1:
				return []
	return [t0, enter_normal]


## Closest distance between two swept segments, and where on each it happens.
## Returns [distance, point_on_a, point_on_b]. Used for knife-vs-knife, which
## must not tunnel: a head-on pair closes ~24px in a single tick.
static func seg_seg_closest(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> Array:
	var da := a1 - a0
	var db := b1 - b0
	var r := a0 - b0
	var aa := da.dot(da)
	var bb := db.dot(db)
	var f := db.dot(r)
	var s := 0.0
	var t := 0.0

	if aa <= 0.000001 and bb <= 0.000001:
		return [r.length(), a0, b0]
	if aa <= 0.000001:
		t = clampf(f / bb, 0.0, 1.0)
	else:
		var c := da.dot(r)
		if bb <= 0.000001:
			s = clampf(-c / aa, 0.0, 1.0)
		else:
			var e := da.dot(db)
			var den := aa * bb - e * e
			s = clampf((e * f - c * bb) / den, 0.0, 1.0) if den > 0.000001 else 0.0
			t = (e * s + f) / bb
			if t < 0.0:
				t = 0.0
				s = clampf(-c / aa, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((e - c) / aa, 0.0, 1.0)

	var pa: Vector2 = a0 + da * s
	var pb: Vector2 = b0 + db * t
	return [(pa - pb).length(), pa, pb]


## Closest approach of two points moving over the SAME tick. Unlike a generic
## segment/segment test, this cannot report a false clash when two knives cross
## the same piece of space at different moments. Returns [distance, point_a,
## point_b, tick_fraction].
static func moving_points_closest(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> Array:
	var rel_start := a0 - b0
	var rel_step := (a1 - a0) - (b1 - b0)
	var den: float = rel_step.length_squared()
	var t := 0.0
	if den > 0.000001:
		t = clampf(-rel_start.dot(rel_step) / den, 0.0, 1.0)
	var pa: Vector2 = a0.lerp(a1, t)
	var pb: Vector2 = b0.lerp(b1, t)
	return [pa.distance_to(pb), pa, pb, t]


## Equal-mass collision response along the contact normal. Restitution creates
## the bounce; damping deliberately bleeds most of the speed so the same gravity
## turns the deflected knives into slow, readable falling hazards.
static func clash_velocities(va: Vector2, vb: Vector2, normal: Vector2,
		restitution: float, damping: float) -> Array:
	var n := normal.normalized()
	if n.is_zero_approx():
		var relative := va - vb
		n = -relative.normalized() if not relative.is_zero_approx() else Vector2.UP
	var closing: float = (va - vb).dot(n)
	var impulse := 0.0
	if closing < 0.0:
		impulse = -(1.0 + clampf(restitution, 0.0, 1.0)) * closing * 0.5
	var keep: float = clampf(damping, 0.0, 1.0)
	return [(va + n * impulse) * keep, (vb - n * impulse) * keep]


func _draw() -> void:
	# Trail is in world space, so undo this node's transform to place it.
	var inv := Transform2D(rotation, position).affine_inverse()
	for i in trail.size() - 1:
		var t: float = float(i) / float(maxi(trail.size() - 1, 1))
		draw_line(inv * trail[i], inv * trail[i + 1],
			Color(color.r, color.g, color.b, 0.32 * t), 1.0 + 2.5 * t)

	# Drawn in local space along +X; node rotation points it along velocity
	# (or tumbles it, once deflected).
	var edge: Color = color.lightened(0.55)
	# A frozen, already-existing knife gets a solid halo and a velocity chevron.
	# Planned shots remain thin translucent paths, so danger versus intention is
	# legible without another HUD sentence.
	if cfg != null and cfg.state in [Phase.PLANNING, Phase.COMMITTING]:
		var local_velocity := vel.rotated(-rotation).normalized()
		if not local_velocity.is_zero_approx():
			var marker_end := local_velocity * 28.0
			draw_line(local_velocity * 16.0, marker_end,
				Color(1.0, 0.96, 0.76, 0.82), 2.0)
			var wing := local_velocity.orthogonal() * 4.0
			draw_line(marker_end, marker_end - local_velocity * 7.0 + wing,
				Color(1.0, 0.96, 0.76, 0.82), 2.0)
			draw_line(marker_end, marker_end - local_velocity * 7.0 - wing,
				Color(1.0, 0.96, 0.76, 0.82), 2.0)
		draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 18,
			Color(edge.r, edge.g, edge.b, 0.55), 1.5)
	if boost_count > 0 or (cfg != null and vel.length() > cfg.arrow_speed_max):
		draw_line(Vector2(-22.0, 0.0), Vector2(-5.0, 0.0),
			Color(1.0, 0.72, 0.18, 0.78), 4.0, true)
		draw_arc(Vector2.ZERO, 9.0, 0.0, TAU, 16, Color(1.0, 0.88, 0.42, 0.62), 1.5)
	# blade
	draw_colored_polygon(PackedVector2Array([
		Vector2(15.0, 0.0), Vector2(1.0, -3.6), Vector2(-3.0, -2.6),
		Vector2(-3.0, 2.6), Vector2(1.0, 3.6),
	]), edge)
	draw_line(Vector2(-3.0, 0.0), Vector2(15.0, 0.0), color.darkened(0.35), 1.0)
	# guard and grip
	draw_line(Vector2(-3.5, -6.0), Vector2(-3.5, 6.0), color, 2.5)
	draw_line(Vector2(-4.0, 0.0), Vector2(-13.0, 0.0), color.darkened(0.25), 3.0)
	draw_circle(Vector2(-13.5, 0.0), 2.2, color)

	# A deflected knife carries one ring per impact (up to three). Re-hit knives
	# shift toward hot gold, so the most chaotic hazards are also the easiest to
	# identify while time is suspended.
	if clashed:
		var heat: float = clampf(float(clash_count - 1) / 2.0, 0.0, 1.0)
		var glint: Color = Color(1.0, 1.0, 1.0, 0.30).lerp(Color(1.0, 0.48, 0.12, 0.62), heat)
		for ring in mini(clash_count, 3):
			draw_arc(Vector2.ZERO, 11.0 + float(ring) * 4.0, 0.0, TAU, 16,
				Color(glint.r, glint.g, glint.b, glint.a / float(ring + 1)), 1.0)
