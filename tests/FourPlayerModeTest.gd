extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true

	game._on_menu_start(true, 0, 4)
	game._ui.refresh()
	_check(game.players.size() == 4, "four-player mode must spawn four fighters")
	_check(game._ui._pips[3][0].visible,
		"the four-player HUD must expose Player 4's score pips")
	_check(not game.is_ai(0), "Player 1 must remain human")
	for i in range(1, 4):
		_check(game.is_ai(i), "Player %d must be AI-controlled" % (i + 1))
		_check(game._ai_searches[i] != null, "Player %d must receive an independent AI search" % (i + 1))

	var unique_spawns := {}
	for player in game.players:
		unique_spawns[player.position] = true
	_check(unique_spawns.size() == 4, "all four fighters must start at distinct sockets")

	# The nearest-target policy lets AI fighters attack each other instead of all
	# three unfairly tunnelling Player 1.
	_check(game._ai_target_for(1) != 1 and game._ai_target_for(1) > 0,
		"an AI must be able to choose another AI as its rival")

	for i in range(1, 4):
		game._ai_searches[i].finish()
		game._ai_searches[i].apply()
	game._tick_ai(game.ai_think_max + 0.1)
	_check(game.players[1].plan.confirmed and game.players[2].plan.confirmed \
			and game.players[3].plan.confirmed,
		"all three AIs must finish and confirm independent plans")
	game._confirm(0)
	_check(game.state == Phase.COMMITTING,
		"the turn must commit after the human and all three AIs confirm")

	game._on_player_hit(2, game.players[2].position, 3)
	_check(game.score[3] == 1 and game.score[0] == 0 and game.score[1] == 0 and game.score[2] == 0,
		"a four-player hit must score for the knife owner")
	game._begin_execution()
	game._end_execution()
	_check(game.turn == 2 and game.players[2].alive,
		"a defeated fighter must respawn when the next four-player turn begins")
	_check(game._ai_searches[1] != null and game._ai_searches[2] != null \
			and game._ai_searches[3] != null,
		"all three AI searches must be rebuilt for the next turn")

	game._on_menu_start(false, 0, 2)
	game._ui.refresh()
	_check(game.players.size() == 2 and not game.is_ai(1),
		"switching back to local duel must restore two human fighters")
	_check(not game._ui._pips[2][0].visible and not game._ui._pips[3][0].visible,
		"duel HUD must hide the inactive Player 3 and Player 4 scores")

	if _failures == 0:
		print("Four-player mode: all tests passed")
	else:
		push_error("Four-player mode: %d test(s) failed" % _failures)
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
