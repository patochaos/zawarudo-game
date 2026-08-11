extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._on_menu_start(true, 0)
	game.state = Phase.GAME_OVER
	game.winner = 0
	game.score[0] = game.hits_to_win
	game._cycle_rematch_level(1)
	game._ui.refresh()
	await process_frame
	await process_frame

	var error := _save("res://previews/match-result-options.png")
	if error != OK:
		quit(error)
		return

	game._touch_controls.enabled = true
	game._touch_controls._update_context()
	game._ui.set_touch_mode(true)
	game._ui.refresh()
	await process_frame
	await process_frame
	error = _save("res://previews/match-result-touch-options.png")
	quit(error)


func _save(output: String) -> Error:
	var image := root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(output))
	if error == OK:
		print("Match result preview saved: %s" % output)
	else:
		push_error("Could not save match result preview (error %d)" % error)
	return error
