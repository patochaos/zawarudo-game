extends CanvasLayer

## Compact match HUD. Detailed player-plan panels were deliberately removed so
## the arena, ghosts and world-space previews remain the focus.


class HudChrome:
	extends Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()

	func _draw() -> void:
		var gold := Color(0.84, 0.60, 0.19, 0.68)
		draw_colored_polygon(PackedVector2Array([
			Vector2(452.0, 0.0), Vector2(828.0, 0.0), Vector2(790.0, 190.0), Vector2(490.0, 190.0),
		]), Color(0.035, 0.018, 0.065, 0.72))
		draw_line(Vector2(490.0, 188.0), Vector2(790.0, 188.0), gold, 2.0)
		draw_line(Vector2(0.0, 630.0), Vector2(1280.0, 630.0), gold, 2.0)

var gm

var _turn_label: Label
var _timer_label: Label
var _phase_label: Label
var _level_label: Label
var _score_label: Label
var _pips: Array[Array] = []
var _hint_p1: Label
var _hint_p2: Label

const _HINT_P2 := "P2   HOLD ←/→ walk · ↑ jump · ↓ let time run · , /. aim · hold ENTER fire · P toggle SUPER · R-SHIFT confirm · BACKSPACE rollback · / reset path"
const _HINT_AI := "P2   played by the AI — it plans blind too, so its ghost and trajectory stay hidden from you"
const _HINT_ONLINE_YOU := "YOU — P%d   HOLD A/D walk · W jump · S let time run · MOUSE aim · hold LMB fire · T SUPER · L-SHIFT confirm · RMB/R rollback · F reset"
const _HINT_ONLINE_RIVAL := "P%d   ONLINE OPPONENT — their plan stays hidden until both players lock fate"
var _banner_bg: ColorRect
var _banner_rule: ColorRect
var _banner: Label

const _PIP_EMPTY := Color(0.20, 0.22, 0.27, 0.9)

var help_visible: bool = false
var _help: Array[CanvasItem] = []
var _tuning: Label
var _over_bg: ColorRect
var _over_label: Label


func build(manager) -> void:
	gm = manager
	var chrome := HudChrome.new()
	chrome.size = Vector2(1280.0, 720.0)
	chrome.z_index = -1
	add_child(chrome)

	_level_label = _mk_label(Vector2(440.0, 8.0), 400.0, 15, HORIZONTAL_ALIGNMENT_CENTER)
	_level_label.add_theme_color_override("font_color", Color(0.52, 0.58, 0.68))
	_turn_label = _mk_label(Vector2(540.0, 26.0), 200.0, 20, HORIZONTAL_ALIGNMENT_CENTER)
	_timer_label = _mk_label(Vector2(490.0, 46.0), 300.0, 62, HORIZONTAL_ALIGNMENT_CENTER)
	_phase_label = _mk_label(Vector2(490.0, 116.0), 300.0, 20, HORIZONTAL_ALIGNMENT_CENTER)
	# Best-of-N pips, P1 filling leftward from the centre and P2 rightward.
	for i in 2:
		var row: Array[ColorRect] = []
		for h in gm.hits_to_win:
			var pip := ColorRect.new()
			var off: float = 14.0 + float(h) * 20.0
			pip.position = Vector2(640.0 - off - 6.0 if i == 0 else 640.0 + off - 6.0, 146.0)
			pip.size = Vector2(13.0, 13.0)
			pip.color = _PIP_EMPTY
			add_child(pip)
			row.append(pip)
		_pips.append(row)
	_score_label = _mk_label(Vector2(490.0, 166.0), 300.0, 13, HORIZONTAL_ALIGNMENT_CENTER)
	_score_label.add_theme_color_override("font_color", Color(0.45, 0.50, 0.60))
	_score_label.text = "FIRST TO %d HITS" % gm.hits_to_win

	# --- bottom control bar -------------------------------------------------
	var bar := ColorRect.new()
	bar.position = Vector2(0.0, 630.0)
	bar.size = Vector2(1280.0, 90.0)
	bar.color = Color(0.035, 0.018, 0.06, 0.94)
	add_child(bar)
	_help.append(bar)

	_hint_p1 = _hint(638.0, gm.PLAYER_COLORS[0],
		"P1   HOLD A/D walk · W jump · S let time run · MOUSE aim · hold LMB fire · T toggle SUPER · L-SHIFT confirm · R rollback · F reset path")
	_hint_p2 = _hint(658.0, gm.PLAYER_COLORS[1], "")
	_hint(678.0, Color(0.70, 0.78, 0.66),
		"PAD  L-stick walk · A jump · DOWN let time run · R-STICK aim · hold R2 fire · Y toggle SUPER · START confirm · B rollback · X reset        GHOST MOVES WHILE INPUT IS HELD")

	_tuning = _mk_label(Vector2(16.0, 700.0), 1248.0, 12, HORIZONTAL_ALIGNMENT_CENTER)
	_tuning.add_theme_color_override("font_color", Color(0.45, 0.50, 0.58))
	_help.append(_tuning)
	for item in _help:
		item.visible = help_visible

	# Hit banner — sits below the compact centre HUD without covering the arena's
	# most important ground-level action.
	_banner_bg = ColorRect.new()
	_banner_bg.position = Vector2(340.0, 194.0)
	_banner_bg.size = Vector2(600.0, 50.0)
	_banner_bg.color = Color(0.08, 0.09, 0.13, 0.94)
	_banner_bg.visible = false
	add_child(_banner_bg)

	_banner_rule = ColorRect.new()
	_banner_rule.position = Vector2(340.0, 240.0)
	_banner_rule.size = Vector2(600.0, 3.0)
	_banner_rule.visible = false
	add_child(_banner_rule)

	_banner = _mk_label(Vector2(340.0, 201.0), 600.0, 30, HORIZONTAL_ALIGNMENT_CENTER)
	_banner.size = Vector2(600.0, 40.0)
	_banner.visible = false

	_over_bg = ColorRect.new()
	_over_bg.position = Vector2.ZERO
	_over_bg.size = Vector2(1280.0, 720.0)
	_over_bg.color = Color(0.02, 0.02, 0.04, 0.72)
	_over_bg.visible = false
	add_child(_over_bg)

	_over_label = _mk_label(Vector2(240.0, 260.0), 800.0, 52, HORIZONTAL_ALIGNMENT_CENTER)
	_over_label.size = Vector2(800.0, 260.0)
	_over_label.visible = false


func _hint(y: float, col: Color, text: String) -> Label:
	var l := _mk_label(Vector2(16.0, y), 1248.0, 13, HORIZONTAL_ALIGNMENT_CENTER)
	l.text = text
	l.add_theme_color_override("font_color", col.darkened(0.15))
	_help.append(l)
	return l


## H hides the control reference once a tester has learned the bindings.
func toggle_help() -> bool:
	help_visible = not help_visible
	for n in _help:
		n.visible = help_visible
	return help_visible


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
	_turn_label.text = "TURN %d" % gm.turn
	var match_rule := "FIRST TO %d HITS" % gm.hits_to_win
	if gm.core_active:
		match_rule += "   ·   CORE: FULL SUPER (%d TURN%s LEFT)" % [
			gm.core_turns_left, "" if gm.core_turns_left == 1 else "S"]
	elif gm.core_announced:
		match_rule += "   ·   CORE MATERIALIZES NEXT TURN"
	else:
		var remaining: int = maxi(0, gm.core_hitless_turns_to_announce - gm.hitless_execution_streak)
		match_rule += "   ·   CORE IN %d HITLESS TURN%s" % [remaining, "" if remaining == 1 else "S"]
	_score_label.text = match_rule
	_level_label.text = "LEVEL %d/%d — %s   ·   %s" \
		% [gm.level_index + 1, Levels.count(), gm.level_name, gm.level_wrap]
	if gm.online_mode:
		_level_label.text += "   ·   ROOM %s" % gm.online_room
		_hint_p1.text = _HINT_ONLINE_YOU % 1 if gm.online_player == 0 else _HINT_ONLINE_RIVAL % 1
		_hint_p2.text = _HINT_ONLINE_YOU % 2 if gm.online_player == 1 else _HINT_ONLINE_RIVAL % 2
	else:
		_hint_p1.text = "P1   HOLD A/D walk · W jump · S let time run · MOUSE aim · hold LMB fire · T toggle SUPER · L-SHIFT confirm · R rollback · F reset path"
		_hint_p2.text = _HINT_AI if gm.vs_ai else _HINT_P2

	for i in 2:
		for h in _pips[i].size():
			_pips[i][h].color = gm.PLAYER_COLORS[i] if h < gm.score[i] else _PIP_EMPTY

	# hit banner, fading out over its last half second
	var bt: float = gm.banner_time
	_banner_bg.visible = bt > 0.0
	_banner.visible = bt > 0.0
	if bt > 0.0:
		var a: float = clampf(bt / 0.5, 0.0, 1.0)
		_banner.text = gm.banner_text
		_banner.add_theme_color_override("font_color",
			Color(gm.banner_color.r, gm.banner_color.g, gm.banner_color.b, a))
		_banner_bg.color = Color(0.08, 0.09, 0.13, 0.94 * a)
		var edge := Color(gm.banner_color.r, gm.banner_color.g, gm.banner_color.b, 0.85 * a)
		_banner_rule.color = edge
		_banner_rule.visible = true
	else:
		_banner_rule.visible = false

	match gm.state:
		Phase.PLANNING:
			_timer_label.text = "%.1f" % maxf(gm.planning_time_left, 0.0)
			var frac: float = gm.planning_time_left / maxf(gm.planning_duration, 0.001)
			_timer_label.add_theme_color_override("font_color",
				Color(1.0, 0.35, 0.3) if frac < 0.25 else Color(0.92, 0.95, 1.0))
			_phase_label.text = "TIME SUSPENDED — PLAN"
			_phase_label.add_theme_color_override("font_color", Color(0.86, 0.66, 1.0))
		Phase.COMMITTING:
			_timer_label.text = "%.2f" % maxf(gm.commit_time_left, 0.0)
			_timer_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
			_phase_label.text = "FATE LOCKED"
			_phase_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		Phase.EXECUTING:
			_timer_label.text = "%.2f" % gm.exec_time_left()
			_timer_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.55))
			_phase_label.text = "TIME FLOWS — EXECUTING"
			_phase_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.55))
		Phase.GAME_OVER:
			_timer_label.text = ""
			_phase_label.text = "GAME OVER"
			_phase_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		Phase.ONLINE_WAIT:
			_timer_label.text = "—"
			_timer_label.add_theme_color_override("font_color", Color(0.72, 0.62, 0.92))
			_phase_label.text = "WAITING FOR OPPONENT"
			_phase_label.add_theme_color_override("font_color", Color(0.72, 0.62, 0.92))

	var pads := ""
	for i in 2:
		if gm._pads[i] >= 0:
			pads += "  P%d=pad%d" % [i + 1, gm._pads[i]]
	_tuning.text = "PLANNING %.0fs  [F1 5 | F2 8 | F3 10]   EXECUTION %.2fs  [F5 .40 | F6 .75 | F7 1.2]   F9 restart   F10 next level   M sound %s   H hide debug/help   ESC menu%s" \
		% [gm.planning_duration, gm.execution_duration, "OFF" if gm._sfx.muted else "on", pads]

	var over: bool = gm.state == Phase.GAME_OVER
	_over_bg.visible = over
	_over_label.visible = over
	if over:
		var controls := "ENTER request rematch     ESC leave room" if gm.online_mode \
			else "ENTER rematch     F10 next level"
		var tail := "\n%d — %d\n\n%s" % [gm.score[0], gm.score[1], controls]
		if gm.winner >= 0:
			_over_label.text = "PLAYER %d TAKES THE MATCH" % (gm.winner + 1) + tail
			_over_label.add_theme_color_override("font_color", gm.PLAYER_COLORS[gm.winner].lightened(0.2))
		else:
			_over_label.text = "DRAW" + tail
			_over_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
