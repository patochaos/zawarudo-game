extends SceneTree

## Deterministic art-direction capture for the stained-glass planning slice.

const MAIN_SCENE := preload("res://scenes/Main.tscn")


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game._menu.ruleset = game._menu.Ruleset.ORIGINAL
	game._on_menu_start(true, 0, 2)
	game._transition.visible = false
	game._time_stop._freeze_flash = 0.0
	game.players[0].plan.set_aim_from_vector(Vector2(0.94, -0.34),
		game.aim_min_angle, game.aim_max_angle)
	game.players[0].plan.power = 0.72
	for tick in 14:
		game._pilot_step(0, 1, tick == 3, true)
	game._rebuild_ghost_paths()
	game._preview.queue_redraw()
	game._ui.refresh()
	for i in 4:
		await process_frame

	var output := "res://previews/stained-glass-planning-v1.png"
	var image := root.get_texture().get_image()
	if image == null or image.get_width() < 1 or image.get_height() < 1:
		push_error("Could not read the stained-glass planning viewport")
		quit(1)
		return
	var error := image.save_png(ProjectSettings.globalize_path(output))
	if error == OK:
		print("Stained-glass planning preview saved: %s" % output)
	else:
		push_error("Could not save stained-glass planning preview (error %d)" % error)
	root.remove_child(game)
	game.free()
	await process_frame
	quit(error)
