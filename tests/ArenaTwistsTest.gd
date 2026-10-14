extends SceneTree

## The twist rules: timed shutters (a pure function of the tick) and stasis
## fields (a pure function of position). Each must behave the same for
## execution and for the predictions a plan is built on.

const MAIN := preload("res://scenes/Main.tscn")
const GALLERY := 1
const HALL := 2
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_shutter_clock()
	await _test_shutters_in_world()
	await _test_stasis()
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
