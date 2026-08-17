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
	game.fighter_visual_style = GAME_MANAGER.FighterVisualStyle.CEL_PROOF
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game._on_menu_start(false, 0, 2)
	game.vs_ai = false
	game.set_physics_process(false)
	game._transition.visible = false
	game._preview.visible = false
	game._ui.visible = false
	game._time_stop.visible = false
	game.players[0].position = Vector2(575.0, 596.0)
	game.players[1].position = Vector2(705.0, 596.0)
	for player: Player in game.players:
		player.alive = true
		player.on_ground = true
		player.vel = Vector2.ZERO
		player.plan.confirmed = false
		player.plan.shot_tick = -1
	game._camera.enabled = true
	game._camera.gm = null
	game._camera.position = Vector2(640.0, 560.0)
	game._camera.zoom = Vector2.ONE * 2.6

	game.state = Phase.PLANNING
	game.world_tick = 6
	game.players[0].plan.aim_angle = -18.0
	await _sync_visual(game)
	var error := await _save("res://previews/cel-proof-idle-aim.png")

	game.state = Phase.EXECUTING
	game.exec_tick = 12
	game.players[0].plan.shot_tick = 12
	await _sync_visual(game)
	var next_error := await _save("res://previews/cel-proof-shot.png")
	if error == OK:
		error = next_error

	game.players[0].alive = false
	game.players[0].queue_redraw()
	await _sync_visual(game)
	next_error = await _save("res://previews/cel-proof-hit.png")
	if error == OK:
		error = next_error

	# Final acceptance frame at the real gameplay camera scale.
	game.players[0].alive = true
	game.players[0].plan.shot_tick = -1
	game.players[0].position = Vector2(230.0, 596.0)
	game.players[1].position = Vector2(1050.0, 596.0)
	game.state = Phase.PLANNING
	game._camera.position = Vector2(640.0, 360.0)
	game._camera.zoom = Vector2.ONE
	await _sync_visual(game)
	next_error = await _save("res://previews/cel-proof-gameplay-scale.png")
	if error == OK:
		error = next_error

	root.remove_child(game)
	game.free()
	await process_frame
	quit(error)


func _sync_visual(game) -> void:
	var visual := game.players[0].get_node_or_null("FighterVisual") as FighterVisual
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
		print("Cel fighter proof saved: %s" % output)
	else:
		push_error("Could not save cel fighter proof (error %d)" % error)
	return error
