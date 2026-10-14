extends SceneTree

const MAIN := preload("res://scenes/Main.tscn")
const Capture := preload("res://tests/VisualCaptureHelper.gd")
var game
var error := OK


func _init() -> void:
	call_deferred("run")


func snap(label: String) -> void:
	game._time_stop._freeze_flash = 0.0
	game._time_stop._resume_flash = 0.0
	game._preview.queue_redraw()
	game._ui.refresh()
	await Capture.settle(self, 3)
	error = Capture.save(self, "res://previews/interception-" + label + ".png", "Interception")
	if error != OK:
		quit(error)


func run() -> void:
	game = MAIN.instantiate()
	game.offline_tuning_path = ""
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game._sfx.muted = true
	game._settings["telemetry"] = false
	game._apply_setting("telemetry")
	await Capture.pin_window(self)
	await Capture.await_transition(self, game)
	game._menu._select(game._menu.ROW_INTERCEPTION)
	await snap("menu")
	game._menu._row_buttons[game._menu.ROW_INTERCEPTION].pressed.emit()
	await Capture.await_transition(self, game)
	await snap("opening")
	for tick in game.movement_tick_budget():
		game._pilot_step(0, 1, tick == 0, true)
	game.players[0].plan.shot_tick = 20
	game.players[0].plan.power = 0.55
	game.players[0].plan.set_aim_from_vector(Vector2(1, 0.3), game.aim_min_angle, game.aim_max_angle)
	game._rebuild_ghost_paths()
	await snap("planning")
	await Capture.pin_window(self, Vector2i(1024, 576))
	await snap("planning-small")
	game._open_menu()
	await Capture.await_transition(self, game)
	game._menu._select(game._menu.ROW_INTERCEPTION)
	await snap("menu-small")
	game.start_interception()
	await Capture.await_transition(self, game)
	game.state = Phase.GAME_OVER
	game.winner = 0
	game.score[0] = 3
	await snap("result-small")
	game._touch_controls.configure(game, true)
	game._ui.set_touch_mode(true)
	await snap("result-touch")
	game.free()
	await process_frame
	quit(error)
