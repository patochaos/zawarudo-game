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
	game._transition.visible = false

	game._on_menu_team_battle()
	_check(game.state == Phase.TEAM_SELECT and game._team_select.visible,
		"Team Battle must open the device-and-side formation screen")
	game._team_select.debug_join_device(7, "TEST PAD")
	game._team_select.debug_set_side(TeamSelectLayer.KEYBOARD_DEVICE,
		TeamSelectLayer.SIDE_AZURE, true)
	game._team_select.debug_set_side(7, TeamSelectLayer.SIDE_CRIMSON, true)
	var slots: Array = game._team_select.build_slots()
	_check(slots.size() == 4 and slots[0]["team"] == 0 and slots[1]["team"] == 1 \
		and slots[2]["team"] == 0 and slots[3]["team"] == 1,
		"the formation must alternate Crimson/Azure slots for authored team spawns")
	_check(slots[0]["device"] == 7 and slots[1]["device"] == TeamSelectLayer.KEYBOARD_DEVICE,
		"human input ownership must survive side assignment")
	_check(slots[2]["role"] == "AI" and slots[3]["role"] == "AI",
		"unfilled team positions must become CPU allies")

	game._team_select._try_confirm()
	_check(game.state == Phase.CHARACTER_SELECT and game._character_select.independent_mode,
		"a locked formation must proceed to independent team character selection")
	_check(game._character_select.locked[2] and game._character_select.locked[3],
		"CPU roster slots must arrive ready while humans choose their fighters")
	game._character_select._confirm(0)
	game._character_select._confirm(1)
	_check(game.state == Phase.PLANNING and game.team_mode and game.players.size() == 4,
		"locking both human fighters must start a four-fighter team match")
	_check(game.player_teams == [0, 1, 0, 1],
		"team identities must reach gameplay unchanged")
	_check(not game.is_ai(0) and not game.is_ai(1) and game.is_ai(2) and game.is_ai(3),
		"mixed human/CPU ownership must be evaluated per slot")
	_check(game._keyboard_player() == 1 and game._input_map_for(1) == game.K_P1,
		"keyboard controls must follow their assigned fighter instead of always driving P1")
	_check(game._ai_target_for(2) in [1, 3],
		"a Crimson CPU fighter must target only Azure opponents")

	game.state = Phase.EXECUTING
	game._on_player_hit(2, game.players[2].position, 0)
	_check(game.team_score == [0, 0] and game.score[0] == 0,
		"friendly fire must remove the ally without awarding a point")
	game.players[2].alive = true
	game._on_player_hit(1, game.players[1].position, 0)
	_check(game.team_score == [1, 0] and game.score[0] == 1,
		"an enemy hit must advance both the team score and the scorer stat")
	game.players[1].alive = true
	game.team_score[0] = game.hits_to_win - 1
	game._on_player_hit(1, game.players[1].position, 0)
	_check(game.state == Phase.GAME_OVER and game.winning_team == 0,
		"reaching the shared hit limit must end the match for the scoring team")
	_check("CRIMSON" in game._score_text(),
		"team results must name both formations instead of presenting free-for-all scores")

	var setup_game = MAIN_SCENE.instantiate()
	root.add_child(setup_game)
	await process_frame
	setup_game._sfx.muted = true
	setup_game._menu._activate(setup_game._menu.ROW_PLAY)
	setup_game._menu._select(setup_game._menu.SETUP_MODE)
	setup_game._menu.handle_key(KEY_RIGHT)
	setup_game._menu._select(setup_game._menu.SETUP_PLAYERS)
	setup_game._menu.handle_key(KEY_RIGHT)
	setup_game._menu.handle_key(KEY_RIGHT)
	setup_game._menu._activate(setup_game._menu._setup_start_row())
	_check(setup_game.state == Phase.PLANNING and setup_game.team_mode \
			and setup_game.player_teams == [0, 1, 0, 1],
		"the one-screen Team Battle setup must reach gameplay with its formation intact")
	setup_game._ai_searches.fill(null)
	setup_game.free()

	if _failures == 0:
		print("Team battle: all tests passed")
	else:
		push_error("Team battle: %d test(s) failed" % _failures)
	game._ai_searches.fill(null)
	game.free()
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
