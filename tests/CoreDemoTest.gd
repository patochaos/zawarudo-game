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
	check(game._menu._page_names() == ["START DUEL", "LEARN TO PLAY", "ONLINE", "CONTROLS", "OPTIONS", "SEND FEEDBACK", "QUIT"], "public demo must have no experiment or setup destinations")
	game._menu._activate(game._menu.ROW_PLAY)
	check(game.demo_match and game.state == Phase.PLANNING and game.hits_to_win == 3, "Start Duel must directly launch first to three")
	check(game.level_index == 1 and game.wrap_x and game.wrap_y, "Start Duel must use Endless Descent with four-way wrapping")
	check(game.player_difficulty(1) == game.Difficulty.NOVICE and game.planning_time_left == 8.0, "first opponent must be Novice with eight-second turns")
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
	check(lesson.lesson == 1 and game.players[1].plan.recorded_ticks() == 30, "interception lesson must author a moving target")
	game.players[0].plan.shot_tick = 0
	game.players[0].plan.power = 0.55
	game.players[0].plan.set_aim_from_vector(Vector2(1, 0.15), game.aim_min_angle, game.aim_max_angle)
	game._rebuild_ghost_paths()
	execute(game)
	check(lesson.completed, "interception lesson must be solvable through a real projectile hit")
	if not lesson.completed:
		game.free()
		await process_frame
		quit(failures)
		return
	lesson.advance()
	lesson.advance()
	check(lesson.lesson == 2 and game.arrows.size() == 1, "persistence exercise must start with an earlier knife")
	var old_id: int = game.arrows[0].network_id
	for tick in 30: game._pilot_step(0, 0, tick == 0, true)
	execute(game)
	check(lesson.between_turns, "surviving the first knife must lead to another timed window")
	var pos: Vector2 = game.players[0].position
	var count: int = game.arrows.size()
	check(count > 0, "the earlier knife must still exist at the second freeze")
	lesson.advance()
	check(game.players[0].position == pos and game.arrows.size() == count, "the second window must preserve fighter and projectile state")
	if count > 0: check(game.arrows[0].network_id == old_id, "the earlier projectile must keep its identity")
	execute(game)
	check(lesson.completed, "a correctly recorded escape must survive the persistence exercise")
	var lesson_results := 0
	for event in game._telemetry._events:
		if event["event"] == "lesson_result": lesson_results += 1
	check(lesson_results >= 4, "tutorial telemetry must retain failed attempts and all completed lessons")
	lesson.advance()
	check(not lesson.active and game.demo_match and game.hits_to_win == 3, "finishing onboarding must start the real demo duel")
	game._ui.refresh()
	check(not game._ui._harder_button.visible, "harder rematch must stay off the live match HUD")
	game.state = Phase.GAME_OVER
	game.winner = 0
	game._finish_match_telemetry()
	game._ui.refresh()
	check(game._ui._harder_button.visible and not game._ui._arena_next_button.visible, "demo results must offer difficulty progression while retaining the arena")
	game._ui._harder_button.pressed.emit()
	check(game.player_difficulty(1) == game.Difficulty.STANDARD and game.hits_to_win == 3, "harder rematch must change CPU skill, keeping demo rules")
	check(game.level_index == 1 and game.wrap_x and game.wrap_y, "harder rematch must retain Endless Descent and wrapping")
	game._open_menu()
	game.free()
	await process_frame
	print("Core demo: %d failures" % failures)
	quit(failures)
