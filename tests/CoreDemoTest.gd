extends SceneTree

const MAIN := preload("res://scenes/Main.tscn")
var failures := 0

func _init() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func execute(game) -> void:
	game._begin_execution()
	while game.state == Phase.EXECUTING and game.exec_tick < game.exec_ticks_total:
		game._sim_tick(game.tick_dt())
		game._capture_replay_frame()
		game.exec_tick += 1
	if game.state == Phase.EXECUTING: game._end_execution()

func run() -> void:
	var game = MAIN.instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game._sfx.muted = true
	# Ladder progress is saved on a demo win; keep it off the player's settings.
	game.settings_path = "user://test-coredemotest-settings.cfg"
	game._settings["ladder_progress"] = 0
	check(game._menu._page_names() == ["START DUEL", "CUSTOM MATCH", "INTERCEPTION", "LEARN TO PLAY", "ONLINE", "CONTROLS", "OPTIONS", "GAME TUNING", "SEND FEEDBACK", "QUIT"], "public demo must expose Custom Match, Interception and offline tuning alongside its primary destinations")
	game._menu._activate(game._menu.ROW_PLAY)
	check(game.demo_match and game.state == Phase.PLANNING and game.hits_to_win == 3, "Start Duel must directly launch first to three")
	check(game.level_index == Opponents.arena(0) and game.level_name == "CROSSHAIR COURT", "Start Duel must open on the readable walled court")
	check(game.player_difficulty(1) == game.Difficulty.NOVICE and game.demo_opponent == 0 and game.planning_time_left == 8.0, "first opponent must be the ladder's first rung, Novice skill, with eight-second turns")
	game._physics_process(0.5)
	check(game.planning_time_left == 8.0, "the opening wipe must not consume planning time")
	game._transition.visible = false
	game._ui.refresh()
	check(game._ui._lock_plan.visible and game._ui.help_visible, "first duel must expose lock and basic controls")
	check(not game._ui._locked_status.visible and "RELEASE TO THROW" in game._ui._hint_p2.text, "unlocked empty plan must offer throw guidance")
	check(game._ui.pointer_on_action(game._ui._lock_plan.position + Vector2(10, 10)), "compact Lock button must intercept aiming clicks")
	game._ui._lock_plan.pressed.emit()
	check(game.players[0].plan.confirmed, "clicking Lock must submit the actual plan")
	game._ui.refresh()
	check(not game._ui._lock_plan.visible and game._ui._locked_status.visible, "locked plan must replace the action with status")
	check(game._ui._hint_p2.text.is_empty(), "locked plan without a shot must not prompt a throw")
	game._open_menu()
	check(game._telemetry.latest_report.get("outcome") == "abandoned", "leaving an unfinished match must save it")
	game.open_feedback()
	game._feedback._notes.text = "Aim & jump? #1\nI wanted another match."
	check("mailto:patochaos@gmail.com?" in game._feedback.email_uri() and "%26" in game._feedback.email_uri(), "email draft must encode user text and use the authorized destination")
	check("abandoned" in game._feedback.feedback_text(), "feedback must include unfinished-match evidence")
	game._feedback.close()
	game._on_menu_tutorial()
	var lesson = game._practice
	check(lesson.active and game.state == Phase.TUTORIAL, "Learn to Play must explain the first exercise before starting its clock")
	lesson.advance()
	check(game.planning_time_left == 8.0 and not game.tutorial_mode, "playable lessons must use the ordinary timed planner")
	game._physics_process(8.1)
	check(game.state == Phase.EXECUTING, "an empty lesson plan must execute at the deadline")
	while game.exec_tick < game.exec_ticks_total:
		game._sim_tick(game.tick_dt())
		game.exec_tick += 1
	game._end_execution()
	check(not lesson.completed and game.state == Phase.TUTORIAL, "empty move attempt must offer retry, not pass")
	lesson.advance()
	for tick in 30: game._pilot_step(0, 1, false, false)
	execute(game)
	check(lesson.completed, "real recorded movement must reach the lesson target")
	lesson.advance()
	lesson.advance()
	check(lesson.lesson == 1 and game.players[1].plan.jump_at(lesson.JUMP_WINDUP_TICKS), "landing lesson must author a committed jump after its windup")
	check(lesson.target_landing_tick > lesson.JUMP_WINDUP_TICKS and lesson.target_landing_tick < game.exec_ticks(), "the target must land before the execution window ends")
	var jump_path: PackedVector2Array = game.ghost_path[1].duplicate()
	var jump_start: Vector2 = game.players[1].position
	var jump_visual = game.players[1].get_node("FighterVisual")
	check(jump_visual.scale.y < 1.0 and game.players[1].on_ground, "jump preparation must pose the visual while the real body stays grounded")
	game.players[0].plan.shot_tick = 0
	game.players[0].plan.power = 0.75
	game.players[0].plan.set_aim_from_vector(game.players[1].shoulder() - game.players[0].shoulder(), game.aim_min_angle, game.aim_max_angle)
	game._begin_execution()
	var path_matches := true
	while game.exec_tick < game.exec_ticks_total:
		game._sim_tick(game.tick_dt())
		path_matches = path_matches and game.players[1].position.distance_to(jump_path[game.exec_tick + 1]) < 0.001
		game.exec_tick += 1
	lesson._process(0.0)
	check(path_matches and game.players[1].on_ground and game.players[1].position.y < jump_start.y - 80, "the revealed jump must execute accurately and land on the raised ledge")
	check(game.players[0].position == Vector2(320, 476) and game.players[0].on_ground, "the shooter must remain supported by the starting ledge while aiming without movement")
	check(jump_visual.scale == Vector2.ONE, "the windup pose must release when the jump executes")
	game._end_execution()
	check(not lesson.completed and game.players[1].alive, "aiming at the starting body must miss at the recommended charge and offer a retry")
	lesson.advance()
	check(game.ghost_path[1] == jump_path and game.players[1].position == jump_start, "retry must restore the same jump and landing cue")
	game.players[0].plan.shot_tick = 0
	game.players[0].plan.power = 0.75
	game.players[0].plan.set_aim_from_vector(lesson.landing_aim_point() - game.players[0].shoulder(), game.aim_min_angle, game.aim_max_angle)
	game._rebuild_ghost_paths()
	execute(game)
	check(lesson.completed, "pre-aiming at the landing must complete the lesson through a real projectile hit")
	if not lesson.completed:
		game.free()
		await process_frame
		quit(failures)
		return
	lesson.advance()
	lesson.advance()
	check(lesson.lesson == 2 and game.arrows.size() == 2, "persistence exercise must reveal both the low knife and the landing threat from the start")
	execute(game)
	check(not game.players[0].alive and not lesson.completed and not lesson.between_turns, "standing still must fail the first dodge window")
	lesson.advance()
	for tick in 30: game._pilot_step(0, 0, tick == 0, true)
	execute(game)
	check(lesson.between_turns, "jumping the low knife must lead to another timed window")
	var pos: Vector2 = game.players[0].position
	var threats: Array = []
	for knife in game.arrows:
		threats.append([knife.network_id, knife.position, knife.vel, knife.age_ticks])
	check(threats.size() == 2, "both knives must remain in flight at the second freeze")
	lesson.advance()
	check(game.players[0].position == pos and game.arrows.size() == threats.size(), "the second window must preserve fighter and projectile state")
	for i in mini(game.arrows.size(), threats.size()):
		var knife = game.arrows[i]
		check([knife.network_id, knife.position, knife.vel, knife.age_ticks] == threats[i], "the freeze must preserve knife identity, momentum and age without retargeting")
	execute(game)
	check(not game.players[0].alive and not lesson.completed and not lesson.between_turns, "coasting straight down must be caught by the landing knife and offer a full retry")
	lesson.advance()
	check(lesson.survival_windows == 0 and game.players[0].position == Vector2(400, 596) and game.arrows.size() == 2, "a failed landing must restart the complete two-window exercise")
	for tick in 30: game._pilot_step(0, 0, tick == 0, true)
	execute(game)
	for i in mini(game.arrows.size(), threats.size()):
		var knife = game.arrows[i]
		check([knife.network_id, knife.position, knife.vel, knife.age_ticks] == threats[i], "retrying the same jump must reproduce the same threats at the next freeze")
	lesson.advance()
	for tick in 30: game._pilot_step(0, -1, false, false)
	execute(game)
	check(lesson.completed and game.players[0].alive, "jumping first and steering left at the next freeze must escape both knives")
	var lesson_results := 0
	for event in game._telemetry._events:
		if event["event"] == "lesson_result": lesson_results += 1
	check(lesson_results >= 4, "tutorial telemetry must retain failed attempts and all completed lessons")
	lesson.advance()
	check(not lesson.active and game.demo_match and game.hits_to_win == 3, "finishing onboarding must start the real demo duel")
	game._ui.refresh()
	check(not game._ui._next_opponent_button.visible, "next opponent must stay off the live match HUD")
	game.state = Phase.GAME_OVER
	game.winner = 0
	game._finish_match_telemetry()
	game._record_ladder_result(0)
	game._ui.refresh()
	check(game._ui._next_opponent_button.visible and game._ui._arena_next_button.visible, "a won demo result must offer the next opponent and let the player revisit beaten ones")
	game._ui._next_opponent_button.pressed.emit()
	check(game.demo_opponent == 1 and game.hits_to_win == 3, "next opponent must advance one rung, keeping demo rules")
	check(game.level_index == Opponents.arena(1) and game.level_name == Opponents.arena_name(1), "next opponent must be fought in its own arena")
	game._open_menu()
	game.free()
	await process_frame
	print("Core demo: %d failures" % failures)
	quit(failures)
