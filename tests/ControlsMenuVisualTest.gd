extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const VisualCapture := preload("res://tests/VisualCaptureHelper.gd")


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	await VisualCapture.pin_window(self)
	game._menu._activate(game._menu.ROW_CONTROLS)
	await VisualCapture.await_transition(self, game)

	var error := VisualCapture.save(self, "res://previews/controls-menu.png",
		"Controls menu preview")
	quit(error)
