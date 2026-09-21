extends CanvasLayer

## Three timed exercises using the ordinary planner and execution physics.
var gm
var active := false
var lesson := 0
var attempt := 0
var completed := false
var between_turns := false
var survival_windows := 0
var _panel: Panel
var _title: Label
var _body: Label
var _action: Button
var _hint: Label
var _markers: Control
const TITLES := ["01  MOVE, LOCK, WATCH", "02  CATCH A MOVING TARGET", "03  THE WORLD REMEMBERS"]

class Markers:
	extends Control
	var practice
	func _draw() -> void:
		if not practice.active or practice.gm.state == Phase.TUTORIAL: return
		var font := preload("res://assets/fonts/AtkinsonHyperlegible-Regular.ttf")
		if practice.lesson == 0:
			draw_rect(Rect2(300, 563, 155, 55), Color(0.96, 0.69, 0.18, 0.14))
			draw_rect(Rect2(300, 563, 155, 55), Color(1.0, 0.85, 0.35), false, 2.0)
			draw_string(font, Vector2(305, 553), "FINISH HERE", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
		var p = practice.gm.players[0]
		draw_string(font, p.position + Vector2(-20, -106), "YOU", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)

func _ready() -> void:
	layer = 14
	_panel = Panel.new()
	_panel.position = Vector2(220, 155)
	_panel.size = Vector2(840, 410)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.02, 0.065, 0.98)
	style.border_color = Color(0.96, 0.69, 0.18)
	style.set_border_width_all(2)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	_title = _label(Vector2(30, 24), Vector2(780, 42), 25)
	_body = _label(Vector2(30, 82), Vector2(780, 225), 22)
	_body.add_theme_font_override("font", preload("res://assets/fonts/AtkinsonHyperlegible-Regular.ttf"))
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_action = Button.new()
	_action.position = Vector2(30, 330)
	_action.size = Vector2(430, 54)
	_action.add_theme_font_size_override("font_size", 18)
	_action.pressed.connect(advance)
	_panel.add_child(_action)
	var back := Button.new()
	back.position = Vector2(606, 330)
	back.size = Vector2(204, 54)
	back.text = "ESC  MENU"
	back.pressed.connect(func(): gm._open_menu())
	_panel.add_child(back)
	_hint = Label.new()
	_hint.position = Vector2(270, 200)
	_hint.size = Vector2(740, 44)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_override("font", preload("res://assets/fonts/AtkinsonHyperlegible-Regular.ttf"))
	_hint.add_theme_font_size_override("font_size", 21)
	_hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	_hint.add_theme_constant_override("shadow_offset_x", 2)
	_hint.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_hint)
	_markers = Markers.new()
	_markers.practice = self
	_markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_markers)
	visible = false

func _label(at: Vector2, dimensions: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.size = dimensions
	label.add_theme_font_size_override("font_size", font_size)
	_panel.add_child(label)
	return label

func start() -> void:
	gm._abandon_match("learn_to_play")
	gm._set_close_camera_mode(false)
	gm.fate_trial_mode = false
	gm.tutorial_mode = false
	gm.online_mode = false
	gm.demo_match = false
	gm._tuning.handle_key(KEY_BACKSPACE, false)
	gm._menu.close()
	gm._transition.visible = false
	active = true
	lesson = 0
	attempt = 0
	survival_windows = 0
	completed = false
	between_turns = false
	gm._telemetry.begin_match("guided_practice", "TRAINING TUNNEL", "touch" if gm._touch_controls.enabled else "keyboard_mouse")
	gm._telemetry_finished = false
	gm._telemetry.record("tutorial_started", 0)
	show_briefing()

func stop() -> void:
	active = false
	visible = false

func show_briefing(message: String = "") -> void:
	gm.state = Phase.TUTORIAL
	gm._ui.visible = false
	gm._time_stop._freeze_flash = 0.0
	gm._time_stop._resume_flash = 0.0
	visible = true
	_panel.visible = true
	_hint.visible = false
	_title.text = TITLES[lesson]
	var move_keys: String = gm._menu._keys_text("right")
	var jump_keys: String = gm._menu._keys_text("jump")
	var instructions: Array[String] = [
		"Hold %s to record a move into the gold zone. Your body waits; the ghost shows your future. Then lock with Left Shift or the Lock Plan button." % move_keys,
		"The target moves left. Aim ahead of it with the mouse, hold left-click to charge, then release to place your throw. Lock and watch. Only this lesson reveals the opponent's route.",
		"An earlier knife is already coming from your left. Jump with %s and hold it to record your escape. Survive two turns: knives keep moving from the last freeze." % jump_keys,
	]
	_body.text = message if not message.is_empty() else instructions[lesson] + "\n\nEvery attempt gives you 8 seconds. The current plan executes when time runs out."
	_action.text = "ENTER  START DUEL" if completed and lesson == 2 else ("ENTER  NEXT LESSON" if completed else "ENTER  START · 8 SECONDS")
	if between_turns: _action.text = "ENTER  NEXT TURN · 8 SECONDS"
	_markers.queue_redraw()

func advance() -> void:
	if not active or gm.state != Phase.TUTORIAL: return
	if completed:
		if lesson == 2:
			gm._telemetry.record("tutorial_completed", gm.turn)
			gm._telemetry.finish_match(-1, gm.score, gm.turn)
			gm._telemetry_finished = true
			stop()
			gm.start_demo_duel()
			return
		lesson += 1
		completed = false
		attempt = 0
		show_briefing()
		return
	begin_attempt()

func begin_attempt() -> void:
	attempt += 1
	if not between_turns:
		survival_windows = 0
		# A dummy is confirmed explicitly; it never reads or responds to input.
		gm.team_mode = false
		gm.planning_duration = 8.0
		gm.planning_shrink_per_round = 0.0
		gm.execution_duration = 0.75
		gm._start_local_match(0, 2, [0, 0], {
			"roles": ["HUMAN", "DUMMY"], "devices": [gm.KEYBOARD_DEVICE, gm.NO_DEVICE],
			"match_lives": 7, "difficulty": 0,
		})
		gm.players[0].position = Vector2(220 if lesson == 0 else (430 if lesson == 1 else 400), 596)
		gm.players[1].position = Vector2(750 if lesson == 1 else 1060, 596)
		gm._begin_planning(true)
		if lesson == 1:
			for tick in 30: gm.players[1].plan.record(-1, false, false)
		if lesson == 2:
			gm._seed_fate_trial_threat()
			gm.arrows[0].position.x += 100.0
			gm.arrows[0].prev_pos = gm.arrows[0].position
			gm.arrows[0].vel = Vector2(420, -70)
			gm.arrows[0].age_ticks = gm.exec_ticks()
	else:
		gm._begin_planning(false)
	between_turns = false
	gm.players[1].plan.confirmed = true
	gm._ai_searches.fill(null)
	gm._rebuild_ghost_paths()
	gm._transition.visible = false
	gm._ui.visible = true
	gm._ui.show_controls(true)
	gm._telemetry.record("lesson_attempt", gm.turn, {"lesson": lesson + 1, "attempt": attempt})
	_panel.visible = false
	_hint.visible = true
	_hint.text = ["Move into the gold zone, then LOCK PLAN", "Aim ahead of the moving target, then LOCK PLAN", "Dodge the old knife. Survive both turns."][lesson]
	_markers.queue_redraw()

func finish_window() -> void:
	var success := false
	match lesson:
		0: success = gm.players[0].position.x >= 300 and gm.players[0].position.x <= 455
		1: success = not gm.players[1].alive and gm.players[0].plan.has_shot()
		2:
			if gm.players[0].alive:
				survival_windows += 1
				if survival_windows < 2:
					between_turns = true
					gm._telemetry.record("lesson_window_survived", gm.turn, {"lesson": 3})
					show_briefing("You escaped the first window. The world has not reset. Read where the remaining knives will go, then survive one more timed turn.")
					return
				success = true
	gm._telemetry.record("lesson_result", gm.turn, {"lesson": lesson + 1, "success": success})
	completed = success
	var messages: Array[String] = [
		"Your recorded move became real. The ghost is a preview; execution is the result. Next, place a throw on that route.",
		"You intercepted the target. In a real duel, the CPU's route is hidden: predict where it will go instead of aiming only where it stands.",
		"You survived a world that remembers. You're ready: one Duelist, one CPU, first to three hits. Every turn still has eight seconds.",
	]
	var retries: Array[String] = [
		"Try again. Hold your right-move control until the ghost reaches the gold zone, then lock. You can reset your route before the deadline.",
		"That throw missed. Try a short charge toward the target's future position. Aim from your ghost, release, then lock. Every retry restores the same target route.",
		"The earlier knife caught you. Hold jump to record an arc before locking. Watch the old knife's path; the freeze never makes it harmless.",
	]
	show_briefing(messages[lesson] if success else retries[lesson])

func handle_key(code: int) -> bool:
	if code == KEY_ESCAPE:
		gm._open_menu()
		return true
	if gm.state == Phase.TUTORIAL:
		if code in [KEY_ENTER, KEY_KP_ENTER]: advance()
		return true
	return false

func _process(_delta: float) -> void:
	if active: _markers.queue_redraw()
