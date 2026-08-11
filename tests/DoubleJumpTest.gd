extends SceneTree

const GAME_MANAGER := preload("res://scripts/GameManager.gd")

var _failures: int = 0


func _init() -> void:
	_test_live_double_jump()
	_test_planned_double_jump()
	_test_drop_through_thin_ledges()
	_test_thick_ground_is_not_a_door()
	_test_planned_drop_replays()
	_test_drop_lands_on_the_next_ledge_down()
	_test_drop_clears_a_thick_ledge()
	if _failures == 0:
		print("Double jump: all tests passed")
	else:
		push_error("Double jump: %d test(s) failed" % _failures)
	quit(_failures)


func _test_live_double_jump() -> void:
	var gm = GAME_MANAGER.new()
	var no_solids: Array[Rect2] = []
	gm.solid_rects = no_solids
	var p := Player.new()
	p.cfg = gm
	p.on_ground = true
	var dt := gm.tick_dt()

	p.sim_free(dt, 0, true, true)
	_check(not p.on_ground and p.air_jumps_left == 1,
		"the ground jump must preserve one mid-air jump")
	p.sim_free(dt, 0, false, false)
	p.sim_free(dt, 0, true, true)
	_check(p.air_jumps_left == 0 and p.vel.y < -gm.jump_impulse * 0.9,
		"the second press must reset upward speed and spend the air jump")
	p.sim_free(dt, 0, false, false)
	p.sim_free(dt, 0, true, true)
	_check(p.air_jumps_left == 0 and p.vel.y > -gm.jump_impulse * 0.8,
		"a third press before landing must not add another impulse")

	var floor_rects: Array[Rect2] = [Rect2(-100.0, 100.0, 200.0, 20.0)]
	gm.solid_rects = floor_rects
	p.position = Vector2(0.0, 50.0)
	p.vel = Vector2(0.0, 300.0)
	p.on_ground = false
	p.air_jumps_left = 0
	for tick in 30:
		p.sim_free(dt, 0, false, false)
		if p.on_ground:
			break
	_check(p.on_ground and p.air_jumps_left == Player.MAX_AIR_JUMPS,
		"landing must restore the mid-air jump")

	p.free()
	gm.free()


func _test_planned_double_jump() -> void:
	var gm = GAME_MANAGER.new()
	var no_solids: Array[Rect2] = []
	gm.solid_rects = no_solids
	var p := Player.new()
	p.cfg = gm
	p.on_ground = true
	gm.players = [p]
	gm._jump_prev[0] = true
	gm._reset_pilot(0)
	_check(not gm._jump_prev[0],
		"a new planning phase must discard a stale jump edge when no button is held")

	_check(gm._pilot_step(0, 0, true, true), "the ground jump tick must record")
	_check(gm._pilot_step(0, 0, false, false), "the release tick must record")
	_check(gm._pilot_step(0, 0, true, true), "the air-jump tick must record")
	_check(p.plan.jump_at(0) and p.plan.jump_at(2),
		"the plan must preserve both jump impulses on their exact ticks")
	_check(gm.ghost_air_jumps[0] == 0, "the planning ghost must spend its air jump")
	gm._pilot_step(0, 0, false, false)
	gm._pilot_step(0, 0, true, true)
	_check(not p.plan.jump_at(4), "the planning ghost must reject a third airborne jump")

	p.position = Vector2.ZERO
	p.vel = Vector2.ZERO
	p.on_ground = true
	p.air_jumps_left = Player.MAX_AIR_JUMPS
	for tick in 3:
		p.sim_step(gm.tick_dt(), tick)
	_check(p.air_jumps_left == 0 and p.vel.y < -gm.jump_impulse * 0.9,
		"execution must replay the recorded air jump exactly")

	p.free()
	gm.free()


## A thin ledge is a door you go down through; a fat one is a floor.
func _test_drop_through_thin_ledges() -> void:
	var gm = GAME_MANAGER.new()
	var ledge := Rect2(-100.0, 100.0, 200.0, 16.0)
	var below := Rect2(-100.0, 400.0, 200.0, 100.0)
	var rects: Array[Rect2] = [ledge, below]
	gm.solid_rects = rects
	var p := Player.new()
	p.cfg = gm
	p.position = Vector2(0.0, ledge.position.y - Player.HALF.y)
	p.on_ground = true
	var dt := gm.tick_dt()

	# Standing still on the ledge stays standing still on the ledge.
	for tick in 20:
		p.sim_free(dt, 0, false, false)
	_check(p.on_ground and is_equal_approx(p.position.y, ledge.position.y - Player.HALF.y),
		"a thin ledge must hold a body that has not asked to leave it")

	p.sim_free(dt, 0, false, false, true)
	_check(not p.on_ground and p.vel.y > 0.0,
		"down+jump must release the body downward, not launch it")
	for tick in 40:
		p.sim_free(dt, 0, false, false)
		if p.on_ground:
			break
	_check(p.position.y > ledge.end.y,
		"the drop must actually pass through the ledge instead of catching on it")
	_check(p.on_ground and is_equal_approx(p.position.y, below.position.y - Player.HALF.y),
		"a drop must land the body on the next surface down")

	# Collision has to come back, or every later ledge would be a hole.
	p.position = Vector2(0.0, ledge.position.y - Player.HALF.y - 120.0)
	p.vel = Vector2.ZERO
	p.on_ground = false
	for tick in 60:
		p.sim_free(dt, 0, false, false)
		if p.on_ground:
			break
	_check(p.on_ground and is_equal_approx(p.position.y, ledge.position.y - Player.HALF.y),
		"the ledge must be solid again once the drop has expired")
	p.free()
	gm.free()


func _test_thick_ground_is_not_a_door() -> void:
	var gm = GAME_MANAGER.new()
	var floor_rects: Array[Rect2] = [Rect2(-200.0, 300.0, 400.0, 100.0)]
	gm.solid_rects = floor_rects
	var p := Player.new()
	p.cfg = gm
	p.position = Vector2(0.0, 300.0 - Player.HALF.y)
	p.on_ground = true
	var landed: float = p.position.y

	p.sim_free(gm.tick_dt(), 0, false, false, true)
	for tick in 30:
		p.sim_free(gm.tick_dt(), 0, false, false)
	_check(p.on_ground and is_equal_approx(p.position.y, landed),
		"asking to drop through solid ground must leave the body exactly where it was")
	p.free()
	gm.free()


## The drop is part of the recording, so the ghost and the executed body have to
## end in the same place — the same contract every other input obeys.
func _test_planned_drop_replays() -> void:
	var gm = GAME_MANAGER.new()
	var rects: Array[Rect2] = [Rect2(-100.0, 100.0, 200.0, 16.0), Rect2(-100.0, 400.0, 200.0, 100.0)]
	gm.solid_rects = rects
	var p := Player.new()
	p.cfg = gm
	p.position = Vector2(0.0, 100.0 - Player.HALF.y)
	p.on_ground = true
	gm.players = [p]
	gm._reset_pilot(0)

	_check(gm._pilot_step(0, 0, false, false, true), "the drop tick must record")
	_check(p.plan.drop_at(0), "the plan must remember the drop on its exact tick")
	_check(not p.plan.jump_at(0), "a drop tick must never also read as a jump")
	for tick in 12:
		gm._pilot_step(0, 0, false, false)
	gm._rebuild_ghost_paths()
	var promised: PackedVector2Array = gm.ghost_path[0]

	for tick in gm.exec_ticks():
		p.sim_step(gm.tick_dt(), tick)
	_check(promised[promised.size() - 1].distance_to(p.position) < 0.001,
		"a planned drop must execute exactly where the ghost promised")
	_check(p.position.y > 116.0, "the executed drop must end below the ledge it left")
	p.free()
	gm.free()


## One level down, not all of them. A timer-only immunity would carry the body
## straight through a ledge sitting inside the drop's fall distance.
func _test_drop_lands_on_the_next_ledge_down() -> void:
	var gm = GAME_MANAGER.new()
	var upper := Rect2(-100.0, 300.0, 200.0, 16.0)
	var lower := Rect2(-100.0, 375.0, 200.0, 16.0)     # only 75px below
	var rects: Array[Rect2] = [upper, lower, Rect2(-100.0, 600.0, 200.0, 100.0)]
	gm.solid_rects = rects
	var p := Player.new()
	p.cfg = gm
	p.position = Vector2(0.0, upper.position.y - Player.HALF.y)
	p.on_ground = true

	p.sim_free(gm.tick_dt(), 0, false, false, true)
	for tick in 60:
		p.sim_free(gm.tick_dt(), 0, false, false)
		if p.on_ground:
			break
	_check(p.on_ground and is_equal_approx(p.position.y, lower.position.y - Player.HALF.y),
		"a drop must stop on the very next ledge down, not fall past it")
	p.free()
	gm.free()


## The body is 48px tall, so clearing a ledge means travelling its thickness
## plus a whole body before collision may resume.
func _test_drop_clears_a_thick_ledge() -> void:
	var gm = GAME_MANAGER.new()
	var bridge := Rect2(-200.0, 500.0, 400.0, 26.0)
	var rects: Array[Rect2] = [bridge, Rect2(-200.0, 620.0, 400.0, 100.0)]
	gm.solid_rects = rects
	var p := Player.new()
	p.cfg = gm
	p.position = Vector2(0.0, bridge.position.y - Player.HALF.y)
	p.on_ground = true

	p.sim_free(gm.tick_dt(), 0, false, false, true)
	for tick in 60:
		p.sim_free(gm.tick_dt(), 0, false, false)
		if p.on_ground:
			break
	_check(p.position.y > bridge.end.y,
		"the drop must fully clear a ledge as thick as the arena bridges")
	_check(p.on_ground and is_equal_approx(p.position.y, 620.0 - Player.HALF.y),
		"clearing a bridge must land the body on the floor beneath it")
	p.free()
	gm.free()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
