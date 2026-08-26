extends SceneTree

## Regenerates the six tutorial images from the real match scene at the authored
## 1280×720 viewport. These are product captures, not tutorial mockups.

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const VisualCapture := preload("res://tests/VisualCaptureHelper.gd")
const OUTPUT_DIR := "res://assets/art/tutorial"


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	await process_frame
	await process_frame

	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game.start_quick_match(false, 3, 2)
	game.vs_ai = false
	game._transition.visible = false
	game._settings["high_contrast_previews"] = true
	game._apply_settings()
	for i in 2:
		game._reset_pilot(i)
	var error := await _save_frame(game, "tutorial-plan.png")
	if error != OK:
		quit(error)
		return

	for tick in 24:
		game._pilot_step(0, 1, false, true)
	for tick in 16:
		game._pilot_step(1, -1, false, true)
	_refresh_game(game)
	error = await _save_frame(game, "tutorial-move.png")
	if error != OK:
		quit(error)
		return

	for i in 2:
		game._reset_pilot(i)
	for tick in 30:
		game._pilot_step(0, 1, tick == 0, true)
	for tick in 24:
		game._pilot_step(1, -1, tick == 4, true)
	_refresh_game(game)
	error = await _save_frame(game, "tutorial-jump.png")
	if error != OK:
		quit(error)
		return

	game.players[0].plan.set_aim_from_vector(Vector2(0.92, -0.28),
		game.aim_min_angle, game.aim_max_angle)
	game.players[0].plan.power = 0.88
	game.players[0].plan.shot_tick = 18
	game.players[1].plan.set_aim_from_vector(Vector2(-0.90, -0.34),
		game.aim_min_angle, game.aim_max_angle)
	game.players[1].plan.power = 0.62
	game.players[1].plan.shot_tick = 12
	_refresh_game(game)
	error = await _save_frame(game, "tutorial-attack.png")
	if error != OK:
		quit(error)
		return

	game._confirm(0)
	game._confirm(1)
	_refresh_game(game)
	error = await _save_frame(game, "tutorial-lock.png")
	if error != OK:
		quit(error)
		return

	game._begin_execution()
	for tick in 22:
		game._sim_tick(game.tick_dt())
		game.exec_tick += 1
	game._on_player_hit(1, game.players[1].position, 0)
	_refresh_game(game)
	error = await _save_frame(game, "tutorial-result.png")
	if error != OK:
		quit(error)
		return

	root.remove_child(game)
	game.free()
	await process_frame
	quit(0)


func _refresh_game(game) -> void:
	game._rebuild_ghost_paths()
	game._preview.queue_redraw()
	game._ui.refresh()


func _save_frame(game, filename: String) -> Error:
	await VisualCapture.await_transition(self, game)
	return VisualCapture.save(self, "%s/%s" % [OUTPUT_DIR, filename],
		"Tutorial game image", Vector2i(1280, 720))
