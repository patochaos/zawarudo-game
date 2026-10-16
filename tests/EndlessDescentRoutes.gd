extends SceneTree
const MAIN := preload("res://scenes/Main.tscn")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var game = MAIN.instantiate()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game.randomize_spawns = false
	game.start_quick_match(false, 4, 2)
	game.set_physics_process(false)
	var report := {}
	var failures := 0
	for side in 2:
		for direction in [0, -1 if side == 0 else 1]:
			var pos: Vector2 = game.players[side].position
			var vel := Vector2(0, -game.jump_impulse)
			var ground := false
			var min_y := pos.y
			var bonks := 0
			for tick in 80:
				var old_vy := vel.y
				var step := Player.step_state(pos, vel, ground, direction, true, game.tick_dt(), game)
				pos = step[0]; vel = step[1]; ground = step[2]
				if old_vy < -100 and vel.y == 0.0: bonks += 1
				min_y = minf(min_y, pos.y)
				if ground: break
			report["p%d_dir%d" % [side, direction]] = {"rise": game.players[side].position.y - min_y,
				"landing": [pos.x, pos.y], "ceiling_hits": bonks}
			if direction != 0 and (bonks != 0 or absf(pos.y - 456.0) > 1.0):
				failures += 1
				push_error("A held outward opening jump must reach the permanent stair without a ceiling collision")
	print("DESCENT ROUTES ", JSON.stringify(report))
	game.free()
	quit(failures)
