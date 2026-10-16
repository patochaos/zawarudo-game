extends CanvasLayer
class_name OnlineLobby

signal create_requested(level: int, weapon: int, capacity: int)
signal join_requested(code: String, weapon: int)
signal cancel_requested
signal ui_navigated
signal ui_accepted

const GOLD := Color(0.96, 0.76, 0.28)
const VIOLET := Color(0.76, 0.42, 1.0)
const TEXT := Color(0.84, 0.87, 0.94)
const DIM := Color(0.56, 0.61, 0.71)
const ROOM_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
## Nicknames share the chrome's all-caps voice and stay short enough for four of
## them on the occupancy line. MUST match sanitizePlayerName() on the room service.
const NAME_ALPHABET := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-"
const MAX_NAME_LENGTH := 12
const FIGHTER_ROSTER := Roster.ORDER
## Room codes and names are read off one screen and typed on another, so they use
## the hyperlegible face: the display face draws 0/O, 8/B and 2/Z too alike.
const CODE_FONT := preload("res://assets/fonts/AtkinsonHyperlegible-Regular.ttf")
const CODE_SPACING := 10
const BROWSER_COPY_STATE := "__zawarudoCopy"
## Async Clipboard API first, then the older execCommand path, which some
## embedding iframes still allow. Either way the outcome lands in a window flag
## that _process reads back.
const BROWSER_COPY_SCRIPT := """(function (flag, text) {
	window[flag] = "pending";
	function fallback() {
		try {
			var area = document.createElement("textarea");
			area.value = text;
			area.setAttribute("readonly", "");
			area.style.position = "fixed";
			area.style.opacity = "0";
			document.body.appendChild(area);
			area.select();
			var copied = document.execCommand("copy");
			document.body.removeChild(area);
			window[flag] = copied ? "ok" : "fail";
		} catch (error) {
			window[flag] = "fail";
		}
	}
	if (navigator.clipboard && window.isSecureContext) {
		navigator.clipboard.writeText(text).then(function () { window[flag] = "ok"; }, fallback);
	} else {
		fallback();
	}
})("%s", %s);"""


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
			draw_line(Vector2(390.0, 349.0), Vector2(570.0, 349.0),
				Color(GOLD.r, GOLD.g, GOLD.b, 0.28), 1.0)
			draw_line(Vector2(710.0, 349.0), Vector2(890.0, 349.0),
				Color(GOLD.r, GOLD.g, GOLD.b, 0.28), 1.0)

var level: int = 0
var weapon: int = 0
var capacity: int = 4
## The sanitized nickname this machine will register with the room. Empty means
## the other players see the plain seat number.
var nickname: String = ""
var _capacity_button: Button
var _occupancy: Label
var _name_caption: Label
var _name_input: LineEdit
var _code_input: LineEdit
var _room_label: Label
var _room_caption: Label
var _join_divider: Label
var _status: Label
var _status_rule: ColorRect
var _create: Button
var _join: Button
var _copy: Button
var _chrome: LobbyChrome
## Seconds left to hear back from the browser about a clipboard write. Zero means
## no copy is pending.
var _copy_wait: float = 0.0


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
	heading.text = "ONLINE BATTLE"
	# The name row sits where the intro copy used to be: it is the one thing a
	# player types before choosing a fighter, and the eyebrow already carries the
	# premise.
	_name_caption = _label(Vector2(425.0, 190.0), 110.0, 12, VIOLET)
	_name_caption.text = "YOUR NAME //"
	_name_input = _text_input(Vector2(545.0, 180.0), Vector2(310.0, 34.0), 17,
		MAX_NAME_LENGTH, "OPTIONAL")
	_name_input.tooltip_text = "Letters, digits, spaces, _ and - only. Saved on this device."
	_name_input.text_changed.connect(_sanitize_name_input)
	_name_input.text_submitted.connect(func(_text): _code_input.grab_focus())

	_create = _button(Vector2(360.0, 258.0), Vector2(360.0, 54.0),
		"01   CREATE PRIVATE ROOM", true)
	_create.pressed.connect(func(): create_requested.emit(level, weapon, capacity))
	_capacity_button = _button(Vector2(734.0, 258.0), Vector2(186.0, 54.0), "4 PLAYERS  ›")
	_capacity_button.tooltip_text = "Choose a 2-player duel or 4-player free-for-all. The match starts when the room is full."
	_capacity_button.pressed.connect(func():
		capacity = 2 if capacity == 4 else 4
		_refresh_choices())

	_join_divider = _label(Vector2(300.0, 328.0), 680.0, 13, DIM)
	_join_divider.text = "OR JOIN AN EXISTING ROOM"

	_code_input = _text_input(Vector2(360.0, 360.0), Vector2(356.0, 54.0), 28, 6,
		"6-CHARACTER CODE")
	_code_input.add_theme_font_override("font", _spaced_code_font())
	_code_input.tooltip_text = "Codes never use 0, O, 1 or I."
	_code_input.text_changed.connect(_sanitize_code)
	_code_input.text_submitted.connect(func(_text): _request_join())

	_join = _button(Vector2(734.0, 360.0), Vector2(186.0, 54.0), "02   JOIN", true)
	_join.pressed.connect(_request_join)

	_room_caption = _label(Vector2(330.0, 235.0), 620.0, 13, DIM)
	_room_caption.text = "ROOM CODE // SHARE WITH YOUR PLAYERS"
	_room_caption.visible = false
	_room_label = _label(Vector2(390.0, 276.0), 500.0, 50, VIOLET)
	_room_label.add_theme_font_override("font", _spaced_code_font())
	_room_label.visible = false
	_copy = _button(Vector2(500.0, 386.0), Vector2(280.0, 46.0), "COPY ROOM CODE", true)
	_copy.visible = false
	_copy.pressed.connect(copy_room_code)
	# Wider than the other copy lines: four full-length nicknames have to fit.
	_occupancy = _label(Vector2(260.0, 452.0), 760.0, 15, TEXT)
	_occupancy.visible = false

	_status_rule = ColorRect.new()
	_status_rule.position = Vector2(430.0, 562.0)
	_status_rule.size = Vector2(420.0, 2.0)
	_status_rule.color = Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.40)
	add_child(_status_rule)
	_status = _label(Vector2(330.0, 568.0), 620.0, 15, Color(0.62, 0.78, 0.70))
	_status.text = ""

	var back := _button(Vector2(500.0, 598.0), Vector2(280.0, 36.0), "‹  BACK TO MENU")
	back.pressed.connect(func(): cancel_requested.emit())
	visible = false


## `saved_name` is the nickname remembered from the last room, so a returning
## player only has to type it once.
func open(selected_level: int, selected_weapon: int = 0, saved_name: String = "") -> void:
	level = selected_level
	weapon = selected_weapon if selected_weapon in FIGHTER_ROSTER else 0
	visible = true
	_chrome.set_room_active(false)
	nickname = sanitize_name(saved_name)
	_name_input.text = nickname
	_code_input.text = ""
	_code_input.editable = true
	_copy_wait = 0.0
	_create.visible = true
	_join_divider.visible = true
	_join.visible = true
	_code_input.visible = true
	_room_caption.visible = false
	_room_label.visible = false
	_copy.visible = false
	_occupancy.visible = false
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
	_copy.visible = true
	_set_choices_visible(false)
	_room_label.text = code
	_chrome.set_room_active(true)
	_occupancy.visible = true
	_occupancy.text = "CONNECTING TO ROOM"
	var who := "PLAYER %d" % (player + 1) if nickname.is_empty() \
		else "%s (P%d)" % [nickname, player + 1]
	set_status("YOU ARE %s // %s" % [who,
		"SHARE THIS CODE WITH YOUR PLAYERS" if player == 0 else "CONNECTING TO ROOM"], false)


## `names` holds one nickname per seat as the room reports them; a missing or
## empty entry falls back to the seat number.
func update_room(connected: Array, room_capacity: int, selected_level: int,
		names: Array = []) -> void:
	capacity = room_capacity
	level = selected_level
	_refresh_choices()
	# Anyone in the room can share the code when a seat opens up again.
	_copy.visible = _room_label.visible
	var slots := PackedStringArray()
	var count := 0
	for i in capacity:
		var present := i < connected.size() and bool(connected[i])
		if present:
			count += 1
		slots.append("%s %s" % [seat_tag(i, names), "JOINED" if present else "WAITING"])
	var seats := "  ·  ".join(slots)
	# Long nicknames step the font down rather than spilling past the frame.
	_occupancy.add_theme_font_size_override("font_size", 15 if seats.length() <= 64 else 12)
	_occupancy.text = "%d/%d CONNECTED\n%s" % [count, capacity, seats]


## The label a seat gets everywhere online: its nickname, or P1..P4 without one.
static func seat_tag(slot: int, names: Array) -> String:
	if slot >= 0 and slot < names.size():
		var tag := str(names[slot]).strip_edges()
		if not tag.is_empty():
			return tag
	return "P%d" % (slot + 1)


## Upper-case, allowed characters only, single spaces, at most MAX_NAME_LENGTH.
## The room service applies the same rule, so what a player sees locally is
## what every other client receives.
static func sanitize_name(value: String) -> String:
	var clean := ""
	for character in value.to_upper():
		if character in NAME_ALPHABET:
			clean += character
	while "  " in clean:
		clean = clean.replace("  ", " ")
	return clean.strip_edges().left(MAX_NAME_LENGTH).strip_edges()


func set_status(text: String, is_error: bool) -> void:
	_status.text = text
	var color := Color(1.0, 0.38, 0.34) if is_error else Color(0.62, 0.82, 0.72)
	_status.add_theme_color_override("font_color", color)
	_status_rule.color = Color(color.r, color.g, color.b, 0.55)


func handle_key(code: int) -> bool:
	if code == KEY_ESCAPE:
		cancel_requested.emit()
		return true
	# A name is edited mid-word far more often than a six-character code, so its
	# field keeps the arrows for the caret; Enter hands focus to the code field.
	if _name_input.visible and _name_input.has_focus():
		return false
	if code in [KEY_ENTER, KEY_KP_ENTER] and _code_input.visible:
		_request_join()
		return true
	return false


func _refresh_choices() -> void:
	_capacity_button.text = "%d PLAYERS  ›" % capacity


## Fighters and the arena are chosen once everyone is in the room, so before it
## exists the only settings are the name and the room size.
func _set_choices_visible(can_edit: bool) -> void:
	_capacity_button.visible = can_edit
	_name_caption.visible = can_edit
	_name_input.visible = can_edit


## Copies the code and reports what really happened. A browser can refuse the
## write (an embedding page without clipboard permission, or no user gesture),
## and claiming success then leaves whatever was copied before on the clipboard.
func copy_room_code() -> void:
	var code := _room_label.text
	if code.is_empty():
		return
	if OS.has_feature("web"):
		JavaScriptBridge.eval(BROWSER_COPY_SCRIPT % [BROWSER_COPY_STATE, JSON.stringify(code)], true)
		_copy_wait = 2.0
		set_status("COPYING…", false)
		return
	DisplayServer.clipboard_set(code)
	_report_copy(DisplayServer.clipboard_get().strip_edges() == code)


func _process(delta: float) -> void:
	if _copy_wait <= 0.0:
		return
	var result = JavaScriptBridge.eval("window.%s || ''" % BROWSER_COPY_STATE, true)
	if result == "ok" or result == "fail":
		_copy_wait = 0.0
		_report_copy(result == "ok")
		return
	_copy_wait -= delta
	if _copy_wait <= 0.0:
		_report_copy(false)


func _report_copy(copied: bool) -> void:
	if copied:
		set_status("CODE %s COPIED // SHARE WITH YOUR PLAYERS" % _room_label.text, false)
	else:
		set_status("COPY BLOCKED // TELL YOUR PLAYERS THE CODE %s" % _room_label.text, true)


## The code face with extra room between letters, so six characters read as six.
static func _spaced_code_font() -> FontVariation:
	var spaced := FontVariation.new()
	spaced.base_font = CODE_FONT
	spaced.spacing_glyph = CODE_SPACING
	return spaced


func _sanitize_code(value: String) -> void:
	var clean := ""
	var dropped_lookalike := false
	for character in value.to_upper():
		if character in ROOM_ALPHABET:
			clean += character
		elif character in "0O1I":
			dropped_lookalike = true
	if dropped_lookalike:
		set_status("CODES NEVER USE 0, O, 1 OR I // CHECK THAT LETTER", true)
	if clean == value:
		return
	_code_input.set_block_signals(true)
	_code_input.text = clean.left(6)
	_code_input.caret_column = _code_input.text.length()
	_code_input.set_block_signals(false)


## Filters as the player types but keeps inner spaces, so "PATO CHAOS" can be
## written in order; `nickname` holds the trimmed value the room will receive.
func _sanitize_name_input(value: String) -> void:
	var clean := ""
	for character in value.to_upper():
		if character in NAME_ALPHABET:
			clean += character
	clean = clean.left(MAX_NAME_LENGTH)
	nickname = sanitize_name(clean)
	if clean == value:
		return
	_name_input.set_block_signals(true)
	_name_input.text = clean
	_name_input.caret_column = clean.length()
	_name_input.set_block_signals(false)


func _request_join() -> void:
	var code := _code_input.text.strip_edges().to_upper()
	if code.length() != 6:
		set_status("ENTER ALL 6 CHARACTERS TO JOIN", true)
		_code_input.grab_focus()
		return
	join_requested.emit(code, weapon)


func _text_input(pos: Vector2, box: Vector2, font_size: int, max_length: int,
		placeholder: String) -> LineEdit:
	var input := LineEdit.new()
	input.position = pos
	input.size = box
	input.max_length = max_length
	input.placeholder_text = placeholder
	input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	input.add_theme_font_override("font", CODE_FONT)
	input.add_theme_font_size_override("font_size", font_size)
	input.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0))
	input.add_theme_color_override("font_placeholder_color", Color(0.45, 0.49, 0.58))
	input.add_theme_color_override("caret_color", GOLD)
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color(0.035, 0.022, 0.064, 0.98)
	input_style.border_color = Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.52)
	input_style.set_border_width_all(2)
	input_style.set_corner_radius_all(3)
	input_style.content_margin_left = 14.0
	input_style.content_margin_right = 14.0
	input.add_theme_stylebox_override("normal", input_style)
	var focus_style := input_style.duplicate()
	focus_style.border_color = GOLD
	input.add_theme_stylebox_override("focus", focus_style)
	input.focus_entered.connect(func(): ui_navigated.emit())
	add_child(input)
	return input


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
