extends SceneTree

## Regenerates the six tutorial images from the real match scene at the authored
## 1280×720 viewport. These are product captures, not tutorial mockups.

const MAIN_SCENE := preload("res://scenes/Main.tscn")
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
	game._on_menu_start(false, 3, 2)
	game.vs_ai = false
	game._transition.visible = false
	game._settings["high_contrast_previews"] = true
	game._apply_settings()
	for i in 2:
		game._reset_pilot(i)
	await _save_frame("tutorial-plan.png")

	for tick in 24:
		game._pilot_step(0, 1, false, true)
	for tick in 16:
		game._pilot_step(1, -1, false, true)
	_refresh_game(game)
	await _save_frame("tutorial-move.png")

	for i in 2:
		game._reset_pilot(i)
	for tick in 30:
		game._pilot_step(0, 1, tick == 0, true)
	for tick in 24:
		game._pilot_step(1, -1, tick == 4, true)
	_refresh_game(game)
	await _save_frame("tutorial-jump.png")

	game.players[0].plan.set_aim_from_vector(Vector2(0.92, -0.28),
		game.aim_min_angle, game.aim_max_angle)
	game.players[0].plan.power = 0.88
	game.players[0].plan.shot_tick = 18
	game.players[1].plan.set_aim_from_vector(Vector2(-0.90, -0.34),
		game.aim_min_angle, game.aim_max_angle)
	game.players[1].plan.power = 0.62
	game.players[1].plan.shot_tick = 12
	_refresh_game(game)
	await _save_frame("tutorial-attack.png")

	game._confirm(0)
	game._confirm(1)
	_refresh_game(game)
	await _save_frame("tutorial-lock.png")

	game._begin_execution()
	for tick in 22:
		game._sim_tick(game.tick_dt())
		game.exec_tick += 1
	game._on_player_hit(1, game.players[1].position, 0)
	_refresh_game(game)
	await _save_frame("tutorial-result.png")

	root.remove_child(game)
	game.free()
	await process_frame
	quit(0)


func _refresh_game(game) -> void:
	game._rebuild_ghost_paths()
	game._preview.queue_redraw()
	game._ui.refresh()


func _save_frame(filename: String) -> void:
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	if image == null or image.get_width() != 1280 or image.get_height() != 720:
		push_error("Tutorial capture must render at 1280×720, got %s" % [
			"no image" if image == null else "%d×%d" % [image.get_width(), image.get_height()],
		])
		quit(1)
		return
	var output := "%s/%s" % [OUTPUT_DIR, filename]
	var error := image.save_png(ProjectSettings.globalize_path(output))
	if error != OK:
		push_error("Could not save tutorial game image %s (error %d)" % [output, error])
		quit(error)
		return
	print("Tutorial game image saved: %s" % output)
