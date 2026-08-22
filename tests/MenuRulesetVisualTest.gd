extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const VisualCapture := preload("res://tests/VisualCaptureHelper.gd")


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
	var error := await _save_frame(game,
		"res://previews/menu-dossier-character.png", "Character dossier")
	if error == OK:
		game._menu._select(game._menu.SETUP_MODE)
		error = await _save_frame(game,
			"res://previews/menu-dossier-mode.png", "Mode dossier")
	if error == OK:
		game._menu._select(game._menu._setup_arena_row())
		game._menu.handle_key(KEY_RIGHT)
		error = await _save_frame(game,
			"res://previews/menu-dossier-arena.png", "Arena dossier")
	if error == OK:
		game._menu._select(game._menu._setup_lives_row())
		error = await _save_frame(game,
			"res://previews/menu-ruleset.png", "Rules dossier")
	quit(error)


func _save_frame(game, output: String, label: String) -> Error:
	await VisualCapture.await_transition(self, game)
	return VisualCapture.save(self, output, "%s preview" % label)
