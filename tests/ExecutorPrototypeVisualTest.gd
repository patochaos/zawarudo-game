extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const VisualCapture := preload("res://tests/VisualCaptureHelper.gd")


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var game = MAIN_SCENE.instantiate()
	game.fighter_visuals_enabled = true
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game.start_quick_match(false, 0, 2)
	game._transition.visible = false
	game._preview.visible = false
	game.vs_ai = false
	game.set_physics_process(false)
	for player: Player in game.players:
		player.alive = true
		player.plan.confirmed = false
		player.plan.shot_tick = -1

	game.state = Phase.PLANNING
	game.world_tick = 15
	game.players[0].on_ground = true
	game.players[0].vel = Vector2.ZERO
	game.players[1].on_ground = true
	game.players[1].vel = Vector2(100.0, 0.0)
	await _sync_visuals(game)
	var error := await _save("res://previews/executor-prototype-godot-idle-run.png")

	game.state = Phase.EXECUTING
	game.world_tick = 25
	game.exec_tick = 10
	game.players[0].on_ground = false
	game.players[0].vel = Vector2(0.0, -180.0)
	game.players[1].on_ground = false
	game.players[1].vel = Vector2(0.0, 180.0)
	await _sync_visuals(game)
	var next_error := await _save("res://previews/executor-prototype-godot-jump.png")
	if error == OK:
		error = next_error

	game.exec_tick = 20
	game.players[0].on_ground = true
	game.players[0].vel = Vector2.ZERO
	game.players[0].plan.shot_tick = 20
	game.players[0].plan.aim_angle = 0.0
	game.players[1].on_ground = true
	game.players[1].vel = Vector2.ZERO
	await _sync_visuals(game)
	next_error = await _save("res://previews/executor-prototype-godot-shot.png")
	if error == OK:
		error = next_error

	root.remove_child(game)
	game.free()
	await process_frame
	quit(error)


func _sync_visuals(game) -> void:
	for player: Player in game.players:
		var visual := player.get_node_or_null("FighterVisual") as FighterVisual
		if visual != null:
			visual.sync_from_player()
			visual.queue_redraw()
	await VisualCapture.await_transition(self, game)


func _save(output: String) -> Error:
	await VisualCapture.settle(self, 1)
	return VisualCapture.save(self, output, "Executor prototype preview")
