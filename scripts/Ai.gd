extends RefCounted
class_name Ai

## A planning opponent, playing by the same rules a human does.
##
## It knows exactly what a human knows: the world state, where every arrow is
## and where it is going, and its own plan. It does NOT read the human's plan.
## Instead it guesses: it plays out three hypotheses for what the opponent
## might do this window (hold, run left, run right) and prefers the shot that
## covers the most of them. That is the same prediction problem the game asks a
## human to solve, which is the point.
##
## It drives the ordinary piloting API, so its movement is recorded, costs
## stamina and replays exactly like a player's.
##
## The search is spread over frames. A full sweep costs tens of milliseconds in
## GDScript, which would be a visible hitch at the top of every planning phase;
## instead `step()` is given a few milliseconds per frame and finishes long
## before the AI is due to confirm.

## Candidate movements as [direction, jump, ticks, air_jump_tick]; `ticks < 0`
## means "as long as the stamina allows" and -1 skips the second jump.
const MOVES := [
	[0, false, 0, -1],
	[-1, false, 18, -1], [1, false, 18, -1],
	[-1, false, -1, -1], [1, false, -1, -1],
	[-1, true, -1, -1], [1, true, -1, -1], [0, true, -1, -1],
	[-1, true, -1, 15], [1, true, -1, 15], [0, true, -1, 15],
]

const COARSE_STEP := 10.0        # degrees
const REFINE_SPAN := 8.0
const REFINE_STEP := 2.0
const COARSE_POWERS := [0.4, 0.7, 1.0]
const REFINE_POWERS := [-0.12, -0.06, 0.0, 0.06, 0.12]
const FLIGHT_CAP := 110          # ticks of arrow flight to look ahead
const HYPOTHESES := [-1, 0, 1]   # what the opponent might do with their feet
## A knife that lands after the window is seen by the opponent during their
## next planning phase. The later it arrives (in the opponent's own time, since
## a body in stasis reacts just as slowly), the surer the dodge; what remains
## is the value of a hazard parked where they wanted to stand.
const LATE_HIT_FADE_TICKS := 12.0
const LATE_HIT_FLOOR := 0.15
## Out of reach: no full-power probe throw reaches a hypothesis before the
## window ends. Then a route that ends where such a throw exists is worth
## taking, so the CPU steps into a firing spot instead of wandering on the
## tiebreak and lobbing knives that arrive turns later.
const REACH_PROBE_ELEVATIONS := [-40.0, -15.0, 8.0, 25.0, 45.0]
const PROBE_HIT_RADIUS := 40.0        # near enough for the refined search to land
const ENGAGE_BONUS := 40.0
## A knife that comes back off HARD terrain and crosses the thrower's own
## route is a plan to get hit; nothing a near miss offers is worth that.
const SELF_HIT_SCORE := -900.0

var done: bool = false
## Per-opponent weights (see Opponents.NEUTRAL_STYLE). Neutral unless the slot
## is a named ladder opponent.
var _style: Dictionary = Opponents.NEUTRAL_STYLE

var _gm
var _idx: int
var _me: Player
var _foe: Player
var _dt: float
var _futures: Array = []
var _cands: Array = []
var _queue: Array = []           # pending [cand, fire_tick, elevation, power]
var _cursor: int = 0
var _best: Dictionary = {"score": -INF}
var _best_total: float = -INF
var _best_cand: Dictionary = {}
var _refined: bool = false

# Cached so the innermost loops never touch the manager or allocate.
var _wrapx: bool = false
var _seam: float = 0.0
var _wide: Vector2 = Vector2.ZERO


## Segment vs a body box, wrap-aware, allocation-free. This runs tens of
## thousands of times per turn, and building an array of seam copies here was
## costing more than the collision maths.
func _hits_body(a: Vector2, b: Vector2, centre: Vector2) -> bool:
	var r := Rect2(centre - Player.HALF, Player.SIZE)
	if Knife.seg_hits_rect(a, b, r):
		return true
	if not _wrapx:
		return false
	if r.position.x < _seam and Knife.seg_hits_rect(a, b, Rect2(r.position + _wide, r.size)):
		return true
	if r.end.x > _wide.x - _seam and Knife.seg_hits_rect(a, b, Rect2(r.position - _wide, r.size)):
		return true
	return false


func begin(gm, idx: int, foe_idx: int) -> void:
	_style = gm.ai_style_for(idx) if gm.has_method("ai_style_for") else Opponents.neutral_style()
	_gm = gm
	_idx = idx
	_me = gm.players[idx]
	_foe = gm.players[foe_idx]
	_dt = gm.tick_dt()
	_wrapx = gm.wrap_x
	_seam = gm.SEAM_MARGIN
	_wide = Vector2(gm.ARENA_W, 0.0)
	# The same integer budget _pilot_step enforces. Deriving it independently
	# let the two disagree by a tick whenever movement_budget was not an exact
	# multiple of the tick, and the AI would then arm its shot from a point it
	# had never evaluated.
	var budget: int = gm.movement_tick_budget()
	var move_options: Array = []
	for move in MOVES:
		if move[1] and gm.jump_impulse_for(idx) <= 0.0:
			continue
		if move[3] >= 0 and gm.air_jumps_for(idx) <= 0:
			continue
		move_options.append(move)
	if _gm.interception_mode:
		# Airborne motion coasts without a recording. Neutral input lets the CPU
		# brake in the air to hold the crossing or dodge a projectile.
		move_options.append([0, false, -1, -1])
		if _me.on_ground and not _gm.core_spawn_points.is_empty():
			var to_core: Vector2 = _gm.wrap_delta(_me.position, _gm.core_spawn_points[0])
			if to_core.y > Player.SIZE.y and absf(to_core.x) <= Player.HALF.x + _gm.core_collect_radius:
				# The core is directly below the upper crossing. A deliberate drop
				# avoids waiting on the shelf because both exits first move away.
				move_options.append([0, false, -1, -1, true])

	var threats := _threat_paths()
	_futures = _foe_futures()
	# Stasis fields and cover can put the rival beyond anything that lands this
	# window. Measured with the real flight, so a knife that would crawl through
	# a field for two turns does not count as reach.
	var out_of_reach: bool = not _gm.interception_mode \
		and not _in_reach_from(_me.position)

	# Rank movements by safety first. This part is cheap enough to do at once.
	var scored: Array = []
	for m in move_options:
		var ticks: int = budget if m[2] < 0 else mini(m[2], budget)
		var drop: bool = m.size() > 4 and m[4]
		var path := _walk(_me, m[0], m[1], ticks, m[3], drop)
		var safety: float = 0.0
		if not _me.is_invulnerable():
			safety = -600.0 * float(_style["safety_scale"]) * _danger(path, threats)
		var core_value: float = _core_value(path)
		var variety: float = 12.0 if ticks > 0 and not _gm.interception_mode else 0.0
		var engage_value: float = 0.0
		if out_of_reach and _in_reach_from(path[path.size() - 1]):
			# A fighter that cannot land anything this window prefers a
			# route that ends where the next throw can: over the pillar's line,
			# out of a stasis field, onto the ledge with a view.
			engage_value = ENGAGE_BONUS
		# Safety usually ties across candidates, and only the top few get a shot
		# search. Without a tiebreak the list order alone decides, so the jump
		# options were never even considered. The jitter also makes the AI
		# harder to read, which matters in a game about prediction.
		# INTERCEPTION gives the player a consistent intention to read. Its
		# objective and visible threats decide the route without a random nudge.
		var toss: float = 0.0 if _gm.interception_mode else _gm.rng.randf() * 10.0
		var style_value: float = _style_route_value(path, m[1])
		scored.append({"move": m, "ticks": ticks, "path": path, "drop": drop,
			"danger": -safety,
			"base": safety + core_value + variety + engage_value + toss + style_value})
	if _gm.interception_mode:
		# A promising shot must not buy a route through a visible projectile
		# when the current world already offers a safe alternative.
		var safe: Array = scored.filter(func(c): return c["danger"] <= 0.0)
		if not safe.is_empty():
			scored = safe
	scored.sort_custom(func(a, b): return a["base"] > b["base"])
	# A patient opponent keeps the knife unless a throw clears its bar. The
	# safest route is the plan it falls back to; apply() throws only when _best
	# carries an elevation.
	if float(_style["withhold_score"]) > 0.0 and not scored.is_empty():
		_best_cand = scored[0]
		_best = {"score": float(_style["withhold_score"]), "withheld_by_style": true}
		_best_total = float(scored[0]["base"]) + float(_style["withhold_score"])

	var searched: int = mini(gm.ai_moves_searched_for(idx), scored.size())
	for i in searched:
		_cands.append(scored[i])
	_build_coarse_queue()


## Returns true once the search has finished. Give it a microsecond budget.
func step(budget_usec: int) -> bool:
	if done:
		return true
	var deadline: int = Time.get_ticks_usec() + budget_usec
	while _cursor < _queue.size():
		_evaluate(_queue[_cursor])
		_cursor += 1
		if Time.get_ticks_usec() >= deadline:
			return false
	if not _refined:
		_refined = true
		_build_refine_queue()
		if _cursor < _queue.size():
			return false
	done = true
	return true


func finish() -> void:
	while not step(1_000_000):
		pass


## Locks the best result already evaluated without synchronously draining the
## rest of the queue. Used only when the shared planning clock expires.
func complete_early() -> void:
	done = true


## Replays the decision through the normal piloting API, so stamina, the ghost
## and the recording all end up exactly as if a human had done it.
func apply() -> void:
	if _best_cand.is_empty():
		return
	var dir: int = _best_cand["move"][0]
	var jump: bool = _best_cand["move"][1]
	var air_jump_tick: int = _best_cand["move"][3]
	var drop: bool = _best_cand.get("drop", false)
	var ticks: int = _best_cand["ticks"]
	var fire_at: int = _best.get("tick", -1) if _best.has("elev") else -1

	for t in ticks:
		if fire_at == t:
			_arm()
		var jump_now: bool = (t == 0 and jump) or t == air_jump_tick
		_gm._pilot_step(_idx, dir, jump_now, jump, drop and t == 0)
	if fire_at >= ticks:
		_arm()


func _arm() -> void:
	if not _best.has("elev"):
		return
	var pl: PlayerPlan = _me.plan
	var j: float = _gm.ai_aim_jitter_for(_idx)
	pl.set_aim_from_vector(Vector2(float(_best["side"]), -1.0), _gm.aim_min_angle, _gm.aim_max_angle)
	pl.set_elevation(_best["elev"] + _gm.rng.randf_range(-j, j), _gm.aim_min_angle, _gm.aim_max_angle)
	pl.power = clampf(_best["power"] + _gm.rng.randf_range(-0.02, 0.02), 0.0, 1.0)
	# The AI has no physical button, but makes the same explicit choice immediately
	# before placing its shot rather than receiving an automatic upgrade.
	if _gm.super_meter[_idx] >= 1.0:
		_gm.super_armed[_idx] = true
	_gm._release_charge(_idx)


# ------------------------------------------------------------ search queue ---

## On a wrapping arena the short way to the opponent may be out the back, so
## both facings are searched.
func _sides() -> Array:
	if _gm.wrap_x:
		return [1, -1]
	return [1 if _foe.position.x >= _me.position.x else -1]


func _build_coarse_queue() -> void:
	var top: float = float(_gm.aim_max_angle)
	for cand in _cands:
		var ticks: int = cand["ticks"]
		var fire_ticks: Array = [0] if ticks <= 0 else [0, ticks]
		for ft in fire_ticks:
			var origin: Vector2 = cand["path"][clampi(ft, 0, cand["path"].size() - 1)]
			# Downward shots only make sense from above, and the flat-ground
			# range formula does not describe them, so they skip the prefilter.
			var lo := 5.0
			if origin.y < _foe.position.y - 60.0:
				lo = maxf(float(_gm.aim_min_angle), -45.0)
			for side in _sides():
				var e := lo
				while e <= top:
					for power in COARSE_POWERS:
						if e < 5.0 or _plausible(origin, side, e, power):
							_queue.append([cand, ft, e, power, side])
					e += COARSE_STEP


func _build_refine_queue() -> void:
	if not _best.has("elev"):
		return
	var top: float = float(_gm.aim_max_angle)
	var cand: Dictionary = _best_cand
	var ft: int = _best["tick"]
	var e0: float = _best["elev"]
	var p0: float = _best["power"]
	var side: int = _best["side"]
	var e := maxf(0.0, e0 - REFINE_SPAN)
	while e <= minf(top, e0 + REFINE_SPAN):
		for dp in REFINE_POWERS:
			_queue.append([cand, ft, e, clampf(p0 + dp, 0.0, 1.0), side])
		e += REFINE_STEP


func _evaluate(item: Array) -> void:
	var cand: Dictionary = item[0]
	var ft: int = item[1]
	var elev: float = item[2]
	var power: float = item[3]
	var side: int = item[4]
	var path: PackedVector2Array = cand["path"]
	var origin: Vector2 = path[clampi(ft, 0, path.size() - 1)]

	var res := _fire(origin, side, elev, power, ft, cand)
	var total: float = cand["base"] + res["score"] + _style_shot_value(res, ft, power, side)
	if total > _best_total:
		_best_total = total
		_best = res
		_best["tick"] = ft
		_best["elev"] = elev
		_best["power"] = power
		_best["side"] = side
		_best_cand = cand


# ------------------------------------------------------------- simulation ----

## One movement candidate, played out over a whole window: driven for `ticks`,
## then coasting like the real thing.
func _walk(who: Player, dir: int, jump: bool, ticks: int,
		air_jump_tick: int = -1, drop: bool = false) -> PackedVector2Array:
	var pos: Vector2 = who.position
	var vel: Vector2 = who.vel
	var og: bool = who.on_ground
	var air_jumps: int = who.air_jumps_left
	var drop_ticks: int = who.drop_ticks if _gm.interception_mode else 0
	var drop_from_y: float = who.drop_from_y if _gm.interception_mode else 0.0
	var path := PackedVector2Array()
	path.append(pos)
	for t in _gm.exec_ticks():
		var d: int = dir if t < ticks else 0
		var jump_now: bool = t < ticks and ((t == 0 and jump) or t == air_jump_tick)
		if _gm.interception_mode:
			var drop_result := Player.apply_drop(pos.y, vel, og, drop_ticks, drop_from_y,
				drop and t == 0 and t < ticks)
			vel = drop_result[0]
			og = drop_result[1]
			drop_ticks = drop_result[2]
			drop_from_y = drop_result[3]
		var jump_result := Player.apply_jump(vel, og, air_jumps, jump_now,
			_gm.jump_impulse_for(who.index), _gm.air_jump_impulse_for(who.index),
			_gm.air_jumps_for(who.index))
		vel = jump_result[0]
		og = jump_result[1]
		air_jumps = jump_result[2]
		var st := Player.step_state(pos, vel, og, d, jump and t < ticks, _dt, _gm,
			_gm.world_tick + t, drop_ticks, drop_from_y, _gm.movement_speed_scale(who.index),
			_gm.jump_impulse_for(who.index), _gm.max_fall_speed_for(who.index), t < ticks)
		pos = st[0]
		vel = st[1]
		og = st[2]
		if og:
			air_jumps = _gm.air_jumps_for(who.index)
		path.append(pos)
	return path


## Every live arrow, played forward over the coming window.
func _threat_paths() -> Array:
	var out: Array = []
	for a in _gm.arrows:
		var pos: Vector2 = a.position
		var vel: Vector2 = a.vel
		var ricochets: int = a.ricochet_count
		var pts := PackedVector2Array()
		pts.append(pos)
		for t in _gm.exec_ticks():
			var st := Knife.step_state(pos, vel, _dt, _gm, a.clashed)
			var nxt: Vector2 = st[0]
			vel = st[1]
			# A forceful knife banks off HARD terrain and stays live, so a throw
			# into the pillar is a threat on the way back, not a dead knife.
			var contact := _first_platform_impact(pos, st[2], _gm.world_tick + t + 1)
			if not contact.is_empty():
				var normal: Vector2 = contact[1]
				if not Knife.can_ricochet_velocity(vel, normal, contact[2], _gm, ricochets):
					break
				vel = vel.bounce(normal) * _gm.knife_ricochet_retention
				ricochets += 1
				pos = pos.lerp(st[2], float(contact[0])) + normal * 2.0
				pts.append(pos)
				continue
			pos = nxt
			pts.append(pos)
		out.append(pts)
	return out


func _danger(path: PackedVector2Array, threats: Array) -> float:
	for pts in threats:
		var n: int = mini(pts.size(), path.size()) - 1
		for t in n:
			# a step that crossed a seam is a teleport, not a sweep. Testing it
			# as one segment would flag the whole width of the arena as lethal
			if pts[t].distance_squared_to(pts[t + 1]) > 40000.0:
				continue
			if _hits_body(pts[t], pts[t + 1], path[t]):
				# earlier hits are worse: less chance the world saves you
				return 1.0 + float(n - t) / float(maxi(n, 1))
	return 0.0


## The objective is worth contesting, but never outweighs the existing danger
## penalty. While telegraphed, the AI starts closing distance; once tangible,
## a route that actually touches it receives the larger collection value.
func _core_value(path: PackedVector2Array) -> float:
	var territory_value: float = _interception_position_value(path) if _gm.interception_mode else 0.0
	if (not _gm.core_active and not _gm.core_announced) or _gm.super_meter[_idx] >= 1.0:
		return territory_value
	var start_distance: float = _gm.wrap_delta(_me.position, _gm.core_position).length()
	var closest: float = start_distance
	for point in path:
		closest = minf(closest, _gm.wrap_delta(point, _gm.core_position).length())
	var progress: float = clampf((start_distance - closest) / 200.0, 0.0, 1.0)
	var approach_scale := 1.0 if _gm.core_active else 0.5
	var value: float = _gm.ai_core_approach_value * approach_scale * progress
	if _gm.core_active and _gm.path_touches_core(path):
		value += _gm.ai_core_collect_value
	return value + territory_value


## Stay near the authored crossing between cores and after collecting one.
## End position matters: passing through then drifting away is less useful
## than arriving where the next core can be contested. This only reads the
## public arena and the CPU's simulated route.
func _interception_position_value(path: PackedVector2Array) -> float:
	if path.is_empty() or _gm.core_spawn_points.is_empty():
		return 0.0
	var target: Vector2 = _gm.core_spawn_points[0]
	var start_distance: float = _gm.wrap_delta(path[0], target).length()
	var end_distance: float = _gm.wrap_delta(path[path.size() - 1], target).length()
	var progress: float = clampf((start_distance - end_distance) / 200.0, -1.0, 1.0)
	var nearby: float = clampf(1.0 - end_distance / 160.0, 0.0, 1.0)
	return 120.0 * progress + 60.0 * nearby


## Three guesses at what the opponent's feet will do this window.
func _foe_futures() -> Array:
	var out: Array = []
	var controlled_ticks: int = _gm.movement_tick_budget() if _gm.interception_mode else _gm.exec_ticks()
	for d in HYPOTHESES:
		out.append(_walk(_foe, d, false, controlled_ticks))
	return out


## Closed-form range check. A shot whose flat-ground range is nowhere near the
## distance to the opponent cannot be worth simulating, and discarding those
## before they cost anything is most of the speed-up.
func _plausible(origin: Vector2, side: int, elev: float, power: float) -> bool:
	var ang: float = elev if side > 0 else 180.0 - elev
	var direct := Vector2(cos(deg_to_rad(ang)), -sin(deg_to_rad(ang)))
	var launch_vel: Vector2 = _gm.knife_launch_velocity(direct, power)
	var launch_elev: float = atan2(-launch_vel.y, absf(launch_vel.x))
	var reach: float = launch_vel.length_squared() * sin(2.0 * launch_elev) \
		/ _gm.arrow_gravity
	var dx: float = _dist_along(origin.x, side)
	return reach > dx * 0.5 and reach < dx * 2.0 + 200.0


## How far the opponent is if you set off in `side`, going around the seam when
## the arena wraps. Firing away from them is only meaningful if it wraps.
func _dist_along(ox: float, side: int) -> float:
	var d: float = (_foe.position.x - ox) * float(side)
	if _gm.wrap_x:
		return fposmod(d, _gm.ARENA_W)
	return d if d > 0.0 else 1e9


## Flies the full knife fan and scores the distinct movement hypotheses it
## covers. The alternatives are mutually exclusive futures, so a knife may be
## checked against all of them without one hypothetical hit consuming it.
func _fire(origin: Vector2, side: int, elev: float, power: float, fire_tick: int,
		candidate: Dictionary = {}) -> Dictionary:
	var ang: float = elev if side > 0 else 180.0 - elev
	var r := deg_to_rad(ang)
	var dir := Vector2(cos(r), -sin(r))
	var launch: Vector2 = origin + Vector2(0.0, -6.0)
	var covered := [false, false, false]
	var hit_ticks := [-1, -1, -1]
	var closest := 1e9
	var self_hit := false
	var own_path: PackedVector2Array = candidate.get("path", PackedVector2Array())
	# The foe prediction ends with the window; past it the hypothesis is frozen
	# where it stopped, which is a guess about the next turn, not a fact.
	var horizon: int = _horizon()

	for launch_vel in _gm.knife_launch_velocities(dir, power):
		var knife_dir: Vector2 = launch_vel.normalized()
		var pos: Vector2 = launch + knife_dir * 22.0
		var vel: Vector2 = launch_vel
		var ricochets := 0
		for t in FLIGHT_CAP:
			var st := Knife.step_state(pos, vel, _dt, _gm)
			var nxt: Vector2 = st[0]
			vel = st[1]
			var raw: Vector2 = st[2]
			var world_t: int = fire_tick + t
			# HARD terrain returns a forceful knife exactly as the runtime does;
			# the flight goes on, so a bank can still cover a hypothesis, and a
			# throw into the wall beside the thrower is seen coming straight back.
			var contact := _first_platform_impact(pos, raw, _gm.world_tick + world_t + 1)
			if not contact.is_empty():
				var normal: Vector2 = contact[1]
				if not Knife.can_ricochet_velocity(vel, normal, contact[2], _gm, ricochets):
					break
				vel = vel.bounce(normal) * _gm.knife_ricochet_retention
				ricochets += 1
				pos = pos.lerp(raw, float(contact[0])) + normal * 2.0
				continue
			if t >= Knife.SELF_HIT_GRACE_TICKS and not own_path.is_empty() \
					and _hits_body(pos, raw, own_path[clampi(world_t, 0, own_path.size() - 1)]):
				self_hit = true
				break

			for h in _futures.size():
				var f: PackedVector2Array = _futures[h]
				var fi: int = clampi(world_t, 0, f.size() - 1)
				if not covered[h] and _hits_body(pos, raw, f[fi]):
					covered[h] = true
					hit_ticks[h] = world_t
				# A near miss only means something while the foe is where the
				# prediction says; later the knife is approaching a guess.
				if world_t <= horizon:
					closest = minf(closest, _gm.wrap_delta(nxt, f[fi]).length())
			pos = nxt
			if not _gm.world_bounds.has_point(pos):
				break

	# covering more hypotheses beats covering one; near-misses still beat nothing
	var hits := 0
	var late_hits := 0
	var hit_value := 0.0
	for h in covered.size():
		if not covered[h]:
			continue
		if hit_ticks[h] <= horizon:
			hits += 1
			hit_value += 1.0
		else:
			late_hits += 1
			var f: PackedVector2Array = _futures[h]
			hit_value += _late_hit_value(hit_ticks[h] - horizon, f[f.size() - 1])
	var score := hit_value * 1000.0 - closest * 0.05 - float(fire_tick) * 0.2
	if self_hit:
		score += SELF_HIT_SCORE
	return {"score": score, "knife_hits": hits,
		"late_hits": late_hits, "closest": closest, "hit_ticks": hit_ticks,
		"self_hit": self_hit}


## Earliest swept contact of `a -> b` with the terrain standing at `abs_tick`,
## as [fraction, outward normal, platform]; empty when the segment is clear.
## Walks the platforms directly so the material comes with the hit without
## building a collider list for every tick of every candidate knife.
func _first_platform_impact(a: Vector2, b: Vector2, abs_tick: int) -> Array:
	var first: Array = []
	for pf: Dictionary in _gm.platforms:
		if pf.has("cycle") and not _gm.platform_present_at(pf, abs_tick):
			continue
		if pf.has("motion"):
			var impact := Knife.segment_rect_impact(a, b, _gm.platform_rect_at(pf, abs_tick))
			if not impact.is_empty() and (first.is_empty() or impact[0] < first[0]):
				first = [impact[0], impact[1], pf]
			continue
		for rect: Rect2 in pf["rects"]:
			var impact := Knife.segment_rect_impact(a, b, rect)
			if not impact.is_empty() and (first.is_empty() or impact[0] < first[0]):
				first = [impact[0], impact[1], pf]
	return first


## The last tick the foe prediction covers.
func _horizon() -> int:
	if _futures.is_empty():
		return _gm.exec_ticks()
	return _futures[0].size() - 1


## Worth of a hit that lands `late_ticks` after the prediction ends, as a
## fraction of a hit inside the window. The opponent plans again with the knife
## in view, so the fraction falls with the time they get to step aside, counted
## in their own clock: inside a stasis field the body is as slow as the knife.
func _late_hit_value(late_ticks: int, foe_pos: Vector2) -> float:
	var reaction: float = float(late_ticks) * _gm.time_scale_at(foe_pos)
	return maxf(LATE_HIT_FLOOR, 1.0 - reaction / LATE_HIT_FADE_TICKS)


## Whether a full-power probe shot from `origin` reaches a foe hypothesis
## before the window ends. Flown with the knife's real integrator, so a stasis
## field, the pillar in between and the world edge all count.
func _in_reach_from(origin: Vector2) -> bool:
	var horizon: int = _horizon()
	if _futures.is_empty():
		return true
	var targets := PackedVector2Array()
	for f in _futures:
		targets.append(f[f.size() - 1])
	var probes: Array = []
	for side in _sides():
		for elev in REACH_PROBE_ELEVATIONS:
			if elev < 0.0 and origin.y >= _foe.position.y - 60.0:
				continue
			var ang: float = elev if side > 0 else 180.0 - elev
			probes.append(Vector2(cos(deg_to_rad(ang)), -sin(deg_to_rad(ang))))
	var reached := false
	for direction: Vector2 in probes:
		var vel: Vector2 = _gm.knife_launch_velocity(direction, 1.0)
		var pos: Vector2 = origin + Vector2(0.0, -6.0) + vel.normalized() * 22.0
		for t in horizon:
			var st := Knife.step_state(pos, vel, _dt, _gm)
			vel = st[1]
			var raw: Vector2 = st[2]
			if _segment_blocked(pos, raw, t):
				break
			pos = _gm.wrap_point(raw)
			for target in targets:
				if _gm.wrap_delta(pos, target).length() <= PROBE_HIT_RADIUS:
					reached = true
			if reached or not _gm.world_bounds.has_point(pos):
				break
		if reached:
			break
	return reached


func _segment_blocked(from: Vector2, to: Vector2, t: int) -> bool:
	for solid: Rect2 in _gm.solids_at(_gm.world_tick + t + 1):
		if Knife.seg_hits_rect(from, to, solid):
			return true
	return false


## What a named opponent wants from a route beyond staying alive: a distance
## to the rival, the high ground, or simply to be in the air.
func _style_route_value(path: PackedVector2Array, jumps: bool) -> float:
	var value := 0.0
	var end: Vector2 = path[path.size() - 1]
	var target: float = float(_style["range_target"])
	if target >= 0.0:
		var dist: float = _gm.wrap_delta(end, _foe.position).length()
		value -= absf(dist - target) * float(_style["range_weight"])
	var height_weight: float = float(_style["height_weight"])
	if height_weight != 0.0:
		value += clampf((_foe.position.y - end.y) / 120.0, -1.0, 1.0) * height_weight
	if jumps:
		value += float(_style["jump_bias"])
	return value


## Knife preferences layered over the shared hit score: throw timing, draw
## strength and the seam shot. A result without knife_hits is left alone.
func _style_shot_value(res: Dictionary, fire_tick: int, power: float, side: int) -> float:
	if not res.has("knife_hits"):
		return 0.0
	var value := -(float(_style["fire_tick_cost"]) - 0.2) * float(fire_tick)
	value += float(_style["power_bias"]) * (power - 0.7)
	if _gm.wrap_x and float(_style["seam_bias"]) != 0.0:
		var direct: int = 1 if _foe.position.x >= _me.position.x else -1
		if side != direct:
			value += float(_style["seam_bias"])
	return value
