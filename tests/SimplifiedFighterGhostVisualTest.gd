extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var game = MAIN_SCENE.instantiate()
	game.simplified_fighter_proto_enabled = true
	game.fighter_visuals_enabled = true
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game._on_menu_start(false, 0, 2)
	game._transition.visible = false
	game.vs_ai = false
	game.state = Phase.PLANNING
	var player: Player = game.players[0]
	game.ghost_path[0] = PackedVector2Array([
		player.position,
		player.position + Vector2(145.0, -45.0),
	])
	game._preview.queue_redraw()
	for i in 5:
		await process_frame

	var output := "res://previews/gilded-executor-small-with-ghost-v1.png"
	var image := root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(output))
	if error == OK:
		print("Simplified fighter ghost preview saved: %s" % output)
	else:
		push_error("Could not save simplified fighter ghost preview (error %d)" % error)
	root.remove_child(game)
	game.free()
	await process_frame
	quit(error)
