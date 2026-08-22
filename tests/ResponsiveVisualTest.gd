extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const VisualCapture := preload("res://tests/VisualCaptureHelper.gd")
const TARGETS := [Vector2i(1024, 576), Vector2i(1600, 900), Vector2i(1024, 768)]


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._transition.visible = false
	game._on_menu_start(true, 0, 2)
	game._transition.visible = false
	await VisualCapture.await_transition(self, game)
	for target: Vector2i in TARGETS:
		DisplayServer.window_set_size(target)
		await VisualCapture.settle(self, 5)
		var output := "res://previews/responsive-%dx%d.png" % [target.x, target.y]
		var error := VisualCapture.save(self, output, "Responsive preview")
		if error != OK:
			quit(error)
			return
	root.remove_child(game)
	game.free()
	await process_frame
	quit(0)
