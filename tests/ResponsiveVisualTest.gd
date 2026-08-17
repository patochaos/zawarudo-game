extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const TARGETS := [Vector2i(1024, 576), Vector2i(1600, 900), Vector2i(1024, 768)]


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._transition.visible = false
	game._on_menu_start(true, 0, 2)
	game._transition.visible = false
	for target: Vector2i in TARGETS:
		DisplayServer.window_set_size(target)
		for i in 5:
			await process_frame
		var image := root.get_texture().get_image()
		if image == null or image.get_width() < 1 or image.get_height() < 1:
			push_error("Could not read the responsive viewport at %s" % target)
			quit(1)
			return
		var output := "res://previews/responsive-%dx%d.png" % [target.x, target.y]
		var error := image.save_png(ProjectSettings.globalize_path(output))
		if error != OK:
			push_error("Could not save responsive preview %s (error %d)" % [output, error])
			quit(error)
			return
		print("Responsive preview saved: %s (%dx%d texture)" % [
			output, image.get_width(), image.get_height()])
	root.remove_child(game)
	game.free()
	await process_frame
	quit(0)
