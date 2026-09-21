extends SceneTree
const Capture := preload("res://tests/VisualCaptureHelper.gd")

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await Capture.pin_window(self)
	game._sfx.muted = true
	game._menu.developer_mode = true
	game._menu._activate(game._menu.ROW_EXPERIMENTS)
	game._menu._select(game._menu.ROW_CLASS_LAB)
	game._transition.visible = false
	await Capture.settle(self)
	var error := Capture.save(self, "res://previews/class-lab-menu.png", "Class Lab menu")
	for kind in [Roster.DASHBLADE, Roster.SHOCK, Roster.CHAKRAM]:
		ClassLab.start(game, false, kind)
		game.set_physics_process(false)
		game.players[0].plan.set_aim_from_vector(Vector2(1, -0.35), -90, 90)
		game.players[0].plan.power = 0.65
		game.charging[0] = true
		game._preview.queue_redraw()
		game._ui.refresh()
		await Capture.settle(self)
		error = maxi(error, Capture.save(self, "res://previews/class-lab-%d.png" % kind, "Class Lab preview"))
	ClassLab.start(game, true, Roster.SHOCK, Roster.CHAKRAM)
	game.set_physics_process(false)
	for tick in 360:
		game._freeplay_tick(game.tick_dt())
	game._preview.queue_redraw()
	await Capture.settle(self)
	error = maxi(error, Capture.save(self, "res://previews/class-lab-live.png", "Class Lab real time"))
	game.queue_free()
	await process_frame
	quit(error)
