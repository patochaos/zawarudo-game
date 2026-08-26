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
	game.local_weapon_choices[0] = game.Weapon.DASHBLADE
	game.local_weapon_choices[1] = game.Weapon.KNIVES
	game.start_quick_match(false, 0, 2)
	game._transition.visible = false
	game.vs_ai = false
	game.state = Phase.PLANNING

	var rook: Player = game.players[0]
	rook.vel = Vector2(180.0, 0.0)
	rook.on_ground = true
	rook.plan.shot_tick = 1
	game.world_tick = 8
	game.ghost_path[0] = PackedVector2Array([
		rook.position,
		rook.position + Vector2(145.0, -45.0),
	])
	game.ghost_velocity_path[0] = PackedVector2Array([
		Vector2(180.0, 0.0),
		Vector2(500.0, -180.0),
	])
	game.ghost_ground_path[0] = PackedByteArray([1, 0])
	var visual := rook.get_node("FighterVisual") as FighterVisual
	visual.sync_from_player()
	visual.queue_redraw()
	game._preview.queue_redraw()
	for i in 5:
		await process_frame

	var error := VisualCapture.save(self,
		"res://previews/rook-animated-v1-in-game.png",
		"Animated Rook in-game preview", Vector2i(1280, 720))
	root.remove_child(game)
	game.free()
	await process_frame
	quit(error)
