extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const VisualCapture := preload("res://tests/VisualCaptureHelper.gd")


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

	var error := VisualCapture.save(self, "res://previews/gilded-executor-small-with-ghost-v1.png",
		"Simplified fighter ghost preview")
	root.remove_child(game)
	game.free()
	await process_frame
	quit(error)
