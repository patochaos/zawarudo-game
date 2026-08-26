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

	game._on_roster_confirmed({
		"mode": MatchSetupLayer.BattleMode.VS,
		"player_count": 4,
		"roles": ["HUMAN", "AI", "AI", "AI"],
		"devices": [-2, -1, -1, -1],
		"teams": [-1, -1, -1, -1],
		"weapons": [0, 0, 0, 0],
		"level": 0,
		"match_lives": 5,
		"difficulty": game.Difficulty.STANDARD,
		"difficulties": [game.Difficulty.STANDARD, game.Difficulty.STANDARD,
			game.Difficulty.NOVICE, game.Difficulty.RUTHLESS],
	})
	game._ui.refresh()
	_check(not game._online_state_digest().is_empty(),
		"the deterministic state digest must serialize every live player field")
	_check(game.players.size() == 4, "four-player mode must spawn four fighters")
	_check(game.hits_to_win == 5, "new matches must default to five hits")
	_check(is_equal_approx(game._planning_duration_for_turn(1), 5.0) \
		and is_equal_approx(game._planning_duration_for_turn(3), 5.0) \
		and is_equal_approx(game._planning_duration_for_turn(4), 4.5) \
		and is_equal_approx(game._planning_duration_for_turn(5), 4.0) \
		and is_equal_approx(game._planning_duration_for_turn(6), 3.5) \
		and is_equal_approx(game._planning_duration_for_turn(20), 3.5),
		"planning time must shrink after round three and stop at the AI-safe floor")
	_check(not game._ui._fighter_seals[0].visible and not game._ui._fighter_seals[1].visible,
		"the portrait fighter seals must remain exclusive to 1v1")
	_check(game._ui._pips[3][0].visible,
		"the four-player HUD must expose Player 4's score pips")
	_check(not game.is_ai(0), "Player 1 must remain human")
	for i in range(1, 4):
		_check(game.is_ai(i), "Player %d must be AI-controlled" % (i + 1))
		_check(game._ai_searches[i] != null, "Player %d must receive an independent AI search" % (i + 1))
	_check(game.player_difficulty(2) == game.Difficulty.NOVICE \
		and game.player_difficulty(3) == game.Difficulty.RUTHLESS,
		"the configured match must carry each CPU's skill preset into live play")

	var unique_spawns := {}
	for player in game.players:
		unique_spawns[player.position] = true
	_check(unique_spawns.size() == 4, "all four fighters must start at distinct sockets")

	# Respawning uses the socket whose nearest living player is farthest away,
	# which is the relevant safety measure once three rivals occupy the map.
	game.players[0].position = Vector2(100.0, 596.0)
	game.players[1].position = Vector2(640.0, 596.0)
	game.players[2].position = Vector2(1100.0, 596.0)
	game.players[3].alive = false
	var expected_respawn: Vector2 = game.respawn_points[0]
	var expected_safety := -INF
	for candidate: Vector2 in game.respawn_points:
		var nearest := INF
		for living in 3:
			nearest = minf(nearest,
				game.wrap_delta(candidate, game.players[living].position).length_squared())
		if nearest > expected_safety:
			expected_safety = nearest
			expected_respawn = candidate
	game._respawn(3)
	_check(game.players[3].position == expected_respawn,
		"a four-player respawn must maximize distance from its nearest living rival")
	game.players[2].alive = false
	game.players[3].alive = false
	game._respawn(2)
	game._respawn(3)
	_check(game.players[2].position != game.players[3].position,
		"two fighters respawning together must occupy different safe sockets")

	# The nearest-target policy lets AI fighters attack each other instead of all
	# three unfairly tunnelling Player 1.
	_check(game._ai_target_for(1) != 1 and game._ai_target_for(1) > 0,
		"an AI must be able to choose another AI as its rival")
	# Equal-distance ties rotate with the turn instead of all collapsing onto the
	# lowest player index (which made the human P1 slot an accidental dogpile).
	game.players[0].position = Vector2(440.0, 360.0)
	game.players[1].position = Vector2(640.0, 360.0)
	game.players[2].position = Vector2(840.0, 360.0)
	game.players[3].position = Vector2(640.0, 560.0)
	game.players[2].alive = true
	game.players[3].alive = true
	game.turn = 1
	var first_tie_target: int = game._ai_target_for(1)
	game.turn = 2
	var next_tie_target: int = game._ai_target_for(1)
	_check(first_tie_target != next_tie_target,
		"symmetric nearest-target ties must rotate across turns")
	game.turn = 1
	game.score[0] = 3
	game.players[0].position = Vector2(340.0, 360.0)
	game.players[2].position = Vector2(760.0, 360.0)
	_check(game._ai_target_for(1) == 0,
		"a nearby score leader must draw multi-player AI pressure before snowballing")
	game.score[0] = 0

	var cursors_before := []
	for i in range(1, 4):
		cursors_before.append(game._ai_searches[i]._cursor)
	game._tick_ai(0.0)
	var searches_advanced := 0
	for i in range(1, 4):
		if game._ai_searches[i]._cursor > cursors_before[i - 1]:
			searches_advanced += 1
	_check(searches_advanced == 1,
		"four-player planning must advance only one AI search per frame")

	for i in range(1, 4):
		game._ai_searches[i].finish()
		game._ai_searches[i].apply()
	game._tick_ai(3.1)
	_check(game.players[1].plan.confirmed and game.players[2].plan.confirmed \
			and game.players[3].plan.confirmed,
		"all three AIs must finish and confirm independent plans")
	game._confirm(0)
	_check(game.state == Phase.COMMITTING,
		"the turn must commit after the human and all three AIs confirm")

	game._begin_execution()
	game._on_player_hit(2, game.players[2].position, 3)
	_check(game.score[3] == 1 and game.score[0] == 0 and game.score[1] == 0 and game.score[2] == 0,
		"a four-player hit must score for the knife owner")
	var first_hit_pause: float = game._hit_pause_left
	_check(is_equal_approx(first_hit_pause, game.HIT_PAUSE_DURATION),
		"the first execution hit must use the short hit-stop duration")
	# Model the first pause having elapsed before another knife lands later in the
	# same execution. That later impact must not start a second apparent stall.
	game._hit_pause_left = 0.0
	game._on_player_hit(1, game.players[1].position, 3)
	_check(is_zero_approx(game._hit_pause_left),
		"later four-player hits must not restart the same execution's hit-stop")
	game._end_execution()
	_check(game.turn == 2 and game.players[2].alive,
		"a defeated fighter must respawn when the next four-player turn begins")
	_check(game._ai_searches[1] != null and game._ai_searches[2] != null \
			and game._ai_searches[3] != null,
		"all three AI searches must be rebuilt for the next turn")
	game._begin_execution()
	_check(not game._hit_pause_used_this_execution and is_zero_approx(game._hit_pause_left),
		"a new execution must restore one fresh hit-stop opportunity")

	game._on_roster_confirmed({
		"mode": MatchSetupLayer.BattleMode.VS,
		"player_count": 3,
		"roles": ["HUMAN", "AI", "AI"],
		"devices": [-2, -1, -1],
		"teams": [-1, -1, -1],
		"weapons": [0, 0, 0],
		"level": 0,
		"match_lives": 5,
		"difficulty": game.Difficulty.STANDARD,
		"difficulties": [game.Difficulty.STANDARD, game.Difficulty.STANDARD,
			game.Difficulty.STANDARD],
	})
	_check(game.players.size() == 3 and game.is_ai(1) and game.is_ai(2),
		"three-player mode must spawn one human and two AI rivals")
	_check(game.platforms.size() == Levels.build(0, 3)["platforms"].size(),
		"three-player mode must load the arena's authored 3P platform variant")

	game._on_roster_confirmed({
		"mode": MatchSetupLayer.BattleMode.VS,
		"player_count": 2,
		"roles": ["HUMAN", "HUMAN"],
		"devices": [-2, 0],
		"teams": [-1, -1],
		"weapons": [0, 0],
		"level": 0,
		"match_lives": 7,
		"difficulty": game.Difficulty.STANDARD,
		"difficulties": [game.Difficulty.STANDARD, game.Difficulty.STANDARD],
	})
	game._ui.refresh()
	_check(game.players.size() == 2 and not game.is_ai(1),
		"switching back to local duel must restore two human fighters")
	_check(game.hits_to_win == 7 and game._ui._fighter_seals[0].points_to_win == 7,
		"the pre-match lives choice must reach the match rules and duel HUD")
	_check(game._ui._fighter_seals[0].visible and game._ui._fighter_seals[1].visible,
		"the 1v1 HUD must show one mirrored fighter seal per player")
	_check(game._ui._fighter_seals[0].size.y <= 58.0 \
		and game._ui._fighter_seals[1].size.y <= 58.0 \
		and game._ui._phase_track.position.y < 58.0,
		"all persistent duel HUD elements must stay inside the single top rail")
	_check(game._ui._banner_bg.position.y >= 600.0,
		"transient hit feedback must stay at the bottom instead of covering high action")
	_check(game._ui._fighter_seals[0].player_index == 0 \
		and game._ui._fighter_seals[1].player_index == 1,
		"the mirrored fighter seals must retain their P1/P2 identities")
	_check(not game._ui._pips[0][0].visible and not game._ui._pips[1][0].visible,
		"the 1v1 fighter seals must replace the anonymous centre score pips")
	game.score[0] = 2
	game.super_meter[0] = 0.65
	game.super_armed[0] = true
	game._ui.refresh()
	_check(game._ui._fighter_seals[0].points == 2 \
		and is_equal_approx(game._ui._fighter_seals[0].super_meter, 0.65) \
		and game._ui._fighter_seals[0].super_armed,
		"the 1v1 fighter seal must read live score, SUPER meter and armed state")
	_check(not game._ui._pips[2][0].visible and not game._ui._pips[3][0].visible,
		"duel HUD must hide the inactive Player 3 and Player 4 scores")
	game.state = Phase.GAME_OVER
	game.winner = 0
	game.rematch_level_index = 0
	game.rematch_level_name = str(Levels.build(0)["name"])
	game._ui.refresh()
	_check(game._ui._over_chrome.visible and game._ui._replay_button.visible \
		and game._ui._rematch_button.visible and game._ui._menu_button.visible,
		"the desktop result screen must expose visible replay, rematch and menu actions")
	game._ui._arena_next_button.pressed.emit()
	_check(game.rematch_level_index == 1,
		"the result screen's next-arena button must change the pending rematch arena")

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
