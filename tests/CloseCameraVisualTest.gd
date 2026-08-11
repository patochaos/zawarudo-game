extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._menu.ruleset = game._menu.Ruleset.CAMERA_PROTOTYPE
	game._on_menu_start(false, 0)
	game.vs_ai = false
	for i in 2:
		game._reset_pilot(i)

	# Put both plans on the new platform rhythm and expose the lower jump arc.
	for tick in 18:
		game._pilot_step(0, 1, tick == 0, true)
	game.players[0].plan.set_aim_from_vector(Vector2(0.9, -0.35),
		game.aim_min_angle, game.aim_max_angle)
	game.players[0].plan.power = 0.88
	game.players[0].plan.shot_tick = 12

	game.players[1].plan.set_aim_from_vector(Vector2(-0.9, -0.35),
		game.aim_min_angle, game.aim_max_angle)
	game.players[1].plan.power = 0.45
	game.players[1].plan.shot_tick = 0
	game._rebuild_ghost_paths()
	game.banner_text = "CLOSE CAMERA — DIRECT + SMALL LOB"
	game.banner_color = Color(0.62, 0.95, 1.0)
	game.banner_time = 4.0
	game._ui.refresh()
	await process_frame
	await process_frame
	await process_frame

	var output := "res://previews/close-camera-ruleset.png"
	var image := root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(output))
	if error == OK:
		print("Close-camera preview saved: %s" % output)
	else:
		push_error("Could not save close-camera preview (error %d)" % error)
	quit(error)
