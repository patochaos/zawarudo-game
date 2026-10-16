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
const SHOCK_SETUP_ORB_TARGET := 2
const FLIGHT_CAP := 110          # ticks of arrow flight to look ahead
const HYPOTHESES := [-1, 0, 1]   # what the opponent might do with their feet
const VELOCITY_DASH_DANGER_WEIGHT := 900.0
const VELOCITY_PARRY_ALIGNMENT := 0.82
const VELOCITY_PARRY_FAILURE_SCORE := -350.0
const VELOCITY_WITHHOLD_SCORE := -220.0
## A knife that lands after the window is seen by the opponent during their
## next planning phase. The later it arrives (in the opponent's own time, since
## a body in stasis reacts just as slowly), the surer the dodge; what remains
## is the value of a hazard parked where they wanted to stand.
const LATE_HIT_FADE_TICKS := 12.0
const LATE_HIT_FLOOR := 0.15
## Out of reach: no full-power probe throw reaches a hypothesis before the
## window ends. Then a route is also judged by how soon a throw from where it
## ends could arrive, so the CPU works toward a firing spot instead of
## wandering on the tiebreak and lobbing knives that arrive turns later.
const REACH_PROBE_ELEVATIONS := [5.0, 20.0, 35.0, 50.0]
const PROBE_HIT_RADIUS := 40.0        # near enough for the refined search to land
const TRAVEL_SAMPLE_PX := 32.0
const BLOCKED_DETOUR_TICKS := 30.0
const ENGAGE_WEIGHT := 1.0           # score per tick of arrival past the window

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
	var horizon: float = float(_horizon())
	var out_of_reach: bool = not _gm.uses_dashblade(_idx) and not _gm.interception_mode \
		and _arrival_from(_me.position) > horizon

	# Rank movements by safety first — this part is cheap enough to do at once.
	var scored: Array = []
	for m in move_options:
		var ticks: int = budget if m[2] < 0 else mini(m[2], budget)
		var drop: bool = m.size() > 4 and m[4]
		var path := _walk(_me, m[0], m[1], ticks, m[3], drop)
		var safety: float = 0.0
		if not _me.is_invulnerable():
			safety = -600.0 * float(_style["safety_scale"]) * _danger(path, threats)
			# A rival Rook is a potential body projectile even though its plan
			# remains private. Test a small envelope of plausible release moments and
			# reward routes which leave the committed line before it arrives.
			if _gm.uses_dashblade(_foe.index):
				safety -= VELOCITY_DASH_DANGER_WEIGHT * _velocity_dash_danger(path)
		var core_value: float = _core_value(path)
		var variety: float = 12.0 if ticks > 0 and not _gm.interception_mode else 0.0
		# A body-dash kit cannot create pressure from the opposite side of the
		# arena. Prefer safe paths that close the gap instead of letting the generic
		# projectile planner wander on a random tiebreak.
		var engage_value: float = 0.0
		if _gm.uses_dashblade(_idx):
			engage_value = -_gm.wrap_delta(path[path.size() - 1], _foe.position).length() * 0.22
		elif out_of_reach:
			# A projectile kit that cannot land anything this window moves toward
			# a spot a throw could land from, not merely toward the rival: a wall
			# or a stasis field between the two is part of the distance.
			engage_value = -ENGAGE_WEIGHT * maxf(0.0,
				_arrival_from(path[path.size() - 1]) - horizon)
		# Safety usually ties across candidates, and only the top few get a shot
		# search — without a tiebreak the list order alone decides, so the jump
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
	# Not attacking is a legal tactical answer. Seed the search with the safest
	# movement-only plan against The Rook; a projectile plan must beat this after
	# accounting for the chance that a frontal shot is simply parried back.
	if _gm.uses_dashblade(_foe.index) and not scored.is_empty():
		_best_cand = scored[0]
		_best = {"score": VELOCITY_WITHHOLD_SCORE, "withheld_for_velocity": true}
		_best_total = float(scored[0]["base"]) + VELOCITY_WITHHOLD_SCORE
	# A patient opponent keeps the knife unless a throw clears its bar. The
	# safest route is the plan it falls back to; apply() throws only when _best
	# carries an elevation.
	elif float(_style["withhold_score"]) > 0.0 and not scored.is_empty():
		_best_cand = scored[0]
		_best = {"score": float(_style["withhold_score"]), "withheld_by_style": true}
		_best_total = float(scored[0]["base"]) + float(_style["withhold_score"])

	# A body-dash kit has to search every route, since the route is the attack.
	var searched: int = scored.size() if gm.uses_dashblade(idx) \
		else mini(gm.ai_moves_searched_for(idx), scored.size())
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
	if _gm.uses_dashblade(_idx):
		_aim_dashblade(pl)
	elif _gm.uses_shock(_idx):
		_aim_shock(pl)
	elif _gm.uses_chakram(_idx):
		_aim_chakram(pl)
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
		# The lance falls, so aim above the mark by the same lead the search used.
		plan.set_aim_from_vector(
			plasma_launch_direction(_gm, origin, target,
				1.0 if _idx % 2 == 0 else -1.0),
			_gm.aim_min_angle, _gm.aim_max_angle)
		plan.power = 1.0


func _aim_chakram(plan: PlayerPlan) -> void:
	plan.attack_mode = int(_best.get("attack_mode", 0))
	if plan.attack_mode == 1:
		# ABSOLUTION has no aim choice; movement determines the dangerous return
		# line. Preserve the existing facing instead of snapping the pose randomly.
		return
	# The coarse/refined search already chose this exact elevation and side. Do
	# not collapse it back onto the stationary foe after evaluating the real arc.
	plan.power = clampf(float(_best.get("power", plan.power)), 0.0, 1.0)


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
						if _gm.uses_dashblade(_idx) or _gm.uses_shock(_idx) \
								or _gm.uses_chakram(_idx) or e < 5.0 \
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
		if a is InterceptProjectile:
			for forecast in ClassLab.forecast(a, _gm.exec_ticks()):
				if forecast.lethal:
					var future := PackedVector2Array()
					for tick in forecast.offset:
						future.append(Vector2(-100000, -100000))
					future.append_array(forecast.path)
					out.append(future)
			continue
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
	for chakram in _gm.chakrams:
		if chakram.shooter == _idx:
			continue
		out.append(_chakram_threat_path(chakram))
	return out


func _chakram_threat_path(chakram) -> PackedVector2Array:
	var pts := PackedVector2Array([chakram.position])
	var pos: Vector2 = chakram.position
	var vel: Vector2 = chakram.vel
	var owner = null
	for player: Player in _gm.players:
		if player.index == chakram.shooter:
			owner = player
			break
	for _tick in _gm.exec_ticks():
		if chakram.is_holding():
			pts.append(pos)
			continue
		if chakram.is_returning() and owner != null and owner.alive:
			var desired: Vector2 = pos.direction_to(owner.position) * chakram.return_speed
			vel = vel.move_toward(desired, chakram.return_acceleration * _dt)
			vel.y += chakram.outbound_gravity * chakram.return_gravity_scale * _dt
		else:
			vel.x *= maxf(0.0, 1.0 - chakram.outbound_drag * _dt)
			vel.y += chakram.outbound_gravity * _dt
		pos = _gm.wrap_point(pos + vel * _dt)
		pts.append(pos)
	return pts


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
## not pressure—it is ammunition for The Rook's moving guard. Range includes
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
		# likelihood that The Rook would choose this frontal line in the first place.
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
	if _gm.class_lab and _gm.player_weapons[_idx] != Roster.DUELIST:
		return _fire_lab(origin, side, elev, power, fire_tick)
	if _gm.uses_dashblade(_idx):
		return _fire_dashblade(origin, power, fire_tick, candidate)
	if _gm.uses_shock(_idx):
		return _fire_shock(origin, fire_tick, candidate)
	if _gm.uses_chakram(_idx):
		return _fire_chakram(origin, side, elev, power, fire_tick, candidate)
	var ang: float = elev if side > 0 else 180.0 - elev
	var r := deg_to_rad(ang)
	var dir := Vector2(cos(r), -sin(r))
	var launch: Vector2 = origin + Vector2(0.0, -6.0)
	var covered := [false, false, false]
	var hit_ticks := [-1, -1, -1]
	var closest := 1e9
	# The foe prediction ends with the window; past it the hypothesis is frozen
	# where it stopped, which is a guess about the next turn, not a fact.
	var horizon: int = _horizon()

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
	var parry_risk := _velocity_front_parry_risk(origin, dir,
		_gm.knife_launch_velocity(dir, power).length(), fire_tick, candidate)
	if parry_risk > 0.0:
		score = lerpf(score, VELOCITY_PARRY_FAILURE_SCORE, parry_risk)
	return {"score": score, "velocity_parry_risk": parry_risk, "knife_hits": hits,
		"late_hits": late_hits, "closest": closest, "hit_ticks": hit_ticks}


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


## How many ticks the kit's best full-power probe throw from `origin` needs
## to reach a foe hypothesis, flown with the real integrators so stasis
## fields, the pillar in between and the world edge all count. A throw that
## never arrives is charged the ground it still had to cover, priced along the
## straight line to the target at the clock of every field on the way, plus a
## detour when a wall blocks that line. At or under the horizon, a hit is on
## the table this window.
func _arrival_from(origin: Vector2) -> float:
	var horizon: int = _horizon()
	var best := INF
	if _futures.is_empty():
		return best
	var targets := PackedVector2Array()
	for f in _futures:
		targets.append(f[f.size() - 1])
	if _gm.uses_shock(_idx):
		var pace: float = maxf(_gm.shock_plasma_speed_for_power(1.0) * _dt, 1.0)
		for target in targets:
			var direction := plasma_launch_direction(_gm, origin, target,
				1.0 if _idx % 2 == 0 else -1.0)
			var pos: Vector2 = Player.shoulder_at(origin) + direction * 24.0
			var bolt: Vector2 = direction * _gm.shock_plasma_speed_for_power(1.0)
			var reach_left: float = _gm.shock_plasma_range_for_power(1.0)
			var flown := 0
			for t in FLIGHT_CAP:
				var flight := ShockPlasma.step_state(pos, bolt, _dt, _gm)
				var raw: Vector2 = flight[0]
				bolt = flight[1]
				var step: float = pos.distance_to(raw)
				if reach_left < step or _segment_blocked(pos, raw, t, ShockPlasma.COLLISION_RADIUS):
					break
				reach_left -= step
				flown = t + 1
				pos = _gm.wrap_point(raw)
				if _gm.wrap_delta(pos, target).length() <= PROBE_HIT_RADIUS:
					best = minf(best, float(flown))
					break
				if flown == horizon:
					best = minf(best, float(flown) + _travel_cost(pos, target, pace, false))
				if not _gm.world_bounds.has_point(pos):
					break
			if best <= float(horizon):
				return best
			best = minf(best, float(flown) + _travel_cost(pos, target, pace, false))
		return best
	var full_pace: float = maxf(_gm.arrow_speed_max * _dt, 1.0)
	var launch: Vector2 = origin + Vector2(0.0, -6.0)
	for side in _sides():
		for elev in REACH_PROBE_ELEVATIONS:
			var ang: float = elev if side > 0 else 180.0 - elev
			var dir := Vector2(cos(deg_to_rad(ang)), -sin(deg_to_rad(ang)))
			var vel: Vector2 = _gm.knife_launch_velocity(dir, 1.0)
			var pos: Vector2 = launch + vel.normalized() * 22.0
			var flown := 0
			var arrived := false
			for t in FLIGHT_CAP:
				var st := Arrow.step_state(pos, vel, _dt, _gm)
				vel = st[1]
				if _segment_blocked(pos, st[2], t, 0.0):
					break
				pos = st[0]
				flown = t + 1
				for target in targets:
					if _gm.wrap_delta(pos, target).length() <= PROBE_HIT_RADIUS:
						arrived = true
						best = minf(best, float(flown))
				if arrived:
					break
				if flown == horizon:
					for target in targets:
						best = minf(best, float(flown) + _travel_cost(pos, target, full_pace, true))
				if not _gm.world_bounds.has_point(pos):
					break
			if best <= float(horizon):
				return best
			if not arrived:
				for target in targets:
					best = minf(best, float(flown) + _travel_cost(pos, target, full_pace, true))
	return best


## Ticks a projectile already at `from` would still need to cover the straight
## line to `target`, sampled through every stasis field on the way, plus a
## detour when a solid blocks the line.
func _travel_cost(from: Vector2, target: Vector2, pace: float, stasis: bool) -> float:
	var delta: Vector2 = _gm.wrap_delta(from, target)
	var length: float = delta.length()
	var cost := 0.0
	if stasis and length > 0.0:
		var samples: int = maxi(1, int(ceil(length / TRAVEL_SAMPLE_PX)))
		var step: float = length / float(samples)
		for i in samples:
			var at: Vector2 = _gm.wrap_point(from + delta * ((float(i) + 0.5) / float(samples)))
			cost += step / (pace * _gm.time_scale_at(at))
	else:
		cost = length / pace
	for solid: Rect2 in _gm.solids_at(_gm.world_tick):
		var impact := Arrow.segment_rect_impact(from, from + delta, solid)
		if not impact.is_empty() and float(impact[0]) > 0.01 and float(impact[0]) < 0.99:
			return cost + BLOCKED_DETOUR_TICKS
	return cost


func _segment_blocked(from: Vector2, to: Vector2, t: int, radius: float) -> bool:
	for solid: Rect2 in _gm.solids_at(_gm.world_tick + t + 1):
		if Arrow.seg_hits_rect(from, to, solid.grow(radius) if radius > 0.0 else solid):
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


## Knife-only preferences layered over the shared hit score: throw timing,
## draw strength and the seam shot. Kit attacks keep their own evaluators.
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


## Eclipse cannot be evaluated as a reskinned dagger. DECREE is walked through
## the real corona integrator for the remaining execution window, including its
## drag, gravity, HARD bank and consecration. ABSOLUTION separately traces every
## callable corona—including its real platform skid—toward this movement
## candidate and wins only when the returning formation beats a new threat.
func _fire_chakram(origin: Vector2, side: int, elev: float, power: float,
		fire_tick: int, candidate: Dictionary = {}) -> Dictionary:
	var ang: float = elev if side > 0 else 180.0 - elev
	var direction := Vector2(cos(deg_to_rad(ang)), -sin(deg_to_rad(ang)))
	var decree := _score_chakram_decree(origin, direction, power, fire_tick, candidate)
	var absolution := _score_chakram_absolution(fire_tick, candidate)
	return absolution if float(absolution["score"]) > float(decree["score"]) else decree


func _score_chakram_decree(origin: Vector2, direction: Vector2, power: float,
		fire_tick: int, candidate: Dictionary) -> Dictionary:
	var disc := Chakram.new()
	disc.cfg = _gm
	disc.shooter = _idx
	disc.begin_lifecycle(_gm.turn)
	disc.position = Player.shoulder_at(origin) + direction.normalized() * 24.0
	disc.prev_pos = disc.position
	disc.vel = _gm.chakram_launch_velocities(direction, power)[0]
	var launch_speed: float = disc.vel.length()
	var covered := [false, false, false]
	var closest := INF
	for local_tick in maxi(0, _gm.exec_ticks() - fire_tick):
		var world_t := fire_tick + local_tick
		var result: Dictionary = disc.sim_step(_dt, [], _gm.turn)
		for h in _futures.size():
			var future: PackedVector2Array = _futures[h]
			var fi := clampi(world_t, 0, future.size() - 1)
			var miss: float = _gm.wrap_delta(disc.position, future[fi]).length()
			closest = minf(closest, miss)
			if not covered[h] and _hits_body(disc.prev_pos, disc.position, future[fi]):
				covered[h] = true
		if not result["alive"]:
			break
	var endpoint_value := 0.0
	for future: PackedVector2Array in _futures:
		var endpoint: Vector2 = future[future.size() - 1]
		var distance: float = _gm.wrap_delta(disc.position, endpoint).length()
		# Consecrating near several plausible endpoints is useful even before a
		# direct hit; distance prevents random empty-corner placements from tying.
		endpoint_value += maxf(0.0, 260.0 - distance) * 0.42
	var hits := covered.count(true)
	var score := float(hits) * 1125.0 + endpoint_value \
		- closest * 0.055 - float(fire_tick) * 0.2
	var parry_risk := _velocity_front_parry_risk(
		origin, direction, launch_speed, fire_tick, candidate)
	if parry_risk > 0.0:
		score = lerpf(score, VELOCITY_PARRY_FAILURE_SCORE, parry_risk)
	disc.free()
	return {"score": score, "attack_mode": 0,
		"velocity_parry_risk": parry_risk}


func _score_chakram_absolution(fire_tick: int, candidate: Dictionary) -> Dictionary:
	var callable: Array = _gm.recallable_chakrams(_idx)
	if callable.is_empty() or not candidate.has("path"):
		return {"score": -INF, "attack_mode": 1}
	var owner_path: PackedVector2Array = candidate["path"]
	var owner := Player.new()
	owner.cfg = _gm
	owner.index = _idx
	owner.alive = true
	var returning: Array = []
	var preview_discs: Array = []
	for live_disc in callable:
		var disc := Chakram.new()
		disc.cfg = _gm
		disc.shooter = _idx
		disc.network_id = live_disc.network_id
		disc.launch_turn = live_disc.launch_turn
		disc.age_ticks = live_disc.age_ticks
		disc.position = live_disc.position
		disc.prev_pos = live_disc.position
		disc.outbound_gravity = live_disc.outbound_gravity
		disc.return_speed = live_disc.return_speed
		disc.return_acceleration = live_disc.return_acceleration
		disc.return_gravity_scale = live_disc.return_gravity_scale
		disc.max_lifetime_ticks = live_disc.max_lifetime_ticks
		disc.force_recall()
		returning.append(disc)
		preview_discs.append(disc)
	var covered := [false, false, false]
	var closest := INF
	for world_t in range(fire_tick, _gm.exec_ticks()):
		var owner_tick := clampi(world_t, 0, owner_path.size() - 1)
		owner.position = owner_path[owner_tick]
		var still_returning: Array = []
		for disc in returning:
			var result: Dictionary = disc.sim_step(_dt, [owner], _gm.turn)
			for h in _futures.size():
				var future: PackedVector2Array = _futures[h]
				var fi := clampi(world_t, 0, future.size() - 1)
				closest = minf(closest,
					_gm.wrap_delta(disc.position, future[fi]).length())
				if not covered[h] and _hits_body(
						disc.prev_pos, disc.position, future[fi]):
					covered[h] = true
			if result["alive"]:
				still_returning.append(disc)
		returning = still_returning
		if returning.is_empty():
			break
	var hits := covered.count(true)
	# A recall without a credible crossing should lose to establishing another
	# corona. Calling several established threats is modestly valuable even when
	# only one supplies the actual crossing.
	var score := float(hits) * 1325.0 - closest * 0.07 \
		+ float(callable.size() - 1) * 65.0 - float(fire_tick) * 0.2 \
		- (180.0 if hits == 0 else 0.0)
	for disc in preview_discs:
		disc.free()
	owner.free()
	return {"score": score, "attack_mode": 1}


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


## Pulse decisions are direct lines (plasma or plasma-to-orb), while the
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
	# Out of reach counts as blocked. A combo the lance cannot physically arrive
	# at is not a plan, and scoring it as one made the Witch commit to detonations
	# from across the arena that were never going to land.
	var out_of_reach: bool = not establish_orb \
		and distance > _gm.shock_plasma_range_for_power(1.0)
	var blocked: bool = false if establish_orb else \
		(out_of_reach or _line_blocked(origin, target, ShockPlasma.COLLISION_RADIUS, fire_tick))
	var payoff := 520.0 if establish_orb else (1600.0 if combo_ready else 1000.0)
	return {"score": (payoff if not blocked else 0.0) \
		- distance * 0.035 - float(fire_tick) * 0.2,
		"attack_mode": 1 if establish_orb else 0}


## Where to point a falling lance so it arrives at `target`. Aiming straight at
## a point only works for a projectile that does not drop; now that the bolt is
## ballistic, a flat aim undershoots by 0.5 * g * t^2. This is the same
## first-order lead a player makes by eye, and both the search and the shot it
## finally arms go through it so the two cannot disagree.
static func plasma_launch_direction(gm, origin: Vector2, target: Vector2,
		fallback_side: float = 1.0) -> Vector2:
	var delta: Vector2 = gm.wrap_delta(origin, target)
	var speed: float = maxf(gm.shock_plasma_speed_for_power(1.0), 1.0)
	# Two passes: the drop depends on the flight time, which depends on the
	# lengthened aim. One correction converges closely enough at these speeds.
	var aim: Vector2 = delta
	for refinement in 2:
		var flight_time: float = aim.length() / speed
		aim = delta - Vector2(0.0, 0.5 * gm.shock_plasma_gravity * flight_time * flight_time)
	if aim.is_zero_approx():
		return Vector2(fallback_side, 0.0)
	return aim.normalized()


func _shock_plasma_solution(origin: Vector2, fire_tick: int) -> Dictionary:
	var best := {"score": -INF, "target": _future_target(fire_tick)}
	for aimed_future: PackedVector2Array in _futures:
		var target: Vector2 = aimed_future[clampi(fire_tick, 0, aimed_future.size() - 1)]
		for refinement in 2:
			var distance: float = _gm.wrap_delta(origin, target).length()
			var travel_ticks := roundi(distance / maxf(_gm.shock_plasma_speed * _dt, 0.001))
			target = aimed_future[clampi(fire_tick + travel_ticks, 0, aimed_future.size() - 1)]
		var direction: Vector2 = plasma_launch_direction(_gm, origin, target,
			1.0 if _idx % 2 == 0 else -1.0)
		var pos: Vector2 = Player.shoulder_at(origin) + direction * 24.0
		var covered := [false, false, false]
		var closest := INF
		# The bolt expires at its authored range, not at the edge of the search,
		# and it falls on the way. Walking it straight and forever would let the
		# AI plan shots that never arrive and then score them as though they had.
		var bolt: Vector2 = direction * _gm.shock_plasma_speed_for_power(1.0)
		var reach_left: float = _gm.shock_plasma_range_for_power(1.0)
		for t in mini(72, _gm.exec_ticks() - fire_tick):
			var flight := ShockPlasma.step_state(pos, bolt, _dt, _gm)
			var raw: Vector2 = flight[0]
			bolt = flight[1]
			var step: float = pos.distance_to(raw)
			if reach_left < step:
				break
			reach_left -= step
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


func _fire_lab(origin: Vector2, side: int, elev: float, power: float, fire_tick: int) -> Dictionary:
	var angle := deg_to_rad(elev if side > 0 else 180.0 - elev)
	var direction := Vector2(cos(angle), -sin(angle))
	var projectile = ClassLab.make_projectile(_gm, _gm.player_weapons[_idx], origin + Vector2(0, -6) + direction * 22, direction, power)
	var paths: Array = ClassLab.forecast(projectile, FLIGHT_CAP)
	projectile.free()
	var covered := [false, false, false]
	var closest := 1e9
	for forecast in paths:
		if not forecast.lethal:
			continue
		var path: PackedVector2Array = forecast.path
		for tick in range(1, path.size()):
			for h in _futures.size():
				var future: PackedVector2Array = _futures[h]
				var at: Vector2 = future[clampi(fire_tick + forecast.offset + tick - 1, 0, future.size() - 1)]
				covered[h] = covered[h] or _hits_body(path[tick - 1], path[tick], at)
				closest = minf(closest, path[tick].distance_to(at))
	return {"score": float(covered.count(true)) * 1000.0 - closest * 0.05 - float(fire_tick) * 0.2, "velocity_parry_risk": 0.0}
