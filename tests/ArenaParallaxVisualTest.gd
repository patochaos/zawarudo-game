extends SceneTree

## Captures the same arena with the fight settled at its left and right edges,
## so the far/mid layer slide and the execution lighting can be inspected.
## Run WINDOWED (see VisualCaptureHelper.gd); writes previews/arena-parallax-*.png.
const MAIN := preload("res://scenes/Main.tscn")
const Capture := preload("res://tests/VisualCaptureHelper.gd")
const ARENA := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = MAIN.instantiate()
	root.add_child(game)
	await process_frame
	await Capture.pin_window(self)
	game._sfx.muted = true
	game.start_quick_match(false, ARENA, 2)
	game.set_physics_process(false)
	game._transition.visible = false
	game._time_stop._freeze_flash = 0.0
	game._time_stop._resume_flash = 0.0
	var backdrop = game._backdrop
	backdrop.set_process(false)
	# Planning: cold pass, no slide, whatever the fighters' positions.
	game.players[0].position = Vector2(120.0, 600.0)
	game.players[1].position = Vector2(220.0, 600.0)
	game._preview.queue_redraw()
	game._ui.refresh()
	await Capture.settle(self, 4)
	if not _save("planning-left"):
		return
	game._begin_execution()
	game._time_stop._resume_flash = 0.0
	for side in [["left", 120.0], ["right", 1160.0]]:
		game.players[0].position = Vector2(side[1], 600.0)
		game.players[1].position = Vector2(side[1], 200.0)
		for _step in 60:
			backdrop._process(0.1)
		game._preview.queue_redraw()
		game._ui.refresh()
		await Capture.settle(self, 4)
		if not _save("execution-" + side[0]):
			return
	game.free()
	await process_frame
	quit(0)


func _save(state: String) -> bool:
	var error := Capture.save(self, "res://previews/arena-parallax-%s.png" % state,
		"Arena parallax %s" % state, Vector2i(1280, 720))
	if error != OK:
		quit(error)
	return error == OK
