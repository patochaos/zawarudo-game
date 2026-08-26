extends SceneTree

## Team Battle is a rule on the match setup screen, not a screen of its own.
## Sides alternate by slot so the arena's authored team spawns stay correct, and
## which side you fight for is decided by which slot your device claims.

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

	var roster = game._roster
	var setup = game._setup
	game._menu._activate(game._menu.ROW_PLAY)
	_check(game.state == Phase.ROSTER, "Play must open the lineup screen")

	# The formation is built by filling slots, not by naming a head count.
	roster._set_role(1, roster.ROLE_PLAYER)
	roster._set_role(2, roster.ROLE_CPU_FIRST + 1)
	roster._set_role(3, roster.ROLE_CPU_FIRST + 1)
	roster.debug_join_device(7)
	_check(roster.devices == [roster.KEYBOARD_DEVICE, 7, roster.NO_DEVICE, roster.NO_DEVICE],
		"a joining pad must take the seat waiting for it, which is what puts it on Azure")
	_check(roster.build_lineup()["roles"] == ["HUMAN", "HUMAN", "AI", "AI"],
		"unfilled team positions must become CPU allies")

	roster._set_ready(0, true)
	roster._set_ready(1, true)
	roster._confirm()
	_check(game.state == Phase.MATCH_SETUP, "a settled lineup must hand over to the rules")
	setup.row = setup.ROW_MODE
	setup.handle_key(KEY_D)
	_check(setup.battle_mode == setup.BattleMode.TEAM_BATTLE,
		"Team Battle must be a rule on the setup screen rather than a separate page")

	var config: Dictionary = setup.build_config()
	_check(config["teams"] == [0, 1, 0, 1] and config["roles"] == ["HUMAN", "HUMAN", "AI", "AI"],
		"the emitted configuration must carry side and ownership together")

	setup.row = setup.ROW_START
	setup.handle_key(KEY_ENTER)
	await process_frame
	_check(game.state == Phase.PLANNING and game.team_mode and game.players.size() == 4,
		"locking every slot must start a four-fighter team match")
	_check(game.player_teams == [0, 1, 0, 1],
		"team identities must reach gameplay unchanged")
	_check(not game.is_ai(0) and not game.is_ai(1) and game.is_ai(2) and game.is_ai(3),
		"mixed human/CPU ownership must be evaluated per slot")
	# The keyboard seat is Player 1 in every mode now; a second human is a pad.
	_check(game._keyboard_player() == 0 and game._input_map_for(0) == game.key_bindings,
		"the keyboard seat must drive the slot it holds on the roster screen")
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

	# Leaving Team Battle must retire the sides rather than leave them latched.
	game._open_menu()
	game._menu._activate(game._menu.ROW_PLAY)
	roster._debug_pads.clear()
	roster.refresh_connections()
	_check(roster.kinds[1] == roster.SlotKind.CPU,
		"a pad that unplugged must leave a CPU ally rather than a dead seat")
	setup.row = setup.ROW_MODE
	setup.handle_key(KEY_A)
	_check(setup.battle_mode == setup.BattleMode.VS \
			and setup.build_config()["teams"] == [-1, -1, -1, -1],
		"returning to VS must clear every side assignment")

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
