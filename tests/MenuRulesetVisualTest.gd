extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._transition.visible = false
	game._menu._activate(game._menu.ROW_PLAY)
	game._menu._select(game._menu.SETUP_PLAYERS)
	game._menu.handle_key(KEY_RIGHT)
	game._menu.handle_key(KEY_RIGHT)
	game._menu._select(game._menu.SETUP_FIRST_FIGHTER)
	game._menu.handle_key(KEY_RIGHT)
	game._menu._select(game._menu.SETUP_FIRST_FIGHTER + 1)
	game._menu.handle_key(KEY_RIGHT)
	game._menu.handle_key(KEY_RIGHT)
	await _save_frame("res://previews/menu-dossier-character.png", "Character dossier")
	game._menu._select(game._menu.SETUP_MODE)
	await _save_frame("res://previews/menu-dossier-mode.png", "Mode dossier")
	game._menu._select(game._menu._setup_arena_row())
	game._menu.handle_key(KEY_RIGHT)
	await _save_frame("res://previews/menu-dossier-arena.png", "Arena dossier")
	game._menu._select(game._menu._setup_lives_row())
	await _save_frame("res://previews/menu-ruleset.png", "Rules dossier")
	quit(OK)


func _save_frame(output: String, label: String) -> void:
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(output))
	if error == OK:
		print("%s preview saved: %s" % [label, output])
	else:
		push_error("Could not save %s preview (error %d)" % [label, error])
