extends SceneTree

## Captures the rendered breakable states (cracked, broken), the shard burst
## mid-flight, and the match setup plan with the arena's room behind it.
## Run WINDOWED (see VisualCaptureHelper.gd); writes previews/platform-damage-*.png.
const MAIN := preload("res://scenes/Main.tscn")
const Capture := preload("res://tests/VisualCaptureHelper.gd")
## The first rotation arena whose four-player layout carries breakable cover.
const ARENA := 1


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = MAIN.instantiate()
	root.add_child(game)
	await process_frame
	await Capture.pin_window(self)
	game._sfx.muted = true
	game.start_quick_match(false, ARENA, 4)
	game.set_physics_process(false)
	game._transition.visible = false
	game._time_stop._freeze_flash = 0.0
	game._time_stop._resume_flash = 0.0
	game._begin_execution()
	game._time_stop._resume_flash = 0.0
	var cover: Array = []
	for platform: Dictionary in game._arena.platforms:
		if platform["hp"] > 0:
			cover.append(platform)
	if cover.is_empty():
		push_error("arena %d has no breakable cover to capture" % ARENA)
		quit(1)
		return
	for platform: Dictionary in cover:
		platform["max_hp"] = maxi(int(platform.get("max_hp", platform["hp"])), 3)
		platform["hp"] = platform["max_hp"] - 1
	game._arena.queue_redraw()
	game._ui.refresh()
	await Capture.settle(self, 4)
	if not _save("cracked"):
		return
	for platform: Dictionary in cover:
		platform["hp"] = 1
	game._arena.queue_redraw()
	await Capture.settle(self, 2)
	if not _save("broken"):
		return
	# Shards one third of the way through their flight, from each cover centre.
	game._effects.set_process(false)
	for platform: Dictionary in cover:
		var r: Rect2 = platform["rect"]
		game._effects.add(Effects.Kind.SHATTER, r.position + r.size * 0.5, Color(0.85, 0.55, 0.42))
	for f in game._effects._fx:
		f["t"] = Effects.LIFE[Effects.Kind.SHATTER] * 0.33
	game._effects.queue_redraw()
	await Capture.settle(self, 2)
	if not _save("shatter"):
		return
	game.free()
	await process_frame
	# The rules screen, where the plan now sits on the arena's rendered layers.
	game = MAIN.instantiate()
	root.add_child(game)
	await process_frame
	await Capture.pin_window(self)
	game._sfx.muted = true
	game.state = Phase.MATCH_SETUP
	game._menu.visible = false
	game._setup.open(game._roster.build_lineup())
	for level in [0, 4]:
		game._setup.level = level
		game._setup._refresh()
		await Capture.settle(self, 4)
		if not _save("setup-%d" % level):
			return
	game.free()
	await process_frame
	quit(0)


func _save(state: String) -> bool:
	var error := Capture.save(self, "res://previews/platform-damage-%s.png" % state,
		"Platform damage %s" % state, Vector2i(1280, 720))
	if error != OK:
		quit(error)
	return error == OK
