extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const VisualCapture := preload("res://tests/VisualCaptureHelper.gd")


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var game = MAIN_SCENE.instantiate()
	game.force_touch_controls = true
	root.add_child(game)
	await process_frame
	game.start_quick_match(true, 0)
	await VisualCapture.await_transition(self, game)

	var error := VisualCapture.save(self, "res://previews/touch-controls-mvp.png",
		"Touch controls preview")
	quit(error)
