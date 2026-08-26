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
	game._menu._activate(game._menu.ROW_ONLINE)
	game._transition.visible = false
	await VisualCapture.await_transition(self, game)
	var error := _save("res://previews/online-lobby-current.png")
	if error != OK:
		quit(error)
		return
	root.remove_child(game)
	game.free()
	await process_frame
	game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	await VisualCapture.pin_window(self)
	game._menu._activate(game._menu.ROW_ONLINE)
	game._transition.visible = false
	game._online_lobby.show_room("ZA2W9D", 0)
	await VisualCapture.await_transition(self, game)
	error = _save("res://previews/online-room-current.png")
	quit(error)


func _save(output: String) -> Error:
	return VisualCapture.save(self, output, "Online lobby preview")
