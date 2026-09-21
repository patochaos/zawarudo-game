extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const VisualCapture := preload("res://tests/VisualCaptureHelper.gd")


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	await VisualCapture.pin_window(self)
	game._transition.visible = false
	game._menu.developer_mode = true
	game._menu._activate(game._menu.ROW_EXPERIMENTS)
	game._menu._select(game._menu.ROW_CLOSE_CAMERA)
	game._menu._refresh()
	await VisualCapture.settle(self, 3)
	var error := VisualCapture.save(self, "user://close-camera-menu.png",
		"Close Camera menu preview", Vector2i(1280, 720))
	if error != OK:
		quit(error)
		return

	game._menu._activate(game._menu.ROW_CLOSE_CAMERA)
	await VisualCapture.await_transition(self, game)
	for tick in 18:
		game._pilot_step(0, 1, tick == 0, true)
	game.players[0].plan.set_aim_from_vector(Vector2(0.9, -0.35),
		game.aim_min_angle, game.aim_max_angle)
	game.players[0].plan.power = 0.88
	game.players[0].plan.shot_tick = 12
	game._rebuild_ghost_paths()
	game.banner_text = "CLOSE CAMERA — TWO-DAGGER TRAJECTORY"
	game.banner_color = Color(0.62, 0.95, 1.0)
	game.banner_time = 4.0
	game._ui.refresh()
	await VisualCapture.settle(self, 45)
	error = VisualCapture.save(self, "user://close-camera-planning.png",
		"Close Camera planning preview", Vector2i(1280, 720))
	quit(error)
