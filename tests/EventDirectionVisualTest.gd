extends SceneTree
## Captures the Gate 3 beats: impact crop, the SUPER anticipation and
## tear-away, and the final tableau. Run windowed:
##   godot --path . --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/EventDirectionVisualTest.gd --quit-after 600
const MAIN := preload("res://scenes/Main.tscn")
const Capture := preload("res://tests/VisualCaptureHelper.gd")
var game
var error := OK


func _init() -> void:
	call_deferred("run")


func snap(name: String) -> void:
	game._transition.visible = false
	game._preview.queue_redraw()
	game._ui.refresh()
	game._event_direction.queue_redraw()
	await Capture.settle(self, 2)
	error = Capture.save(self, "res://previews/direction-" + name + ".png", "Event direction")
	if error != OK:
		quit(error)


func run() -> void:
	game = MAIN.instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game._sfx.muted = true
	game.settings_path = "user://test-eventdirectionvisual-settings.cfg"
	await Capture.pin_window(self)
	var ed = game._event_direction
	ed.set_process(false)

	game.start_demo_duel(0)
	game._transition.visible = false
	for tick in 12:
		game._pilot_step(0, 1, tick == 0, true)
	game._confirm(0)

	ed.clear()
	game.state = Phase.EXECUTING
	ed.impact(game.players[1].position, game.players[1].color)
	ed._process(0.04)
	await snap("impact")

	ed.clear()
	game._super_freeze.play(0, game.players[0].color, 0, false, game.super_cutin_duration)
	ed.super_beats(0, game.players[0].color, game.super_cutin_duration)
	for moment in [0.06, 0.50, 0.95]:
		game._super_freeze._art.elapsed = moment * game.super_cutin_duration
		ed._process(moment * game.super_cutin_duration - (0.0 if moment == 0.06 else 0.0))
		await snap("super-%d" % int(moment * 100.0))
	game._super_freeze.cancel()

	ed.clear()
	game.state = Phase.GAME_OVER
	game.winner = 0
	game.players[1].alive = false
	game.score[0] = 3
	game.score[1] = 1
	game._time_stop.visible = false
	game._record_ladder_result(0)
	ed.tableau(0)
	ed._process(0.5)
	await snap("tableau")
	quit(0)
