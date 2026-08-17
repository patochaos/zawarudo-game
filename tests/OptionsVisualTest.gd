extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game._transition.visible = false
	game._settings["high_contrast_previews"] = true
	game._menu.configure_options(game._settings)
	game._menu._page = game._menu.MenuPage.OPTIONS
	game._menu._cursor = game._menu.OPTION_PREVIEW_CONTRAST
	game._menu._refresh()
	for i in 3:
		await process_frame

	var output := "res://previews/options-accessibility.png"
	var image := root.get_texture().get_image()
	if image == null or image.get_width() < 1 or image.get_height() < 1:
		push_error("Could not read the rendered viewport for the options preview")
		quit(1)
		return
	var error := image.save_png(ProjectSettings.globalize_path(output))
	if error == OK:
		print("Options accessibility preview saved: %s" % output)
	else:
		push_error("Could not save options accessibility preview (error %d)" % error)
	root.remove_child(game)
	game.free()
	await process_frame
	quit(error)
