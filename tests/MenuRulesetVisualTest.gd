extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._menu._select(game._menu.ROW_MODE_AI_B)
	await process_frame
	await process_frame

	var output := "res://previews/menu-ruleset.png"
	var image := root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(output))
	if error == OK:
		print("Version B menu preview saved: %s" % output)
	else:
		push_error("Could not save Version B menu preview (error %d)" % error)
	quit(error)
