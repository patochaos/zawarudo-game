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
	game._menu.developer_mode = true
	game._menu._activate(game._menu.ROW_EXPERIMENTS)
	game._menu._select(game._menu.ROW_REAL_TIME)
	game._transition.visible = false
	await Capture.settle(self)
	var error := Capture.save(self, "res://previews/real-time-menu.png", "Real-time menu")
	if error != OK:
		quit(error)
		return
	game._menu._activate(game._menu.ROW_REAL_TIME)
	game._transition.visible = false
	game.set_physics_process(false)
	game.players[0].plan.set_aim_from_vector(Vector2(1, -0.3), -90, 90)
	game.charging[0] = true
	game.players[0].plan.power = 0.65
	game._preview.queue_redraw()
	await Capture.settle(self)
	error = Capture.save(self, "res://previews/real-time-guide.png", "Real-time subtle guide")
	if error != OK:
		quit(error)
		return
	game.real_time_aim_guide = false
	game._preview.queue_redraw()
	await Capture.settle(self)
	error = Capture.save(self, "res://previews/real-time-clean.png", "Real-time no guide")
	root.remove_child(game)
	game.free()
	await process_frame
	quit(error)
