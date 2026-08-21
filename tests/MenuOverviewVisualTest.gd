extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._transition.visible = false
	await process_frame
	var error := _save("res://previews/menu-main-current.png")
	if error != OK:
		quit(error)
		return
	game._menu._activate(game._menu.ROW_OPTIONS)
	await process_frame
	await process_frame
	error = _save("res://previews/menu-options-current.png")
	quit(error)


func _save(output: String) -> Error:
	var image := root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(output))
	if error == OK:
		print("Menu preview saved: %s" % output)
	else:
		push_error("Could not save menu preview (error %d)" % error)
	return error
