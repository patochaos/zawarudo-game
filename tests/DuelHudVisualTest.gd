extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const VisualCapture := preload("res://tests/VisualCaptureHelper.gd")


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game.start_quick_match(true, 0, 2)
	await VisualCapture.await_transition(self, game)
	game.score[0] = 2
	game.score[1] = 1
	game.super_meter[0] = 0.65
	game.super_meter[1] = 0.35
	game._ui.refresh()
	await VisualCapture.settle(self)

	var error := VisualCapture.save(self, "res://previews/hud-1v1-implemented.png",
		"Implemented 1v1 HUD preview")
	quit(error)
