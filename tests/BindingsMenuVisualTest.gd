extends SceneTree

## Reference shots of the two screens that changed shape: the controls sheet
## with its rebinding route, and the Player 1 key list itself.

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
	game._transition.visible = false

	game._menu._activate(game._menu.ROW_CONTROLS)
	game._menu._open_bindings()
	game._menu._select(2)
	await VisualCapture.await_transition(self, game)
	var list_error := VisualCapture.save(self, "res://previews/controls-bindings.png",
		"Key binding list preview")

	game._menu._activate(2)
	await VisualCapture.await_transition(self, game)
	var capture_error := VisualCapture.save(self, "res://previews/controls-bindings-armed.png",
		"Armed binding row preview")

	if list_error == OK and capture_error == OK:
		print("Binding previews saved")
	else:
		push_error("Could not save binding previews (%d, %d)" % [list_error, capture_error])
	quit(list_error if list_error != OK else capture_error)
