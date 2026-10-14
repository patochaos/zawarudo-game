extends CanvasLayer

## Three timed exercises using the ordinary planner and execution physics.
var gm
var active := false
var lesson := 0
var attempt := 0
var completed := false
var between_turns := false
var survival_windows := 0
var survival_knife_ids: Array[int] = []
var _panel: Panel
var _title: Label
var _body: Label
var _action: Button
var _hint: Label
var _markers: Control
var target_landing := Vector2.ZERO
var target_landing_tick := -1
var _jump_visual: Node2D
var _jump_visual_position := Vector2.ZERO
var _jump_visual_scale := Vector2.ONE
const JUMP_WINDUP_TICKS := 4
const JUMP_HOLD_TICKS := 8
const JUMP_HINT := "Aim at the gold ring. Charge about 3/4, release, then LOCK PLAN."
const DODGE_HINT := "Jump over the low knife. The second covers your landing."
const LANDING_HINT := "Read the incoming knife. Steer toward a safe landing."
const TITLES := ["01  MOVE, LOCK, WATCH", "02  CATCH THE LANDING", "03  THE WORLD REMEMBERS"]

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
		if practice.lesson == 1 and practice.target_landing_tick >= 0:
			var gold := Color(1.0, 0.85, 0.35)
			var landing: Vector2 = practice.target_landing
			var feet := landing + Vector2(0, Player.HALF.y)
			draw_line(feet + Vector2(-36, 0), feet + Vector2(36, 0), gold, 4.0, true)
			draw_string(font, landing + Vector2(-55, -83), "LANDS HERE", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, gold)
			if practice.gm.state == Phase.PLANNING:
				var aim: Vector2 = practice.landing_aim_point()
				draw_arc(aim, 18, 0, TAU, 32, Color(0.025, 0.015, 0.04, 0.95), 5.0, true)
				draw_arc(aim, 18, 0, TAU, 32, gold, 2.0, true)
				for side in [-1, 1]:
					draw_line(aim + Vector2(side * 22, 0), aim + Vector2(side * 28, 0), gold, 2.0)
				var opponent: Vector2 = practice.gm.players[1].position
				draw_string(font, opponent + Vector2(34, -42), "JUMP READY", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, gold)
		if practice.lesson == 2 and practice.gm.state == Phase.PLANNING:
			for knife: Arrow in practice.gm.arrows:
				var threat: int = practice.survival_knife_ids.find(knife.network_id)
				if threat < 0: continue
				var caption := "1  LOW KNIFE" if threat == 0 else "2  LANDING KNIFE"
				draw_string(font, knife.position + Vector2(-48, -38), caption,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.74, 0.55))
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
	_restore_jump_visual()
	active = false
	visible = false

func show_briefing(message: String = "") -> void:
	_restore_jump_visual()
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
		"The opponent is preparing to jump onto the marked ledge. Aim at the gold ring on the landing ghost. Hold left-click to charge about three-quarters, release, then lock. Watch them jump into your throw. Only this lesson reveals their route.",
		"Two knives are already in flight. Hold %s to jump over the low knife from your left. The knife from the right covers the landing of a straight jump. At the next freeze, read its path and steer toward a safe landing. Survive both turns." % jump_keys,
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
	_restore_jump_visual()
	target_landing_tick = -1
	attempt += 1
	if not between_turns:
		survival_windows = 0
		survival_knife_ids.clear()
		# A dummy is confirmed explicitly; it never reads or responds to input.
		gm.team_mode = false
		gm.planning_duration = 8.0
		gm.planning_shrink_per_round = 0.0
		gm.execution_duration = 0.75
		gm._start_local_match(0, 2, [0, 0], {
			"roles": ["HUMAN", "DUMMY"], "devices": [gm.KEYBOARD_DEVICE, gm.NO_DEVICE],
			"match_lives": 7, "difficulty": 0,
		})
		gm.players[0].position = Vector2(220 if lesson == 0 else 400, 596)
		gm.players[1].position = Vector2(1060, 596)
		if lesson == 1:
			# Lower the middle ledge only for this exercise. A short ground jump
			# reaches it before the freeze, with a clear firing lane from the left.
			for platform in gm.platforms:
				if platform["rect"] == Rect2(510, 420, 260, 16):
					platform["rect"] = Rect2(510, 520, 260, 16)
			gm._rebuild_solids()
			gm._arena.setup(gm.platforms)
			gm.players[0].position = Vector2(320, 476)
			gm.players[1].position = Vector2(820, 596)
		gm._begin_planning(true)
		if lesson == 1:
			for tick in gm.movement_tick_budget():
				gm.players[1].plan.record(-1 if tick >= JUMP_WINDUP_TICKS else 0,
					tick == JUMP_WINDUP_TICKS,
					tick >= JUMP_WINDUP_TICKS and tick < JUMP_WINDUP_TICKS + JUMP_HOLD_TICKS)
		if lesson == 2:
			_seed_survival_knife(Vector2(192, 584), Vector2(420, -70))
			# This fixed throw crosses the natural straight-jump landing in the
			# second window. It is visible now and never retargets the player.
			_seed_survival_knife(Vector2(950, 584), Vector2(-620, -120))
	else:
		gm._begin_planning(false)
	between_turns = false
	gm.players[1].plan.confirmed = true
	gm._ai_searches.fill(null)
	gm._rebuild_ghost_paths()
	if lesson == 1:
		# Read the first real ground contact after takeoff, not the final point
		# of a guessed arc. The same plan and geometry drive execution.
		for tick in range(JUMP_WINDUP_TICKS + 1, gm.ghost_path[1].size()):
			if gm.ghost_ground_path[1][tick] == 1:
				target_landing = gm.ghost_path[1][tick]
				target_landing_tick = tick
				break
		_jump_visual = gm.players[1].get_node_or_null("FighterVisual")
		if _jump_visual != null:
			_jump_visual_position = _jump_visual.position
			_jump_visual_scale = _jump_visual.scale
		_sync_jump_preparation()
	gm._transition.visible = false
	gm._ui.visible = true
	gm._ui.show_controls(true)
	gm._telemetry.record("lesson_attempt", gm.turn, {"lesson": lesson + 1, "attempt": attempt})
	_panel.visible = false
	_hint.visible = true
	_hint.text = ["Move into the gold zone, then LOCK PLAN", JUMP_HINT,
		LANDING_HINT if survival_windows > 0 else DODGE_HINT][lesson]
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
					show_briefing("You survived the jump. The second knife is still incoming, and the world has not reset. Read its path and change your landing if it crosses your ghost. Steering left is one way to escape. Survive one more turn.")
					return
				success = true
	gm._telemetry.record("lesson_result", gm.turn, {"lesson": lesson + 1, "success": success})
	completed = success
	var messages: Array[String] = [
		"Your recorded move became real. The ghost is a preview; execution is the result. Next, place a throw on that route.",
		"You placed a throw before the jump and caught the opponent's future position. In a real duel, their route is hidden. Read their movement and look for the next landing.",
		"You escaped both knives across two turns. A safe jump can still have a dangerous landing: read the next threat at every freeze. You're ready for a Duelist versus CPU match, first to three hits.",
	]
	var retries: Array[String] = [
		"Try again. Hold your right-move control until the ghost reaches the gold zone, then lock. You can reset your route before the deadline.",
		"Try the landing. Stay on your ledge and aim at the gold ring, above the marked platform. Charge about three-quarters, release, then lock. Every retry restores the same jump, so you can adjust your aim or charge.",
		("The second knife caught your landing. Jump over the low knife again, then steer left during the next plan to land elsewhere. Both knives repeat the same paths on every retry."
			if survival_windows > 0 else "The low knife caught you. Hold jump to record your escape before locking. Then watch the second knife at the next freeze: it covers the landing of a straight jump."),
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

func landing_aim_point() -> Vector2:
	# Aim high on the landing silhouette to allow for the ordinary knife arc.
	return Player.shoulder_at(target_landing) + Vector2(0, -16)

func _seed_survival_knife(at: Vector2, velocity: Vector2) -> void:
	gm._seed_fate_trial_threat()
	var knife: Arrow = gm.arrows[-1]
	knife.position = at
	knife.prev_pos = at
	knife.vel = velocity
	knife.rotation = velocity.angle()
	knife.age_ticks = gm.exec_ticks()
	survival_knife_ids.append(knife.network_id)

func _sync_jump_preparation() -> void:
	if not is_instance_valid(_jump_visual): return
	var preparing: bool = active and lesson == 1 and (gm.state == Phase.PLANNING \
		or (gm.state == Phase.EXECUTING and gm.exec_tick < JUMP_WINDUP_TICKS))
	# A restrained crouch uses the current sprite and keeps its feet anchored.
	# Only the visual child changes; the body and its collision stay frozen.
	_jump_visual.scale = _jump_visual_scale * (Vector2(1.06, 0.86) if preparing else Vector2.ONE)
	_jump_visual.position = _jump_visual_position + (Vector2(0, Player.HALF.y * 0.14) if preparing else Vector2.ZERO)

func _restore_jump_visual() -> void:
	if is_instance_valid(_jump_visual):
		_jump_visual.position = _jump_visual_position
		_jump_visual.scale = _jump_visual_scale
	_jump_visual = null

func _process(_delta: float) -> void:
	if active:
		_sync_jump_preparation()
		if lesson == 1:
			_hint.text = "Watch your throw meet the landing." if gm.state == Phase.EXECUTING else JUMP_HINT
		elif lesson == 2:
			_hint.text = "Watch both knives keep moving." if gm.state == Phase.EXECUTING \
				else (LANDING_HINT if survival_windows > 0 else DODGE_HINT)
		_markers.queue_redraw()
