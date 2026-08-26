extends SceneTree

const GAME_MANAGER := preload("res://scripts/GameManager.gd")
const TELEMETRY := preload("res://scripts/Telemetry.gd")
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_telemetry_report()
	await _test_tutorial_launch()
	await process_frame
	if _failures == 0:
		print("Playtest readiness: all tests passed")
	else:
		push_error("Playtest readiness: %d test(s) failed" % _failures)
	quit(_failures)


func _test_telemetry_report() -> void:
	var telemetry = TELEMETRY.new()
	root.add_child(telemetry)
	telemetry.begin_match("tutorial", "TEST ARENA", "keyboard_mouse")
	telemetry.record("plan_locked", 1, {"movement_ticks": 12, "power": 0.5})
	var scores: Array[int] = [3, 1, 0, 0]
	telemetry.finish_match(0, scores, 4, "digest")
	_check(not telemetry.latest_report.is_empty(), "a finished match must produce a report")
	_check(telemetry.latest_report["winner"] == 1,
		"the report must use human-facing player numbers")
	_check(telemetry.latest_report["events"].size() >= 3,
		"the report must retain the playtest event timeline")
	telemetry.queue_free()


func _test_tutorial_launch() -> void:
	var game = GAME_MANAGER.new()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game._on_menu_tutorial()
	await process_frame
	_check(game.tutorial_mode and game.state == Phase.TUTORIAL,
		"How To Play must launch as a distinct, paused mode")
	_check(game._tutorial.visible and game._tutorial.active and game._tutorial.page == 0,
		"the illustrated briefing must open on its first page")
	_check(game._tutorial.GAME_IMAGES.size() == game._tutorial.PAGES.size(),
		"every briefing page must have its own real-game image")
	var tutorial_image_paths: Dictionary = {}
	for image: Texture2D in game._tutorial.GAME_IMAGES:
		tutorial_image_paths[image.resource_path] = true
		_check(image.get_width() == 1280 and image.get_height() == 720,
			"tutorial game images must use the verified 1280x720 capture size")
	_check(tutorial_image_paths.size() == game._tutorial.PAGES.size(),
		"briefing pages must not repeat a generic gameplay image")
	_check(game._tutorial._game_image.texture == game._tutorial.GAME_IMAGES[0],
		"the first briefing page must display its real-game PLAN capture")
	_check(not game._ui.visible and not game._menu.visible,
		"the briefing must hide both match HUD and menu chrome")
	var state_before: int = game.state
	game._physics_process(0.5)
	_check(game.state == state_before and game._tutorial.page == 0,
		"waiting on a briefing page must not advance simulation or navigation")
	for expected_page in range(1, game._tutorial.PAGES.size()):
		game._tutorial.advance()
		_check(game._tutorial.page == expected_page and game.state == Phase.TUTORIAL,
			"each Next action must advance exactly one briefing page")
		_check(game._tutorial._game_image.texture == game._tutorial.GAME_IMAGES[expected_page],
			"each briefing page must display its matching real-game capture")
	game._tutorial.advance()
	_check(game.state == Phase.MENU and game._menu.visible \
		and not game.tutorial_mode and not game._tutorial.visible,
		"Done on the final page must return cleanly to the title menu")
	game._set_player_count(2)
	game._begin_planning(false)
	var secret_key := InputEventKey.new()
	secret_key.keycode = KEY_F7
	secret_key.pressed = true
	game._unhandled_key_input(secret_key)
	_check(game._secret_triple_match,
		"secret F7 must enable the three-knife rule for the current match")
	game._begin_planning(false)
	_check(game._secret_triple_match,
		"the secret three-knife rule must survive subsequent turns")
	game._spawn_arrow(game.players[0])
	game._spawn_arrow(game.players[1])
	_check(game.arrows.size() == 6,
		"the permanent secret rule must give both players three knives")
	_check(is_equal_approx(game.arrows[0].vel.length(), game.arrows[1].vel.length()) \
		and is_equal_approx(game.arrows[1].vel.length(), game.arrows[2].vel.length()),
		"all secret knives must use the same normal launch speed")
	var super_key := InputEventKey.new()
	super_key.keycode = KEY_F8
	super_key.pressed = true
	game._unhandled_key_input(super_key)
	_check(game.super_meter[0] == 1.0,
		"F8 must restore the full-SUPER shortcut for Player 1")
	super_key.shift_pressed = true
	game._unhandled_key_input(super_key)
	_check(game.super_meter[1] == 1.0,
		"Shift+F8 must restore the full-SUPER shortcut for Player 2")
	game.hit_freeze_enabled = true
	game.state = Phase.EXECUTING
	game._on_player_hit(1, game.players[1].position, 0)
	_check(game._hit_pause_left > 0.0 and game._time_stop._impact_flash > 0.0,
		"a hit must trigger both presentation hit-stop and the impact flash")
	game._open_menu()
	game._menu._activate(game._menu.ROW_ONLINE)
	_check(game.state == Phase.ONLINE_LOBBY and game._online_lobby.visible,
		"the restored Online row must open the existing private-room lobby")
	_check(game._transition.visible and game._transition._title == "PRIVATE PLANS",
		"opening Online must receive the same authored transition as local modes")
	var initial_online_level: int = game._online_lobby.level
	game._online_lobby._cycle_level(1)
	game._online_lobby._cycle_fighter(1)
	_check(game._online_lobby.level == posmod(initial_online_level + 1, Levels.count()) \
		and game._online_lobby.weapon == game._online_lobby.FIGHTER_ROSTER[1],
		"the online lobby must expose every arena and roster fighter before room creation")
	_check("HOST ARENA" in game._online_lobby._level_label.text \
		and "ROOK" in game._online_lobby._fighter_label.text,
		"the online lobby must explain which room settings the player is choosing")
	game._online_lobby._sanitize_code("abci12z9")
	_check(game._online_lobby._code_input.text == "ABC2Z9",
		"the lobby must normalize room codes and remove ambiguous characters")
	game._online_lobby._code_input.text = "ABC2Z"
	game._online_lobby._request_join()
	_check("6 CHARACTERS" in game._online_lobby._status.text,
		"an incomplete room code must fail locally with an actionable message")
	game.online_player = 0
	game.online_room = "TEST24"
	game._start_online_match(6, 1234, 1, [game.Weapon.SHOCK, game.Weapon.DASHBLADE])
	_check(game.online_mode and game.level_index == 6 \
		and game.player_weapons[0] == game.Weapon.SHOCK \
		and game.player_weapons[1] == game.Weapon.DASHBLADE,
		"a server match start must install both selected fighters on the selected arena")
	var orb_key := InputEventKey.new()
	orb_key.keycode = KEY_2
	orb_key.pressed = true
	game._unhandled_key_input(orb_key)
	_check(game.players[0].plan.attack_mode == 1,
		"online character-specific keys must control the locally assigned fighter")
	game.queue_free()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
