extends SceneTree

const MAIN := preload("res://scenes/Main.tscn")
const Capture := preload("res://tests/VisualCaptureHelper.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = MAIN.instantiate()
	root.add_child(game)
	await process_frame
	await Capture.pin_window(self)
	game._sfx.muted = true
	for index in [1, 3]:
		game.start_quick_match(false, index, 2)
		game.set_physics_process(false)
		game._transition.visible = false
		game._time_stop._freeze_flash = 0.0
		game._time_stop._resume_flash = 0.0
		game._ui.refresh()
		await Capture.settle(self, 4)
		if Capture.save(self, "res://previews/prototype-arena-%d.png" % index,
				"Prototype arena %d" % index, Vector2i(1280, 720)) != OK:
			quit(1)
			return
		game._setup.level = index
		game._setup.open({"player_count": 2, "weapons": [0, 0], "roles": ["HUMAN", "AI"]})
		await Capture.settle(self, 4)
		if Capture.save(self, "res://previews/prototype-setup-%d.png" % index,
				"Prototype setup %d" % index, Vector2i(1280, 720)) != OK:
			quit(1)
			return
		game._setup.close()
	game.free()
	quit(0)
