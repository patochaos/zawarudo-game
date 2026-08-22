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
	game._on_menu_start(false, 3, 2)
	game._transition.visible = false
	game.vs_ai = false
	game._settings["high_contrast_previews"] = true
	game._apply_settings()
	for i in 2:
		game._reset_pilot(i)

	for tick in 22:
		game._pilot_step(0, 1, tick == 3, true)
	for tick in 17:
		game._pilot_step(1, -1, tick == 7, true)
	game.players[0].plan.set_aim_from_vector(Vector2(0.9, -0.28),
		game.aim_min_angle, game.aim_max_angle)
	game.players[0].plan.power = 0.88
	game.players[0].plan.shot_tick = 14
	game.players[1].plan.set_aim_from_vector(Vector2(-0.86, -0.42),
		game.aim_min_angle, game.aim_max_angle)
	game.players[1].plan.power = 0.66
	game.players[1].plan.shot_tick = 9
	game._rebuild_ghost_paths()
	game._preview.queue_redraw()
	game.banner_text = "HIGH CONTRAST — PLANNING READABILITY"
	game.banner_color = Color(1.0, 0.86, 0.28)
	game.banner_time = 4.0
	game._ui.refresh()
	await VisualCapture.await_transition(self, game, 3)

	var error := VisualCapture.save(self, "res://previews/high-contrast-planning.png",
		"High-contrast planning preview")
	root.remove_child(game)
	game.free()
	await process_frame
	quit(error)
