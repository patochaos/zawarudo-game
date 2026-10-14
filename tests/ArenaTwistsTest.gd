extends SceneTree

## The three twist rules: timed shutters (a pure function of the tick), stasis
## fields and lodestones (pure functions of position). Each must behave the
## same for execution and for the predictions a plan is built on.

const MAIN := preload("res://scenes/Main.tscn")
const GALLERY := 7
const HALL := 8
const REACH := 9
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_shutter_clock()
	await _test_shutters_in_world()
	await _test_stasis()
	await _test_lodestone()
	print("Arena twists: %d failures" % failures)
	quit(failures)


func _test_shutter_clock() -> void:
	var cycle := {"period": 210, "solid": 105, "phase": 0}
	check(Mover.cycle_solid(cycle, 0) and Mover.cycle_solid(cycle, 104)
		and not Mover.cycle_solid(cycle, 105) and not Mover.cycle_solid(cycle, 209)
		and Mover.cycle_solid(cycle, 210), "a gate is solid for the first `solid` ticks of each period")
	var left: Array = Mover.cycle_ticks_left(cycle, 100)
	check(left[0] == 5 and left[1] == 105, "the countdown reports ticks left in the current state")
	check(not Mover.cycle_solid({"period": 210, "solid": 105, "phase": 105}, 0),
		"phase shifts the clock")


func _boot(level: int):
	var game = MAIN.instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game._sfx.muted = true
	game._load_level(level)
	game.restart()
	game._transition.visible = false
	return game


func _test_shutters_in_world() -> void:
	var game = await _boot(GALLERY)
	var gate: Dictionary = {}
	for pf in game.platforms:
		if pf.has("cycle") and int(pf["cycle"]["phase"]) == 0:
			gate = pf
	check(not gate.is_empty(), "the gallery authors a gate on phase 0")
	var rect: Rect2 = gate["rect"]
	check(game.solids_at(0).has(rect) and not game.solids_at(110).has(rect),
		"an open gate leaves the collision set for the ticks it is open")
	check(game.platform_colliders_at(110).all(func(c): return c["rect"] != rect),
		"knife previews skip an open gate")

	var dt: float = game.tick_dt()
	var standing := Vector2(rect.get_center().x, rect.position.y - Player.HALF.y)
	var held: Array = Player.step_state(standing, Vector2.ZERO, true, 0, false, dt, game, 0)
	var dropped: Array = Player.step_state(standing, Vector2.ZERO, true, 0, false, dt, game, 104)
	check(held[2] and not dropped[2] and dropped[0].y > standing.y,
		"a body on a gate stays while it is solid and falls the tick it opens")

	game._apply_movers(110)
	check(not gate["present"] and gate["rects"].is_empty(),
		"execution geometry drops an open gate so live knives pass through")
	game._apply_movers(0)
	check(gate["present"] and not gate["rects"].is_empty(), "the gate returns on its clock")

	root.remove_child(game)
	game.free()
	await process_frame


func _test_stasis() -> void:
	var game = await _boot(HALL)
	var inside := Vector2(500.0, 400.0)
	check(is_equal_approx(game.time_scale_at(inside), 0.35) and is_equal_approx(game.time_scale_at(Vector2(200.0, 400.0)), 1.0),
		"time runs at the field's scale inside and normally outside")
	var dt: float = game.tick_dt()
	var slow: Array = Arrow.step_state(inside, Vector2(600.0, 0.0), dt, game)
	var fast: Array = Arrow.step_state(Vector2(200.0, 400.0), Vector2(600.0, 0.0), dt, game)
	var ratio: float = (slow[2].x - inside.x) / (fast[2].x - 200.0)
	check(ratio > 0.34 and ratio < 0.36, "a knife inside the field covers about 35 percent of the distance")
	var airborne: Array = Player.step_state(inside, Vector2.ZERO, false, 0, false, dt, game, 0)
	var falling: Array = Player.step_state(Vector2(200.0, 400.0), Vector2.ZERO, false, 0, false, dt, game, 0)
	check(airborne[1].y < falling[1].y and airborne[1].y > 0.0, "a body in the field falls slower")

	await _check_prediction_matches_runtime(game, Vector2(330.0, 330.0), Vector2(650.0, 0.0),
		"stasis")
	root.remove_child(game)
	game.free()
	await process_frame


func _test_lodestone() -> void:
	var game = await _boot(REACH)
	var pylon: Vector2 = game.lodestones[0]["at"]
	var pull: Vector2 = game.knife_pull_at(pylon + Vector2(100.0, 0.0))
	check(pull.x < 0.0 and is_zero_approx(pull.y) and is_equal_approx(pull.length(), 1800.0 * (1.0 - 100.0 / 210.0)),
		"the pull points at the pylon with linear falloff")
	check(game.knife_pull_at(pylon + Vector2(0.0, -300.0)) == Vector2.ZERO, "nothing beyond the rim")

	var dt: float = game.tick_dt()
	var start := Vector2(150.0, 200.0)
	var launch := Vector2(620.0, 0.0)
	var bent := _closest_approach(game, start, launch, 40, dt, pylon)
	var stones: Array = game.lodestones
	game.lodestones = []
	var straight := _closest_approach(game, start, launch, 40, dt, pylon)
	game.lodestones = stones
	check(bent < straight - 10.0, "a knife passing the pylon curls toward it (%0.0f vs %0.0f)" % [bent, straight])

	await _check_prediction_matches_runtime(game, start, launch, "lodestone", 40)
	root.remove_child(game)
	game.free()
	await process_frame


func _closest_approach(game, pos: Vector2, vel: Vector2, ticks: int, dt: float, to: Vector2) -> float:
	var nearest := INF
	for t in ticks:
		var st: Array = Arrow.step_state(pos, vel, dt, game)
		pos = st[2]
		vel = st[1]
		nearest = minf(nearest, pos.distance_to(to))
	return nearest


## The known-path preview and a live knife must agree tick for tick, or a
## trap the player read on the board is not the trap that lands.
func _check_prediction_matches_runtime(game, start: Vector2, launch: Vector2, label: String,
		ticks: int = 60) -> void:
	var dt: float = game.tick_dt()
	var predicted: Dictionary = PredictionSystem.predict_arrow(start, launch, game, float(ticks) * dt, game.world_tick)
	var knife := Arrow.new()
	knife.cfg = game
	knife.position = start
	knife.vel = launch
	knife.shooter = -1
	game._arrow_layer.add_child(knife)
	var alive := true
	for t in ticks:
		var result: Dictionary = knife.sim_step(dt, [])
		if not result["alive"]:
			alive = false
			break
	var path: PackedVector2Array = predicted["path"]
	check(alive and not predicted["blocked"] and path.size() == ticks + 1
		and path[ticks].distance_to(knife.position) < 0.01,
		"%s: the knife preview must match the live knife (%s vs %s)" % [label, path[path.size() - 1], knife.position])
	knife.queue_free()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
