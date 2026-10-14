extends SceneTree

## The `--vs-3-cpu` playtest shortcut must land in a live four-fighter match
## with the keyboard human in slot 1 and three STANDARD CPUs.

const MAIN_SCENE := preload("res://scenes/Main.tscn")
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	# A stale roster choice must not leak into the shortcut.
	game._roster.difficulties[2] = game.Difficulty.RUTHLESS

	game.start_vs_three_cpu()
	_check(game.state == Phase.PLANNING, "the shortcut must start a match, not a menu")
	_check(game.players.size() == 4, "the shortcut must spawn four fighters")
	_check(not game.team_mode, "the shortcut must be a free-for-all")
	_check(not game.is_ai(0) and game.player_devices[0] == game.KEYBOARD_DEVICE,
		"Player 1 must be the keyboard human")
	for i in range(1, 4):
		_check(game.is_ai(i), "Player %d must be a CPU" % (i + 1))
		_check(game.player_difficulty(i) == game.Difficulty.STANDARD,
			"Player %d must play at STANDARD" % (i + 1))

	if _failures == 0:
		print("Vs three CPU launch: all tests passed")
	else:
		push_error("Vs three CPU launch: %d test(s) failed" % _failures)
	game._ai_searches.fill(null)
	await process_frame
	await process_frame
	game.queue_free()
	await process_frame
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
