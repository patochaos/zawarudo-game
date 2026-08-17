extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game._menu.ruleset = game._menu.Ruleset.CAMERA_PROTOTYPE
	game._on_menu_start(true, 0, 2)
	game.score[0] = 2
	game.score[1] = 1
	game.super_meter[0] = 0.65
	game.super_meter[1] = 0.35
	game._ui.refresh()
	await process_frame
	await process_frame

	var output := "res://previews/hud-1v1-implemented.png"
	var image := root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(output))
	if error == OK:
		print("Implemented 1v1 HUD preview saved: %s" % output)
	else:
		push_error("Could not save implemented 1v1 HUD preview (error %d)" % error)
	quit(error)
