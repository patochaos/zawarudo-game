extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game._on_menu_tutorial()
	await process_frame
	await process_frame

	var error := OK
	for page in game._tutorial.PAGES.size():
		if page > 0:
			game._tutorial.advance()
			await process_frame
			await process_frame
		var output := "res://previews/tutorial-briefing-%02d.png" % (page + 1)
		var image := root.get_texture().get_image()
		error = image.save_png(ProjectSettings.globalize_path(output))
		if error != OK:
			push_error("Could not save tutorial page %d (error %d)" % [page + 1, error])
			break
		print("Tutorial briefing preview saved: %s" % output)
	quit(error)
