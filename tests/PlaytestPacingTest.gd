extends SceneTree

## October 2026 playtest: dealt spawns, slowed execution, kill beat, UNDO.

const MAIN_SCENE := preload("res://scenes/Main.tscn")
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game._transition.visible = false
	_test_dealt_spawns(game)
	_test_pacing(game)
	_test_undo(game)
	root.remove_child(game)
	game.free()
	await process_frame
	if failures == 0:
		print("Playtest pacing: all tests passed")
	quit(failures)


func _test_dealt_spawns(game) -> void:
	# One human against one CPU always opens on the authored left socket.
	for attempt in 6:
		game.start_quick_match(true, 3, 2)
		_check(game.players[0].position == Levels.build(3, 2)["spawns"][0]
			and game.players[0].position.x < game.players[1].position.x,
			"vs CPU the human must always open on the left")
	var openings := {}
	for attempt in 12:
		game.start_quick_match(false, 0, 2)
		var a: Vector2 = game.players[0].position
		var b: Vector2 = game.players[1].position
		openings[a] = true
		_check(game.wrapped_distance(a, b) >= game.SPAWN_MIN_GAP_DUEL,
			"dealt duel spawns must keep rivals apart")
	_check(openings.size() > 1, "P1 must not always open on the same socket")
	# Online peers share the seed, so they must deal the same opening.
	game.rng.seed = 77
	game._load_level(3)
	var first: Array = game.spawns.duplicate()
	game.rng.seed = 77
	game._load_level(3)
	_check(game.spawns == first, "the deal must be deterministic for a shared seed")
	for i in 2:
		for orb in game.hazards:
			_check(game.spawns[i].distance_to(orb.home) > orb.blast_radius + Player.HALF.length(),
				"dealt spawns must start outside orb blasts")
	game.randomize_spawns = false
	game._load_level(0)
	_check(game.spawns[0] == Levels.build(0, 2)["spawns"][0], "the deal can be switched off")
	game.randomize_spawns = true


func _test_pacing(game) -> void:
	game.start_quick_match(true, 0, 2)
	_check(is_equal_approx(game.presentation_time_scale(), 1.0), "planning runs at full speed")
	game._begin_execution()
	_check(is_equal_approx(game.presentation_time_scale(), game.execution_playback_speed),
		"moving time is slowed for readability")
	game._on_player_hit(1, game.players[1].position, 0)
	_check(is_equal_approx(game.presentation_time_scale(), game.kill_playback_speed)
		and game._camera.enabled and game._camera.is_focusing(),
		"a kill slows further and pushes the camera in")
	# After the beat, playback eases back up instead of snapping to full pace.
	game._kill_slowmo_left = 0.001
	game._physics_process(game.tick_dt())
	var easing: float = game.presentation_time_scale()
	_check(easing > game.kill_playback_speed - 0.001 and easing < game.execution_playback_speed,
		"play must resume gradually after the kill beat")
	game._begin_kill_beat(game.players[1].position)
	# A kill late in the window holds the last frame until its beat has played.
	game.exec_tick = game.exec_ticks_total
	game._physics_process(game.tick_dt())
	_check(game.state == Phase.EXECUTING, "the window must not end mid kill beat")
	for step in 400:
		if game.state != Phase.EXECUTING:
			break
		game._physics_process(game.tick_dt())
	_check(game.state != Phase.EXECUTING, "the beat must end and planning resume")
	game._process(0.016)
	_check(is_equal_approx(Engine.time_scale, 1.0), "time scale must return to normal")


func _test_undo(game) -> void:
	game.start_quick_match(true, 0, 2)
	game.charging[0] = true
	game._release_charge(0)
	game._rollback(0)
	_check(not game.players[0].plan.has_shot() and game.banner_text.contains("THROW UNDONE"),
		"UNDO must clear the throw and say so")
	game.charging[0] = true
	game._release_charge(0)
	game.online_mode = true
	game.online_player = 0
	game._online_plan_sent = true
	game._rollback(0)
	_check(game.players[0].plan.has_shot() and game.banner_text.contains("ALREADY SENT"),
		"UNDO must not edit a plan the server already has")
	game.online_mode = false
	game._online_plan_sent = false


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
