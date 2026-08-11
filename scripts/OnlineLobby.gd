extends CanvasLayer
class_name OnlineLobby

signal create_requested(level: int)
signal join_requested(code: String)
signal cancel_requested

const GOLD := Color(0.96, 0.76, 0.28)
const VIOLET := Color(0.76, 0.42, 1.0)
const TEXT := Color(0.82, 0.86, 0.94)

var level: int = 0
var _code_input: LineEdit
var _room_label: Label
var _status: Label
var _create: Button
var _join: Button
var _copy: Button


func _ready() -> void:
	layer = 20
	var veil := ColorRect.new()
	veil.size = Vector2(1280.0, 720.0)
	veil.color = Color(0.02, 0.01, 0.04, 0.94)
	add_child(veil)

	var panel := ColorRect.new()
	panel.position = Vector2(260.0, 105.0)
	panel.size = Vector2(760.0, 510.0)
	panel.color = Color(0.055, 0.035, 0.09, 0.98)
	add_child(panel)

	var heading := _label(Vector2(300.0, 138.0), 680.0, 44, GOLD)
	heading.text = "ONLINE DUEL"
	var copy := _label(Vector2(330.0, 202.0), 620.0, 18, TEXT)
	copy.text = "Each player uses their own screen and controls.\nPlans stay private until both players lock fate."

	_create = _button(Vector2(410.0, 286.0), Vector2(460.0, 52.0), "CREATE PRIVATE ROOM")
	_create.pressed.connect(func(): create_requested.emit(level))

	var or_label := _label(Vector2(300.0, 354.0), 680.0, 16, Color(0.48, 0.52, 0.62))
	or_label.text = "— OR JOIN WITH A 6-CHARACTER CODE —"

	_code_input = LineEdit.new()
	_code_input.position = Vector2(410.0, 394.0)
	_code_input.size = Vector2(270.0, 52.0)
	_code_input.max_length = 6
	_code_input.placeholder_text = "ROOM CODE"
	_code_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_input.add_theme_font_size_override("font_size", 25)
	_code_input.text_submitted.connect(func(_text): _request_join())
	add_child(_code_input)

	_join = _button(Vector2(695.0, 394.0), Vector2(175.0, 52.0), "JOIN")
	_join.pressed.connect(_request_join)

	_room_label = _label(Vector2(300.0, 278.0), 680.0, 40, VIOLET)
	_room_label.visible = false
	_copy = _button(Vector2(520.0, 350.0), Vector2(240.0, 44.0), "COPY CODE")
	_copy.visible = false
	_copy.pressed.connect(func():
		DisplayServer.clipboard_set(_room_label.text)
		set_status("CODE COPIED — SEND IT TO PLAYER 2", false))

	_status = _label(Vector2(330.0, 470.0), 620.0, 18, Color(0.62, 0.68, 0.78))
	_status.text = ""

	var back := _button(Vector2(500.0, 542.0), Vector2(280.0, 44.0), "‹ BACK TO MENU")
	back.pressed.connect(func(): cancel_requested.emit())
	visible = false


func open(selected_level: int) -> void:
	level = selected_level
	visible = true
	_code_input.text = ""
	_code_input.editable = true
	_create.visible = true
	_join.visible = true
	_code_input.visible = true
	_room_label.visible = false
	_copy.visible = false
	set_status("LEVEL: %s" % Levels.build(level)["name"], false)


func close() -> void:
	visible = false


func show_room(code: String, player: int) -> void:
	_create.visible = false
	_join.visible = false
	_code_input.visible = false
	_room_label.visible = true
	_copy.visible = player == 0
	_room_label.text = code
	set_status("YOU ARE PLAYER %d — %s" % [player + 1,
		"SEND THIS CODE TO PLAYER 2" if player == 0 else "CONNECTING TO HOST"], false)


func set_status(text: String, is_error: bool) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", Color(1.0, 0.38, 0.34) if is_error \
		else Color(0.62, 0.78, 0.70))


func handle_key(code: int) -> bool:
	if code == KEY_ESCAPE:
		cancel_requested.emit()
		return true
	if code in [KEY_ENTER, KEY_KP_ENTER] and _code_input.visible:
		_request_join()
		return true
	return false


func _request_join() -> void:
	join_requested.emit(_code_input.text.strip_edges().to_upper())


func _label(pos: Vector2, width: float, size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = pos
	label.size = Vector2(width, 100.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 3)
	label.add_theme_constant_override("shadow_offset_y", 4)
	add_child(label)
	return label


func _button(pos: Vector2, size: Vector2, text: String) -> Button:
	var button := Button.new()
	button.position = pos
	button.size = size
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 19)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	add_child(button)
	return button
