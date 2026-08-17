extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const GAME_MANAGER := preload("res://scripts/GameManager.gd")


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var game = MAIN_SCENE.instantiate()
	game.fighter_visuals_enabled = true
	game.fighter_visual_style = GAME_MANAGER.FighterVisualStyle.RIGGED_PROTOTYPE
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game._on_menu_start(false, 0, 2)
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
	await process_frame
	await process_frame


func _save(output: String) -> Error:
	await process_frame
	var image := root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(output))
	if error == OK:
		print("Executor prototype preview saved: %s" % output)
	else:
		push_error("Could not save Executor prototype preview (error %d)" % error)
	return error
