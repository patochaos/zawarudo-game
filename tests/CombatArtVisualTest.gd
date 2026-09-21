extends SceneTree

const MAIN := preload("res://scenes/Main.tscn")
const Capture := preload("res://tests/VisualCaptureHelper.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = MAIN.instantiate()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game.start_quick_match(false, 0, 2)
	game.set_physics_process(false)
	game._transition.visible = false
	game._time_stop.visible = false
	game._effects.set_process(false)
	game._super_freeze._art.set_process(false)
	for pixels in [Vector2i(1280, 720), Vector2i(1024, 576)]:
		await Capture.pin_window(self, pixels)
		for player in 2:
			game._super_freeze.play(player, game.PLAYER_COLORS[player], 0, player == 1)
			for moment in [0.10, 0.52, 0.83]:
				game._super_freeze._art.elapsed = moment * game._super_freeze.DURATION
				game._super_freeze._art.queue_redraw()
				await Capture.settle(self)
				if Capture.save(self, "res://previews/combat-super-%d-p%d-%d.png" %
					[pixels.x, player, int(moment * 100)], "SUPER", pixels) != OK:
					quit(1)
					return
		game._super_freeze.cancel()
		game.state = Phase.EXECUTING
		game._preview.queue_redraw()
		game._ui.refresh()
		for reduced in [false, true]:
			game._effects.clear_all()
			game._effects.reduced_flashes = reduced
			for i in 8:
				game._effects.add(Effects.Kind.CLASH if i < 4 else Effects.Kind.SPARK,
					Vector2(400 + (i % 4) * 150, 340 + (i / 4) * 100),
					game.PLAYER_COLORS[i % 2])
				game._effects._fx[-1]["t"] = float(i % 4) * 0.09
			game._effects.queue_redraw()
			await Capture.settle(self)
			if Capture.save(self, "res://previews/combat-impacts-%d-%s.png" %
				[pixels.x, str(reduced)], "Impacts", pixels) != OK:
				quit(1)
				return
	game.free()
	quit(0)
