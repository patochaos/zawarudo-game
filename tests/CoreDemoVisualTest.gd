extends SceneTree
const MAIN := preload("res://scenes/Main.tscn")
const Capture := preload("res://tests/VisualCaptureHelper.gd")
var game
var error := OK
func _init() -> void: call_deferred("run")
func snap(name: String) -> void:
	game._transition.visible = false
	game._time_stop._freeze_flash = 0.0
	game._time_stop._resume_flash = 0.0
	game._preview.queue_redraw()
	game._ui.refresh()
	await Capture.settle(self, 3)
	error = Capture.save(self, "res://previews/demo-" + name + ".png", "Core demo")
	if error != OK: quit(error)
func execute_window() -> void:
	game._begin_execution()
	while game.exec_tick < game.exec_ticks_total:
		game._sim_tick(game.tick_dt())
		game.exec_tick += 1
	game._end_execution()
func run() -> void:
	game = MAIN.instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game._sfx.muted = true
	await Capture.pin_window(self)
	await snap("menu")
	game.start_demo_duel()
	await snap("planning-empty")
	game._confirm(0)
	await snap("planning-locked-empty")
	game.start_demo_duel()
	for tick in 24: game._pilot_step(0, 1, tick == 0, true)
	game.players[0].plan.shot_tick = 12
	game.players[0].plan.power = 0.55
	game._rebuild_ghost_paths()
	await snap("planning")
	await Capture.pin_window(self, Vector2i(1024, 576))
	await snap("planning-small")
	game._confirm(0)
	await snap("planning-locked-small")
	await Capture.pin_window(self)
	game.start_demo_duel()
	for i in 5:
		game.players[1].position = Vector2(450 + i * 90, 260)
		game.players[1].plan.set_aim_from_vector(Vector2(-0.2, -1), game.aim_min_angle, game.aim_max_angle)
		game.players[1].plan.power = 0.75
		game._spawn_arrow(game.players[1])
	game.players[1].position = Vector2(930, 610)
	game._rebuild_ghost_paths()
	game._confirm(0)
	await snap("planning-incoming")
	game._preview.high_contrast = true
	await snap("planning-incoming-contrast")
	game._preview.high_contrast = false
	game._on_menu_tutorial()
	await snap("lesson-briefing")
	game._practice.advance()
	await snap("lesson-move")
	game._practice.lesson = 1
	game._practice.show_briefing()
	await snap("lesson-jump-briefing")
	game._practice.begin_attempt()
	await snap("lesson-intercept")
	await Capture.pin_window(self, Vector2i(1024, 576))
	await snap("lesson-intercept-small")
	await Capture.pin_window(self)
	game.players[0].plan.shot_tick = 0
	game.players[0].plan.power = 0.75
	game.players[0].plan.set_aim_from_vector(game._practice.landing_aim_point() - game.players[0].shoulder(), game.aim_min_angle, game.aim_max_angle)
	game._rebuild_ghost_paths()
	await snap("lesson-jump-aim")
	game._begin_execution()
	while game.exec_tick < game._practice.target_landing_tick:
		game._sim_tick(game.tick_dt())
		game.exec_tick += 1
	await snap("lesson-jump-landing")
	while game.exec_tick < game.exec_ticks_total:
		game._sim_tick(game.tick_dt())
		game.exec_tick += 1
	game._end_execution()
	await snap("lesson-jump-result")
	game._practice.advance()
	await snap("lesson-dodge-briefing")
	game._practice.advance()
	await snap("lesson-persistence")
	await Capture.pin_window(self, Vector2i(1024, 576))
	await snap("lesson-persistence-small")
	await Capture.pin_window(self)
	for tick in 30: game._pilot_step(0, 0, tick == 0, true)
	execute_window()
	await snap("lesson-dodge-next-briefing")
	game._practice.advance()
	await snap("lesson-landing-threat")
	await Capture.pin_window(self, Vector2i(1024, 576))
	await snap("lesson-landing-threat-small")
	await Capture.pin_window(self)
	execute_window()
	await snap("lesson-dodge-retry")
	game._practice.advance()
	for tick in 30: game._pilot_step(0, 0, tick == 0, true)
	execute_window()
	game._practice.advance()
	for tick in 30: game._pilot_step(0, -1, false, false)
	game._rebuild_ghost_paths()
	await snap("lesson-safe-landing")
	execute_window()
	await snap("lesson-dodge-result")
	game.start_demo_duel()
	game.state = Phase.GAME_OVER
	game.winner = 0
	game.score[0] = 3
	game._finish_match_telemetry()
	await snap("result")
	game.open_feedback()
	game._feedback._notes.text = "I tried to jump past the incoming knife. I want to try a shorter throw next match."
	await snap("feedback")
	game.free()
	await process_frame
	quit(error)
