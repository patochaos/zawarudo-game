extends SceneTree

## Moving geometry and pulse orbs. The point of every check here is that the
## kinetic arenas stay inside the design contracts the static ones already obey:
## the same state and the same plans produce the same outcome, and planning shows
## the player's real intent rather than a snapshot that execution then betrays.

const GAME_MANAGER := preload("res://scripts/GameManager.gd")
const PENDULUM := 2
const FOUNDRY := 3

var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_motion_is_a_pure_function()
	await _test_preview_matches_execution()
	await _test_lift_carries_its_rider()
	await _test_orb_detonates_and_recharges()
	await _test_blast_pushes_bodies_outward()
	await _test_prototype_is_playable()
	await _test_short_turns_and_auto_ready()
	if _failures == 0:
		print("Kinetic arenas: all tests passed")
	else:
		push_error("Kinetic arenas: %d test(s) failed" % _failures)
	quit(_failures)


# --------------------------------------------------------------- pure math ---

func _test_motion_is_a_pure_function() -> void:
	var motion := {"axis": Vector2.DOWN, "travel": 200.0, "period": 100, "phase": 0.0}
	_check(Mover.offset(motion, 0).is_equal_approx(Vector2.ZERO),
		"a mover must start at its authored home position")
	_check(Mover.offset(motion, 50).is_equal_approx(Vector2(0.0, 200.0)),
		"a mover must reach the far end at half its period")
	_check(Mover.offset(motion, 25).is_equal_approx(Vector2(0.0, 100.0)),
		"the sweep must be linear, so speed is constant and readable")
	_check(Mover.offset(motion, 137).is_equal_approx(Mover.offset(motion, 37)),
		"the same tick must always give the same position, forever")
	_check(Mover.offset(motion, -3).is_equal_approx(Mover.offset(motion, 97)),
		"negative ticks must fold into the cycle rather than run off the rail")

	var phased := {"axis": Vector2.DOWN, "travel": 200.0, "period": 100, "phase": 0.5}
	_check(phased_is_opposite(motion, phased),
		"opposite phase must put two lifts at opposite ends of their travel")


func phased_is_opposite(a: Dictionary, b: Dictionary) -> bool:
	for tick in [0, 17, 43, 88]:
		var sum: float = Mover.offset(a, tick).y + Mover.offset(b, tick).y
		if absf(sum - 200.0) > 0.001:
			return false
	return true


# ----------------------------------------------------------- plan honesty ----

## The contract that matters most: what the ghost promised is what execution
## delivers, on an arena whose floor is moving the whole time.
func _test_preview_matches_execution() -> void:
	var gm = await _fresh_game(PENDULUM)
	# Advance the world so the lifts are mid-sweep rather than at a symmetric
	# extreme, which is where an off-by-one in the tick maths would hide.
	gm.world_tick = 91
	gm._apply_movers(gm.world_tick)

	var p: Player = gm.players[0]
	p.position = Vector2(320.0, 470.0)
	p.vel = Vector2.ZERO
	p.on_ground = false
	gm._reset_pilot(0)
	for i in 22:
		gm._pilot_step(0, 1, i == 0, i < 6)
	gm._rebuild_ghost_paths()
	var promised: PackedVector2Array = gm.ghost_path[0]

	gm.state = Phase.EXECUTING
	gm.exec_tick = 0
	gm.exec_ticks_total = gm.exec_ticks()
	var walked := PackedVector2Array()
	walked.append(p.position)
	for tick in gm.exec_ticks():
		gm._sim_tick(gm.tick_dt())
		gm.exec_tick += 1
		walked.append(p.position)

	_check(promised.size() == walked.size(),
		"the ghost path must cover exactly the executed window")
	var worst := 0.0
	for i in mini(promised.size(), walked.size()):
		worst = maxf(worst, promised[i].distance_to(walked[i]))
	_check(worst < 0.001,
		"a plan made over moving geometry must execute exactly as previewed (drift %.4fpx)" % worst)
	gm.free()


# ------------------------------------------------------------------ riding ---

func _test_lift_carries_its_rider() -> void:
	var gm = await _fresh_game(PENDULUM)
	var lift := _find_mover(gm)
	_check(not lift.is_empty(), "PENDULUM must author at least one moving platform")
	if lift.is_empty():
		gm.free()
		return

	# Park the world where this lift is climbing, and stand a fighter on it.
	var climbing := -1
	for tick in 300:
		var rise: float = gm.platform_rect_at(lift, tick + 1).position.y \
			- gm.platform_rect_at(lift, tick).position.y
		if rise < -0.1:
			climbing = tick
			break
	_check(climbing >= 0, "a vertical lift must spend part of its cycle rising")

	gm.world_tick = climbing
	gm._apply_movers(gm.world_tick)
	var top: Rect2 = lift["rect"]
	var p: Player = gm.players[0]
	p.position = Vector2(top.get_center().x, top.position.y - Player.HALF.y)
	p.vel = Vector2.ZERO
	p.on_ground = true
	var started_at: float = p.position.y

	gm.state = Phase.EXECUTING
	gm.exec_tick = 0
	gm.exec_ticks_total = gm.exec_ticks()
	gm._reset_pilot(0)
	for tick in gm.exec_ticks():
		gm._sim_tick(gm.tick_dt())
		gm.exec_tick += 1

	var lift_now: Rect2 = lift["rect"]
	_check(p.position.y < started_at - 1.0,
		"a fighter standing on a climbing lift must be carried upward with it")
	_check(absf((p.position.y + Player.HALF.y) - lift_now.position.y) < 1.5,
		"a carried fighter must stay on the lip, neither clipped into it nor left behind")
	_check(p.on_ground, "a carried fighter must still count as grounded")
	gm.free()


# -------------------------------------------------------------------- orbs ---

func _test_orb_detonates_and_recharges() -> void:
	var gm = await _fresh_game(FOUNDRY)
	_check(not gm.hazards.is_empty(), "FOUNDRY must author pulse orbs")
	if gm.hazards.is_empty():
		gm.free()
		return
	var orb: Hazard = gm.hazards[0]
	_check(orb.charged, "orbs must begin a match loaded")

	var knife := _launch_knife(gm, orb.position + Vector2(-90.0, 0.0), Vector2(600.0, 0.0))
	gm.state = Phase.EXECUTING
	for tick in 30:
		gm._step_arrows(gm.tick_dt())
		if not orb.charged:
			break

	_check(not orb.charged, "a knife reaching a loaded orb must set it off")
	_check(not gm.arrows.has(knife), "the triggering knife must be spent on the orb")
	_check(orb.windows_left == orb.recharge_windows,
		"a spent orb must start its full recharge")

	for window in orb.recharge_windows:
		_check(not orb.charged, "an orb must stay dark for its whole recharge")
		orb.end_of_window()
	_check(orb.charged, "an orb must come back after its recharge windows elapse")
	gm.free()


func _test_blast_pushes_bodies_outward() -> void:
	var gm = await _fresh_game(FOUNDRY)
	if gm.hazards.is_empty():
		gm.free()
		return
	var orb: Hazard = gm.hazards[0]
	gm.state = Phase.EXECUTING

	var p: Player = gm.players[0]
	p.position = orb.position + Vector2(-40.0, 0.0)
	p.vel = Vector2.ZERO
	p.on_ground = true
	var bystander := _launch_knife(gm, orb.position + Vector2(0.0, -50.0), Vector2(0.0, 0.0))
	var far_knife := _launch_knife(gm,
		orb.position + Vector2(orb.blast_radius + 60.0, 0.0), Vector2(0.0, 0.0))

	gm._detonate(orb, gm.arrows)
	# Read the push out now: this manager is live in the tree, so the first
	# awaited frame below would run a real execution tick over the top of it.
	var pushed: Vector2 = p.vel

	_check(p.vel.x < -1.0, "the blast must throw a fighter away from the orb, not toward it")
	_check(not p.on_ground or p.vel.y >= 0.0,
		"a fighter thrown upward must be released from the surface underneath")
	_check(bystander.vel.y < -1.0, "a knife above the orb must be driven further up")
	_check(bystander.clashed, "a knife shoved by a pulse must read as off its aimed line")
	_check(far_knife.vel.is_zero_approx(), "the blast must stop dead at its drawn radius")

	# Determinism: the same blast on the same state must produce the same push.
	var again = await _fresh_game(FOUNDRY)
	again.state = Phase.EXECUTING
	var q: Player = again.players[0]
	q.position = again.hazards[0].position + Vector2(-40.0, 0.0)
	q.vel = Vector2.ZERO
	q.on_ground = true
	again._detonate(again.hazards[0], again.arrows)
	_check(q.vel.is_equal_approx(pushed), "the same pulse on the same state must push identically")

	again.free()
	gm.free()


# --------------------------------------------------------------- prototype ---

## The prototype arena is deliberately outside LevelLayoutTest: the rule it
## breaks on purpose is the five-vertical-tiers rule, which is exactly the
## platform-soup convention the experiment is questioning. It still has to be
## PLAYABLE, so the parts that are not up for debate are checked here.
func _test_prototype_is_playable() -> void:
	var level := Levels.build_prototype()
	var spawns: Array = level["spawns"]
	_check(spawns.size() >= 4, "the prototype arena still needs four spawn sockets")

	for tick in range(0, 260, 10):
		var rects: Array[Rect2] = []
		var moving: Array[Rect2] = []
		for platform: Dictionary in level["platforms"]:
			var rect: Rect2 = platform["rect"]
			if platform.has("motion"):
				rect = Rect2(platform["home"] + Mover.offset(platform["motion"], tick), rect.size)
				moving.append(rect)
			rects.append(rect)
		for i in spawns.size():
			_check(not _body_overlaps(spawns[i], rects),
				"prototype P%d spawn sits inside terrain at tick %d" % [i + 1, tick])
		for core in level["core_spawns"]:
			_check(not _body_overlaps(core, rects),
				"a prototype Core socket sits inside terrain at tick %d" % tick)
		for lift in moving:
			for other in rects:
				if other != lift and other.size.y < 70.0 and lift.intersects(other):
					_check(false, "the prototype lift grinds through geometry at tick %d" % tick)
					return

	for i in spawns.size():
		_check(_is_supported(spawns[i], level["platforms"]),
			"prototype P%d spawn must stand on a surface" % (i + 1))

	var gm = await _fresh_game(0)
	gm.prototype_mode = true
	_check(gm.knife_offsets(0.0).size() == 2,
		"close camera must throw its fixed knife pair at any draw")
	_check(gm.knife_offsets(1.0).size() == 2,
		"close camera must keep the fixed pair at full draw")
	gm.prototype_mode = false
	_check(gm.knife_offsets(0.5).size() == gm.knives_per_shot,
		"turning the prototype off must restore the authored fan")
	gm.free()


## Short turns only work if finishing your action readies you automatically —
## otherwise the confirm press eats the window. Rollback has to remain a real
## escape hatch, or the loop becomes a commitment you cannot take back.
func _test_short_turns_and_auto_ready() -> void:
	var gm = await _fresh_game(0)
	gm.vs_ai = false
	var authored: float = gm.planning_duration

	gm.prototype_mode = true
	gm._sync_prototype_timings()
	_check(gm.planning_duration < authored,
		"prototype mode must shorten the planning window")
	_check(gm.ai_think_max <= gm.prototype_planning_duration * 0.6,
		"the AI's deliberation must fit inside a short window")

	gm.state = Phase.PLANNING
	gm._reset_pilot(0)
	gm._reset_pilot(1)
	var p: Player = gm.players[0]
	var grace: float = gm.prototype_ready_grace

	_idle(gm, grace * 2.0)
	_check(not p.plan.confirmed,
		"a player who has not thrown yet must not be marked ready")

	gm.charging[0] = true
	gm._release_charge(0)
	_check(p.plan.has_shot(), "releasing the charge must place the shot")

	# Throwing is not the end of the turn. Piloting after the shot has to keep
	# working, so readiness cannot land on the throw itself.
	gm._auto_ready_finished_plans(0.016)
	_check(not p.plan.confirmed,
		"throwing alone must not ready a player who may still want to move")
	var before: int = p.plan.recorded_ticks()
	for i in 8:
		gm._pilot_step(0, 1, false, false)
		gm._auto_ready_finished_plans(0.016)
	_check(p.plan.recorded_ticks() > before,
		"the ghost must still accept pilot input after the shot is placed")
	_check(not p.plan.confirmed,
		"a player still driving after the throw must not be readied under them")

	# Hands off for the grace period: now the action really is finished.
	_idle(gm, grace + 0.1)
	_check(p.plan.confirmed,
		"finishing the action must mark the player ready without a confirm press")

	gm._rollback(0)
	_check(not p.plan.confirmed and not p.plan.has_shot(),
		"rollback must un-fire the shot and drop the ready state with it")
	_idle(gm, grace * 2.0)
	_check(not p.plan.confirmed,
		"auto-ready must not re-confirm a plan that was just rolled back")

	# Charging is mid-action, not a finished one.
	gm.charging[0] = true
	gm._release_charge(0)
	gm.charging[0] = true
	_idle(gm, grace * 2.0)
	_check(not p.plan.confirmed, "a player still drawing must not be readied under them")
	gm.charging[0] = false

	gm.prototype_mode = false
	gm._sync_prototype_timings()
	_check(is_equal_approx(gm.planning_duration, authored),
		"turning the prototype off must restore the authored planning window")
	_idle(gm, grace * 3.0)
	_check(not p.plan.confirmed,
		"outside prototype mode the confirm press must still be required")
	gm.free()


## Runs the auto-ready rule over `seconds` of a player doing nothing at all.
func _idle(gm, seconds: float) -> void:
	var step := 0.016
	var elapsed := 0.0
	while elapsed < seconds:
		gm._auto_ready_finished_plans(step)
		elapsed += step


func _is_supported(spawn: Vector2, platforms: Array) -> bool:
	for platform: Dictionary in platforms:
		var rect: Rect2 = platform["rect"]
		if absf(rect.position.y - (spawn.y + Player.HALF.y)) <= 0.1 \
				and spawn.x >= rect.position.x - Player.HALF.x \
				and spawn.x <= rect.end.x + Player.HALF.x:
			return true
	return false


func _body_overlaps(centre: Vector2, rects: Array[Rect2]) -> bool:
	for rect in rects:
		if absf(centre.x - rect.get_center().x) < Player.HALF.x + rect.size.x * 0.5 \
				and absf(centre.y - rect.get_center().y) < Player.HALF.y + rect.size.y * 0.5:
			return true
	return false


# ----------------------------------------------------------------- harness ---

func _fresh_game(level: int):
	var gm = GAME_MANAGER.new()
	gm.vs_ai = false
	root.add_child(gm)
	await process_frame
	gm._load_level(level)
	gm.restart()
	return gm


func _find_mover(gm) -> Dictionary:
	for pf in gm.platforms:
		if pf.has("motion") and pf["motion"].get("axis", Vector2.ZERO).y != 0.0:
			return pf
	return {}


func _launch_knife(gm, at: Vector2, vel: Vector2) -> Arrow:
	var a := Arrow.new()
	a.cfg = gm
	a.shooter = 0
	a.volley = gm._next_volley
	gm._next_volley += 1
	a.network_id = gm._next_arrow_id
	gm._next_arrow_id += 1
	a.color = Color.WHITE
	a.position = at
	a.prev_pos = at
	a.vel = vel
	gm._arrow_layer.add_child(a)
	gm.arrows.append(a)
	return a


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
