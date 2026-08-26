extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	await process_frame
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game._on_menu_start(true, 0)
	await process_frame
	await process_frame
	await process_frame
	await process_frame
	var kinds := [Effects.Kind.SPARK, Effects.Kind.SHATTER, Effects.Kind.KILL,
		Effects.Kind.CLASH, Effects.Kind.AFTERMATH, Effects.Kind.EXPLOSION]
	var colors := [Color(1.0, 0.76, 0.24), Color(0.45, 0.92, 1.0),
		Color(1.0, 0.32, 0.38), Color(0.94, 0.86, 0.56),
		Color(0.75, 0.38, 1.0), Color(0.36, 0.96, 1.0)]
	for i in kinds.size():
		game._effects.add(kinds[i], Vector2(190.0 + float(i) * 178.0, 420.0), colors[i],
			1.2 if kinds[i] == Effects.Kind.EXPLOSION else 1.0)
		if kinds[i] == Effects.Kind.AFTERMATH:
			game._effects._fx[-1]["label"] = "AFTERMATH"
	await process_frame
	await process_frame
	var output := "res://previews/kenney-vfx-polish.png"
	var image := root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(output))
	if error == OK:
		print("Kenney VFX preview saved: %s" % output)
	else:
		push_error("Could not save Kenney VFX preview (error %d)" % error)
	quit(error)
