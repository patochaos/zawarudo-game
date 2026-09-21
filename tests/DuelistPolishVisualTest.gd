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
	game.start_quick_match(false, 0, 2)
	game._transition.visible = false
	game._time_stop._freeze_flash = 0.0
	game._time_stop._resume_flash = 0.0
	game._preview.queue_redraw()
	game.set_physics_process(false)
	game._reset_pilot(0)
	for t in 24:
		game._pilot_step(0, 1, t == 0, t < 12)
	game.players[0].plan.shot_tick = 12
	game.players[0].plan.power = 0.6
	game._rebuild_ghost_paths()
	game._ui.refresh()
	await Capture.settle(self)
	var error := Capture.save(self, "res://previews/duelist-polish-planning.png", "Duelist planning")
	if error != OK:
		quit(error)
		return
	await Capture.pin_window(self, Vector2i(1024, 576))
	await Capture.settle(self)
	error = Capture.save(self, "res://previews/duelist-polish-small.png", "Duelist small planning")
	if error != OK:
		quit(error)
		return
	await Capture.pin_window(self)
	game._begin_execution()
	for t in game.exec_ticks():
		game.exec_tick = t
		game._sim_tick(game.tick_dt())
		game._capture_replay_frame()
	game._end_execution()
	game._ui._turn_review.open_last_turn()
	game._ui._turn_review.seek(30)
	await Capture.settle(self)
	error = Capture.save(self, "res://previews/duelist-polish-review.png", "Duelist last-turn review")
	if error != OK:
		quit(error)
		return
	game._ui._turn_review.visible = false
	game.start_quick_match(false, 0, 4)
	game._transition.visible = false
	game._time_stop._freeze_flash = 0.0
	game._time_stop._resume_flash = 0.0
	game._preview.queue_redraw()
	game._ui.refresh()
	await Capture.settle(self)
	error = Capture.save(self, "res://previews/duelist-polish-four.png", "Four-player timelines")
	root.remove_child(game)
	game.free()
	await process_frame
	quit(error)
