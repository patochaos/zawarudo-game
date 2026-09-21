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
	game.start_quick_match(false, 2, 2)
	game.set_physics_process(false)
	game._transition.visible = false
	game._time_stop._freeze_flash = 0.0
	game._time_stop._resume_flash = 0.0
	game._reset_pilot(0)
	for tick in 22:
		game._pilot_step(0, 1, tick == 0, tick < 12)
	game.players[0].plan.shot_tick = 12
	game.players[0].plan.power = 0.6
	game._rebuild_ghost_paths()
	game._preview.queue_redraw()
	game._ui.refresh()
	var suffix := "before" if "--before" in OS.get_cmdline_user_args() else "after"
	await Capture.settle(self)
	if Capture.save(self, "res://previews/pendulum-art-%s.png" % suffix,
			"Pendulum planning", Vector2i(1280, 720)) != OK:
		quit(1)
		return
	await Capture.pin_window(self, Vector2i(1024, 576))
	await Capture.settle(self)
	if Capture.save(self, "res://previews/pendulum-art-small-%s.png" % suffix,
			"Pendulum small", Vector2i(1024, 576)) != OK:
		quit(1)
		return
	await Capture.pin_window(self)
	game._preview.high_contrast = true
	game._preview.queue_redraw()
	await Capture.settle(self)
	if Capture.save(self, "res://previews/pendulum-art-contrast-%s.png" % suffix,
			"Pendulum high contrast") != OK:
		quit(1)
		return
	game._preview.high_contrast = false
	game._begin_execution()
	for tick in 13:
		game.exec_tick = tick
		game._sim_tick(game.tick_dt())
	game._time_stop._resume_flash = 0.0
	game._ui.refresh()
	game._preview.queue_redraw()
	await Capture.settle(self)
	if Capture.save(self, "res://previews/pendulum-art-release-%s.png" % suffix,
			"Pendulum release") != OK:
		quit(1)
		return
	# Optional short animation proof: one second running, one frozen, one
	# resumed. Sample the actual draw path at 12 fps without a video export.
	if "--machinery" in OS.get_cmdline_user_args():
		await Capture.pin_window(self, Vector2i(1024, 576))
		game._backdrop.set_process(false)
		for frame in 36:
			game.world_tick = (frame * 5 if frame < 12 else 60 if frame < 24 else 60 + (frame - 24) * 5)
			game.state = Phase.PLANNING if frame >= 12 and frame < 24 else Phase.EXECUTING
			game._backdrop.queue_redraw()
			game._preview.queue_redraw()
			game._ui.refresh()
			await Capture.settle(self)
			if Capture.save(self, "res://previews/pendulum-motion-%02d.png" % frame,
					"Pendulum motion", Vector2i(1024, 576)) != OK:
				quit(1)
				return
		await Capture.pin_window(self)
	game.start_quick_match(false, 2, 4)
	game.set_physics_process(false)
	game._transition.visible = false
	game._time_stop._freeze_flash = 0.0
	game._time_stop._resume_flash = 0.0
	game._ui.refresh()
	await Capture.settle(self)
	var error := Capture.save(self, "res://previews/pendulum-art-four-%s.png" % suffix,
		"Pendulum four players")
	root.remove_child(game)
	game.free()
	quit(error)
