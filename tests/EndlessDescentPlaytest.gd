extends SceneTree

## Reproducible 1v1 bot playtest using the real planner and execution loop.
## Results describe these bots, not human fun or an optimal layout.
const MAIN := preload("res://scenes/Main.tscn")
const Capture := preload("res://tests/VisualCaptureHelper.gd")
var label := "baseline"
var visual := false
var samples := 4


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
		if arg == "--visual": visual = true
		if arg.begins_with("--samples="): samples = int(arg.trim_prefix("--samples="))
	call_deferred("_run")


func _run() -> void:
	var game = MAIN.instantiate()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game.hit_freeze_enabled = false
	var reports := []
	for sample in samples:
		game.start_quick_match(false, 1, 2)
		game.rng.seed = 90210 + sample * 137
		game.restart()
		game.set_physics_process(false)
		game._transition.visible = false
		game._time_stop.visible = false
		var report := {"seed": 90210 + sample * 137, "first_hit_turn": -1,
			"ticks": 0, "upper_ticks": 0, "centre_ticks": 0, "vertical_wraps": 0,
			"side_wraps": 0, "shots": 0, "max_idle_turns": 0}
		var quiet := 0
		while game.state != Phase.GAME_OVER and game.turn <= 24:
			var score_before: int = game.score[0] + game.score[1]
			for i in 2:
				var ai := Ai.new()
				ai.begin(game, i, 1 - i)
				ai.finish()
				ai.apply()
				if game.players[i].plan.has_shot(): report.shots += 1
			game._begin_execution()
			while game.state == Phase.EXECUTING:
				var before := [game.players[0].position, game.players[1].position]
				var clock_before: int = game.world_tick
				game._sim_tick(game.tick_dt())
				if game.world_tick == clock_before:
					game._super_freeze.cancel()
					continue
				for i in 2:
					var pos: Vector2 = game.players[i].position
					report.ticks += 1
					if pos.y < 330: report.upper_ticks += 1
					if pos.x > 430 and pos.x < 850: report.centre_ticks += 1
					if absf(pos.y - before[i].y) > 600: report.vertical_wraps += 1
					if absf(pos.x - before[i].x) > 1100: report.side_wraps += 1
				game.exec_tick += 1
				if visual and sample == 0 and game.turn <= 4 and game.exec_tick == 22:
					await Capture.pin_window(self)
					game._ui.refresh()
					game._preview.queue_redraw()
					await Capture.settle(self)
					if Capture.save(self, "res://previews/descent-%s-turn%d.png" % [label, game.turn], "Descent playtest") != OK:
						quit(1)
						return
				if game.state == Phase.EXECUTING and game.exec_tick >= game.exec_ticks_total:
					game._end_execution()
			var total: int = game.score[0] + game.score[1]
			if total > score_before:
				if report.first_hit_turn == -1: report.first_hit_turn = game.turn
				quiet = 0
			else: quiet += 1
			report.max_idle_turns = maxi(report.max_idle_turns, quiet)
			await process_frame
		report["turns"] = game.turn
		report["score"] = Array(game.score).duplicate()
		report["winner"] = game.winner
		reports.append(report)
		print("DESCENT SAMPLE ", JSON.stringify(report))
	var file := FileAccess.open("res://previews/descent-%s.json" % label, FileAccess.WRITE)
	file.store_string(JSON.stringify(reports, "\t"))
	game.free()
	quit(0)
