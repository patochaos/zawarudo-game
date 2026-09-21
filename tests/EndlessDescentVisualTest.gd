extends SceneTree
const MAIN := preload("res://scenes/Main.tscn")
const Capture := preload("res://tests/VisualCaptureHelper.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var game = MAIN.instantiate()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game.start_quick_match(false, 1, 2)
	game.set_physics_process(false)
	game._transition.visible = false
	game._time_stop._freeze_flash = 0.0
	game._time_stop._resume_flash = 0.0
	for i in 2:
		game._reset_pilot(i)
		for tick in 24:
			game._pilot_step(i, -1 if i == 0 else 1, tick == 0, true)
		game.players[i].plan.shot_tick = 12
		game.players[i].plan.power = 0.75
	game._rebuild_ghost_paths()
	for pixels in [Vector2i(1280, 720), Vector2i(1024, 576)]:
		await Capture.pin_window(self, pixels)
		for contrast in [false, true]:
			game._preview.high_contrast = contrast
			game._preview.queue_redraw()
			game._ui.refresh()
			await Capture.settle(self)
			if not _save("plan-%d-%s" % [pixels.x, str(contrast)]): return
	await Capture.pin_window(self)
	game._preview.high_contrast = false
	game._begin_execution()
	for tick in 20:
		game.exec_tick = tick
		game._sim_tick(game.tick_dt())
	game._time_stop._resume_flash = 0.0
	game._ui.refresh()
	game._preview.queue_redraw()
	await Capture.settle(self)
	if not _save("execution"): return
	# Destroy all temporary cover to review the permanent routes and open shaft.
	game.platforms = game.platforms.filter(func(pf): return int(pf["hp"]) < 0)
	game._rebuild_solids()
	game._arena.setup(game.platforms)
	await Capture.settle(self)
	if not _save("cover-gone"): return
	game.start_quick_match(false, 1, 4)
	game.set_physics_process(false)
	game._transition.visible = false
	game._time_stop.visible = false
	game._ui.refresh()
	await Capture.settle(self)
	if not _save("four-player"): return
	game.free()
	quit(0)

func _save(suffix: String) -> bool:
	var error := Capture.save(self, "res://previews/descent-polish-%s.png" % suffix, "Descent " + suffix)
	if error != OK: quit(error)
	return error == OK
