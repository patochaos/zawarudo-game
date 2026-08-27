extends SceneTree

## Moving geometry and pulse orbs. The point of every check here is that the
## kinetic arenas stay inside the design contracts the static ones already obey:
## the same state and the same plans produce the same outcome, and planning shows
## the player's real intent rather than a snapshot that execution then betrays.

const GAME_MANAGER := preload("res://scripts/GameManager.gd")
const PENDULUM := 2
const PULSE_CHAMBER := 3

var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_motion_is_a_pure_function()
	await _test_ghost_path_cache()
	await _test_preview_matches_execution()
	await _test_lift_carries_its_rider()
	await _test_orb_detonates_and_recharges()
	await _test_blast_pushes_bodies_outward()
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


func _test_ghost_path_cache() -> void:
	var gm = await _fresh_game(PENDULUM)
	gm._rebuild_ghost_paths()
	var sentinel := PackedVector2Array([Vector2(-999.0, -999.0)])
	gm.ghost_path[0] = sentinel
	gm._refresh_dirty_ghost_paths()
	_check(gm.ghost_path[0] == sentinel,
		"an unchanged planning frame must reuse its cached ghost prediction")
	gm._mark_ghost_path_dirty(0)
	gm._refresh_dirty_ghost_paths()
	_check(gm.ghost_path[0] != sentinel and gm.ghost_path[0].size() == gm.exec_ticks() + 1,
		"a dirty plan must rebuild one complete execution prediction")
	gm.free()


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
	var gm = await _fresh_game(PULSE_CHAMBER)
	_check(not gm.hazards.is_empty(), "PULSE CHAMBER must author pulse orbs")
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
	_check(gm.arrows.has(knife), "the triggering knife must survive and be relaunched by the orb")
	_check(knife.vel.x < 0.0 and is_equal_approx(knife.vel.length(), orb.dagger_launch_speed),
		"a triggering knife must fire back outward at full player-throw force")
	_check(not knife.clashed, "a pulse-relaunched knife must fly like a throw, not heavy clash debris")
	_check(orb.windows_left == orb.recharge_windows,
		"a spent orb must start its full recharge")

	for window in orb.recharge_windows:
		_check(not orb.charged, "an orb must stay dark for its whole recharge")
		orb.end_of_window()
	_check(orb.charged, "an orb must come back after its recharge windows elapse")
	gm.free()


func _test_blast_pushes_bodies_outward() -> void:
	var gm = await _fresh_game(PULSE_CHAMBER)
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
	_check(bystander.vel.y < -1.0 and is_equal_approx(
		bystander.vel.length(), orb.dagger_launch_speed),
		"a knife above the orb must be relaunched upward at full throw force")
	_check(not bystander.clashed, "pulse-launched knives must retain ordinary throw gravity")
	_check(far_knife.vel.is_zero_approx(), "the blast must stop dead at its drawn radius")

	# Determinism: the same blast on the same state must produce the same push.
	var again = await _fresh_game(PULSE_CHAMBER)
	again.state = Phase.EXECUTING
	var q: Player = again.players[0]
	q.position = again.hazards[0].position + Vector2(-40.0, 0.0)
	q.vel = Vector2.ZERO
	q.on_ground = true
	again._detonate(again.hazards[0], again.arrows)
	_check(q.vel.is_equal_approx(pushed), "the same pulse on the same state must push identically")

	again.free()
	gm.free()


# ----------------------------------------------------------------- harness ---

func _fresh_game(level: int):
	var gm = GAME_MANAGER.new()
	gm.vs_ai = false
	root.add_child(gm)
	await process_frame
	# This is a deterministic simulation suite, not an audio integration test.
	# Muting before restart avoids leaving backend-specific playback handles alive
	# when the short-lived manager is freed (Linux reports those as resource leaks).
	gm._sfx.muted = true
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
