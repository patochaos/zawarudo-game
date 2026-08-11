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
	telemetry.begin_match("tutorial", "TEST ARENA", "wide", "keyboard_mouse")
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
	_check(game.tutorial_mode, "Tutorial must launch as a distinct mode")
	_check(game.state == Phase.PLANNING, "Tutorial must use the real planning loop")
	_check(game.players.size() == 1 and not game.vs_ai,
		"Tutorial must contain one player and no enemy")
	_check(game.level_name == "TRAINING TUNNEL" and game.wrap_x and not game.wrap_y,
		"Tutorial must use its quiet horizontal-wrap arena")
	_check(game.hazards.is_empty() and game.core_spawn_points.is_empty(),
		"Tutorial arena must not contain hazards or a Temporal Core")
	_check(game._tutorial.visible, "the action coach must be visible during Tutorial")
	_check(not game._tutorial.timed_turns_started,
		"Tutorial steps must begin without timed turns")
	var time_before: float = game.planning_time_left
	game._physics_process(0.5)
	_check(game.planning_time_left == time_before,
		"waiting must not advance the tutorial clock")

	game._pilot_step(0, 1, false, true)
	_check(not game._tutorial.observe_planning() and game._tutorial.stage == 0,
		"movement must not complete before the stamina bar is empty")
	while game._pilot_step(0, 1, false, true):
		pass
	_check(game._tutorial.observe_planning() and game._tutorial.stage == 1,
		"horizontal input must complete only after all stamina is spent")
	game._begin_planning(false)
	game._pilot_step(0, 0, true, true)
	_check(not game._tutorial.observe_planning() and game._tutorial.stage == 1,
		"one jump must not complete before the new stamina bar is empty")
	while game._pilot_step(0, 0, false, true):
		pass
	_check(game._tutorial.observe_planning() and game._tutorial.stage == 2,
		"jump input must complete only after all stamina is spent")
	game._begin_planning(false)
	game.players[0].plan.shot_tick = 0
	_check(game._tutorial.observe_planning() and game._tutorial.stage == 3,
		"a released shot must complete the mouse step")
	game._begin_planning(false)
	game._tutorial.observe_planning()
	_check(game._tutorial.timed_turns_started and game.planning_time_left > 0.0,
		"normal timed turns must begin only after all three actions")
	_check(not game._menu.visible, "launching Tutorial must close the main menu")
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
	game.queue_free()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
