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
	var st := Arrow.step_state(from, vel, dt, cfg)
	var to: Vector2 = st[0]
	vel = st[1]
	var raw: Vector2 = st[2]
	age_ticks += 1

	var result := {"alive": true, "hit_player": -1, "hit_platform": -1}

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

	for idx in cfg.platforms.size():
		for r in cfg.platforms[idx]["rects"]:
			if seg_hits_rect(from, raw, r):
				result["alive"] = false
				result["hit_platform"] = idx
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
	return "%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%s" % [
		network_id, shooter, volley, age_ticks,
		int(round(position.x * 10000.0)), int(round(position.y * 10000.0)),
		int(round(vel.x * 10000.0)), int(round(vel.y * 10000.0)),
		1 if clashed else 0, int(round(spin * 10000.0)), clash_count,
		clash_cooldown, ";".join(cooldown_parts),
	]


## Returns [wrapped_pos, vel, raw_pos]. Shared with PredictionSystem so previews
## match reality.
##
## Collision must be tested against `pos -> raw_pos`, the UNWRAPPED segment: the
## solid set carries seam copies of anything near an edge, so the overhanging
## segment meets the same geometry it would on the far side. Only after that is
## the position folded back into the arena.
static func step_state(pos: Vector2, vel: Vector2, dt: float, cfg) -> Array:
	vel.y += cfg.arrow_gravity * dt
	var raw: Vector2 = pos + vel * dt
	return [cfg.wrap_point(raw), vel, raw]


## Slab-method segment vs AABB test.
static func seg_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for axis in 2:
		var dd: float = d[axis]
		var lo: float = r.position[axis]
		var hi: float = r.end[axis]
		if absf(dd) < 0.000001:
			if a[axis] < lo or a[axis] > hi:
				return false
		else:
			var ta: float = (lo - a[axis]) / dd
			var tb: float = (hi - a[axis]) / dd
			if ta > tb:
				var tmp := ta
				ta = tb
				tb = tmp
			t0 = maxf(t0, ta)
			t1 = minf(t1, tb)
			if t0 > t1:
				return false
	return true


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
