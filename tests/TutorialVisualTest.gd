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
	game._on_menu_tutorial()
	await VisualCapture.await_transition(self, game)

	var error := OK
	for page in game._tutorial.PAGES.size():
		if page > 0:
			game._tutorial.advance()
			await VisualCapture.await_transition(self, game)
		var output := "res://previews/tutorial-briefing-%02d.png" % (page + 1)
		error = VisualCapture.save(self, output, "Tutorial briefing preview")
		if error != OK:
			break
	quit(error)
