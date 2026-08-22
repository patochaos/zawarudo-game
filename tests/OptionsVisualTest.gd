extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const VisualCapture := preload("res://tests/VisualCaptureHelper.gd")


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
	await VisualCapture.await_transition(self, game, 3)

	var error := VisualCapture.save(self, "res://previews/options-accessibility.png",
		"Options accessibility preview")
	root.remove_child(game)
	game.free()
	await process_frame
	quit(error)
