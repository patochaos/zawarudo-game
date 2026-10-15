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
	game.set_physics_process(false)
	game._time_stop._freeze_flash = 0.0
	game._time_stop._resume_flash = 0.0
	game.state = Phase.EXECUTING
	game.world_tick = 0
	game.exec_tick = 12
	var left: Player = game.players[0]
	var right: Player = game.players[1]
	left.position = Vector2(470, 470)
	right.position = Vector2(790, 470)
	left.facing = 1
	right.facing = -1
	for p: Player in game.players:
		p.on_ground = true
		p.vel = Vector2.ZERO
		p.plan.confirmed = false
	left.plan.shot_tick = 12
	right.plan.shot_tick = -1
	game._ui.refresh()
	for p: Player in game.players:
		p.get_node("FighterVisual").sync_from_player()
	await Capture.settle(self, 5)
	var error := Capture.save(self, "res://previews/duelist-sprite-polish-gameplay.png", "Duelist sprite polish")
	if error == OK:
		await Capture.pin_window(self, Vector2i(1024, 576))
		await Capture.settle(self, 5)
		error = Capture.save(self, "res://previews/duelist-sprite-polish-small.png", "Duelist sprite polish small")
	root.remove_child(game)
	game.free()
	await process_frame
	quit(error)
