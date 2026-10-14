extends SceneTree

const GAME_MANAGER := preload("res://scripts/GameManager.gd")
const TUNING := preload("res://scripts/OfflineTuning.gd")
const MAIN_SCENE := preload("res://scenes/Main.tscn")
const TEST_PATH := "user://offline_tuning_test.cfg"
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_persistence_and_validation()
	_test_presets()
	_test_simulation()
	await _test_menu_and_online_boundary()
	if _failures == 0:
		print("Offline tuning: all tests passed")
	else:
		push_error("Offline tuning: %d test(s) failed" % _failures)
	quit(_failures)


func _test_persistence_and_validation() -> void:
	var config := ConfigFile.new()
	config.set_value("offline", "knives_per_shot", 99)
	config.set_value("offline", "arrow_speed_min", 1000.0)
	config.set_value("offline", "arrow_speed_max", 400.0)
	config.set_value("offline", "gravity", "invalid")
	config.set_value("offline", "online_mode", true)
	_check(config.save(TEST_PATH) == OK, "test tuning fixture must save")
	var game = GAME_MANAGER.new()
	var tuning = TUNING.new()
	tuning.initialize(game, TEST_PATH)
	_check(game.knives_per_shot == 3 and game.arrow_speed_min <= game.arrow_speed_max,
		"saved counts and inverted speed ranges must be normalized")
	_check(game.gravity == 1400.0 and not game.online_mode,
		"malformed values and unknown properties must not affect the game")
	_check(not tuning.set_value("gravity", NAN) and not tuning.set_value("gravity", "fast"),
		"non-finite and nonnumeric settings must be rejected")
	tuning.set_value("arrow_max_ticks", 2.5)
	tuning.set_value("planning_duration", 2.0)
	tuning.set_value("execution_duration", 0.3)
	tuning.set_value("double_jump_enabled", false)
	_check(game.arrow_max_ticks == 150 and game.minimum_planning_duration == 2.0 \
		and game.movement_budget <= game.execution_duration,
		"seconds must convert to ticks and dependent timings must stay valid")
	var restored_game = GAME_MANAGER.new()
	var restored = TUNING.new()
	restored.initialize(restored_game, TEST_PATH)
	_check(restored.get_value("arrow_max_ticks") == 2.5 \
		and restored_game.knives_per_shot == 3 and not restored_game.double_jump_enabled,
		"new game sessions must load numeric and boolean tuning")
	restored.reset_group("Projectiles")
	_check(restored_game.knives_per_shot == 2 and restored_game.arrow_max_ticks == 900 \
		and not restored_game.double_jump_enabled,
		"category reset must leave other categories alone")
	restored.reset_all()
	_check(restored.modified_count() == 0 and restored_game.double_jump_enabled,
		"reset all must restore every authored value")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	game.free()
	restored_game.free()


func _test_presets() -> void:
	var game = GAME_MANAGER.new()
	var tuning = TUNING.new()
	tuning.initialize(game, "")
	var changes := [0]
	tuning.changed.connect(func(): changes[0] += 1)
	for preset: Dictionary in tuning.PRESETS:
		# A preset must reset even the knobs that its own overrides do not name.
		tuning.set_value("gravity", 4000.0)
		tuning.set_value("real_time_throw_cooldown", 4.0)
		var before: int = changes[0]
		_check(tuning.apply_preset(preset.id), "preset must apply: " + preset.id)
		_check(changes[0] == before + 1, "a whole preset must publish one change")
		_check(game.gravity == 1400.0 and game.real_time_throw_cooldown == 1.2,
			"presets must discard unrelated custom values")
		_check(tuning.matching_preset_id() == preset.id, "active preset must match all values")
		for key: String in preset["values"]:
			var wanted: Variant = preset["values"][key]
			var actual: Variant = tuning.get_value(key)
			_check(actual == wanted if wanted is bool else is_equal_approx(float(actual), float(wanted)),
				"preset value must survive validation: " + preset.id + "/" + key)
		_check(game.movement_budget < game.execution_duration \
			and game.aim_preview_duration < game.execution_duration,
			"presets must leave an unpiloted tail and an incomplete aiming guide")
		_check((game.super_waves - 1) * game.super_wave_interval_ticks < game.exec_ticks(),
			"preset super volleys must fit the action window")
		_check(game.knife_launch_velocities(Vector2.RIGHT, 1.0).size() == game.knives_per_shot,
			"preset knife count must reach real launch generation")
	tuning.apply_preset("crossfire")
	tuning.apply_preset("tactical_duel")
	_check(game.knives_per_shot == 2 and game.knife_spread_max == 26.0 \
		and game.super_waves == 5 and is_equal_approx(game.arrow_drag, 0.45),
		"switching presets must remove the previous preset's overrides")
	_check(game.player_move_speed / game.player_air_acceleration < game.movement_budget,
		"Tactical duel must let a full-speed fighter brake within the movement budget")
	var stable: Dictionary = tuning._values.duplicate()
	_check(not tuning.apply_preset("missing") and tuning._values == stable,
		"unknown preset IDs must leave the current profile intact")
	game.state = Phase.ONLINE_LOBBY
	_check(not tuning.apply_preset("crossfire") and tuning._values == stable,
		"lobby must reject preset changes")
	game.state = Phase.PLANNING
	game.online_mode = true
	_check(not tuning.apply_preset("clear_read") and tuning._values == stable,
		"online matches must reject preset changes")
	game.online_mode = false
	tuning._path = TEST_PATH
	tuning.apply_preset("tactical_duel")
	var restored_game = GAME_MANAGER.new()
	var restored = TUNING.new()
	restored.initialize(restored_game, TEST_PATH)
	_check(restored.matching_preset_id() == "tactical_duel" \
		and restored_game.planning_duration == 10.0 and restored_game.arrow_max_ticks == 540,
		"saved presets must retain their identity and convert lifetime seconds to ticks")
	restored.set_value("knives_per_shot", 3)
	_check(restored.matching_preset_id().is_empty() and restored.profile_name() == "Custom tuning",
		"editing a preset must mark the profile custom")
	restored.reset_all()
	_check(restored.matching_preset_id().is_empty() and restored.profile_name() == "Standard rules",
		"reset all must restore authored defaults")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	restored_game.free()
	game.free()


func _test_simulation() -> void:
	var game = GAME_MANAGER.new()
	var tuning = TUNING.new()
	tuning.initialize(game, "")
	var floor_rects: Array[Rect2] = [Rect2(-1000, 500, 2000, 100)]
	game.solid_rects = floor_rects
	game.world_bounds = Rect2(-10000, -10000, 20000, 20000)
	var player := Player.new()
	player.cfg = game
	game.players = [player]
	var normal := _jump_flight(player, game)
	tuning.set_value("jump_duration_scale", 1.5)
	var stretched := _jump_flight(player, game)
	_check(stretched.x > normal.x * 1.4 and absf(stretched.y - normal.y) < 6.0,
		"jump duration must extend actual air time while preserving height")
	tuning.set_value("double_jump_enabled", false)
	player.position = Vector2(0, 476)
	player.on_ground = true
	player.vel = Vector2.ZERO
	player.sim_free(game.tick_dt(), 0, true, true)
	player.sim_free(game.tick_dt(), 0, false, true)
	var before := player.vel.y
	player.sim_free(game.tick_dt(), 0, true, true)
	_check(player.air_jumps_left == 0 and player.vel.y > before,
		"turning double jump off must block a second jump in flight")
	player.position = Vector2(0, 476)
	player.vel = Vector2.ZERO
	player.on_ground = true
	game._reset_pilot(0)
	game._pilot_step(0, 1, true, true)
	for tick in 15:
		game._pilot_step(0, 1, false, true)
	game._rebuild_ghost_paths()
	var predicted: Vector2 = game.ghost_path[0][-1]
	for tick in game.exec_ticks():
		player.sim_step(game.tick_dt(), tick)
	_check(player.position.distance_to(predicted) < 0.001,
		"modified jump physics must match the recorded ghost")
	tuning.set_value("knives_per_shot", 3)
	tuning.set_value("arrow_speed_max", 1000.0)
	var launches: Array = game.knife_launch_velocities(Vector2.RIGHT, 1.0)
	_check(launches.size() == 3 and is_equal_approx(launches[0].length(), 1000.0),
		"the throw must use the selected count and speed")
	tuning.set_value("arrow_max_ticks", 0.25)
	var arrow := Arrow.new()
	arrow.cfg = game
	arrow.position = Vector2.ZERO
	arrow.vel = Vector2.RIGHT * 100.0
	var result: Dictionary
	for tick in 16:
		result = arrow.sim_step(game.tick_dt(), [])
	_check(not result.alive, "knife lifetime must expire in actual simulation")
	var preview = preload("res://scripts/PreviewLayer.gd").new()
	preview.gm = game
	var expired_path: PackedVector2Array = preview._dagger_trajectory_path(Vector2.ZERO, Vector2.RIGHT * 100)
	_check(expired_path.size() == 16, "the aiming guide must stop at the knife's lifetime")
	tuning.set_value("arrow_max_ticks", 15.0)
	tuning.set_value("aim_preview_duration", 0.2)
	var short_path: PackedVector2Array = preview._dagger_trajectory_path(Vector2.ZERO, Vector2.RIGHT * 100)
	tuning.set_value("aim_preview_duration", 0.8)
	var long_path: PackedVector2Array = preview._dagger_trajectory_path(Vector2.ZERO, Vector2.RIGHT * 100)
	_check(short_path.size() == 13 and long_path.size() == 49,
		"the aiming guide must use the selected path duration")
	preview.free()
	arrow.free()
	player.free()
	game.free()


func _jump_flight(player: Player, game) -> Vector2:
	player.position = Vector2(0, 476)
	player.vel = Vector2.ZERO
	player.on_ground = true
	var top := player.position.y
	var ticks := 0
	for tick in 300:
		player.sim_free(game.tick_dt(), 0, tick == 0, true)
		top = minf(top, player.position.y)
		ticks += 1
		if player.on_ground:
			break
	return Vector2(ticks, 476 - top)


func _test_menu_and_online_boundary() -> void:
	var game = MAIN_SCENE.instantiate()
	game.offline_tuning_path = ""
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game._transition.visible = false
	game._menu._activate(game._menu.ROW_TUNING)
	var panel = game._offline_tuning_layer
	_check(panel != null, "game startup must create the tuning editor")
	if panel == null:
		game.free()
		return
	_check(panel.visible and not game._menu.visible, "main menu must open the tuning editor")
	_check(panel._group == panel.PRESET_GROUP and panel._preset_buttons.size() == 4,
		"tuning must open with four comparable presets")
	panel._preset_buttons["tactical_duel"].pressed.emit()
	_check(game.offline_tuning.matching_preset_id() == "tactical_duel" \
		and panel._preset_buttons["tactical_duel"].disabled \
		and "Tactical duel" in panel._status.text,
		"applying from the UI must update gameplay and show the active preset")
	panel.handle_key(KEY_ESCAPE)
	game.start_demo_duel()
	_check(game.planning_time_left == 10.0 and not game.double_jump_enabled \
		and game.arrow_speed_max == 680.0,
		"Start duel must use the chosen preset")
	game._open_menu()
	game._menu._activate(game._menu.ROW_TUNING)
	game.offline_tuning.reset_all()
	for group: String in panel._groups:
		panel._show_group(group)
		for key: String in panel._controls:
			var control: Dictionary = panel._controls[key]
			if control.has("spin"):
				_check(is_equal_approx(control.spin.value, float(game.offline_tuning.get_value(key))),
					"numeric control must show the actual value for " + key)
	panel._show_group("Timing")
	panel._controls["planning_duration"].spin.value = 12.0
	panel._show_group("Movement")
	panel._controls["double_jump_enabled"].toggle.button_pressed = false
	panel._show_group("Projectiles")
	panel._controls["knives_per_shot"].spin.value = 3
	panel._controls["arrow_speed_max"].slider.value = 1000
	panel._controls["aim_preview_duration"].spin.value = 1.5
	panel.handle_key(KEY_ESCAPE)
	_check(not panel.visible and game._menu.visible and game._menu._cursor == game._menu.ROW_TUNING,
		"Escape must return to the tuning entry")
	game.start_demo_duel()
	_check(game.planning_duration == 12.0 and game.knives_per_shot == 3 \
		and game.arrow_speed_max == 1000.0 and not game.double_jump_enabled,
		"Start duel must preserve saved tuning through its baseline reset")
	_check(game.planning_time_left == 12.0, "the actual freeze countdown must use the setting")
	game._open_menu()
	game._on_menu_tutorial()
	game._practice.advance()
	_check(game.planning_duration == 8.0 and game.knives_per_shot == 2 and game.double_jump_enabled,
		"authored lessons must remain playable with standard rules")
	game._open_menu()
	game._on_menu_online()
	_check(game.planning_duration == 8.0 and game.knives_per_shot == 2,
		"entering the online lobby must restore standard rules")
	_check(not game.offline_tuning.set_value("knives_per_shot", 3),
		"the online lobby must reject tuning mutations")
	# Direct match start also enforces the boundary, including rematches.
	game.arrow_speed_max = 1234.0
	game.online_player = 0
	game._start_online_match(0, 42, 1)
	for definition: Dictionary in game.offline_tuning.definitions:
		var key: String = definition.key
		_check(game.get(key) == game.offline_tuning._defaults[key],
			"online must restore authored value for " + key)
	_check(not game.offline_tuning.set_value("double_jump_enabled", false),
		"active online matches must reject tuning mutations")
	game._leave_online()
	game.start_demo_duel()
	_check(game.planning_duration == 12.0 and game.knives_per_shot == 3 \
		and not game.double_jump_enabled and game.aim_preview_duration == 1.5,
		"returning offline must restore saved tuning after an online match")
	root.remove_child(game)
	game.free()
	await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
