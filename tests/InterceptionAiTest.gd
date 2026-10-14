extends SceneTree

const GAME_MANAGER := preload("res://scripts/GameManager.gd")
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_readable_objective()
	_test_visible_projectile_changes_route()
	_test_coasting_forecast_matches_replay()
	await _test_authored_crossing()
	if _failures == 0:
		print("Interception AI: all tests passed")
	quit(_failures)


func _fixture():
	var gm = GAME_MANAGER.new()
	gm.interception_mode = true
	gm.wrap_x = false
	gm.wrap_y = false
	gm.player_air_acceleration = 450.0
	gm.double_jump_enabled = false
	gm.set_difficulty(gm.Difficulty.STANDARD)
	var solids: Array[Rect2] = [Rect2(0.0, 600.0, 1280.0, 120.0)]
	var sockets: Array[Vector2] = [Vector2(640.0, 600.0 - Player.HALF.y)]
	gm.solid_rects = solids
	gm.core_spawn_points = sockets
	gm.core_position = gm.core_spawn_points[0]
	gm.core_announced = true
	for i in 2:
		var p := Player.new()
		p.cfg = gm
		p.index = i
		p.position = Vector2(400.0 if i == 0 else 880.0, 600.0 - Player.HALF.y)
		p.on_ground = true
		p.air_jumps_left = gm.air_jumps_for(i)
		gm.players.append(p)
	return gm


func _release(gm) -> void:
	for arrow in gm.arrows:
		arrow.free()
	for player in gm.players:
		player.free()
	gm.free()


func _test_readable_objective() -> void:
	var gm = _fixture()
	gm.rng.seed = 13
	var first := Ai.new()
	first.begin(gm, 1, 0)
	first.finish()
	var route: PackedVector2Array = first._best_cand["path"]
	_check(route[-1].distance_to(gm.core_position) < route[0].distance_to(gm.core_position),
		"CPU must approach the announced crossing in a safe opening")

	# Private input and the random generator must not replace that intention.
	gm.players[0].plan.record(1, true, true)
	gm.players[0].plan.shot_tick = 0
	gm.players[0].plan.power = 1.0
	gm.rng.seed = 987
	var again := Ai.new()
	again.begin(gm, 1, 0)
	again.finish()
	_check(again._best_cand["move"] == first._best_cand["move"]
		and again._best_cand["path"] == route,
		"CPU route must be independent of RNG seed and the private human plan")

	gm.core_announced = false
	gm.super_meter[1] = 1.0
	var closer := PackedVector2Array([gm.players[1].position, gm.core_position])
	var farther := PackedVector2Array([gm.players[1].position, Vector2(1080.0, route[0].y)])
	_check(first._core_value(closer) > first._core_value(farther),
		"CPU must still contest the crossing between cores and with a full meter")
	gm.players[1].position = gm.core_position + Vector2(20.0, 0.0)
	gm.players[1].vel = Vector2(-gm.player_move_speed, 0.0)
	var holding := Ai.new()
	holding.begin(gm, 1, 0)
	holding.finish()
	var held_route: PackedVector2Array = holding._best_cand["path"]
	_check(held_route[-1].distance_to(gm.core_position) < 35.0,
		"CPU must hold the crossing without sliding past it")
	gm.interception_mode = false
	_check(is_zero_approx(first._core_value(closer)) and is_zero_approx(first._core_value(farther)),
		"ordinary AI must retain its existing objective rules")
	_release(gm)


func _test_visible_projectile_changes_route() -> void:
	var gm = _fixture()
	var first := Ai.new()
	first.begin(gm, 1, 0)
	var direct: PackedVector2Array = first._walk(gm.players[1], -1, false, gm.movement_tick_budget())
	# A descending knife crosses the direct approach during this execution.
	var impact_tick := 26
	var dt: float = gm.tick_dt()
	var knife := Arrow.new()
	knife.cfg = gm
	knife.shooter = 0
	knife.position = direct[impact_tick] - Vector2(0.0, 100.0)
	knife.vel.y = (100.0 - gm.arrow_gravity * dt * dt * impact_tick * (impact_tick + 1) * 0.5) \
		/ (impact_tick * dt)
	gm.arrows.append(knife)
	gm.core_announced = false
	gm.core_active = true
	var search := Ai.new()
	search.begin(gm, 1, 0)
	var threats: Array = search._threat_paths()
	_check(search._danger(direct, threats) > 0.0,
		"fixture must place a real visible projectile on the direct objective route")
	search.finish()
	_check(search._danger(search._best_cand["path"], threats) == 0.0,
		"CPU must choose a safe alternative even when the objective is active")
	_release(gm)


func _test_coasting_forecast_matches_replay() -> void:
	var gm = _fixture()
	var search := Ai.new()
	search.begin(gm, 1, 0)
	var player: Player = gm.players[1]
	var ticks := 18
	var forecast: PackedVector2Array = search._walk(player, -1, true, ticks)
	for t in ticks:
		player.plan.record(-1, t == 0, true)
	var matches := true
	var recorded_speed := 0.0
	for t in gm.exec_ticks():
		player.sim_step(gm.tick_dt(), t, gm.world_tick + t)
		matches = matches and player.position.is_equal_approx(forecast[t + 1])
		if t == ticks - 1:
			recorded_speed = player.vel.x
	_check(matches, "AI forecast must match recorded movement and unpiloted coasting on every tick")
	_check(absf(recorded_speed) > 100.0 and is_equal_approx(player.vel.x, recorded_speed),
		"the forecast comparison must include retained horizontal momentum")
	_release(gm)


func _test_authored_crossing() -> void:
	var gm = GAME_MANAGER.new()
	root.add_child(gm)
	await process_frame
	gm.set_physics_process(false)
	gm._sfx.muted = true
	gm.start_interception()
	gm._transition.visible = false
	var cpu: Player = gm.players[1]
	var start: Vector2 = cpu.position
	var search := Ai.new()
	search.begin(gm, 1, 0)
	search.finish()
	search.apply()
	for t in gm.exec_ticks():
		cpu.sim_step(gm.tick_dt(), t, gm.world_tick + t)
	var forecast: PackedVector2Array = search._best_cand["path"]
	_check(cpu.position.is_equal_approx(forecast[-1]),
		"the authored mode must replay the CPU's chosen plan to its forecast position")
	_check(cpu.position.distance_to(gm.core_position) < start.distance_to(gm.core_position)
		and cpu.position.x <= 781.0 and cpu.position.y - Player.HALF.y >= 520.0,
		"the opening CPU plan must enter the low passage toward the announced core")

	# The upper route must also lead back to the objective below its shelf.
	cpu.position = Vector2(640.0, 500.0 - Player.HALF.y)
	cpu.vel = Vector2.ZERO
	cpu.on_ground = true
	gm._reset_pilot(1)
	gm.core_announced = false
	gm.core_active = true
	gm.super_meter[1] = 0.0
	var descending := Ai.new()
	descending.begin(gm, 1, 0)
	descending.finish()
	descending.apply()
	for t in gm.exec_ticks():
		cpu.sim_step(gm.tick_dt(), t, gm.world_tick + t)
		gm._check_core_collection()
	var descent: PackedVector2Array = descending._best_cand["path"]
	_check(cpu.plan.drop_at(0) and cpu.position.is_equal_approx(descent[-1])
		and gm.super_meter[1] >= 1.0 and not gm.core_active,
		"CPU atop the shelf must record a drop, replay its forecast, and collect the core; chose %s ending %s"
		% [descending._best_cand["move"], cpu.position])
	root.remove_child(gm)
	gm.free()
	await process_frame


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error(message)
