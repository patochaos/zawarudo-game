extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._on_menu_start(true, 3, 2)
	game._transition.set_process(false)
	game._transition._elapsed = 0.12
	game._transition._surface.queue_redraw()
	await process_frame
	await process_frame
	var output := "res://previews/arena-transition.png"
	var image := root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(output))
	if error == OK:
		print("Arena transition preview saved: %s" % output)
	else:
		push_error("Could not save arena transition preview (error %d)" % error)
	quit(error)
