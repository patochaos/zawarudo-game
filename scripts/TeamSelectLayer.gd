extends CanvasLayer
class_name TeamSelectLayer

const HUD_FONT := preload("res://assets/kenney/fonts/kenney-future-narrow.ttf")

## FIFA-style local side selection. A physical input device must explicitly
## join before it can claim a side; unfilled formation slots become CPU allies.

signal formation_confirmed(slots: Array, level: int)
signal canceled
signal ui_navigated
signal ui_accepted

const SIDE_NEUTRAL := -1
const SIDE_CRIMSON := 0
const SIDE_AZURE := 1
const KEYBOARD_DEVICE := -2
const MAX_HUMANS := 4

const VOID := Color(0.012, 0.007, 0.026)
const INK := Color(0.035, 0.020, 0.058)
const IVORY := Color(0.93, 0.91, 0.84)
const DIM := Color(0.55, 0.59, 0.69)
const GOLD := Color(0.96, 0.72, 0.24)
const CRIMSON := Color(0.93, 0.19, 0.28)
const AZURE := Color(0.16, 0.66, 0.98)


class FateStage:
	extends Control

	var tokens: Array = []
	var pulse: float = 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()

	func _process(delta: float) -> void:
		pulse += delta
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), VOID)
		# Two rival ink fields meet at a narrow stopped-time fracture. Team color
		# communicates ownership; the gold seam remains the ZAWARUDO signature.
		draw_colored_polygon(PackedVector2Array([
			Vector2.ZERO, Vector2(544.0, 0.0), Vector2(624.0, 720.0), Vector2(0.0, 720.0),
		]), Color(CRIMSON.r, CRIMSON.g, CRIMSON.b, 0.105))
		draw_colored_polygon(PackedVector2Array([
			Vector2(736.0, 0.0), Vector2(1280.0, 0.0), Vector2(1280.0, 720.0), Vector2(656.0, 720.0),
		]), Color(AZURE.r, AZURE.g, AZURE.b, 0.105))
		for i in 13:
			var y := 118.0 + float(i) * 42.0
			var drift := sin(pulse * 0.55 + float(i)) * 5.0
			draw_line(Vector2(606.0 + drift, y), Vector2(674.0 - drift, y - 26.0),
				Color(GOLD.r, GOLD.g, GOLD.b, 0.10 + float(i % 3) * 0.035), 1.0)
		draw_line(Vector2(638.0, 112.0), Vector2(638.0, 620.0),
			Color(GOLD.r, GOLD.g, GOLD.b, 0.42), 2.0)
		draw_line(Vector2(646.0, 112.0), Vector2(646.0, 620.0),
			Color(0.54, 0.22, 0.76, 0.34), 1.0)

		_draw_formation(Vector2(64.0, 190.0), CRIMSON)
		_draw_formation(Vector2(872.0, 190.0), AZURE)
		for token in tokens:
			_draw_token(token)

	func _draw_formation(origin: Vector2, color: Color) -> void:
		for row in 2:
			var rect := Rect2(origin + Vector2(0.0, float(row) * 164.0), Vector2(344.0, 132.0))
			draw_colored_polygon(PackedVector2Array([
				rect.position + Vector2(18.0, 0.0), rect.position + Vector2(rect.size.x, 0.0),
				rect.end - Vector2(18.0, 0.0), rect.position + Vector2(0.0, rect.size.y),
				rect.position,
			]), Color(INK.r, INK.g, INK.b, 0.92))
			draw_polyline(PackedVector2Array([
				rect.position + Vector2(18.0, 0.0), rect.position + Vector2(rect.size.x, 0.0),
				rect.end - Vector2(18.0, 0.0), rect.position + Vector2(0.0, rect.size.y),
				rect.position, rect.position + Vector2(18.0, 0.0),
			]), Color(color.r, color.g, color.b, 0.34), 1.5, true)

	func _draw_token(token: Dictionary) -> void:
		var pos: Vector2 = token["draw_position"]
		var side: int = token["side"]
		var ready: bool = token["ready"]
		var joined: bool = token["joined"]
		var accent := GOLD if side == SIDE_NEUTRAL else (CRIMSON if side == SIDE_CRIMSON else AZURE)
		var rect := Rect2(pos, Vector2(270.0, 82.0))
		draw_colored_polygon(PackedVector2Array([
			rect.position + Vector2(12.0, 0.0), rect.position + Vector2(rect.size.x, 0.0),
			rect.end - Vector2(12.0, 0.0), rect.position + Vector2(0.0, rect.size.y), rect.position,
		]), Color(0.055, 0.035, 0.082, 0.98 if joined else 0.66))
		draw_polyline(PackedVector2Array([
			rect.position + Vector2(12.0, 0.0), rect.position + Vector2(rect.size.x, 0.0),
			rect.end - Vector2(12.0, 0.0), rect.position + Vector2(0.0, rect.size.y),
			rect.position, rect.position + Vector2(12.0, 0.0),
		]), Color(accent.r, accent.g, accent.b, 0.95 if ready else 0.58),
			3.0 if ready else 1.5, true)
		var font := HUD_FONT
		draw_string(font, pos + Vector2(18.0, 29.0), str(token["label"]),
			HORIZONTAL_ALIGNMENT_LEFT, 180.0, 16, IVORY if joined else DIM)
		draw_string(font, pos + Vector2(18.0, 57.0),
			"FATE LOCKED" if ready else ("CHOOSE A SIDE" if joined and side == SIDE_NEUTRAL else \
			("PRESS A / START" if not joined else "PRESS START TO LOCK")),
			HORIZONTAL_ALIGNMENT_LEFT, 232.0, 11, accent)


var devices: Array[Dictionary] = []
var _stage: FateStage
var _status: Label
var _continue: Button
var _arena_label: Label
var selected_level: int = 0
var _keyboard_seen: bool = false


func _ready() -> void:
	layer = 18
	_stage = FateStage.new()
	_stage.size = Vector2(1280.0, 720.0)
	add_child(_stage)

	var eyebrow := _label(Vector2(140.0, 34.0), Vector2(1000.0, 22.0), 12, GOLD)
	eyebrow.text = "LOCAL FORMATION // INPUT OWNERSHIP // 2 VS 2"
	var title := _label(Vector2(120.0, 57.0), Vector2(1040.0, 58.0), 42, IVORY)
	title.text = "DIVIDE THE FATES"
	var red := _label(Vector2(64.0, 135.0), Vector2(344.0, 34.0), 22, CRIMSON)
	red.text = "TEAM CRIMSON"
	var centre := _label(Vector2(484.0, 135.0), Vector2(312.0, 34.0), 13, GOLD)
	centre.text = "UNASSIGNED DEVICES"
	var blue := _label(Vector2(872.0, 135.0), Vector2(344.0, 34.0), 22, AZURE)
	blue.text = "TEAM AZURE"

	var arena_previous := _button(Vector2(368.0, 548.0), Vector2(48.0, 38.0), "‹")
	arena_previous.pressed.connect(func(): _cycle_arena(-1))
	_arena_label = _label(Vector2(426.0, 551.0), Vector2(428.0, 32.0), 14, GOLD)
	var arena_next := _button(Vector2(864.0, 548.0), Vector2(48.0, 38.0), "›")
	arena_next.pressed.connect(func(): _cycle_arena(1))
	_status = _label(Vector2(290.0, 597.0), Vector2(700.0, 24.0), 13, DIM)
	_continue = _button(Vector2(452.0, 638.0), Vector2(376.0, 48.0), "ENTER THE ROSTER  ›")
	_continue.pressed.connect(_try_confirm)
	var hint := _label(Vector2(64.0, 688.0), Vector2(1152.0, 20.0), 11, DIM)
	hint.text = "KEYBOARD  A / D MOVE · SHIFT LOCK      GAMEPAD  D-PAD MOVE · A / START LOCK · B LEAVE      ESC BACK"
	visible = false


func open(initial_level: int = 0) -> void:
	devices.clear()
	selected_level = posmod(initial_level, Levels.count())
	_keyboard_seen = true
	devices.append(_device(KEYBOARD_DEVICE, "KEYBOARD + MOUSE", true))
	for device_id in Input.get_connected_joypads():
		devices.append(_device(device_id, _pad_label(device_id), false))
	visible = true
	_refresh()


func close() -> void:
	visible = false


func refresh_connections() -> void:
	if not visible:
		return
	var connected := Input.get_connected_joypads()
	for device_id in connected:
		if _index_for_device(device_id) < 0 and devices.size() < MAX_HUMANS:
			devices.append(_device(device_id, _pad_label(device_id), false))
	for i in range(devices.size() - 1, -1, -1):
		if devices[i]["device"] != KEYBOARD_DEVICE and devices[i]["device"] not in connected:
			devices.remove_at(i)
	_refresh()


func handle_input(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_ESCAPE:
			canceled.emit()
			return true
		_keyboard_seen = true
		return _handle_device_action(KEYBOARD_DEVICE, key.keycode)
	var joy := event as InputEventJoypadButton
	if joy != null and joy.pressed:
		return _handle_pad_action(joy.device, joy.button_index)
	return false


func debug_join_device(device_id: int, label: String = "TEST PAD") -> void:
	var index := _index_for_device(device_id)
	if index < 0 and devices.size() < MAX_HUMANS:
		devices.append(_device(device_id, label, true))
	elif index >= 0:
		devices[index]["joined"] = true
	_refresh()


func debug_set_side(device_id: int, side: int, ready: bool = false) -> void:
	var index := _index_for_device(device_id)
	if index < 0:
		return
	devices[index]["joined"] = true
	devices[index]["side"] = clampi(side, SIDE_NEUTRAL, SIDE_AZURE)
	devices[index]["ready"] = ready and side != SIDE_NEUTRAL
	_refresh()


func build_slots() -> Array:
	var slots: Array = []
	for side in [SIDE_CRIMSON, SIDE_AZURE]:
		for device in devices:
			if device["joined"] and device["side"] == side:
				slots.append({
					"team": side,
					"role": "HUMAN",
					"device": int(device["device"]),
					"label": str(device["label"]),
				})
		var side_count := 0
		for slot in slots:
			if slot["team"] == side:
				side_count += 1
		while side_count < 2:
			slots.append({"team": side, "role": "AI", "device": -1, "label": "CPU"})
			side_count += 1
	# Alternate team indices so authored four-player spawn sockets remain
	# spatially readable instead of stacking both allies into one corner.
	var ordered: Array = []
	for formation_index in 2:
		for side in [SIDE_CRIMSON, SIDE_AZURE]:
			var candidates := slots.filter(func(slot): return slot["team"] == side)
			ordered.append(candidates[formation_index])
	return ordered


func _handle_device_action(device_id: int, keycode: int) -> bool:
	match keycode:
		KEY_Q:
			_cycle_arena(-1)
		KEY_E:
			_cycle_arena(1)
		KEY_A, KEY_LEFT:
			_move_device(device_id, -1)
		KEY_D, KEY_RIGHT:
			_move_device(device_id, 1)
		KEY_SHIFT, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_toggle_ready(device_id)
		_:
			return false
	return true


func _handle_pad_action(device_id: int, button: int) -> bool:
	var index := _index_for_device(device_id)
	if index < 0:
		if devices.size() >= MAX_HUMANS:
			return true
		devices.append(_device(device_id, _pad_label(device_id), true))
		index = devices.size() - 1
	if not devices[index]["joined"]:
		if button in [JOY_BUTTON_A, JOY_BUTTON_START]:
			devices[index]["joined"] = true
			ui_accepted.emit()
			_refresh()
		return true
	match button:
		JOY_BUTTON_LEFT_SHOULDER:
			_cycle_arena(-1)
		JOY_BUTTON_RIGHT_SHOULDER:
			_cycle_arena(1)
		JOY_BUTTON_DPAD_LEFT:
			_move_device(device_id, -1)
		JOY_BUTTON_DPAD_RIGHT:
			_move_device(device_id, 1)
		JOY_BUTTON_A, JOY_BUTTON_START:
			_toggle_ready(device_id)
		JOY_BUTTON_B:
			devices[index]["side"] = SIDE_NEUTRAL
			devices[index]["ready"] = false
			devices[index]["joined"] = false
			ui_navigated.emit()
			_refresh()
		_:
			return false
	return true


func _move_device(device_id: int, direction: int) -> void:
	var index := _index_for_device(device_id)
	if index < 0:
		return
	var device := devices[index]
	if not device["joined"]:
		device["joined"] = true
	var destination := SIDE_CRIMSON if direction < 0 else SIDE_AZURE
	if device["side"] == destination:
		destination = SIDE_NEUTRAL
	if destination != SIDE_NEUTRAL and _side_human_count(destination) >= 2:
		_status.text = "THAT FORMATION IS FULL"
		return
	device["side"] = destination
	device["ready"] = false
	devices[index] = device
	ui_navigated.emit()
	_refresh()


func _toggle_ready(device_id: int) -> void:
	var index := _index_for_device(device_id)
	if index < 0:
		return
	if not devices[index]["joined"]:
		devices[index]["joined"] = true
		ui_accepted.emit()
		_refresh()
		return
	if devices[index]["side"] == SIDE_NEUTRAL:
		_status.text = "CHOOSE CRIMSON OR AZURE BEFORE LOCKING FATE"
		return
	devices[index]["ready"] = not devices[index]["ready"]
	ui_accepted.emit()
	_refresh()
	if _can_confirm():
		_try_confirm()


func _try_confirm() -> void:
	if not _can_confirm():
		_status.text = "EVERY JOINED DEVICE MUST CHOOSE A SIDE AND LOCK FATE"
		return
	ui_accepted.emit()
	formation_confirmed.emit(build_slots(), selected_level)


func _can_confirm() -> bool:
	var joined_count := 0
	for device in devices:
		if not device["joined"]:
			continue
		joined_count += 1
		if device["side"] == SIDE_NEUTRAL or not device["ready"]:
			return false
	return joined_count > 0


func _refresh() -> void:
	var neutral_index := 0
	var side_indices := [0, 0]
	for device in devices:
		var side: int = device["side"]
		if side == SIDE_NEUTRAL:
			device["draw_position"] = Vector2(505.0, 210.0 + float(neutral_index) * 94.0)
			neutral_index += 1
		else:
			var base_x := 101.0 if side == SIDE_CRIMSON else 909.0
			device["draw_position"] = Vector2(base_x, 215.0 + float(side_indices[side]) * 164.0)
			side_indices[side] += 1
	_stage.tokens = devices
	_stage.queue_redraw()
	_arena_label.text = "ARENA %02d / %02d  —  %s" % [
		selected_level + 1, Levels.count(), str(Levels.build(selected_level, 4)["name"])]
	_continue.disabled = not _can_confirm()
	_continue.modulate = Color.WHITE if not _continue.disabled else Color(0.45, 0.46, 0.52)
	if _can_confirm():
		_status.text = "FORMATION COMPLETE — EMPTY SLOTS WILL BE FILLED BY CPU FIGHTERS"
	else:
		_status.text = "%d DEVICE%s JOINED · CRIMSON %d/2 · AZURE %d/2" % [
			_joined_count(), "" if _joined_count() == 1 else "S",
			_side_human_count(SIDE_CRIMSON), _side_human_count(SIDE_AZURE)]


func _cycle_arena(direction: int) -> void:
	selected_level = posmod(selected_level + direction, Levels.count())
	ui_navigated.emit()
	_refresh()


func _device(device_id: int, label: String, joined: bool) -> Dictionary:
	return {
		"device": device_id,
		"label": label,
		"joined": joined,
		"side": SIDE_NEUTRAL,
		"ready": false,
		"draw_position": Vector2.ZERO,
	}


func _pad_label(device_id: int) -> String:
	var name := Input.get_joy_name(device_id).strip_edges()
	return "PAD %d" % (device_id + 1) if name.is_empty() else name.to_upper().left(22)


func _index_for_device(device_id: int) -> int:
	for i in devices.size():
		if devices[i]["device"] == device_id:
			return i
	return -1


func _joined_count() -> int:
	var count := 0
	for device in devices:
		if device["joined"]:
			count += 1
	return count


func _side_human_count(side: int) -> int:
	var count := 0
	for device in devices:
		if device["joined"] and device["side"] == side:
			count += 1
	return count


func _label(pos: Vector2, dimensions: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = pos
	label.size = dimensions
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.01, 0.005, 0.02, 0.96))
	label.add_theme_constant_override("outline_size", 3)
	add_child(label)
	return label


func _button(pos: Vector2, dimensions: Vector2, text: String) -> Button:
	var button := Button.new()
	button.position = pos
	button.size = dimensions
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", IVORY)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.10, 0.052, 0.15, 0.98)
	normal.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.58)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.25, 0.09, 0.34, 0.98)
	hover.border_color = GOLD
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	add_child(button)
	return button
