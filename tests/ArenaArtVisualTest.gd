extends SceneTree

const MAIN := preload("res://scenes/Main.tscn")
const Capture := preload("res://tests/VisualCaptureHelper.gd")
const ARENAS := [0, 1, 3, 4, 5, 6]
var _gallery: Image


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_gallery = Image.create(1280, 1080, false, Image.FORMAT_RGBA8)
	for slot in ARENAS.size():
		var index: int = ARENAS[slot]
		var game = MAIN.instantiate()
		root.add_child(game)
		await process_frame
		await Capture.pin_window(self)
		game._sfx.muted = true
		game.start_quick_match(false, index, 2)
		game.set_physics_process(false)
		game._transition.visible = false
		game._time_stop._freeze_flash = 0.0
		game._time_stop._resume_flash = 0.0
		game._reset_pilot(0)
		for tick in 22:
			game._pilot_step(0, 1, tick == 0, tick < 12)
		game.players[0].plan.shot_tick = 12
		game.players[0].plan.power = 0.6
		game._rebuild_ghost_paths()
		game._preview.queue_redraw()
		game._ui.refresh()
		await Capture.settle(self, 4)
		if not _save(index, "planning", Vector2i(1280, 720)):
			return
		await Capture.pin_window(self, Vector2i(1024, 576))
		game._preview.high_contrast = true
		game._preview.queue_redraw()
		await Capture.settle(self)
		if not _save(index, "small-contrast", Vector2i(1024, 576)):
			return
		await Capture.pin_window(self)
		game._preview.high_contrast = false
		game._begin_execution()
		for tick in 13:
			game.exec_tick = tick
			game._sim_tick(game.tick_dt())
		game._time_stop._resume_flash = 0.0
		game._ui.refresh()
		game._preview.queue_redraw()
		await Capture.settle(self)
		if not _save(index, "execution", Vector2i(1280, 720)):
			return
		var thumb := root.get_texture().get_image()
		thumb.resize(640, 360, Image.INTERPOLATE_LANCZOS)
		_gallery.blit_rect(thumb, Rect2i(0, 0, 640, 360), Vector2i(slot % 2 * 640, slot / 2 * 360))
		game.start_quick_match(false, index, 4)
		game.set_physics_process(false)
		game._transition.visible = false
		game._time_stop._freeze_flash = 0.0
		game._time_stop._resume_flash = 0.0
		# Review surviving cover at one hit, so cracks/pips are visibly exercised.
		for platform: Dictionary in game._arena.platforms:
			if platform["hp"] > 0:
				platform["hp"] = 1
		game._arena.queue_redraw()
		game._preview.queue_redraw()
		game._ui.refresh()
		await Capture.settle(self)
		if not _save(index, "four-damage", Vector2i(1280, 720)):
			return
		game.free()
		await process_frame
	var error := _gallery.save_png(ProjectSettings.globalize_path("res://previews/arena-art-gallery.png"))
	quit(error)


func _save(index: int, state: String, size: Vector2i) -> bool:
	var error := Capture.save(self, "res://previews/arena-art-%d-%s.png" % [index, state],
		"Arena %d %s" % [index, state], size)
	if error != OK:
		quit(error)
	return error == OK
