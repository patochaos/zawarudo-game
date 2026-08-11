extends RefCounted
class_name Ai

## A planning opponent, playing by the same rules a human does.
##
## It knows exactly what a human knows: the world state, where every arrow is
## and where it is going, and its own plan. It does NOT read the human's plan.
## Instead it guesses — it plays out three hypotheses for what the opponent
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
const MOVES_SEARCHED := 2        # movement candidates that get a shot search
const FLIGHT_CAP := 110          # ticks of arrow flight to look ahead
const HYPOTHESES := [-1, 0, 1]   # what the opponent might do with their feet

var done: bool = false

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
## thousands of times per turn — building an array of seam copies here was
## costing more than the collision maths.
func _hits_body(a: Vector2, b: Vector2, centre: Vector2) -> bool:
	var r := Rect2(centre - Player.HALF, Player.SIZE)
	if Arrow.seg_hits_rect(a, b, r):
		return true
	if not _wrapx:
		return false
	if r.position.x < _seam and Arrow.seg_hits_rect(a, b, Rect2(r.position + _wide, r.size)):
		return true
	if r.end.x > _wide.x - _seam and Arrow.seg_hits_rect(a, b, Rect2(r.position - _wide, r.size)):
		return true
	return false


func begin(gm, idx: int, foe_idx: int) -> void:
	_gm = gm
	_idx = idx
	_me = gm.players[idx]
	_foe = gm.players[foe_idx]
	_dt = gm.tick_dt()
	_wrapx = gm.wrap_x
	_seam = gm.SEAM_MARGIN
	_wide = Vector2(gm.ARENA_W, 0.0)
	var budget: int = mini(int(round(gm.movement_budget / _dt)), gm.exec_ticks())

	var threats := _threat_paths()
	_futures = _foe_futures()

	# Rank movements by safety first — this part is cheap enough to do at once.
	var scored: Array = []
	for m in MOVES:
		var ticks: int = budget if m[2] < 0 else mini(m[2], budget)
		var path := _walk(_me, m[0], m[1], ticks, m[3])
		var safety: float = 0.0
		if not _me.is_invulnerable():
			safety = -600.0 * _danger(path, threats)
		var core_value: float = _core_value(path)
		var variety: float = 12.0 if ticks > 0 else 0.0
		# Safety usually ties across candidates, and only the top few get a shot
		# search — without a tiebreak the list order alone decides, so the jump
		# options were never even considered. The jitter also makes the AI
		# harder to read, which matters in a game about prediction.
		var toss: float = _gm.rng.randf() * 10.0
		scored.append({"move": m, "ticks": ticks, "path": path,
			"base": safety + core_value + variety + toss})
	scored.sort_custom(func(a, b): return a["base"] > b["base"])

	for i in mini(MOVES_SEARCHED, scored.size()):
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
	var ticks: int = _best_cand["ticks"]
	var fire_at: int = _best.get("tick", -1) if _best.has("elev") else -1

	for t in ticks:
		if fire_at == t:
			_arm()
		var jump_now: bool = (t == 0 and jump) or t == air_jump_tick
		_gm._pilot_step(_idx, dir, jump_now, jump)
	if fire_at >= ticks:
		_arm()


func _arm() -> void:
	if not _best.has("elev"):
		return
	var pl: PlayerPlan = _me.plan
	var j: float = _gm.ai_aim_jitter
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

	var res := _fire(origin, side, elev, power, ft)
	var total: float = cand["base"] + res["score"]
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
		air_jump_tick: int = -1) -> PackedVector2Array:
	var pos: Vector2 = who.position
	var vel: Vector2 = who.vel
	var og: bool = who.on_ground
	var air_jumps: int = who.air_jumps_left
	var path := PackedVector2Array()
	path.append(pos)
	for t in _gm.exec_ticks():
		var d: int = dir if t < ticks else 0
		var jump_now: bool = t < ticks and ((t == 0 and jump) or t == air_jump_tick)
		var jump_result := Player.apply_jump(vel, og, air_jumps, jump_now, _gm.jump_impulse)
		vel = jump_result[0]
		og = jump_result[1]
		air_jumps = jump_result[2]
		# The search never drops through a ledge: it is a deliberate human verb,
		# and adding it would multiply the candidate space for a move the AI has
		# no way to value yet.
		var st := Player.step_state(pos, vel, og, d, jump and t < ticks, _dt, _gm,
			_gm.world_tick + t, 0, 0.0)
		pos = st[0]
		vel = st[1]
		og = st[2]
		if og:
			air_jumps = Player.MAX_AIR_JUMPS
		path.append(pos)
	return path


## Every live arrow, played forward over the coming window.
func _threat_paths() -> Array:
	var out: Array = []
	for a in _gm.arrows:
		var pos: Vector2 = a.position
		var vel: Vector2 = a.vel
		var pts := PackedVector2Array()
		pts.append(pos)
		for t in _gm.exec_ticks():
			var st := Arrow.step_state(pos, vel, _dt, _gm, a.clashed)
			var nxt: Vector2 = st[0]
			vel = st[1]
			var blocked := false
			for r in _gm.solids_at(_gm.world_tick + t + 1):
				if Arrow.seg_hits_rect(pos, st[2], r):
					blocked = true
					break
			if blocked:
				break
			pos = nxt
			pts.append(pos)
		out.append(pts)
	return out


func _danger(path: PackedVector2Array, threats: Array) -> float:
	for pts in threats:
		var n: int = mini(pts.size(), path.size()) - 1
		for t in n:
			# a step that crossed a seam is a teleport, not a sweep — testing it
			# as one segment would flag the whole width of the arena as lethal
			if pts[t].distance_squared_to(pts[t + 1]) > 40000.0:
				continue
			if _hits_body(pts[t], pts[t + 1], path[t]):
				# earlier hits are worse — less chance the world saves you
				return 1.0 + float(n - t) / float(maxi(n, 1))
	return 0.0


## The objective is worth contesting, but never outweighs the existing danger
## penalty. While telegraphed, the AI starts closing distance; once tangible,
## a route that actually touches it receives the larger collection value.
func _core_value(path: PackedVector2Array) -> float:
	if (not _gm.core_active and not _gm.core_announced) or _gm.super_meter[_idx] >= 1.0:
		return 0.0
	var start_distance: float = _gm.wrap_delta(_me.position, _gm.core_position).length()
	var closest: float = start_distance
	for point in path:
		closest = minf(closest, _gm.wrap_delta(point, _gm.core_position).length())
	var progress: float = clampf((start_distance - closest) / 200.0, 0.0, 1.0)
	var approach_scale := 1.0 if _gm.core_active else 0.5
	var value: float = _gm.ai_core_approach_value * approach_scale * progress
	if _gm.core_active and _gm.path_touches_core(path):
		value += _gm.ai_core_collect_value
	return value


## Three guesses at what the opponent's feet will do this window.
func _foe_futures() -> Array:
	var out: Array = []
	for d in HYPOTHESES:
		out.append(_walk(_foe, d, false, _gm.exec_ticks()))
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
func _fire(origin: Vector2, side: int, elev: float, power: float, fire_tick: int) -> Dictionary:
	var ang: float = elev if side > 0 else 180.0 - elev
	var r := deg_to_rad(ang)
	var dir := Vector2(cos(r), -sin(r))
	var launch: Vector2 = origin + Vector2(0.0, -6.0)
	var covered := [false, false, false]
	var closest := 1e9

	for launch_vel in _gm.knife_launch_velocities(dir, power):
		var knife_dir: Vector2 = launch_vel.normalized()
		var pos: Vector2 = launch + knife_dir * 22.0
		var vel: Vector2 = launch_vel
		for t in FLIGHT_CAP:
			var st := Arrow.step_state(pos, vel, _dt, _gm)
			var nxt: Vector2 = st[0]
			vel = st[1]
			var raw: Vector2 = st[2]
			var blocked := false
			for r2 in _gm.solids_at(_gm.world_tick + fire_tick + t + 1):
				if Arrow.seg_hits_rect(pos, raw, r2):
					blocked = true
					break
			if blocked:
				break

			var world_t: int = fire_tick + t
			for h in _futures.size():
				var f: PackedVector2Array = _futures[h]
				var fi: int = clampi(world_t, 0, f.size() - 1)
				if not covered[h] and _hits_body(pos, raw, f[fi]):
					covered[h] = true
				closest = minf(closest, _gm.wrap_delta(nxt, f[fi]).length())
			pos = nxt
			if not _gm.world_bounds.has_point(pos):
				break

	# covering more hypotheses beats covering one; near-misses still beat nothing
	var hits := 0
	for did_hit in covered:
		if did_hit:
			hits += 1
	return {"score": float(hits) * 1000.0 - closest * 0.05 - float(fire_tick) * 0.2}
