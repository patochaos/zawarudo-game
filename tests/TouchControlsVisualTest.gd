extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const VisualCapture := preload("res://tests/VisualCaptureHelper.gd")


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	# Keep the fixed 1280x720 touch layout visible regardless of the desktop's
	# remembered/maximized window state or DPI scale.
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	await process_frame
	var game = MAIN_SCENE.instantiate()
	game.force_touch_controls = true
	root.add_child(game)
	await process_frame
	game.start_quick_match(true, 0)
	await VisualCapture.await_transition(self, game)

	var error := VisualCapture.save(self, "res://previews/touch-controls-mvp.png",
		"Touch controls preview")
	quit(error)
