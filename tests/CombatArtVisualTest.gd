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
	game.free()
	await process_frame
	if not await _capture_impacts():
		return
	if not await _capture_knives():
		return
	quit(0)


## SPARK and CLASH shards on the arena that selects each surface set: Crosshair
## Court (stone), Clockwork Gallery (metal) and Pulse Chamber (glass), through
## the real level load, in normal and reduced-flash modes. Pulse Chamber is also
## captured at 1024x576.
func _capture_impacts() -> bool:
	for arena in [0, 1, 3]:
		var game = MAIN.instantiate()
		root.add_child(game)
		await process_frame
		game._sfx.muted = true
		game.start_quick_match(false, arena, 2)
		game.set_physics_process(false)
		game._transition.visible = false
		game._time_stop.visible = false
		game._effects.set_process(false)
		game.state = Phase.EXECUTING
		var sizes := [Vector2i(1280, 720), Vector2i(1024, 576)] if arena == 3 else [Vector2i(1280, 720)]
		for pixels in sizes:
			await Capture.pin_window(self, pixels)
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
				if Capture.save(self, "res://previews/combat-impacts-%d-%d-%s.png" %
					[arena, pixels.x, str(reduced)], "Impacts", pixels) != OK:
					quit(1)
					return false
		game.free()
		await process_frame
	return true


## The rendered dagger on every arena at match scale: a ring of still cells at
## every 22.5 degrees, two streaking knives, a tumbling clashed one and a wrapped
## trail, for both players. Cosmetic nodes only: nothing joins `arrows`, so no
## simulation state is touched. The last arena is also captured in planning at
## 1024x576, where the halo and velocity chevron must still frame the sprite.
func _capture_knives() -> bool:
	for arena in Levels.count():
		var game = MAIN.instantiate()
		root.add_child(game)
		await process_frame
		await Capture.pin_window(self)
		game._sfx.muted = true
		game.start_quick_match(false, arena, 2)
		game.set_physics_process(false)
		game._transition.visible = false
		game._time_stop.visible = false
		game._effects.set_process(false)
		game.state = Phase.EXECUTING
		var knives: Array = []
		for i in 16:
			var angle := float(i) * TAU / 16.0
			knives.append(_knife(game, Vector2(640.0, 330.0) + Vector2.from_angle(angle) * 150.0,
				Vector2.from_angle(angle) * 520.0, i % 2))
		for i in 2:
			var fast: Vector2 = Vector2(1.0, -0.12 if i == 0 else 0.25).normalized() \
				* game.arrow_speed_max * (1.0 if i == 0 else 1.35)
			var streak = _knife(game, Vector2(300.0, 200.0 + float(i) * 440.0), fast, i)
			streak.boost_count = i
			knives.append(streak)
		var tumbling = _knife(game, Vector2(980.0, 640.0), Vector2(-160.0, 90.0), 1)
		tumbling.clashed = true
		tumbling.clash_count = 2
		tumbling.rotation = 0.7
		knives.append(tumbling)
		var trailing = _knife(game, Vector2(1020.0, 180.0), Vector2(-430.0, 140.0), 0)
		for k in 10:
			trailing.trail.append(trailing.position + Vector2(38.0, -12.0) * float(10 - k))
		knives.append(trailing)
		for k in knives:
			k.queue_redraw()
		game._preview.queue_redraw()
		game._ui.refresh()
		await Capture.settle(self, 4)
		if Capture.save(self, "res://previews/combat-knives-%d.png" % arena,
			"Knives", Vector2i(1280, 720)) != OK:
			quit(1)
			return false
		if arena == Levels.count() - 1:
			await Capture.pin_window(self, Vector2i(1024, 576))
			game.state = Phase.PLANNING
			for k in knives:
				k.queue_redraw()
			game._preview.queue_redraw()
			game._ui.refresh()
			await Capture.settle(self, 4)
			if Capture.save(self, "res://previews/combat-knives-planning-1024.png",
				"Knives", Vector2i(1024, 576)) != OK:
				quit(1)
				return false
		game.free()
		await process_frame
	return true


func _knife(game, at: Vector2, velocity: Vector2, owner: int) -> Arrow:
	var a := Arrow.new()
	a.cfg = game
	a.shooter = owner
	a.color = game.PLAYER_COLORS[owner]
	a.position = at
	a.vel = velocity
	a.rotation = velocity.angle()
	game._arrow_layer.add_child(a)
	return a
