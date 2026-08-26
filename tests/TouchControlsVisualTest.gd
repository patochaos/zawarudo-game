extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	# Keep the fixed 1280x720 touch layout visible regardless of the desktop's
	# remembered/maximized window state or DPI scale.
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	await process_frame
	var game = MAIN_SCENE.instantiate()
	game.force_touch_controls = true
	root.add_child(game)
	await process_frame
	game._on_menu_start(true, 0)
	await process_frame
	await process_frame
	await process_frame
	await process_frame

	var output := "res://previews/touch-controls-mvp.png"
	var image := root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(output))
	if error == OK:
		print("Touch controls preview saved: %s" % output)
	else:
		push_error("Could not save touch controls preview (error %d)" % error)
	quit(error)
