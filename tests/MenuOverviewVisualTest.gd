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
	game._transition.visible = false
	await VisualCapture.await_transition(self, game)
	var error := _save("res://previews/menu-main-current.png")
	if error != OK:
		quit(error)
		return
	game._menu.developer_mode = true
	game._menu._activate(game._menu.ROW_EXPERIMENTS)
	await VisualCapture.await_transition(self, game)
	error = _save("res://previews/menu-experiments-current.png")
	if error != OK:
		quit(error)
		return
	game._menu.handle_key(KEY_ESCAPE)
	game._menu._activate(game._menu.ROW_CONTROLS)
	await VisualCapture.await_transition(self, game)
	error = _save("res://previews/menu-controls-current.png")
	if error != OK:
		quit(error)
		return
	game._menu.handle_key(KEY_ESCAPE)
	game._menu._activate(game._menu.ROW_OPTIONS)
	await VisualCapture.await_transition(self, game)
	error = _save("res://previews/menu-options-current.png")
	quit(error)


func _save(output: String) -> Error:
	return VisualCapture.save(self, output, "Menu preview")
