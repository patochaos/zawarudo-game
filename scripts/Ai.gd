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
const SHOCK_SETUP_ORB_TARGET := 2
const FLIGHT_CAP := 110          # ticks of arrow flight to look ahead
const HYPOTHESES := [-1, 0, 1]   # what the opponent might do with their feet
const VELOCITY_DASH_DANGER_WEIGHT := 900.0
const VELOCITY_PARRY_ALIGNMENT := 0.82
const VELOCITY_PARRY_FAILURE_SCORE := -350.0
const VELOCITY_WITHHOLD_SCORE := -220.0

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
	var move_options: Array = []
	for move in MOVES:
		if move[1] and gm.jump_impulse_for(idx) <= 0.0:
			continue
		if move[3] >= 0 and gm.air_jumps_for(idx) <= 0:
			continue
		move_options.append(move)

	var threats := _threat_paths()
	_futures = _foe_futures()

	# Rank movements by safety first — this part is cheap enough to do at once.
	var scored: Array = []
	for m in move_options:
		var ticks: int = budget if m[2] < 0 else mini(m[2], budget)
		var path := _walk(_me, m[0], m[1], ticks, m[3])
		var safety: float = 0.0
		if not _me.is_invulnerable():
			safety = -600.0 * _danger(path, threats)
			# A rival Velocity is a potential body projectile even though its plan
			# remains private. Test a small envelope of plausible release moments and
			# reward routes which leave the committed line before it arrives.
			if _gm.uses_dashblade(_foe.index):
				safety -= VELOCITY_DASH_DANGER_WEIGHT * _velocity_dash_danger(path)
		var core_value: float = _core_value(path)
		var variety: float = 12.0 if ticks > 0 else 0.0
		# A body-dash kit cannot create pressure from the opposite side of the
		# arena. Prefer safe paths that close the gap instead of letting the generic
		# projectile planner wander on a random tiebreak.
		var engage_value: float = 0.0
		if _gm.uses_dashblade(_idx):
			engage_value = -_gm.wrap_delta(path[path.size() - 1], _foe.position).length() * 0.22
		# Safety usually ties across candidates, and only the top few get a shot
		# search — without a tiebreak the list order alone decides, so the jump
		# options were never even considered. The jitter also makes the AI
		# harder to read, which matters in a game about prediction.
		var toss: float = _gm.rng.randf() * 10.0
		scored.append({"move": m, "ticks": ticks, "path": path,
			"base": safety + core_value + variety + engage_value + toss})
	scored.sort_custom(func(a, b): return a["base"] > b["base"])
	# Not attacking is a legal tactical answer. Seed the search with the safest
	# movement-only plan against Velocity; a projectile plan must beat this after
	# accounting for the chance that a frontal shot is simply parried back.
	if _gm.uses_dashblade(_foe.index) and not scored.is_empty():
		_best_cand = scored[0]
		_best = {"score": VELOCITY_WITHHOLD_SCORE, "withheld_for_velocity": true}
		_best_total = float(scored[0]["base"]) + VELOCITY_WITHHOLD_SCORE

	var searched: int = scored.size() if gm.uses_dashblade(idx) \
		else mini(MOVES_SEARCHED, scored.size())
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
	if _gm.uses_dashblade(_idx):
		_aim_dashblade(pl)
	elif _gm.uses_shock(_idx):
		_aim_shock(pl)
	# The AI has no physical button, but makes the same explicit choice immediately
	# before placing its shot rather than receiving an automatic upgrade.
	if _gm.super_meter[_idx] >= 1.0:
		_gm.super_armed[_idx] = true
	_gm._release_charge(_idx)


## The shared search still chooses movement and launch timing, but these kits do
## not use dagger ballistics. Translate its chosen origin into an honest kit-
## specific decision before going through the normal release API.
func _aim_dashblade(plan: PlayerPlan) -> void:
	var origin := _chosen_origin()
	var target: Vector2 = _best.get("dash_target", _future_target(plan.recorded_ticks()))
	var delta: Vector2 = _gm.wrap_delta(origin, target)
	if delta.is_zero_approx():
		delta = Vector2.RIGHT if _idx % 2 == 0 else Vector2.LEFT
	plan.set_aim_from_vector(delta, _gm.aim_min_angle, _gm.aim_max_angle)
	plan.power = clampf(float(_best.get("power", plan.power)), 0.0, 1.0)


func _aim_shock(plan: PlayerPlan) -> void:
	var origin := _chosen_origin()
	var owned_orbs := _owned_shock_orbs()

	# First establish an orb, then deliberately cash it out with plasma. When a
	# setup has been denied, periodic straight plasma prevents a predictable
	# endless relob loop.
	var foe_target := _future_target(plan.recorded_ticks())
	var combo: Dictionary = _best_shock_combo(owned_orbs)
	var combo_ready: bool = bool(combo.get("ready", false))
	var establish_orb: bool = not combo_ready and _should_establish_shock_orb(owned_orbs)
	plan.attack_mode = 1 if establish_orb else 0
	var target: Vector2 = combo["orb"].position if combo_ready else \
		(_shock_setup_target() if establish_orb else \
		_best.get("shock_target", foe_target) as Vector2)
	var delta: Vector2 = _gm.wrap_delta(origin, target)
	if delta.is_zero_approx():
		delta = Vector2.RIGHT if _idx % 2 == 0 else Vector2.LEFT
	if establish_orb:
		# Give the persistent projectile enough lift to clear bodies and low lips;
		# distance still controls its authored speed through charge.
		var side := 1.0 if delta.x >= 0.0 else -1.0
		var lift := clampf(absf(delta.x) * 0.32 - delta.y, 70.0, 260.0)
		plan.set_aim_from_vector(Vector2(absf(delta.x) * side, -lift),
			_gm.aim_min_angle, _gm.aim_max_angle)
		# The player can use the new full-range lob, but ordinary AI setup should
		# still settle near its target instead of sailing through the whole arena.
		plan.power = clampf(delta.length() / 1150.0, 0.15, 1.0)
	else:
		plan.set_aim_from_vector(delta, _gm.aim_min_angle, _gm.aim_max_angle)
		plan.power = 1.0


func _chosen_origin() -> Vector2:
	if _best_cand.is_empty() or not _best_cand.has("path"):
		return _me.position
	var path: PackedVector2Array = _best_cand["path"]
	return path[clampi(int(_best.get("tick", 0)), 0, path.size() - 1)]


func _future_target(tick: int) -> Vector2:
	if _futures.is_empty():
		return _foe.position
	var hold: PackedVector2Array = _futures[1]
	return hold[clampi(tick, 0, hold.size() - 1)]


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
						if _gm.uses_dashblade(_idx) or _gm.uses_shock(_idx) or e < 5.0 \
								or _plausible(origin, side, e, power):
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
		var jump_result := Player.apply_jump(vel, og, air_jumps, jump_now,
			_gm.jump_impulse_for(who.index), _gm.air_jump_impulse_for(who.index),
			_gm.air_jumps_for(who.index))
		vel = jump_result[0]
		og = jump_result[1]
		air_jumps = jump_result[2]
		# The search never drops through a ledge: it is a deliberate human verb,
		# and adding it would multiply the candidate space for a move the AI has
		# no way to value yet.
		var st := Player.step_state(pos, vel, og, d, jump and t < ticks, _dt, _gm,
			_gm.world_tick + t, 0, 0.0, _gm.movement_speed_scale(who.index),
			_gm.jump_impulse_for(who.index), _gm.max_fall_speed_for(who.index))
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


## Blind counterplay for a possible CUT TO END. The AI does not inspect the
## rival plan; it asks whether an early, middle or late full-power dash from each
## ordinary footwork hypothesis could still catch this candidate route.
func _velocity_dash_danger(path: PackedVector2Array) -> float:
	if not _gm.uses_dashblade(_foe.index) or path.is_empty():
		return 0.0
	var params: Dictionary = _gm.dash_parameters(1.0, false, _gm.frame_debt_max_cells)
	var speed: float = float(params["speed"])
	var ticks: int = int(params["ticks"])
	var budget: int = mini(_gm.movement_tick_budget(), _gm.exec_ticks() - 1)
	var releases: Array[int] = [0, mini(15, budget), budget]
	var worst: float = 0.0
	for future: PackedVector2Array in _futures:
		for release: int in releases:
			if release >= future.size() or release >= path.size():
				continue
			var origin: Vector2 = future[release]
			var target_tick: int = release
			var target: Vector2 = path[target_tick]
			for _refinement in 2:
				var distance: float = _gm.wrap_delta(origin, target).length()
				var travel_ticks: int = clampi(
					roundi(distance / maxf(speed * _dt, 0.001)), 0, ticks)
				target_tick = clampi(release + travel_ticks, 0, path.size() - 1)
				target = path[target_tick]
			var delta: Vector2 = _gm.wrap_delta(origin, target)
			if delta.is_zero_approx():
				continue
			var dash_direction := delta.normalized()
			for t in range(1, ticks + 1):
				var body_tick: int = release + t
				if body_tick >= path.size():
					break
				# The avoidance envelope deliberately ignores fine wall-shimmy detail;
				# it is a cheap blind hypothesis evaluated for every movement option,
				# not a second full AI search or a read of the opponent's real plan.
				var dash_position: Vector2 = _gm.wrap_point(
					origin + dash_direction * speed * _dt * float(t))
				var miss: float = _gm.wrap_delta(dash_position, path[body_tick]).length()
				if miss <= Player.HALF.length() + Dashblade.DEFAULT_GUARD_DEPTH:
					var urgency: float = 1.0 + float(path.size() - body_tick) \
						/ float(maxi(path.size(), 1))
					worst = maxf(worst, urgency)
					break
	return worst


## A projectile launched directly down the line of a plausible incoming dash is
## not pressure—it is ammunition for Velocity's moving guard. Range includes
## both bodies closing during the dash, and angular risk falls to zero for real
## over/under shots which can bypass the narrow front surface.
func _velocity_front_parry_risk(origin: Vector2, projectile_direction: Vector2,
		projectile_speed: float, fire_tick: int, candidate: Dictionary) -> float:
	if not _gm.uses_dashblade(_foe.index) or projectile_direction.is_zero_approx():
		return 0.0
	var params: Dictionary = _gm.dash_parameters(1.0, false, _gm.frame_debt_max_cells)
	var active_time: float = float(params["ticks"]) * _dt
	var closing_reach: float = (float(params["speed"]) + maxf(0.0, projectile_speed)) \
		* active_time + Dashblade.DEFAULT_GUARD_DEPTH + Player.HALF.length()
	var route: PackedVector2Array = candidate.get("path", PackedVector2Array())
	var risk: float = 0.0
	for future: PackedVector2Array in _futures:
		if fire_tick < 0 or fire_tick >= future.size():
			continue
		var foe_origin: Vector2 = future[fire_tick]
		var to_foe: Vector2 = _gm.wrap_delta(origin, foe_origin)
		var distance: float = to_foe.length()
		if distance <= 0.001 or distance > closing_reach:
			continue
		var alignment: float = projectile_direction.normalized().dot(to_foe / distance)
		if alignment <= VELOCITY_PARRY_ALIGNMENT:
			continue
		# If the candidate already escaped far from its launch point, reduce the
		# likelihood that Velocity would choose this frontal line in the first place.
		var escape_scale: float = 1.0
		if not route.is_empty():
			var later: Vector2 = route[clampi(
				fire_tick + int(params["ticks"]), 0, route.size() - 1)]
			var lateral: float = absf(
				_gm.wrap_delta(origin, later).dot(to_foe.normalized().orthogonal()))
			escape_scale = clampf(1.0 - lateral / 140.0, 0.25, 1.0)
		var angular: float = inverse_lerp(VELOCITY_PARRY_ALIGNMENT, 1.0, alignment)
		var proximity: float = clampf(
			(closing_reach - distance) / maxf(closing_reach * 0.35, 1.0),
			0.25, 1.0)
		risk = maxf(risk, angular * proximity * escape_scale)
	return risk


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
func _fire(origin: Vector2, side: int, elev: float, power: float, fire_tick: int,
		candidate: Dictionary = {}) -> Dictionary:
	if _gm.uses_dashblade(_idx):
		return _fire_dashblade(origin, power, fire_tick, candidate)
	if _gm.uses_shock(_idx):
		return _fire_shock(origin, fire_tick, candidate)
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
	var score := float(hits) * 1000.0 - closest * 0.05 - float(fire_tick) * 0.2
	var parry_risk := _velocity_front_parry_risk(origin, dir,
		_gm.knife_launch_velocity(dir, power).length(), fire_tick, candidate)
	if parry_risk > 0.0:
		score = lerpf(score, VELOCITY_PARRY_FAILURE_SCORE, parry_risk)
	return {"score": score, "velocity_parry_risk": parry_risk}


## Trace the real dash body against the same left/hold/right futures used by the
## dagger planner. The chosen target is returned to `_aim_dashblade`, preventing
## the final aim pass from collapsing back to the stationary hypothesis.
func _fire_dashblade(origin: Vector2, power: float, fire_tick: int,
		candidate: Dictionary = {}) -> Dictionary:
	var lost_frames: int = _gm.frame_debt_cells[_idx]
	if candidate.has("path") and candidate.has("move"):
		lost_frames = _gm.projected_frame_debt_for_constant_path(_idx,
			candidate["path"], fire_tick, int(candidate["move"][0]))
	var params: Dictionary = _gm.dash_parameters(power, false, lost_frames)
	var speed: float = float(params["speed"])
	var ticks: int = int(params["ticks"])
	var best := {"score": -INF, "dash_target": _future_target(fire_tick)}
	for aimed_future: PackedVector2Array in _futures:
		var target_tick := fire_tick
		var target: Vector2 = aimed_future[clampi(target_tick, 0, aimed_future.size() - 1)]
		# Refine once for where that hypothesis will stand when the dash arrives.
		for refinement in 2:
			var distance: float = _gm.wrap_delta(origin, target).length()
			var travel_ticks := clampi(roundi(distance / maxf(speed * _dt, 0.001)), 0, ticks)
			target_tick = fire_tick + travel_ticks
			target = aimed_future[clampi(target_tick, 0, aimed_future.size() - 1)]
		var delta: Vector2 = _gm.wrap_delta(origin, target)
		if delta.is_zero_approx():
			delta = Vector2.RIGHT if _idx % 2 == 0 else Vector2.LEFT
		var path: PackedVector2Array = _gm.dash_preview_path(
			origin, delta, power, false, lost_frames)
		var covered := [false, false, false]
		var closest := INF
		for h in _futures.size():
			var future: PackedVector2Array = _futures[h]
			for t in range(1, path.size()):
				var fi := clampi(fire_tick + t, 0, future.size() - 1)
				var miss: float = _gm.wrap_delta(path[t], future[fi]).length()
				closest = minf(closest, miss)
				if miss <= Player.HALF.length() + Dashblade.DEFAULT_GUARD_DEPTH:
					covered[h] = true
					break
		var hits := 0
		for did_hit in covered:
			if did_hit:
				hits += 1
		var score := float(hits) * 1200.0 - closest * 0.08 - float(fire_tick) * 0.2
		if score > float(best["score"]):
			best = {"score": score, "dash_target": target}
	return best


## Static Witch decisions are direct lines (plasma or plasma-to-orb), while the
## orb lob is deliberately established by `_aim_shock`. Score the tactical line
## instead of paying for a ballistic knife simulation that this kit never uses.
func _fire_shock(origin: Vector2, fire_tick: int,
		candidate: Dictionary = {}) -> Dictionary:
	var owned_orbs := _owned_shock_orbs()
	var foe_target := _future_target(fire_tick)
	var combo: Dictionary = _best_shock_combo(owned_orbs)
	var combo_ready: bool = bool(combo.get("ready", false))
	var establish_orb: bool = not combo_ready and _should_establish_shock_orb(owned_orbs)
	if not combo_ready and not establish_orb:
		var plasma_solution := _shock_plasma_solution(origin, fire_tick)
		var plasma_direction: Vector2 = _gm.wrap_delta(
			origin, plasma_solution["target"]).normalized()
		var parry_risk := _velocity_front_parry_risk(origin, plasma_direction,
			_gm.shock_plasma_speed, fire_tick, candidate)
		var plasma_score := float(plasma_solution["score"])
		if parry_risk > 0.0:
			plasma_score = lerpf(plasma_score, VELOCITY_PARRY_FAILURE_SCORE, parry_risk)
		return {
			"score": plasma_score,
			"attack_mode": 0,
			"shock_target": plasma_solution["target"],
			"velocity_parry_risk": parry_risk,
		}
	var target: Vector2 = combo["orb"].position if combo_ready else \
		(_shock_setup_target() if establish_orb else foe_target)
	var distance: float = _gm.wrap_delta(origin, target).length()
	var blocked: bool = false if establish_orb else \
		_line_blocked(origin, target, ShockPlasma.COLLISION_RADIUS, fire_tick)
	var payoff := 520.0 if establish_orb else (1600.0 if combo_ready else 1000.0)
	return {"score": (payoff if not blocked else 0.0) \
		- distance * 0.035 - float(fire_tick) * 0.2,
		"attack_mode": 1 if establish_orb else 0}


func _shock_plasma_solution(origin: Vector2, fire_tick: int) -> Dictionary:
	var best := {"score": -INF, "target": _future_target(fire_tick)}
	for aimed_future: PackedVector2Array in _futures:
		var target: Vector2 = aimed_future[clampi(fire_tick, 0, aimed_future.size() - 1)]
		for refinement in 2:
			var distance: float = _gm.wrap_delta(origin, target).length()
			var travel_ticks := roundi(distance / maxf(_gm.shock_plasma_speed * _dt, 0.001))
			target = aimed_future[clampi(fire_tick + travel_ticks, 0, aimed_future.size() - 1)]
		var direction: Vector2 = _gm.wrap_delta(origin, target).normalized()
		if direction.is_zero_approx():
			direction = Vector2.RIGHT if _idx % 2 == 0 else Vector2.LEFT
		var pos: Vector2 = Player.shoulder_at(origin) + direction * 24.0
		var covered := [false, false, false]
		var closest := INF
		for t in mini(72, _gm.exec_ticks() - fire_tick):
			var raw: Vector2 = pos + direction * float(_gm.shock_plasma_speed) * _dt
			var blocked := false
			for solid: Rect2 in _gm.solids_at(_gm.world_tick + fire_tick + t + 1):
				if Arrow.seg_hits_rect(pos, raw, solid.grow(ShockPlasma.COLLISION_RADIUS)):
					blocked = true
					break
			var world_t := fire_tick + t
			for h in _futures.size():
				var future: PackedVector2Array = _futures[h]
				var fi := clampi(world_t, 0, future.size() - 1)
				if not covered[h] and _hits_body(pos, raw, future[fi]):
					covered[h] = true
				closest = minf(closest, _gm.wrap_delta(raw, future[fi]).length())
			if blocked:
				break
			pos = _gm.wrap_point(raw)
		var hits := 0
		for did_hit in covered:
			if did_hit:
				hits += 1
		var score := float(hits) * 1100.0 - closest * 0.06 - float(fire_tick) * 0.2
		if score > float(best["score"]):
			best = {"score": score, "target": target}
	return best


func _shock_combo_opportunity(orb) -> Dictionary:
	if orb == null or not orb.is_armed():
		return {"ready": false}
	var best_target := -1
	var best_distance := INF
	for player: Player in _gm.players:
		if player.index == _idx or not player.alive:
			continue
		var distance: float = _gm.wrap_delta(orb.position, player.position).length()
		if distance <= _gm.shock_combo_radius * 0.88 and distance < best_distance \
				and _gm._blast_reaches(orb.position, player.position):
			best_target = player.index
			best_distance = distance
	return {"ready": best_target >= 0, "target": best_target, "distance": best_distance}


func _owned_shock_orbs() -> Array:
	var owned: Array = []
	for orb in _gm.shock_orbs:
		if orb.shooter == _idx:
			owned.append(orb)
	return owned


func _best_shock_combo(owned_orbs: Array) -> Dictionary:
	var best := {"ready": false, "orb": null, "distance": INF}
	for orb in owned_orbs:
		var opportunity := _shock_combo_opportunity(orb)
		if bool(opportunity.get("ready", false)) \
				and float(opportunity.get("distance", INF)) < float(best["distance"]):
			best = opportunity.duplicate()
			best["orb"] = orb
	return best


func _should_establish_shock_orb(owned_orbs: Array) -> bool:
	if owned_orbs.size() >= SHOCK_SETUP_ORB_TARGET:
		return false
	if owned_orbs.is_empty():
		return _gm.players.size() > 2 or posmod(_gm.turn - 1, 3) == 0
	# Do not spend the opening two turns stacking setup while rivals attack. Keep
	# plasma pressure between casts, then extend the field if the first orb lives.
	return posmod(_gm.turn - 1, 4) == 0


## In a duel this is simply the foe. In a crowded arena, seed the orb toward
## the opponent with the most neighbours inside a future combo diameter so the
## area-control kit actually plays area control instead of tunnelling on the
## nearest body every turn.
func _shock_setup_target() -> Vector2:
	var best := _foe.position
	var best_crowd := -1
	var best_distance := INF
	for candidate: Player in _gm.players:
		if candidate.index == _idx or not candidate.alive:
			continue
		var crowd := 0
		for other: Player in _gm.players:
			if other.index in [_idx, candidate.index] or not other.alive:
				continue
			if _gm.wrap_delta(candidate.position, other.position).length() \
					<= _gm.shock_combo_radius * 1.75:
				crowd += 1
		var distance: float = _gm.wrap_delta(_me.position, candidate.position).length()
		if crowd > best_crowd or (crowd == best_crowd and distance < best_distance):
			best = candidate.position
			best_crowd = crowd
			best_distance = distance
	return best


func _line_blocked(origin: Vector2, target: Vector2, radius: float, fire_tick: int) -> bool:
	var endpoint: Vector2 = origin + _gm.wrap_delta(origin, target)
	for solid: Rect2 in _gm.solids_at(_gm.world_tick + fire_tick + 1):
		var impact := Arrow.segment_rect_impact(origin, endpoint, solid.grow(radius))
		if not impact.is_empty() and float(impact[0]) > 0.01 and float(impact[0]) < 0.99:
			return true
	return false


