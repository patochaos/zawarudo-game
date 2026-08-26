extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const VisualCapture := preload("res://tests/VisualCaptureHelper.gd")


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game.start_quick_match(true, 3, 2)
	game._transition.set_process(false)
	game._transition._elapsed = 0.12
	game._transition._surface.queue_redraw()
	# This capture documents the wipe itself, so it deliberately does NOT wait
	# for the transition to finish: _process is frozen on a chosen frame above.
	await VisualCapture.settle(self)
	var error := VisualCapture.save(self, "res://previews/arena-transition.png",
		"Arena transition preview")
	quit(error)
