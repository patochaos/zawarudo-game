extends CanvasLayer

## Offline rules editor. Values live on the tuning model; controls are only
## editors, so switching groups never loses a change or its reset value.
signal closed

const BODY_FONT := preload("res://assets/fonts/AtkinsonHyperlegible-Regular.ttf")
const TITLE_FONT := preload("res://assets/kenney/fonts/kenney-future.ttf")
const INK := Color("120b20")
const PANEL := Color("241631")
const GOLD := Color("e8a838")
const TEXT := Color("ebe9f2")
const MUTED := Color("aaa4bb")
const EDGE := Color("493453")
const PRESET_GROUP := "Presets"

var _model
var _root: Control
var _groups: Array[String] = []
var _group: String = ""
var _category_buttons: Dictionary = {}
var _controls: Dictionary = {}
var _preset_buttons: Dictionary = {}
var _preset_cards: Dictionary = {}
var _scroll: ScrollContainer
var _rows: VBoxContainer
var _group_title: Label
var _group_note: Label
var _status: Label
var _reset_category: Button
var _reset_all: Button
var _back: Button
var _refreshing: bool = false


func build(manager) -> void:
	_model = manager.offline_tuning
	layer = 24
	visible = false
	_root = Control.new()
	_root.size = Vector2(1280, 720)
	_root.theme = _make_theme()
	add_child(_root)
	var background := ColorRect.new()
	background.color = INK
	background.size = _root.size
	_root.add_child(background)
	var field := ColorRect.new()
	field.color = PANEL
	field.position = Vector2(34, 26)
	field.size = Vector2(1212, 670)
	field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(field)
	var title := _label(_root, "GAME TUNING", 32, GOLD)
	title.position = Vector2(56, 42)
	title.add_theme_font_override("font", TITLE_FONT)
	var scope := _label(_root, "Offline only", 20, GOLD)
	scope.position = Vector2(1060, 44)
	var intro := _label(_root,
		"Changes save automatically. Online matches always use standard rules.", 18, TEXT)
	intro.position = Vector2(58, 91)
	_rule(Vector2(56, 127), Vector2(1168, 2), GOLD)
	_rule(Vector2(280, 150), Vector2(1, 468), EDGE)

	var category_scroll := ScrollContainer.new()
	category_scroll.position = Vector2(50, 146)
	category_scroll.size = Vector2(218, 410)
	category_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	category_scroll.follow_focus = true
	_root.add_child(category_scroll)
	var categories := VBoxContainer.new()
	categories.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	categories.add_theme_constant_override("separation", 4)
	category_scroll.add_child(categories)
	_groups.append(PRESET_GROUP)
	for definition: Dictionary in _model.definitions:
		var group: String = definition["group"]
		if _groups.has(group):
			continue
		_groups.append(group)
	for group: String in _groups:
		var button := _button(group, Vector2(202, 40))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.pressed.connect(_show_group.bind(group))
		categories.add_child(button)
		_category_buttons[group] = button
	var scope_note := _label(_root, "Applies to offline matches.\nLessons use standard rules.", 15, MUTED)
	scope_note.position = Vector2(64, 570)

	_group_title = _label(_root, "", 24, TEXT)
	_group_title.position = Vector2(304, 145)
	_group_note = _label(_root, "", 16, MUTED)
	_group_note.position = Vector2(304, 175)
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(304, 206)
	_scroll.size = Vector2(910, 409)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_root.add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 8)
	_scroll.add_child(_rows)

	_rule(Vector2(56, 632), Vector2(1168, 1), EDGE)
	_status = _label(_root, "", 17, MUTED)
	_status.position = Vector2(58, 650)
	_status.size = Vector2(440, 24)
	_reset_category = _button("Reset category", Vector2(172, 42))
	_reset_category.position = Vector2(690, 642)
	_reset_category.pressed.connect(func(): _model.reset_group(_group))
	_root.add_child(_reset_category)
	_reset_all = _button("Reset all", Vector2(140, 42))
	_reset_all.position = Vector2(874, 642)
	_reset_all.pressed.connect(func(): _model.reset_all())
	_root.add_child(_reset_all)
	_back = _button("Back", Vector2(196, 42))
	_back.position = Vector2(1026, 642)
	_back.add_theme_stylebox_override("normal", _box(Color("493023"), GOLD))
	_back.pressed.connect(close)
	_root.add_child(_back)
	var hint := _label(_root, "Arrows / D-pad: navigate or adjust     Tab: next control     Esc / B: back", 14, MUTED)
	hint.position = Vector2(58, 696)
	_model.changed.connect(_refresh)
	if not _groups.is_empty():
		_show_group(_groups[0])


func open() -> void:
	visible = true
	_refresh()
	if _category_buttons.has(_group):
		_category_buttons[_group].grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and _root.is_ancestor_of(focused):
		focused.release_focus()
	closed.emit()


## Native Controls process keyboard events first. This also handles the
## directional key codes emitted by the game's controller navigation.
func handle_key(code: int) -> bool:
	if not visible:
		return false
	if code == KEY_ESCAPE:
		close()
		return true
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null or not _root.is_ancestor_of(focused):
		_category_buttons[_group].grab_focus()
		return true
	var direction := -1 if code in [KEY_LEFT, KEY_A] else 1
	if code in [KEY_LEFT, KEY_RIGHT, KEY_A, KEY_D]:
		if focused is Range:
			focused.value += focused.step * direction
		elif focused is LineEdit and focused.get_parent() is SpinBox:
			var spin := focused.get_parent() as SpinBox
			spin.value += spin.step * direction
		else:
			_move_focus(focused, SIDE_LEFT if direction < 0 else SIDE_RIGHT)
	elif code in [KEY_UP, KEY_W, KEY_DOWN, KEY_S]:
		_move_focus(focused, SIDE_TOP if code in [KEY_UP, KEY_W] else SIDE_BOTTOM)
	elif code in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and focused is BaseButton:
		if focused.toggle_mode:
			focused.button_pressed = not focused.button_pressed
		focused.pressed.emit()
	return true


func _move_focus(focused: Control, side: Side) -> void:
	var next := focused.find_valid_focus_neighbor(side)
	if next != null:
		next.grab_focus()


func _show_group(group: String) -> void:
	_group = group
	_controls.clear()
	_preset_buttons.clear()
	_preset_cards.clear()
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for category: String in _category_buttons:
		_category_buttons[category].set_pressed_no_signal(category == group)
	_group_title.text = group
	var count := 0
	if group == PRESET_GROUP:
		_add_presets()
		_group_note.text = "Applying replaces all %d settings. Fine-tune afterwards, then choose Start duel to play." % _model.definitions.size()
	else:
		for definition: Dictionary in _model.definitions:
			if definition["group"] == group:
				_add_setting(definition)
				count += 1
		_group_note.text = "%d settings. Drag a slider, or type a value and press Enter." % count
	_scroll.scroll_vertical = 0
	_refresh()
	_wire_focus()


func _add_presets() -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_rows.add_child(grid)
	for preset: Dictionary in _model.PRESETS:
		var id: String = preset.id
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(0, 196)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", _box(Color("1b1127"), EDGE))
		grid.add_child(card)
		_preset_cards[id] = card
		var contents := VBoxContainer.new()
		contents.add_theme_constant_override("separation", 4)
		card.add_child(contents)
		var heading := HBoxContainer.new()
		contents.add_child(heading)
		var name_label := _label(heading, preset.name, 22, TEXT)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if preset.recommended:
			_label(heading, "Recommended", 14, GOLD)
		var description := _label(contents, preset.description, 16, MUTED)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.custom_minimum_size.y = 54
		description.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var stats := "Freeze: %s s    Action: %s s\nKnives: %d    Double jump: %s" % [
			String.num(float(_model.preset_value(id, "planning_duration")), 2),
			String.num(float(_model.preset_value(id, "execution_duration")), 2),
			int(_model.preset_value(id, "knives_per_shot")),
			"On" if _model.preset_value(id, "double_jump_enabled") else "Off",
		]
		_label(contents, stats, 16, TEXT)
		var apply := _button("Apply preset", Vector2(0, 34))
		apply.add_theme_font_size_override("font_size", 16)
		apply.pressed.connect(func(): _model.apply_preset(id))
		contents.add_child(apply)
		_preset_buttons[id] = apply


func _add_setting(definition: Dictionary) -> void:
	var key: String = definition["key"]
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 118)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _box(Color("1b1127"), EDGE))
	_rows.add_child(card)
	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation", 3)
	card.add_child(contents)
	var title_row := HBoxContainer.new()
	contents.add_child(title_row)
	var name_label := _label(title_row, definition["label"], 19, TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var default_label := _label(title_row, "Default: " + _format_value(definition,
		_model.default_value(key)), 15, MUTED)
	var reset := _button("Reset", Vector2(68, 28))
	reset.add_theme_font_size_override("font_size", 15)
	reset.tooltip_text = "Restore " + definition["label"] + " to its default."
	reset.pressed.connect(func(): _model.set_value(key, _model.default_value(key)))
	title_row.add_child(reset)
	var help := _label(contents, definition["help"], 16, MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var editor_row := HBoxContainer.new()
	editor_row.add_theme_constant_override("separation", 16)
	contents.add_child(editor_row)
	var entry := {"definition": definition, "reset": reset, "default": default_label,
		"card": card}
	if definition["kind"] == "bool":
		var toggle := CheckButton.new()
		toggle.custom_minimum_size = Vector2(140, 30)
		toggle.toggled.connect(func(value: bool): _set_value(key, value))
		editor_row.add_child(toggle)
		entry["toggle"] = toggle
		entry["focus"] = toggle
	else:
		var slider := HSlider.new()
		slider.min_value = definition["min"]
		slider.max_value = definition["max"]
		slider.step = definition["step"]
		slider.rounded = definition["kind"] == "int"
		slider.custom_minimum_size = Vector2(0, 30)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		slider.value_changed.connect(func(value: float): _set_value(key, value))
		editor_row.add_child(slider)
		var spin := SpinBox.new()
		spin.min_value = slider.min_value
		spin.max_value = slider.max_value
		spin.step = slider.step
		spin.rounded = slider.rounded
		spin.custom_minimum_size = Vector2(138, 34)
		# Commit the whole number on Enter or focus loss. Clamping every digit
		# would make it difficult to type values whose minimum is above nine.
		spin.update_on_text_changed = false
		spin.suffix = definition.get("unit", "")
		spin.get_line_edit().alignment = HORIZONTAL_ALIGNMENT_CENTER
		spin.value_changed.connect(func(value: float): _set_value(key, value))
		editor_row.add_child(spin)
		entry["slider"] = slider
		entry["spin"] = spin
		entry["focus"] = slider
	_controls[key] = entry


func _set_value(key: String, value: Variant) -> void:
	if not _refreshing:
		_model.set_value(key, value)
		_refresh()


func _refresh() -> void:
	if _model == null:
		return
	_refreshing = true
	var changed_in_group := false
	for key: String in _controls:
		var entry: Dictionary = _controls[key]
		var value: Variant = _model.get_value(key)
		var modified: bool = value != _model.default_value(key)
		changed_in_group = changed_in_group or modified
		entry["reset"].disabled = not modified
		entry["default"].add_theme_color_override("font_color", GOLD if modified else MUTED)
		if entry.has("toggle"):
			entry["toggle"].set_pressed_no_signal(bool(value))
			entry["toggle"].text = "On" if value else "Off"
		else:
			entry["slider"].set_value_no_signal(float(value))
			entry["spin"].set_value_no_signal(float(value))
	var count: int = _model.modified_count()
	_status.text = _model.profile_name()
	if count > 0:
		_status.text += " (%d changes)" % count
	var active: String = _model.matching_preset_id()
	for id: String in _preset_buttons:
		_preset_buttons[id].text = "Active preset" if id == active else "Apply preset"
		_preset_buttons[id].disabled = id == active
		_preset_cards[id].add_theme_stylebox_override("panel",
			_box(Color("1b1127"), GOLD if id == active else EDGE))
	_status.add_theme_color_override("font_color", GOLD if count > 0 else MUTED)
	if _model.last_save_error != OK:
		_status.text = "Changes active. Could not save to disk."
		_status.add_theme_color_override("font_color", Color("ffb493"))
	_reset_category.disabled = not changed_in_group
	_reset_all.disabled = count == 0
	_refreshing = false


func _wire_focus() -> void:
	var category_controls: Array[Control] = []
	for group: String in _groups:
		category_controls.append(_category_buttons[group])
	var editors: Array[Control] = []
	for button: Button in _preset_buttons.values():
		editors.append(button)
	for key: String in _controls:
		editors.append(_controls[key]["focus"])
	for i in category_controls.size():
		var button := category_controls[i]
		button.focus_neighbor_top = button.get_path_to(category_controls[maxi(i - 1, 0)])
		button.focus_neighbor_bottom = button.get_path_to(category_controls[i + 1] \
			if i + 1 < category_controls.size() else _back)
		if not editors.is_empty():
			button.focus_neighbor_right = button.get_path_to(editors[0])
	for i in editors.size():
		var editor := editors[i]
		editor.focus_neighbor_top = editor.get_path_to(editors[maxi(i - 1, 0)])
		editor.focus_neighbor_bottom = editor.get_path_to(editors[i + 1] \
			if i + 1 < editors.size() else _back)
		var entry: Dictionary = _controls.values()[i] if _group != PRESET_GROUP else {}
		if entry.has("spin"):
			var line_edit: LineEdit = entry["spin"].get_line_edit()
			line_edit.focus_neighbor_top = line_edit.get_path_to(editors[maxi(i - 1, 0)])
			line_edit.focus_neighbor_bottom = line_edit.get_path_to(editors[i + 1] \
				if i + 1 < editors.size() else _back)
	if _group == PRESET_GROUP:
		for i in editors.size():
			var editor := editors[i]
			editor.focus_neighbor_left = editor.get_path_to(editors[i - 1] if i % 2 == 1 \
				else _category_buttons[PRESET_GROUP])
			editor.focus_neighbor_right = editor.get_path_to(editors[mini(i + 1, editors.size() - 1)])
			editor.focus_neighbor_top = editor.get_path_to(editors[i - 2] if i >= 2 \
				else _category_buttons[PRESET_GROUP])
			editor.focus_neighbor_bottom = editor.get_path_to(editors[i + 2] if i + 2 < editors.size() else _back)
	_back.focus_neighbor_top = _back.get_path_to(editors.back() if not editors.is_empty() \
		else category_controls.back())
	_back.focus_neighbor_left = _back.get_path_to(_reset_all)
	_reset_all.focus_neighbor_left = _reset_all.get_path_to(_reset_category)
	_reset_all.focus_neighbor_right = _reset_all.get_path_to(_back)
	_reset_category.focus_neighbor_right = _reset_category.get_path_to(_reset_all)


func _format_value(definition: Dictionary, value: Variant) -> String:
	if definition["kind"] == "bool":
		return "On" if value else "Off"
	return String.num(float(value), 3) + (" " + str(definition["unit"]) if definition.get("unit", "") != "" else "")


func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _button(text: String, minimum: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = minimum
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button


func _rule(pos: Vector2, dimensions: Vector2, color: Color) -> void:
	var line := ColorRect.new()
	line.position = pos
	line.size = dimensions
	line.color = color
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(line)


func _box(fill: Color, border: Color, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style


func _make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = BODY_FONT
	theme.default_font_size = 18
	for type: String in ["Button", "CheckButton"]:
		theme.set_color("font_color", type, TEXT)
		theme.set_color("font_hover_color", type, TEXT)
		theme.set_color("font_pressed_color", type, GOLD)
		theme.set_color("font_disabled_color", type, Color("6f667e"))
		theme.set_stylebox("normal", type, _box(Color("21162f"), EDGE))
		theme.set_stylebox("hover", type, _box(Color("392249"), GOLD))
		theme.set_stylebox("pressed", type, _box(Color("422353"), GOLD))
		theme.set_stylebox("disabled", type, _box(Color("21162f"), Color("34293e")))
		theme.set_stylebox("focus", type, _box(Color(0, 0, 0, 0), GOLD, 2))
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("caret_color", "LineEdit", GOLD)
	theme.set_color("selection_color", "LineEdit", Color("69458a"))
	theme.set_stylebox("normal", "LineEdit", _box(INK, EDGE))
	theme.set_stylebox("focus", "LineEdit", _box(Color(0, 0, 0, 0), GOLD, 2))
	var track := _box(Color("4a3c55"), Color("4a3c55"), 0)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	theme.set_stylebox("slider", "HSlider", track)
	var filled := track.duplicate() as StyleBoxFlat
	filled.bg_color = GOLD
	theme.set_stylebox("grabber_area", "HSlider", filled)
	theme.set_stylebox("grabber_area_highlight", "HSlider", filled)
	theme.set_color("font_color", "Label", TEXT)
	return theme
