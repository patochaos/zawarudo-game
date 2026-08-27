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
	game._sfx.muted = true
	game._menu._activate(game._menu.ROW_SANDBOX)
	game._transition.visible = false
	game.sandbox_toggle_ai()
	await VisualCapture.settle(self, 4)

	var error := VisualCapture.save(self, "user://sandbox-visual.png",
		"Sandbox lab preview", Vector2i(1280, 720))
	quit(error)
