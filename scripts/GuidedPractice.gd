extends CanvasLayer

## Three timed exercises using the ordinary planner and execution physics,
## hosted by the one who stops time. He speaks of himself in the third person,
## calls everything you do useless, and is never wrong. HOST_NAME is the only
## place his name lives: every line reads it through %s.
var gm
var active := false
var lesson := 0
var attempt := 0
var completed := false
var between_turns := false
var survival_windows := 0
var survival_knife_ids: Array[int] = []
## Tests set this to render the pad variant without a controller plugged in.
var force_pad_prompts := false
## Swap this for a dedicated dialogue face once one is added under assets/fonts.
const DIALOGUE_FONT := "res://assets/fonts/AtkinsonHyperlegible-Regular.ttf"
const CHIP_FONT := "res://assets/kenney/fonts/kenney-future.ttf"
## Prompt icons shown inside the input chips, keyed by the chip's label.
const CHIP_ICONS := {
	"A": "res://assets/kenney/prompts/key-a.png",
	"D": "res://assets/kenney/prompts/key-d.png",
	"S": "res://assets/kenney/prompts/key-s.png",
	"SPACE": "res://assets/kenney/prompts/key-space.png",
	"LEFT SHIFT": "res://assets/kenney/prompts/key-shift.png",
	"LEFT-CLICK": "res://assets/kenney/prompts/mouse-left.png",
	"LEFT STICK": "res://assets/kenney/prompts/pad-left-stick.png",
	"PAD A": "res://assets/kenney/prompts/pad-a.png",
	"START": "res://assets/kenney/prompts/pad-menu.png",
	"R2": "res://assets/kenney/prompts/pad-rt.png",
}
var _panel: Panel
var _title: Label
var _host_name: Label
var _host_role: Label
var _body: RichTextLabel
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
const JUMP_HINT := "Gold ring. Three-quarters charge. Release. LOCK. Checkmate."
const DODGE_HINT := "Leap the low knife. The second one is waiting for your landing."
const LANDING_HINT := "Read the knife. Land where it is not."
const TITLES := ["01  TIME, STOP. NOW WALK.", "02  THROW AT THE FUTURE", "03  KNIVES DON'T FORGET"]
const HOST_NAME := "DIO"
const HOST_ROLE := "STOPS TIME. JUDGES YOU."
const PORTRAIT_SIZE := 150.0

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
	_panel.position = Vector2(220, 130)
	_panel.size = Vector2(840, 470)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.02, 0.065, 0.98)
	style.border_color = Color(0.96, 0.69, 0.18)
	style.set_border_width_all(2)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	_title = _label(Vector2(30, 24), Vector2(780, 42), 25)
	var portrait := HostPortrait.new()
	portrait.position = Vector2(30, 82)
	portrait.size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_panel.add_child(portrait)
	_host_name = _label(Vector2(30, 240), Vector2(PORTRAIT_SIZE, 22), 14)
	_host_name.text = HOST_NAME
	_host_name.add_theme_color_override("font_color", Color(0.96, 0.69, 0.18))
	_host_role = _label(Vector2(30, 262), Vector2(172, 20), 13)
	_host_role.text = HOST_ROLE
	_host_role.add_theme_font_override("font", preload("res://assets/fonts/AtkinsonHyperlegible-Regular.ttf"))
	_host_role.add_theme_color_override("font_color", Color(0.68, 0.72, 0.82))
	_host_role.clip_text = true
	_body = RichTextLabel.new()
	_body.position = Vector2(206, 82)
	_body.size = Vector2(604, 296)
	_body.bbcode_enabled = true
	_body.scroll_active = false
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_theme_font_override("normal_font", load(DIALOGUE_FONT))
	_body.add_theme_font_size_override("normal_font_size", 21)
	_body.add_theme_constant_override("line_separation", 6)
	_body.add_theme_color_override("default_color", Color(0.93, 0.94, 0.98))
	_panel.add_child(_body)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_action = Button.new()
	_action.position = Vector2(30, 392)
	_action.size = Vector2(430, 54)
	_action.add_theme_font_size_override("font_size", 18)
	_action.pressed.connect(advance)
	_panel.add_child(_action)
	var back := Button.new()
	back.position = Vector2(606, 392)
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
	var move_keys := _prompt(gm._menu._keys_text("right"), "LEFT STICK")
	var jump_keys := _prompt(gm._menu._keys_text("jump"), "PAD A")
	var lock_keys := _prompt("LEFT SHIFT", "START")
	var throw_keys := _prompt("LEFT-CLICK", "R2")
	# One beat per line. The clock rule is told once, on the first lesson.
	var instructions: Array[String] = [
		"Za Warudo! Time, stop!\nStopped time is a realm for one man. Today I, %s, lend you a sliver of it.\nHold %s: your ghost walks into the gold zone. Your body stays frozen.\nLOCK with %s, and time resumes.\n\nEight seconds per attempt. When the clock runs out, whatever you planned happens. Even nothing." % [HOST_NAME, move_keys, lock_keys],
		"Oh? The fool across from you is approaching the marked ledge.\nLet him. I reveal his route this once.\nAim at the gold ring on his landing ghost.\nHold %s to three-quarters, release, LOCK.\nHe will leap into your knife. If this were chess, I would call it checkmate." % throw_keys,
		"Two knives already hang in the air. Mine.\nHold %s to leap the low one from the left.\nThe one from the right waits for your landing.\nAt the next freeze, read it and land elsewhere.\nSurvive both turns, and I may consider you a human worth stepping on." % jump_keys,
	]
	_body.text = message if not message.is_empty() else instructions[lesson]
	_action.text = "ENTER  PLAYTIME IS OVER. FIGHT." if completed and lesson == 2 else ("ENTER  NEXT LESSON" if completed else "ENTER  TIME RESUMES · 8s")
	if between_turns: _action.text = "ENTER  NEXT TURN · 8s"
	_markers.queue_redraw()

## Keyboard chips plus the fixed pad control when a pad is connected, so the
## briefing never advertises a stick nobody is holding. Keys are gold, pad
## controls violet, and each carries its prompt icon when the atlas has one.
func _prompt(keys: String, pad_control: String) -> String:
	var chips := PackedStringArray()
	for key in keys.split(" / "):
		chips.append(_chip(key.strip_edges().to_upper(), "f5b02e", "2b1a3f"))
	if force_pad_prompts or not Input.get_connected_joypads().is_empty():
		chips.append(_chip(pad_control, "d9a6ff", "2a1540"))
	return " ".join(chips)

func _chip(label: String, text_hex: String, fill_hex: String) -> String:
	var icon: String = CHIP_ICONS.get(label, "")
	var shown := label.trim_prefix("PAD ")
	var inner := "[img=22x22 color=#%s]%s[/img] %s" % [text_hex, icon, shown] if not icon.is_empty() else shown
	return "[bgcolor=#%s][color=#%s][font=%s][font_size=15] %s [/font_size][/font][/color][/bgcolor]" \
		% [fill_hex, text_hex, CHIP_FONT, inner]

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
	_hint.text = ["Ghost into the gold zone, then LOCK. Anything else is USELESS.", JUMP_HINT,
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
					show_briefing("You cleared the jump.\nThe second knife is still coming. The world did not reset for your comfort.\nIf it crosses your ghost, land elsewhere. Left works.\nOne more turn, human.")
					return
				success = true
	gm._telemetry.record("lesson_result", gm.turn, {"lesson": lesson + 1, "success": success})
	completed = success
	var messages: Array[String] = [
		"Your ghost became flesh.\nThe ghost previews. EXECUTE delivers.\nEven a human can learn this. Next: put a knife on that route.",
		"You threw at a spot where nobody stood yet. That is the whole game.\nIn a real duel his route is hidden.\nRead his feet. Guess the landing.",
		"Two knives, two turns, zero holes in you.\nA safe jump can still have a terrible landing. Read the threat at every freeze.\nThe playtime service is now over.\nGo fight the CPU, first to three hits. Do not embarrass me.",
	]
	var retries: Array[String] = [
		"USELESS.\nHold your right-move control until the ghost stands in the gold zone. Then LOCK.\nRESET wipes a bad route.\nAgain. I have all the time in the world. Literally.",
		"USELESS, USELESS.\nStay on your ledge. Aim at the gold ring above the marked platform.\nThree-quarters charge, release, LOCK.\nThe jump repeats on every retry. Your aim does not have to.",
		("The second knife met your landing.\nLeap the low one again, then steer left on the next plan.\nThe knives repeat their paths. Learn their habits, or remain a pincushion."
			if survival_windows > 0 else "The low knife found you.\nHold jump before you LOCK.\nAt the next freeze, watch the second knife. It covers the straight-jump landing.\nOh? You thought a straight jump was clever?"),
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
			_hint.text = "Time resumes. Your knife has an appointment." if gm.state == Phase.EXECUTING else JUMP_HINT
		elif lesson == 2:
			_hint.text = "Time resumes. Knives don't forget." if gm.state == Phase.EXECUTING \
				else (LANDING_HINT if survival_windows > 0 else DODGE_HINT)
		_markers.queue_redraw()
