extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const VisualCapture := preload("res://tests/VisualCaptureHelper.gd")


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var game = MAIN_SCENE.instantiate()
	game.offline_tuning_path = ""
	root.add_child(game)
	await process_frame
	await VisualCapture.pin_window(self)
	game._sfx.muted = true
	game._transition.visible = false
	game._menu._select(game._menu.ROW_TUNING)
	await VisualCapture.settle(self, 3)
	var error := VisualCapture.save(self, "res://previews/offline-tuning-menu.png",
		"Tuning main-menu entry", Vector2i(1280, 720))
	game._menu._activate(game._menu.ROW_TUNING)
	await VisualCapture.await_transition(self, game, 4)
	error = maxi(error, VisualCapture.save(self, "res://previews/offline-tuning-presets.png",
		"Offline tuning presets", Vector2i(1280, 720)))
	game.offline_tuning.apply_preset("tactical_duel")
	await VisualCapture.pin_window(self, Vector2i(960, 540))
	await VisualCapture.settle(self, 3)
	error = maxi(error, VisualCapture.save(self, "res://previews/offline-tuning-presets-small.png",
		"Preset selection at 960x540", Vector2i(960, 540)))
	game.offline_tuning.reset_all()
	await VisualCapture.pin_window(self)
	game._offline_tuning_layer._show_group("Timing")
	await VisualCapture.settle(self, 3)
	error = maxi(error, VisualCapture.save(self, "res://previews/offline-tuning.png",
		"Offline tuning preview", Vector2i(1280, 720)))
	game._offline_tuning_layer._show_group("Projectiles")
	await VisualCapture.settle(self, 3)
	error = maxi(error, VisualCapture.save(self, "res://previews/offline-tuning-projectiles.png",
		"Projectile tuning preview", Vector2i(1280, 720)))
	game._offline_tuning_layer._show_group("Movement")
	await VisualCapture.pin_window(self, Vector2i(960, 540))
	await VisualCapture.settle(self, 3)
	error = maxi(error, VisualCapture.save(self, "res://previews/offline-tuning-movement-small.png",
		"Movement tuning at 960x540", Vector2i(960, 540)))
	root.remove_child(game)
	game.free()
	await process_frame
	quit(error)
