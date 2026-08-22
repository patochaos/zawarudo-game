extends CanvasLayer
class_name OnlineLobby

signal create_requested(level: int, weapon: int)
signal join_requested(code: String, weapon: int)
signal cancel_requested
signal ui_navigated
signal ui_accepted

const GOLD := Color(0.96, 0.76, 0.28)
const VIOLET := Color(0.76, 0.42, 1.0)
const TEXT := Color(0.84, 0.87, 0.94)
const DIM := Color(0.56, 0.61, 0.71)
const ROOM_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const FIGHTER_ROSTER := [0, 2, 4, 3]


class LobbyChrome:
	extends Control

	var room_active: bool = false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()

	func set_room_active(active: bool) -> void:
		room_active = active
		queue_redraw()

	func _draw() -> void:
		# The angled frame shares the title menu's visual grammar while the centre
		# remains calm enough for typing and sharing a room code.
		draw_colored_polygon(PackedVector2Array([
			Vector2(210.0, 74.0), Vector2(1070.0, 74.0), Vector2(1032.0, 636.0),
			Vector2(246.0, 636.0),
		]), Color(0.025, 0.012, 0.050, 0.98))
		draw_polyline(PackedVector2Array([
			Vector2(210.0, 74.0), Vector2(1070.0, 74.0), Vector2(1032.0, 636.0),
			Vector2(246.0, 636.0), Vector2(210.0, 74.0),
		]), Color(GOLD.r, GOLD.g, GOLD.b, 0.55), 1.5, true)
		draw_line(Vector2(326.0, 220.0), Vector2(954.0, 220.0),
			Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.46), 2.0)
		if room_active:
			draw_rect(Rect2(390.0, 266.0, 500.0, 88.0), Color(0.06, 0.025, 0.10, 0.90))
			draw_rect(Rect2(390.0, 266.0, 500.0, 88.0),
				Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.62), false, 2.0)
		else:
			draw_line(Vector2(390.0, 350.0), Vector2(570.0, 350.0),
				Color(GOLD.r, GOLD.g, GOLD.b, 0.28), 1.0)
			draw_line(Vector2(710.0, 350.0), Vector2(890.0, 350.0),
				Color(GOLD.r, GOLD.g, GOLD.b, 0.28), 1.0)
		for i in 3:
			var x := 500.0 + float(i) * 140.0
			var active := (i == 1) if room_active else (i == 0)
			draw_circle(Vector2(x, 601.0), 4.0, GOLD if active else Color(0.24, 0.22, 0.30))
			if i < 2:
				draw_line(Vector2(x + 8.0, 601.0), Vector2(x + 132.0, 601.0),
					Color(GOLD.r, GOLD.g, GOLD.b, 0.18), 1.0)


var level: int = 0
var weapon: int = 0
var _code_input: LineEdit
var _room_label: Label
var _room_caption: Label
var _join_divider: Label
var _status: Label
var _status_rule: ColorRect
var _level_label: Label
var _fighter_label: Label
var _fighter_left: Button
var _fighter_right: Button
var _level_left: Button
var _level_right: Button
var _create: Button
var _join: Button
var _copy: Button
var _chrome: LobbyChrome


func _ready() -> void:
	layer = 20
	var veil := ColorRect.new()
	veil.size = Vector2(1280.0, 720.0)
	veil.color = Color(0.010, 0.006, 0.025, 0.93)
	add_child(veil)

	_chrome = LobbyChrome.new()
	_chrome.size = Vector2(1280.0, 720.0)
	add_child(_chrome)

	var eyebrow := _label(Vector2(300.0, 105.0), 680.0, 12, VIOLET)
	eyebrow.text = "LOCKSTEP // HIDDEN PLANS // PRIVATE ROOM"
	var heading := _label(Vector2(300.0, 132.0), 680.0, 42, GOLD)
	heading.text = "ONLINE DUEL"
	var intro := _label(Vector2(330.0, 184.0), 620.0, 15, TEXT)
	intro.text = "Each duelist uses their own screen. Plans are revealed only after both players lock fate."

	_create = _button(Vector2(360.0, 250.0), Vector2(560.0, 58.0),
		"01   CREATE PRIVATE ROOM", true)
	_create.pressed.connect(func(): create_requested.emit(level, weapon))

	_join_divider = _label(Vector2(300.0, 329.0), 680.0, 13, DIM)
	_join_divider.text = "OR JOIN AN EXISTING DUEL"

	_code_input = LineEdit.new()
	_code_input.position = Vector2(360.0, 376.0)
	_code_input.size = Vector2(356.0, 56.0)
	_code_input.max_length = 6
	_code_input.placeholder_text = "6-CHARACTER CODE"
	_code_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_input.add_theme_font_size_override("font_size", 23)
	_code_input.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0))
	_code_input.add_theme_color_override("font_placeholder_color", Color(0.45, 0.49, 0.58))
	_code_input.add_theme_color_override("caret_color", GOLD)
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color(0.035, 0.022, 0.064, 0.98)
	input_style.border_color = Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.52)
	input_style.set_border_width_all(2)
	input_style.set_corner_radius_all(3)
	input_style.content_margin_left = 14.0
	input_style.content_margin_right = 14.0
	_code_input.add_theme_stylebox_override("normal", input_style)
	var focus_style := input_style.duplicate()
	focus_style.border_color = GOLD
	_code_input.add_theme_stylebox_override("focus", focus_style)
	_code_input.text_changed.connect(_sanitize_code)
	_code_input.text_submitted.connect(func(_text): _request_join())
	_code_input.focus_entered.connect(func(): ui_navigated.emit())
	add_child(_code_input)

	_join = _button(Vector2(734.0, 376.0), Vector2(186.0, 56.0), "02   JOIN", true)
	_join.pressed.connect(_request_join)

	_room_caption = _label(Vector2(330.0, 235.0), 620.0, 13, DIM)
	_room_caption.text = "ROOM CODE // SHARE WITH YOUR OPPONENT"
	_room_caption.visible = false
	_room_label = _label(Vector2(390.0, 276.0), 500.0, 42, VIOLET)
	_room_label.visible = false
	_copy = _button(Vector2(500.0, 377.0), Vector2(280.0, 48.0), "COPY ROOM CODE", true)
	_copy.visible = false
	_copy.pressed.connect(func():
		DisplayServer.clipboard_set(_room_label.text)
		set_status("CODE COPIED — SEND IT TO PLAYER 2", false))

	_fighter_left = _button(Vector2(348.0, 446.0), Vector2(52.0, 32.0), "‹")
	_fighter_left.pressed.connect(func(): _cycle_fighter(-1))
	_fighter_label = _label(Vector2(410.0, 440.0), 460.0, 13, VIOLET)
	_fighter_right = _button(Vector2(880.0, 446.0), Vector2(52.0, 32.0), "›")
	_fighter_right.pressed.connect(func(): _cycle_fighter(1))
	_level_left = _button(Vector2(348.0, 481.0), Vector2(52.0, 32.0), "‹")
	_level_left.pressed.connect(func(): _cycle_level(-1))
	_level_label = _label(Vector2(410.0, 475.0), 460.0, 13, GOLD)
	_level_right = _button(Vector2(880.0, 481.0), Vector2(52.0, 32.0), "›")
	_level_right.pressed.connect(func(): _cycle_level(1))
	_status_rule = ColorRect.new()
	_status_rule.position = Vector2(430.0, 523.0)
	_status_rule.size = Vector2(420.0, 2.0)
	_status_rule.color = Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.40)
	add_child(_status_rule)
	_status = _label(Vector2(330.0, 532.0), 620.0, 15, Color(0.62, 0.78, 0.70))
	_status.text = ""

	var back := _button(Vector2(500.0, 582.0), Vector2(280.0, 40.0), "‹  BACK TO MENU")
	back.pressed.connect(func(): cancel_requested.emit())
	visible = false


func open(selected_level: int, selected_weapon: int = 0) -> void:
	level = selected_level
	weapon = selected_weapon if selected_weapon in FIGHTER_ROSTER else 0
	visible = true
	_chrome.set_room_active(false)
	_code_input.text = ""
	_code_input.editable = true
	_create.visible = true
	_join_divider.visible = true
	_join.visible = true
	_code_input.visible = true
	_room_caption.visible = false
	_room_label.visible = false
	_copy.visible = false
	_set_choices_visible(true)
	_refresh_choices()
	set_status("READY TO CREATE OR JOIN", false)
	_code_input.call_deferred("grab_focus")


func close() -> void:
	visible = false


func show_room(code: String, player: int) -> void:
	_create.visible = false
	_join_divider.visible = false
	_join.visible = false
	_code_input.visible = false
	_room_caption.visible = true
	_room_label.visible = true
	_copy.visible = player == 0
	_set_choices_visible(false)
	_room_label.text = code
	_chrome.set_room_active(true)
	set_status("YOU ARE PLAYER %d — %s" % [player + 1,
		"SEND THIS CODE TO PLAYER 2" if player == 0 else "CONNECTING TO HOST"], false)


func set_status(text: String, is_error: bool) -> void:
	_status.text = text
	var color := Color(1.0, 0.38, 0.34) if is_error else Color(0.62, 0.82, 0.72)
	_status.add_theme_color_override("font_color", color)
	_status_rule.color = Color(color.r, color.g, color.b, 0.55)


func handle_key(code: int) -> bool:
	if code == KEY_ESCAPE:
		cancel_requested.emit()
		return true
	if code in [KEY_ENTER, KEY_KP_ENTER] and _code_input.visible:
		_request_join()
		return true
	return false


func _cycle_fighter(direction: int) -> void:
	var index := FIGHTER_ROSTER.find(weapon)
	weapon = FIGHTER_ROSTER[posmod(index + direction, FIGHTER_ROSTER.size())]
	_refresh_choices()


func _cycle_level(direction: int) -> void:
	level = posmod(level + direction, Levels.count())
	_refresh_choices()


func _refresh_choices() -> void:
	_fighter_label.text = "YOUR FIGHTER // %s" % _fighter_name(weapon)
	_level_label.text = "HOST ARENA // %02d OF %02d  —  %s" % [
		level + 1, Levels.count(), Levels.build(level)["name"]]


func _set_choices_visible(can_edit: bool) -> void:
	_fighter_left.visible = can_edit
	_fighter_right.visible = can_edit
	_level_left.visible = can_edit
	_level_right.visible = can_edit
	_fighter_label.visible = true
	_level_label.visible = true


func _fighter_name(value: int) -> String:
	match value:
		2: return "THE ROOK"
		3: return "THE ECLIPSE"
		4: return "THE PULSE"
		_: return "THE DUELIST"


func _sanitize_code(value: String) -> void:
	var clean := ""
	for character in value.to_upper():
		if character in ROOM_ALPHABET:
			clean += character
	if clean == value:
		return
	_code_input.set_block_signals(true)
	_code_input.text = clean.left(6)
	_code_input.caret_column = _code_input.text.length()
	_code_input.set_block_signals(false)


func _request_join() -> void:
	var code := _code_input.text.strip_edges().to_upper()
	if code.length() != 6:
		set_status("ENTER ALL 6 CHARACTERS TO JOIN", true)
		_code_input.grab_focus()
		return
	join_requested.emit(code, weapon)


func _label(pos: Vector2, width: float, size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = pos
	label.size = Vector2(width, 100.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.92))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 3)
	add_child(label)
	return label


func _button(pos: Vector2, dimensions: Vector2, text: String, primary: bool = false) -> Button:
	var button := Button.new()
	button.position = pos
	button.size = dimensions
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.72))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.15, 0.055, 0.23, 0.96) if primary else Color(0.045, 0.030, 0.075, 0.96)
	normal.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.68 if primary else 0.30)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(3)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.34, 0.11, 0.50, 0.98)
	hover.border_color = GOLD
	hover.set_border_width_all(2)
	button.add_theme_stylebox_override("hover", hover)
	var pressed := hover.duplicate()
	pressed.bg_color = Color(0.22, 0.07, 0.32, 1.0)
	button.add_theme_stylebox_override("pressed", pressed)
	button.mouse_entered.connect(func(): ui_navigated.emit())
	button.pressed.connect(func(): ui_accepted.emit())
	add_child(button)
	return button
