extends SceneTree
## Captures every arena in its duel and four-fighter form so the cut-down and
## the crowd board can be judged side by side. Run windowed:
##   godot --path . --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/ArenaCountsVisualTest.gd --quit-after 600
const MAIN := preload("res://scenes/Main.tscn")
const Capture := preload("res://tests/VisualCaptureHelper.gd")
var game
var error := OK


func _init() -> void:
	call_deferred("run")


func run() -> void:
	game = MAIN.instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game._sfx.muted = true
	game.settings_path = "user://test-arenacountsvisual-settings.cfg"
	await Capture.pin_window(self)
	for index in Levels.count():
		for count in [2, 4]:
			game.start_quick_match(true, index, count)
			game._transition.visible = false
			game._preview.queue_redraw()
			game._ui.refresh()
			await Capture.settle(self, 3)
			error = Capture.save(self, "res://previews/arena-%d-%dp.png" % [index + 1, count], "Arena counts")
			if error != OK:
				quit(error)
	quit(0)
