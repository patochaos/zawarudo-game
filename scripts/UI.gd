extends CanvasLayer

## Compact match HUD. Detailed player-plan panels were deliberately removed so
## the arena, ghosts and world-space previews remain the focus.

const DUELIST_PORTRAIT := preload("res://assets/art/portraits/duelist-portrait-intense-v2.png")
const DASHBLADE_PORTRAIT := preload("res://assets/art/portraits/dashblade-portrait-v1.png")
const CHAKRAM_PORTRAIT := preload("res://assets/art/portraits/broodtail-portrait-v1.png")
const SHOCK_PORTRAIT := preload("res://assets/art/portraits/shockwitch-portrait-v1.png")


class FighterSeal:
	extends Control

	const EMPTY_PIP := Color(0.14, 0.14, 0.20, 0.94)

	var player_index: int = 0
	var accent: Color = Color.WHITE
	var mirrored: bool = false
	var portrait: Texture2D
	var fighter_name: String = "DUELIST"
	var points: int = 0
	var points_to_win: int = 3
	var super_meter: float = 0.0
	var super_armed: bool = false
	var lost_frames: int = -1
	var max_lost_frames: int = 3

	func configure(index: int, color: Color, flip: bool, name: String, texture: Texture2D) -> void:
		player_index = index
		accent = color
		mirrored = flip
		fighter_name = name
		portrait = texture
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(430.0, 58.0)
		queue_redraw()

	func set_identity(name: String, texture: Texture2D) -> void:
		if fighter_name == name and portrait == texture:
			return
		fighter_name = name
		portrait = texture
		queue_redraw()

	func set_state(score_value: int, win_score: int, meter: float, armed: bool,
			debt_cells: int = -1, debt_max: int = 3) -> void:
		points = score_value
		points_to_win = win_score
		super_meter = clampf(meter, 0.0, 1.0)
		super_armed = armed
		lost_frames = debt_cells
		max_lost_frames = maxi(1, debt_max)
		queue_redraw()

	func _mirror_points(source: PackedVector2Array) -> PackedVector2Array:
		if not mirrored:
			return source
		var result := PackedVector2Array()
		for point in source:
			result.append(Vector2(size.x - point.x, point.y))
		return result

	func _draw() -> void:
		# Portrait, score and meter share one uninterrupted rail. The narrow crop
		# preserves fighter recognition without turning the identity into a card.
		var portrait_target := Rect2(0.0, 1.0, 44.0, 55.0)
		var portrait_source := Rect2(150.0, 0.0, 950.0, 950.0)
		var portrait_tint := Color(0.88, 0.58, 1.0, 1.0) \
			if mirrored and fighter_name == "DUELIST" else Color.WHITE
		if mirrored:
			draw_set_transform(Vector2(size.x, 0.0), 0.0, Vector2(-1.0, 1.0))
		if portrait != null:
			draw_texture_rect_region(portrait, portrait_target, portrait_source, portrait_tint)
		if mirrored:
			draw_set_transform(Vector2.ZERO)

		var portrait_frame := _mirror_points(PackedVector2Array([
			Vector2(0.0, 1.0), Vector2(34.0, 1.0), Vector2(44.0, 11.0),
			Vector2(44.0, 46.0), Vector2(34.0, 56.0), Vector2(0.0, 56.0),
		]))
		draw_polyline(portrait_frame + PackedVector2Array([portrait_frame[0]]),
			Color(accent.r, accent.g, accent.b, 0.72), 1.0, true)

		var font := ThemeDB.fallback_font
		var name_x := 52.0 if not mirrored else 270.0
		var name_width := 110.0
		var name_align := HORIZONTAL_ALIGNMENT_LEFT if not mirrored else HORIZONTAL_ALIGNMENT_RIGHT
		draw_string(font, Vector2(name_x, 23.0), "P%d · %s" % [player_index + 1, fighter_name],
			name_align, name_width, 11, accent.lightened(0.22))
		if lost_frames >= 0:
			var debt_label_x := 52.0 if not mirrored else 270.0
			var debt_pip_x := 91.0 if not mirrored else 315.0
			draw_string(font, Vector2(debt_label_x, 42.0), "FRAME",
				HORIZONTAL_ALIGNMENT_LEFT, 36.0, 7, Color(0.52, 0.92, 1.0, 0.82))
			for i in max_lost_frames:
				var cell := Rect2(debt_pip_x + float(i) * 13.0, 34.0, 9.0, 7.0)
				draw_rect(cell, Color(0.34, 0.96, 1.0, 0.88) if i < lost_frames \
					else Color(0.10, 0.15, 0.20, 0.92))
				draw_rect(cell, Color(0.72, 1.0, 1.0, 0.72), false, 1.0)

		var first_pip_x := 169.0
		var pip_step := minf(16.0, 96.0 / float(maxi(1, points_to_win - 1)))
		for i in points_to_win:
			var centre := Vector2(first_pip_x + float(i) * pip_step, 20.0)
			var diamond := PackedVector2Array([
				centre + Vector2(0.0, -4.0), centre + Vector2(4.0, 0.0),
				centre + Vector2(0.0, 4.0), centre + Vector2(-4.0, 0.0),
			])
			if i < points:
				draw_colored_polygon(diamond, accent.lightened(0.18))
			else:
				draw_colored_polygon(diamond, EMPTY_PIP)
			draw_polyline(diamond + PackedVector2Array([diamond[0]]), accent, 1.0, true)

		var bar_x := 306.0 if not mirrored else 14.0
		var bar_width := 110.0
		var bar_rect := Rect2(bar_x, 39.0, bar_width, 4.0)
		# Directly above the bar, never beside it: at 284 the label ran from 284 to
		# 332 while the bar started at 306, so the fill painted over its own name —
		# and on the mirrored side it covered the label completely.
		draw_string(font, Vector2(bar_x, 35.0), "SUPER",
			HORIZONTAL_ALIGNMENT_LEFT if not mirrored else HORIZONTAL_ALIGNMENT_RIGHT,
			bar_width, 8, accent.lightened(0.08))
		draw_rect(bar_rect, Color(0.10, 0.09, 0.14, 0.92))
		draw_rect(bar_rect, Color(accent.r, accent.g, accent.b, 0.62), false, 1.0)
		if super_meter > 0.0:
			var fill_color := Color(1.0, 0.94, 0.58) if super_meter >= 1.0 else accent
			var fill_width := bar_rect.size.x * super_meter
			var fill_x := bar_rect.end.x - fill_width if mirrored else bar_rect.position.x
			draw_rect(Rect2(Vector2(fill_x, bar_rect.position.y),
				Vector2(fill_width, bar_rect.size.y)), fill_color)
		if super_armed:
			var armed_at := Vector2(bar_rect.end.x + 6.0 if not mirrored else bar_rect.position.x - 6.0,
				bar_rect.position.y + 2.5)
			draw_circle(armed_at, 3.0, Color(1.0, 0.96, 0.66))


class HudChrome:
	extends Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()

	func _draw() -> void:
		# A single leaded-glass rail is the only persistent match chrome.
		draw_rect(Rect2(0.0, 0.0, 1280.0, 58.0), Color(0.025, 0.012, 0.045, 0.84))
		draw_line(Vector2(0.0, 57.0), Vector2(1280.0, 57.0),
			Color(0.84, 0.60, 0.19, 0.52), 1.0)


class ResultChrome:
	extends Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()

	func _draw() -> void:
		var gold := Color(0.96, 0.69, 0.18)
		var violet := Color(0.55, 0.20, 0.82)
		# Restrained manga rays frame the result without obscuring the frozen
		# final position, which remains useful context for the winning hit.
		for i in 9:
			var y := 132.0 + float(i) * 58.0
			draw_line(Vector2(0.0, y), Vector2(270.0 + float(i % 3) * 22.0, 360.0),
				Color(violet.r, violet.g, violet.b, 0.035), 2.0)
			draw_line(Vector2(1280.0, y), Vector2(1010.0 - float(i % 3) * 22.0, 360.0),
				Color(gold.r, gold.g, gold.b, 0.035), 2.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(250.0, 176.0), Vector2(1052.0, 176.0), Vector2(1004.0, 610.0),
			Vector2(218.0, 610.0),
		]), Color(0.018, 0.010, 0.035, 0.90))
		draw_polyline(PackedVector2Array([
			Vector2(250.0, 176.0), Vector2(1052.0, 176.0), Vector2(1004.0, 610.0),
			Vector2(218.0, 610.0), Vector2(250.0, 176.0),
		]), Color(gold.r, gold.g, gold.b, 0.48), 1.5, true)
		draw_line(Vector2(380.0, 306.0), Vector2(900.0, 306.0),
			Color(gold.r, gold.g, gold.b, 0.55), 2.0)
		draw_line(Vector2(424.0, 388.0), Vector2(856.0, 388.0),
			Color(violet.r, violet.g, violet.b, 0.42), 1.0)

var gm

var _turn_label: Label
var _timer_label: Label
var _phase_label: Label
var _level_label: Label
var _build_label: Label
var _score_label: Label
var _phase_track: ColorRect
var _phase_fill: ColorRect
var _pips: Array[Array] = []
var _fighter_seals: Array[FighterSeal] = []
var _hint_p1: Label
var _hint_p2: Label

const _HINT_P2_MISSING := "P2  CONNECT A GAMEPAD"
const _HINT_AI := "P2  AI · PLAN HIDDEN"
const _HINT_AI_4P := "P2–P4  AI · PLANS HIDDEN"
const _HINT_ONLINE_YOU := "YOU P%d  A/D MOVE · SPACE JUMP · S WAIT · MOUSE AIM · LMB THROW · T SUPER · SHIFT LOCK · R UNDO"
const _HINT_ONLINE_RIVAL := "P%d  ONLINE · PLAN HIDDEN"
const _HINT_ONLINE_ABANDONED := "OPPONENT DISCONNECTED  ·  ENTER CLAIMS THE MATCH  ·  ESC LEAVES"
const _HINT_ONLINE_BROKEN := "MATCH STOPPED  ·  ESC RETURNS TO THE MENU"
const _HINT_PAD := "PAD P%d  L-STICK MOVE · A JUMP · ↓ WAIT · R-STICK AIM · R2 THROW · Y SUPER · START LOCK · B UNDO"
var _banner_bg: ColorRect
var _banner_rule: ColorRect
var _banner: Label

const _PIP_EMPTY := Color(0.20, 0.22, 0.27, 0.9)

var help_visible: bool = false
var _help: Array[CanvasItem] = []
var _tuning: Label
var _over_bg: ColorRect
var _over_chrome: ResultChrome
var _over_label: Label
var _over_score: Label
var _over_arena: Label
var _over_controls: Label
var _arena_previous_button: Button
var _arena_next_button: Button
var _replay_button: Button
var _rematch_button: Button
var _menu_button: Button
var _report_button: Button
var touch_mode: bool = false


func build(manager) -> void:
	gm = manager
	var chrome := HudChrome.new()
	chrome.size = Vector2(1280.0, 720.0)
	chrome.z_index = -1
	add_child(chrome)

	# Secondary match metadata remains available to tests/debugging but is not
	# persistent match chrome. Combat state alone occupies the top rail.
	_level_label = _mk_label(Vector2(240.0, 682.0), 800.0, 11, HORIZONTAL_ALIGNMENT_CENTER)
	_level_label.add_theme_color_override("font_color", Color(0.52, 0.58, 0.68))
	_level_label.visible = false
	_build_label = _mk_label(Vector2(1060.0, 694.0), 200.0, 9, HORIZONTAL_ALIGNMENT_RIGHT)
	_build_label.text = "PLAYTEST %s" % str(ProjectSettings.get_setting(
		"application/config/version", "DEV"))
	_build_label.add_theme_color_override("font_color", Color(0.38, 0.42, 0.50))
	_build_label.visible = false
	# Which phase you are in decides whether your input matters at all, so it
	# should not be the smallest text on screen while the clock is the largest.
	# The seals own x < 438 and x > 842, so these widths cannot grow.
	_turn_label = _mk_label(Vector2(438.0, 20.0), 92.0, 13, HORIZONTAL_ALIGNMENT_RIGHT)
	_timer_label = _mk_label(Vector2(548.0, 6.0), 184.0, 26, HORIZONTAL_ALIGNMENT_CENTER)
	_timer_label.size.y = 48.0
	_phase_label = _mk_label(Vector2(750.0, 18.0), 92.0, 14, HORIZONTAL_ALIGNMENT_LEFT)
	_phase_track = ColorRect.new()
	_phase_track.position = Vector2(480.0, 53.0)
	_phase_track.size = Vector2(320.0, 3.0)
	_phase_track.color = Color(0.12, 0.11, 0.17, 0.90)
	add_child(_phase_track)
	_phase_fill = ColorRect.new()
	_phase_fill.position = _phase_track.position
	_phase_fill.size = _phase_track.size
	_phase_fill.color = Color(0.86, 0.66, 1.0)
	add_child(_phase_fill)
	# Build all four score rows up front; unused rows stay hidden in duel modes.
	for i in gm.MAX_PLAYERS:
		var row: Array[ColorRect] = []
		for h in gm.MAX_HITS_TO_WIN:
			var pip := ColorRect.new()
			pip.position = Vector2.ZERO
			pip.size = Vector2(11.0, 11.0)
			pip.color = _PIP_EMPTY
			add_child(pip)
			row.append(pip)
		_pips.append(row)
	_score_label = _mk_label(Vector2(440.0, 39.0), 400.0, 9, HORIZONTAL_ALIGNMENT_CENTER)
	_score_label.add_theme_color_override("font_color", Color(0.45, 0.50, 0.60))
	_score_label.text = "FIRST TO %d HITS" % gm.hits_to_win
	_score_label.visible = false

	# Mirrored 1v1 fighter seals. They replace the anonymous centre score pips in
	# duels, but the existing scalable rows remain available for four-player mode.
	for i in 2:
		var seal := FighterSeal.new()
		seal.position = Vector2(8.0, 0.0) if i == 0 else Vector2(842.0, 0.0)
		seal.configure(i, gm.PLAYER_COLORS[i], i == 1, "DUELIST", DUELIST_PORTRAIT)
		add_child(seal)
		_fighter_seals.append(seal)

	# --- bottom control bar -------------------------------------------------
	var bar := ColorRect.new()
	bar.position = Vector2(0.0, 666.0)
	bar.size = Vector2(1280.0, 54.0)
	bar.color = Color(0.035, 0.018, 0.06, 0.94)
	add_child(bar)
	_help.append(bar)

	_hint_p1 = _hint(670.0, gm.PLAYER_COLORS[0],
		"P1  A/D MOVE · SPACE JUMP · S WAIT · MOUSE AIM · LMB THROW · T SUPER · SHIFT LOCK · R UNDO · F RESET")
	_hint_p2 = _hint(695.0, gm.PLAYER_COLORS[1], "")

	_tuning = _mk_label(Vector2(16.0, 700.0), 1248.0, 12, HORIZONTAL_ALIGNMENT_CENTER)
	_tuning.add_theme_color_override("font_color", Color(0.45, 0.50, 0.58))
	_tuning.visible = false
	for item in _help:
		item.visible = help_visible

	# Hit notices are brief bottom toasts. They never add another layer above the
	# action and their existing lifetime fades them away automatically.
	_banner_bg = ColorRect.new()
	_banner_bg.position = Vector2(400.0, 614.0)
	_banner_bg.size = Vector2(480.0, 36.0)
	_banner_bg.color = Color(0.08, 0.09, 0.13, 0.78)
	_banner_bg.visible = false
	add_child(_banner_bg)

	_banner_rule = ColorRect.new()
	_banner_rule.position = Vector2(400.0, 648.0)
	_banner_rule.size = Vector2(480.0, 2.0)
	_banner_rule.visible = false
	add_child(_banner_rule)

	_banner = _mk_label(Vector2(400.0, 618.0), 480.0, 20, HORIZONTAL_ALIGNMENT_CENTER)
	_banner.size = Vector2(480.0, 30.0)
	_banner.visible = false

	_over_bg = ColorRect.new()
	_over_bg.position = Vector2.ZERO
	_over_bg.size = Vector2(1280.0, 720.0)
	_over_bg.color = Color(0.012, 0.008, 0.025, 0.84)
	_over_bg.visible = false
	add_child(_over_bg)
	_over_chrome = ResultChrome.new()
	_over_chrome.size = Vector2(1280.0, 720.0)
	_over_chrome.visible = false
	add_child(_over_chrome)

	_over_label = _mk_label(Vector2(140.0, 205.0), 1000.0, 46, HORIZONTAL_ALIGNMENT_CENTER)
	_over_label.size = Vector2(1000.0, 74.0)
	_over_label.visible = false
	_over_score = _mk_label(Vector2(390.0, 295.0), 500.0, 42, HORIZONTAL_ALIGNMENT_CENTER)
	_over_score.size = Vector2(500.0, 64.0)
	_over_score.visible = false
	_over_arena = _mk_label(Vector2(300.0, 354.0), 680.0, 21, HORIZONTAL_ALIGNMENT_CENTER)
	_over_arena.size = Vector2(800.0, 54.0)
	_over_arena.visible = false
	_over_controls = _mk_label(Vector2(140.0, 568.0), 1000.0, 13, HORIZONTAL_ALIGNMENT_CENTER)
	_over_controls.size = Vector2(1000.0, 34.0)
	_over_controls.visible = false

	_arena_previous_button = _result_button(Vector2(282.0, 352.0), Vector2(52.0, 44.0), "‹", false)
	_arena_previous_button.pressed.connect(func(): gm._cycle_rematch_level(-1))
	_arena_next_button = _result_button(Vector2(946.0, 352.0), Vector2(52.0, 44.0), "›", false)
	_arena_next_button.pressed.connect(func(): gm._cycle_rematch_level(1))
	_replay_button = _result_button(Vector2(342.0, 438.0), Vector2(184.0, 52.0), "R  WATCH REPLAY")
	_replay_button.pressed.connect(func(): gm._start_match_replay())
	_rematch_button = _result_button(Vector2(544.0, 438.0), Vector2(208.0, 52.0), "ENTER  REMATCH", true)
	_rematch_button.pressed.connect(func(): gm._request_rematch())
	_menu_button = _result_button(Vector2(770.0, 438.0), Vector2(168.0, 52.0), "ESC  MENU")
	_menu_button.pressed.connect(_leave_result)
	_report_button = _result_button(Vector2(520.0, 510.0), Vector2(240.0, 42.0), "C  COPY MATCH REPORT")
	_report_button.pressed.connect(func(): gm.copy_match_report())


func _result_button(pos: Vector2, dimensions: Vector2, text: String,
		primary: bool = false) -> Button:
	var button := Button.new()
	button.position = pos
	button.size = dimensions
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", Color(0.94, 0.95, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.70))
	button.add_theme_color_override("font_disabled_color", Color(0.38, 0.39, 0.46))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.17, 0.07, 0.25, 0.94) if primary else Color(0.045, 0.03, 0.075, 0.96)
	normal.border_color = Color(0.91, 0.66, 0.22, 0.78 if primary else 0.36)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(3)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.38, 0.12, 0.56, 0.98)
	hover.border_color = Color(1.0, 0.82, 0.34, 0.96)
	hover.set_border_width_all(2)
	button.add_theme_stylebox_override("hover", hover)
	var pressed := hover.duplicate()
	pressed.bg_color = Color(0.24, 0.08, 0.34, 1.0)
	button.add_theme_stylebox_override("pressed", pressed)
	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.025, 0.02, 0.04, 0.82)
	disabled.border_color = Color(0.20, 0.20, 0.26, 0.72)
	button.add_theme_stylebox_override("disabled", disabled)
	button.mouse_entered.connect(func(): gm._sfx.play("ui_move"))
	button.pressed.connect(func(): gm._sfx.play("ui_accept"))
	button.visible = false
	add_child(button)
	return button


func _leave_result() -> void:
	if gm.online_mode:
		gm._leave_online()
	else:
		gm._open_menu()


func _hint(y: float, col: Color, text: String) -> Label:
	var l := _mk_label(Vector2(16.0, y), 1248.0, 13, HORIZONTAL_ALIGNMENT_CENTER)
	l.text = text
	l.add_theme_color_override("font_color", col.darkened(0.15))
	_help.append(l)
	return l


## H hides the control reference once a tester has learned the bindings.
func toggle_help() -> bool:
	if touch_mode:
		return false
	help_visible = not help_visible
	for n in _help:
		n.visible = help_visible
	return help_visible


func show_controls(show: bool) -> void:
	if touch_mode:
		return
	help_visible = show
	for n in _help:
		n.visible = show


func set_touch_mode(active: bool) -> void:
	touch_mode = active
	if touch_mode:
		help_visible = false
		for item in _help:
			item.visible = false


func _mk_label(pos: Vector2, width: float, size: int, align: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(width, 150.0)
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.90, 0.93, 0.97))
	l.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.92))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.add_theme_color_override("font_outline_color", Color(0.025, 0.01, 0.04, 0.9))
	l.add_theme_constant_override("outline_size", 1)
	add_child(l)
	return l


func refresh() -> void:
	_turn_label.text = "T%d" % gm.turn
	var match_rule := "TRAINING · HORIZONTAL TUNNEL ↔" if gm.tutorial_mode else \
		("CRIMSON  %d   —   %d  AZURE     ·     FIRST TO %d" % [
			gm.team_score[0], gm.team_score[1], gm.hits_to_win] if gm.team_mode else \
		"FIRST TO %d HITS" % gm.hits_to_win)
	if not gm.tutorial_mode and gm.core_active:
		match_rule += "   ·   CORE: FULL SUPER (%d TURN%s LEFT)" % [
			gm.core_turns_left, "" if gm.core_turns_left == 1 else "S"]
	elif not gm.tutorial_mode and gm.core_announced:
		match_rule += "   ·   CORE MATERIALIZES NEXT TURN"
	elif not gm.tutorial_mode:
		var remaining: int = maxi(0, gm.core_hitless_turns_to_announce - gm.hitless_execution_streak)
		match_rule += "   ·   CORE IN %d HITLESS TURN%s" % [remaining, "" if remaining == 1 else "S"]
	_score_label.text = match_rule
	_score_label.visible = gm.team_mode
	_level_label.text = "LEVEL %d/%d — %s   ·   %s" % [
		gm.level_index + 1, Levels.count(), gm.level_name, gm.level_wrap,
	]
	if gm.tutorial_mode:
		_level_label.text = "TUTORIAL — %s   ·   %s" % [gm.level_name, gm.level_wrap]
	if gm.online_mode:
		_level_label.text += "   ·   ROOM %s" % gm.online_room
		_hint_p1.text = ((_HINT_PAD % 1) if gm._pads[0] >= 0 else (_HINT_ONLINE_YOU % 1)) \
			if gm.online_player == 0 else _HINT_ONLINE_RIVAL % 1
		_hint_p2.text = ((_HINT_PAD % 2) if gm._pads[1] >= 0 else (_HINT_ONLINE_YOU % 2)) \
			if gm.online_player == 1 else _HINT_ONLINE_RIVAL % 2
		# Being stranded outlasts any banner, so the way out stays on screen.
		if gm.online_match_broken:
			_hint_p2.text = _HINT_ONLINE_BROKEN
		elif gm.online_peer_lost:
			_hint_p2.text = _HINT_ONLINE_ABANDONED
	elif gm.tutorial_mode:
		_hint_p1.text = ""
		_hint_p2.text = ""
	else:
		if gm.team_mode:
			_level_label.text += "   ·   2V2 TEAM BATTLE"
			_hint_p1.text = "CRIMSON  P1 + P3  ·  COORDINATE PLANS  ·  FRIENDLY FIRE SCORES NO POINT"
			_hint_p2.text = "AZURE  P2 + P4  ·  FIRST TEAM TO %d HITS" % gm.hits_to_win
		else:
			if gm.uses_dashblade(0):
				_hint_p1.text = "P1 VELOCITY  NO JUMP · MOVE TO BANK FRAMES · AIM CUT TO CLIMB · LMB CUT TO END · T SUPER"
			elif gm.uses_chakram(0):
				_hint_p1.text = "P1 BROODTAIL  A/D MOVE · SPACE JUMP · MOUSE AIM · LMB RELEASE · T SUPER · SHIFT LOCK"
			elif gm.uses_shock(0):
				_hint_p1.text = "P1 STATIC WITCH  FLOATY JUMP · LMB PLASMA · RMB ADD ORB · T SUPER"
				_level_label.text += "   ·   P1 %s · %d ORB%s LIVE" % ["PLASMA" \
					if gm.players[0].plan.attack_mode == 0 else "ORB", gm.shock_orb_count(0),
					"" if gm.shock_orb_count(0) == 1 else "S"]
			else:
				_hint_p1.text = \
					"P1  A/D MOVE · SPACE JUMP · S WAIT · MOUSE AIM · LMB THROW · T SUPER · SHIFT LOCK · R UNDO · F RESET"
			if gm.vs_ai:
				_hint_p2.text = _HINT_AI_4P if gm.players.size() == 4 else _HINT_AI
			else:
				if gm._pads[1] >= 0:
					if gm.uses_dashblade(1):
						_hint_p2.text = "PAD P2 VELOCITY · MOVE BANKS FRAMES · R2 CUT TO END · Y SUPER · START LOCK"
					elif gm.uses_chakram(1):
						_hint_p2.text = "PAD P2 BROODTAIL · R-STICK AIM · R2 RELEASE · Y SUPER · START LOCK"
					elif gm.uses_shock(1):
						_hint_p2.text = "PAD P2 STATIC WITCH · R2 FIRE · L1/R1 PLASMA/ORB · Y SUPER"
					else:
						_hint_p2.text = _HINT_PAD % 2
				else:
					_hint_p2.text = _HINT_P2_MISSING
				if gm.uses_shock(1):
					_level_label.text += "   ·   P2 %s · %d ORB%s LIVE" % ["PLASMA" \
						if gm.players[1].plan.attack_mode == 0 else "ORB", gm.shock_orb_count(1),
						"" if gm.shock_orb_count(1) == 1 else "S"]

	var active_players: int = gm.players.size()
	var duel_hud: bool = not gm.tutorial_mode and not gm.team_mode and active_players == 2
	for i in _fighter_seals.size():
		var seal: FighterSeal = _fighter_seals[i]
		seal.visible = duel_hud
		if duel_hud:
			var portrait: Texture2D = DUELIST_PORTRAIT
			match gm.player_weapons[i]:
				2: portrait = DASHBLADE_PORTRAIT
				3: portrait = CHAKRAM_PORTRAIT
				4: portrait = SHOCK_PORTRAIT
			seal.set_identity(gm.weapon_short_name(i), portrait)
			seal.set_state(gm.score[i], gm.hits_to_win, gm.super_meter[i], gm.super_armed[i],
				gm.frame_debt_cells[i] if gm.uses_dashblade(i) else -1,
				gm.frame_debt_max_cells)
	for i in gm.MAX_PLAYERS:
		for h in _pips[i].size():
			var pip: ColorRect = _pips[i][h]
			pip.visible = not gm.tutorial_mode and not duel_hud and \
				((gm.team_mode and i < 2) or (not gm.team_mode and i < active_players)) \
				and h < gm.hits_to_win
			if gm.team_mode and i < 2:
				var team_centre := 520.0 if i == 0 else 760.0
				var team_row_width: float = float(gm.hits_to_win - 1) * 16.0
				pip.position = Vector2(team_centre - team_row_width * 0.5 + float(h) * 16.0 - 5.0, 40.0)
				pip.color = gm.TEAM_COLORS[i] if h < gm.team_score[i] else _PIP_EMPTY
			elif i < active_players:
				var centre: float = lerpf(280.0, 1000.0,
					float(i) / float(maxi(active_players - 1, 1)))
				var row_width: float = float(gm.hits_to_win - 1) * 16.0
				pip.position = Vector2(centre - row_width * 0.5 + float(h) * 16.0 - 5.0, 40.0)
				pip.color = gm.PLAYER_COLORS[i] if h < gm.score[i] else _PIP_EMPTY

	# hit banner, fading out over its last half second
	var bt: float = gm.banner_time
	_banner_bg.visible = bt > 0.0
	_banner.visible = bt > 0.0
	if bt > 0.0:
		var a: float = clampf(bt / 0.5, 0.0, 1.0)
		_banner.text = gm.banner_text
		_banner.add_theme_color_override("font_color",
			Color(gm.banner_color.r, gm.banner_color.g, gm.banner_color.b, a))
		_banner_bg.color = Color(0.08, 0.09, 0.13, 0.78 * a)
		var edge := Color(gm.banner_color.r, gm.banner_color.g, gm.banner_color.b, 0.85 * a)
		_banner_rule.color = edge
		_banner_rule.visible = true
	else:
		_banner_rule.visible = false

	var phase_fraction := 0.0
	var phase_color := Color(0.86, 0.66, 1.0)
	var phase_meter_visible := true
	match gm.state:
		Phase.PLANNING:
			var tutorial_waiting: bool = gm.tutorial_mode and gm._tutorial != null and not gm._tutorial.timed_turns_started
			_timer_label.text = "" if tutorial_waiting else "%.1f" % maxf(gm.planning_time_left, 0.0)
			var frac: float = gm.planning_time_left / maxf(gm.planning_window_duration, 0.001)
			phase_fraction = frac
			phase_meter_visible = not tutorial_waiting
			phase_color = Color(1.0, 0.30, 0.28) if frac < 0.25 else Color(0.72, 0.38, 0.95)
			_timer_label.add_theme_color_override("font_color",
				Color(1.0, 0.35, 0.3) if frac < 0.25 else Color(0.92, 0.95, 1.0))
			_phase_label.text = "PRACTICE" if tutorial_waiting else "PLAN"
			_phase_label.add_theme_color_override("font_color", Color(0.86, 0.66, 1.0))
		Phase.COMMITTING:
			_timer_label.text = "%.2f" % maxf(gm.commit_time_left, 0.0)
			phase_fraction = gm.commit_time_left / maxf(gm.commit_delay, 0.001)
			phase_color = Color(1.0, 0.78, 0.24)
			_timer_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
			_phase_label.text = "LOCKED"
			_phase_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		Phase.EXECUTING:
			_timer_label.text = "%.2f" % gm.exec_time_left()
			phase_fraction = gm.exec_time_left() / maxf(gm.execution_duration, 0.001)
			phase_color = Color(0.35, 0.95, 0.55)
			_timer_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.55))
			_phase_label.text = "EXECUTE"
			_phase_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.55))
		Phase.REPLAY:
			_timer_label.text = "%.1f" % gm.replay_time_left()
			_timer_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.32))
			_phase_label.text = "REPLAY %.1f×" % gm.replay_speed
			_phase_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.32))
			phase_meter_visible = false
		Phase.GAME_OVER:
			_timer_label.text = ""
			_phase_label.text = "GAME OVER"
			_phase_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
			phase_meter_visible = false
		Phase.ONLINE_WAIT:
			_timer_label.text = "—"
			_timer_label.add_theme_color_override("font_color", Color(0.72, 0.62, 0.92))
			_phase_label.text = "WAITING"
			_phase_label.add_theme_color_override("font_color", Color(0.72, 0.62, 0.92))
			phase_meter_visible = false
		_:
			phase_meter_visible = false
	_phase_track.visible = phase_meter_visible
	_phase_fill.visible = phase_meter_visible
	_phase_fill.size.x = 320.0 * clampf(phase_fraction, 0.0, 1.0)
	_phase_fill.color = phase_color

	var pads := ""
	for i in gm.players.size():
		if gm._pads[i] >= 0:
			pads += "  P%d=pad%d" % [i + 1, gm._pads[i]]
	_tuning.text = "PLANNING %.0fs  [F1 5 | F2 8 | F3 10]   EXECUTION %.2fs  [F5 .40 | F6 .75]   F9 restart   F10 next level   M sound %s   H hide debug/help   ESC menu%s" \
		% [gm.planning_duration, gm.execution_duration, "OFF" if gm._sfx.muted else "on", pads]

	var over: bool = gm.state == Phase.GAME_OVER
	var ui_result: bool = over and not touch_mode
	_over_bg.visible = over
	_over_chrome.visible = ui_result
	_over_label.visible = ui_result
	_over_score.visible = ui_result
	_over_arena.visible = ui_result
	_over_controls.visible = ui_result
	var desktop_result: bool = over and not bool(gm._touch_controls.enabled)
	_arena_previous_button.visible = desktop_result
	_arena_next_button.visible = desktop_result
	_replay_button.visible = desktop_result
	_rematch_button.visible = desktop_result
	_menu_button.visible = desktop_result
	_report_button.visible = desktop_result
	var level_locked: bool = bool(gm.online_mode) \
		and (gm.online_player != 0 or bool(gm._online_waiting_rematch))
	_arena_previous_button.disabled = level_locked
	_arena_next_button.disabled = level_locked
	_rematch_button.disabled = gm.online_mode and gm._online_waiting_rematch
	if over:
		var controls: String
		if touch_mode:
			controls = "HOST CHOOSES THE ARENA · WATCH THE FIGHT · OR RUN IT BACK" \
				if gm.online_mode and gm.online_player != 0 else \
				"CHOOSE THE NEXT ARENA · WATCH THE FIGHT · OR RUN IT BACK"
		elif gm.online_mode:
			controls = "KEYBOARD AND GAMEPAD SHORTCUTS REMAIN AVAILABLE" \
				if gm.online_player == 0 else "THE HOST CHOOSES THE NEXT ARENA"
		else:
			controls = "KEYBOARD  ←/→ LEVEL · R REPLAY · ENTER REMATCH     GAMEPAD  D-PAD · Y · A"
		var arena_line := "NEXT ARENA   %02d / %02d   —   %s" % [
			gm.rematch_level_index + 1, Levels.count(), gm.rematch_level_name]
		if gm.online_mode and gm.online_player != 0:
			arena_line = "HOST ARENA — %d/%d — %s" % [
				gm.rematch_level_index + 1, Levels.count(), gm.rematch_level_name]
		_over_score.text = gm._score_text()
		_over_arena.text = arena_line
		_over_controls.text = controls
		_over_score.add_theme_color_override("font_color", Color(0.92, 0.93, 0.98))
		_over_arena.add_theme_color_override("font_color", Color(1.0, 0.82, 0.34))
		_over_controls.add_theme_color_override("font_color", Color(0.68, 0.72, 0.82))
		if gm.team_mode and gm.winning_team >= 0:
			_over_label.text = "TEAM %s TAKES THE MATCH" % gm.TEAM_NAMES[gm.winning_team]
			_over_label.add_theme_color_override("font_color", gm.TEAM_COLORS[gm.winning_team].lightened(0.18))
		elif gm.winner >= 0:
			_over_label.text = "PLAYER %d TAKES THE MATCH" % (gm.winner + 1)
			_over_label.add_theme_color_override("font_color", gm.PLAYER_COLORS[gm.winner].lightened(0.2))
		else:
			_over_label.text = "DRAW"
			_over_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
