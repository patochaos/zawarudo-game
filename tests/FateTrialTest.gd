extends SceneTree

## Trial 01 proves a complete solo journey rather than another difficulty
## preset: direct menu launch, authored public threat, survival victory, failure,
## and retry all stay inside the same deterministic match machinery.

const GAME_MANAGER := preload("res://scripts/GameManager.gd")
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = GAME_MANAGER.new()
	root.add_child(game)
	await process_frame
	# This synchronous physics suite does not exercise audio playback.
	game._sfx.muted = true

	game._menu.developer_mode = true
	game._menu._activate(game._menu.ROW_EXPERIMENTS)
	game._menu._activate(game._menu.ROW_FATE_TRIAL)
	_check(game.fate_trial_mode and game.state == Phase.PLANNING,
		"Fate Trial must launch directly from the title into planning")
	_check(game.level_name == "THE CROSSFIRE" and game.players.size() == 2,
		"Trial 01 must use its authored two-Duelist encounter")
	_check(game.player_weapons[0] == game.Weapon.KNIVES \
		and game.player_weapons[1] == game.Weapon.KNIVES,
		"both the player and hostile echo must use the Duelist kit")
	_check(game.arrows.size() == 1 and game.arrows[0].shooter == 1,
		"the opening freeze must inherit one hostile knife from the left")
	_check(game.players[1].plan.confirmed and game.players[1].plan.has_shot(),
		"the hostile Duelist must arrive with a complete committed plan")
	_check(not game.hides_plan(1) and game.ghost_path[1].size() > 1,
		"the hostile route and shot must be visible during the trial")
	_check(is_equal_approx(game.planning_window_duration,
		game.FATE_TRIAL_PLANNING_DURATION),
		"the solo trial must grant its authored reading time")

	# Doing nothing is not a safe solution: the inherited knife must physically
	# cross the opening spawn and trigger the real hit/failure path.
	game._begin_execution()
	while game.state == Phase.EXECUTING and game.exec_tick < game.exec_ticks_total:
		game._sim_tick(game.tick_dt())
		if game.state == Phase.EXECUTING:
			game.exec_tick += 1
	_check(game.state == Phase.GAME_OVER and not game.fate_trial_succeeded,
		"the opening crossfire must punish a player who commits no escape")
	game._request_rematch()
	_check(game.state == Phase.PLANNING,
		"the failed physical attempt must return to the authored freeze on retry")

	# Ending three safe windows is the objective; score and enemy health are not.
	for survived in range(1, game.FATE_TRIAL_WINDOWS + 1):
		game.state = Phase.EXECUTING
		game._end_execution()
		_check(game.fate_trial_windows_survived == survived,
			"each safe execution must advance trial progress exactly once")
		if survived < game.FATE_TRIAL_WINDOWS:
			_check(game.state == Phase.PLANNING and game.players[1].plan.confirmed,
				"a surviving player must receive the next revealed hostile plan")
	_check(game.state == Phase.GAME_OVER and game.fate_trial_succeeded \
		and game.winner == 0,
		"three survived windows must end in a successful trial result")

	game._request_rematch()
	_check(game.state == Phase.PLANNING and game.fate_trial_windows_survived == 0 \
		and game.arrows.size() == 1,
		"Retry must rebuild the authored opening state, including its old knife")
	game.state = Phase.EXECUTING
	game._on_player_hit(0, game.players[0].position, 1)
	_check(game.state == Phase.GAME_OVER and not game.fate_trial_succeeded \
		and game.winner == 1,
		"any hit on the player must immediately fail the survival trial")

	root.remove_child(game)
	game.free()
	# Flush projectiles queued for deletion during the synchronous simulation.
	await process_frame
	if _failures == 0:
		print("Fate Trial: all tests passed")
	else:
		push_error("Fate Trial: %d test(s) failed" % _failures)
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
