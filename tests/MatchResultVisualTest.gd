extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const VisualCapture := preload("res://tests/VisualCaptureHelper.gd")


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game.start_quick_match(true, 0)
	await VisualCapture.await_transition(self, game)
	game.state = Phase.GAME_OVER
	game.winner = 0
	game.score[0] = game.hits_to_win
	game._cycle_rematch_level(1)
	game._ui.refresh()
	await VisualCapture.settle(self)

	var error := _save("res://previews/match-result-options.png")
	if error != OK:
		quit(error)
		return

	game._touch_controls.enabled = true
	game._touch_controls._update_context()
	game._ui.set_touch_mode(true)
	game._ui.refresh()
	await VisualCapture.settle(self)
	error = _save("res://previews/match-result-touch-options.png")
	quit(error)


func _save(output: String) -> Error:
	return VisualCapture.save(self, output, "Match result preview")
