extends SceneTree

const GAME_MANAGER := preload("res://scripts/GameManager.gd")
var failures := 0


func _init() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func run() -> void:
	var game = GAME_MANAGER.new()
	game.offline_tuning_path = ""
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game._sfx.muted = true
	# Ladder progress is saved on a demo win; keep it off the player's settings.
	game.settings_path = "user://test-interceptionmodetest-settings.cfg"
	game._settings["ladder_progress"] = 0
	game._settings["telemetry"] = false
	game._apply_setting("telemetry")
	game._transition.visible = false
	# A saved local profile must survive a visit to the fixed experiment.
	game.offline_tuning.set_value("player_move_speed", 310.0)
	game.offline_tuning.set_value("player_air_acceleration", 1200.0)
	game.offline_tuning.set_value("jump_duration_scale", 1.4)
	game.offline_tuning.set_value("knives_per_shot", 3)
	game._menu._row_buttons[game._menu.ROW_INTERCEPTION].pressed.emit()
	game._transition.visible = false
	check(game.interception_mode and game.state == Phase.PLANNING,
		"main-menu Interception must directly launch the planner")
	check(game.level_name == "INTERCEPTION COURT" and game.players.size() == 2
		and game.is_ai(1) and not game.is_ai(0) and game.hides_plan(1),
		"Interception must be a two-Duelist duel with a hidden CPU plan")
	check(not game.wrap_x and not game.wrap_y and game.hazards.is_empty(),
		"the focused court must have closed boundaries and no pulse hazards")
	check(game.hits_to_win == 3 and game.player_difficulty(1) == game.Difficulty.STANDARD,
		"the test must use first to three against a Standard CPU")
	check(game.player_move_speed == 260.0 and game.player_air_acceleration == 450.0
		and game.air_jumps_for(0) == 0 and game.air_jumps_for(1) == 0
		and game.jump_impulse_for(0) == 780.0 and game.movement_gravity() == 1400.0,
		"fixed test movement must override the local profile only for this mode")
	check(game.planning_time_left == 8.0 and game.execution_duration == 0.75
		and game.movement_budget == 0.5 and game.knives_per_shot == 2,
		"Interception must retain the authored turn timing and knife pair")
	check(game.core_announced and not game.core_active
		and game.core_position == game.core_spawn_points[0],
		"the central objective must be announced from the first plan")

	# A real complete turn must agree with its preview and brake the ground run
	# before the next planning phase. No extra WAIT recording is required.
	for tick in game.movement_tick_budget():
		game._pilot_step(0, 1, false, false)
	game._rebuild_ghost_paths()
	var forecast: PackedVector2Array = game.ghost_path[0].duplicate()
	game._begin_execution()
	var agrees := true
	while game.exec_tick < game.exec_ticks_total:
		game._sim_tick(game.tick_dt())
		agrees = agrees and game.players[0].position.is_equal_approx(forecast[game.exec_tick + 1])
		game.exec_tick += 1
	game._end_execution()
	check(agrees and game.state == Phase.PLANNING and game.turn == 2,
		"the full execution must match its ghost on every tick and return to planning")
	var stopping_distance: float = game.players[0].position.x - forecast[game.movement_tick_budget()].x
	check(is_zero_approx(game.players[0].vel.x) and stopping_distance <= 20.0,
		"walking must stop within 20px after recorded movement ends")
	print("Interception ground stopping: %.1f px after recorded movement" % stopping_distance)
	check(game.core_active and not game.core_announced,
		"the opening announcement must become collectible for turn two")
	check(game.ghost_path[0][-1].is_equal_approx(game.players[0].position),
		"an empty next plan must keep the stopped walker in place")
	game.players[0].position = game.core_position
	game._check_core_collection()
	check(game.super_meter[0] == 1.0 and not game.core_active,
		"reaching the objective must award the ordinary super resource")

	_test_recorded_brake(game)
	_test_single_jump_and_air_steering(game)
	_test_landing_brakes(game)

	game.state = Phase.GAME_OVER
	game.winner = 0
	game._ui.refresh()
	check(not game._ui._arena_next_button.visible and not game._ui._arena_previous_button.visible,
		"the result screen must keep rematches in the dedicated arena")
	game._touch_controls.context = game._touch_controls.Context.GAME_OVER
	check(game._touch_controls._action_at(game._touch_controls.LEVEL_NEXT_RECT.get_center()).is_empty(),
		"touch results must also hide arena selection in the fixed mode")
	game._cycle_rematch_level(1)
	check(game.rematch_level_name == "INTERCEPTION COURT", "keyboard arena cycling must also stay locked")
	game._request_rematch()
	game._transition.visible = false
	check(game.interception_mode and game.level_name == "INTERCEPTION COURT"
		and game.core_announced and game.turn == 1 and game.score[0] == 0,
		"rematch must reset the duel and early objective while retaining its rules")

	game._open_menu()
	check(not game.interception_mode and game.player_air_acceleration == 1200.0
		and game.player_move_speed == 310.0 and game.double_jump_enabled
		and is_equal_approx(game.jump_duration_scale, 1.4) and game.knives_per_shot == 3,
		"leaving Interception must restore the saved offline profile")
	game.offline_tuning.reset_all()
	game.start_demo_duel()
	check(not game.interception_mode and game.level_name == "CROSSHAIR COURT"
		and game.air_jumps_for(0) == 1 and game.player_air_acceleration == 900.0,
		"Start Duel must still use its ordinary arena and movement")
	for tick in game.movement_tick_budget():
		game.players[0].plan.record(-1, false, false)
	for tick in game.exec_ticks():
		game.players[0].sim_step(game.tick_dt(), tick)
	check(is_zero_approx(game.players[0].vel.x),
		"ordinary modes must retain their existing neutral-input braking")
	game.free()
	await process_frame
	print("Interception mode: %d failures" % failures)
	quit(failures)


func _test_recorded_brake(game) -> void:
	game.restart()
	for tick in game.movement_tick_budget():
		game._pilot_step(0, 1 if tick < 18 else 0, false, false)
	game._rebuild_ghost_paths()
	var forecast: Vector2 = game.ghost_path[0][-1]
	for tick in game.exec_ticks():
		game.players[0].sim_step(game.tick_dt(), tick, tick)
	check(game.players[0].position.is_equal_approx(forecast) and is_zero_approx(game.players[0].vel.x),
		"recorded WAIT must brake intentionally and match the preview")


func _test_single_jump_and_air_steering(game) -> void:
	game.restart()
	# A late takeoff exercises the unpiloted rising arc, then the subsequent
	# freeze. A fresh jump press while airborne must not provide another impulse.
	for tick in game.movement_tick_budget():
		game._pilot_step(0, 0, tick == 24, true)
	game._rebuild_ghost_paths()
	var forecast: PackedVector2Array = game.ghost_path[0].duplicate()
	var agrees := true
	for tick in game.exec_ticks():
		game.players[0].sim_step(game.tick_dt(), tick, tick)
		agrees = agrees and game.players[0].position.is_equal_approx(forecast[tick + 1])
	var player: Player = game.players[0]
	check(agrees and player.vel.y < -280.0,
		"ending control must preserve the rising jump without inserting an early jump cut")
	game._reset_pilot(0)
	game._pilot_step(0, 0, true, true)
	check(not player.plan.jump_at(0) and game.ghost_air_jumps[0] == 0,
		"the next freeze must not grant an airborne jump")
	player.position = Vector2(400, 200)
	player.vel = Vector2(260, 0)
	player.on_ground = false
	player.plan.clear_path()
	for tick in game.movement_tick_budget():
		player.plan.record(-1, false, false)
	for tick in game.movement_tick_budget():
		player.sim_step(game.tick_dt(), tick)
	check(is_equal_approx(player.vel.x, 35.0),
		"half a second of reverse steering must leave some forward speed in the air")


func _test_landing_brakes(game) -> void:
	game.restart()
	var player: Player = game.players[0]
	player.position = Vector2(400, 548)
	player.vel = Vector2(260, 300)
	player.on_ground = false
	game._reset_pilot(0)
	game._rebuild_ghost_paths()
	var forecast: PackedVector2Array = game.ghost_path[0].duplicate()
	var landing_x := -1.0
	var agrees := true
	var kept_air_speed := true
	for tick in game.exec_ticks():
		player.sim_step(game.tick_dt(), tick, tick)
		agrees = agrees and player.position.is_equal_approx(forecast[tick + 1])
		if landing_x < 0.0:
			kept_air_speed = kept_air_speed and is_equal_approx(player.vel.x, 260.0)
			if player.on_ground:
				landing_x = player.position.x
	check(agrees and kept_air_speed and landing_x > 0.0,
		"unpiloted flight must retain speed until landing and match the ghost on every tick")
	check(player.on_ground and is_zero_approx(player.vel.x) and player.position.x - landing_x <= 20.0,
		"landing must brake within 20px without requiring recorded input")
