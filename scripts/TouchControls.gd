extends CanvasLayer
class_name TouchControls

## Mobile-first planning controls. The overlay translates each finger into the
## same held/edge state that keyboard and gamepad polling already consume.

signal confirm_requested
signal rollback_requested
signal reset_requested
signal super_requested
signal menu_requested
signal rematch_requested
signal replay_requested
signal report_requested
signal level_previous_requested
signal level_next_requested

const VIEW_SIZE := Vector2(1280.0, 720.0)
const GOLD := Color(0.96, 0.69, 0.18)
const VIOLET := Color(0.76, 0.30, 1.00)
const SPECTRAL := Color(0.88, 0.92, 1.00)
const INK := Color(0.025, 0.01, 0.045)

const STICK_CENTER := Vector2(112.0, 604.0)
const STICK_RADIUS := 78.0
const STICK_TOUCH_RADIUS := 108.0
const STICK_KNOB_TRAVEL := 40.0
const STICK_DEADZONE := 0.24
const JUMP_CENTER := Vector2(276.0, 648.0)
const JUMP_RADIUS := 48.0
const FIRE_CENTER := Vector2(1192.0, 650.0)
const FIRE_RADIUS := 58.0
const AIM_ZONE := Rect2(610.0, 205.0, 670.0, 390.0)
const MENU_RECT := Rect2(14.0, 14.0, 72.0, 42.0)
const UNDO_RECT := Rect2(718.0, 648.0, 76.0, 48.0)
const RESET_RECT := Rect2(804.0, 648.0, 76.0, 48.0)
const SUPER_RECT := Rect2(890.0, 648.0, 76.0, 48.0)
const LOCK_RECT := Rect2(976.0, 648.0, 104.0, 48.0)
const LEVEL_PREV_RECT := Rect2(244.0, 590.0, 70.0, 58.0)
const LEVEL_NEXT_RECT := Rect2(426.0, 590.0, 70.0, 58.0)
const REPORT_RECT := Rect2(510.0, 590.0, 170.0, 58.0)
const REPLAY_RECT := Rect2(695.0, 590.0, 190.0, 58.0)
const REMATCH_RECT := Rect2(900.0, 590.0, 240.0, 58.0)
const REPLAY_EXIT_RECT := Rect2(1030.0, 18.0, 220.0, 50.0)

enum Context { HIDDEN, PLANNING, FREEPLAY, GAME_OVER, REPLAY }

var enabled: bool = false
var context: int = Context.HIDDEN
var left_held: bool = false
var right_held: bool = false
var jump_held: bool = false
var wait_held: bool = false
var charge_held: bool = false
var aim_active: bool = false
## Movement chooses the initial facing side. Once the player deliberately aims,
## that direction stays independent from the joystick for the rest of the turn.
var aim_latched: bool = false
var aim_position: Vector2 = Vector2(960.0, 360.0)
var stick_vector: Vector2 = Vector2.ZERO

var _touch_actions: Dictionary = {}
var _action_counts: Dictionary = {}
var _surface: Control
var _gm


func _ready() -> void:
	layer = 8
	_surface = Control.new()
	_surface.size = VIEW_SIZE
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.draw.connect(_draw_overlay)
	add_child(_surface)
	visible = false


func configure(manager, should_enable: bool) -> void:
	_gm = manager
	enabled = should_enable
	_update_context()


func _process(_delta: float) -> void:
	_update_context()
	if visible:
		_surface.queue_redraw()


func _update_context() -> void:
	var next_context := Context.HIDDEN
	if enabled and _gm != null:
		match _gm.state:
			Phase.PLANNING:
				next_context = Context.PLANNING
			Phase.FREEPLAY:
				next_context = Context.FREEPLAY
			Phase.GAME_OVER:
				next_context = Context.GAME_OVER
			Phase.REPLAY:
				next_context = Context.REPLAY
	if next_context != context:
		context = next_context
		_release_all()
	visible = enabled and context != Context.HIDDEN


func has_active_touches() -> bool:
	return not _touch_actions.is_empty()


func _input(event: InputEvent) -> void:
	if not enabled or not visible:
		return
	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			_press_touch(touch.index, _canvas_position(touch.position))
		else:
			_release_touch(touch.index)
		get_viewport().set_input_as_handled()
		return
	var drag := event as InputEventScreenDrag
	if drag != null:
		_drag_touch(drag.index, _canvas_position(drag.position))
		get_viewport().set_input_as_handled()
		return

	# Force-touch mode remains testable with a mouse in the editor. It cannot
	# emulate multitouch, but it exercises every hit target and action signal.
	var mouse_button := event as InputEventMouseButton
	if mouse_button != null and mouse_button.button_index == MOUSE_BUTTON_LEFT:
		if mouse_button.pressed:
			_press_touch(-1, _canvas_position(mouse_button.position))
		else:
			_release_touch(-1)
		get_viewport().set_input_as_handled()
		return
	var mouse_motion := event as InputEventMouseMotion
	if mouse_motion != null and _touch_actions.has(-1):
		_drag_touch(-1, _canvas_position(mouse_motion.position))
		get_viewport().set_input_as_handled()


func _canvas_position(viewport_position: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * viewport_position


func _press_touch(id: int, position: Vector2) -> void:
	if _touch_actions.has(id):
		_release_touch(id)
	var action := _action_at(position)
	if action.is_empty():
		return
	_touch_actions[id] = action
	if action == "aim":
		aim_position = position
	elif action == "stick":
		_update_stick(position)
	_set_action(action, true)


func _drag_touch(id: int, position: Vector2) -> void:
	var action: String = _touch_actions.get(id, "")
	if action == "aim":
		aim_position = position
		_surface.queue_redraw()
	elif action == "stick":
		_update_stick(position)


func _release_touch(id: int) -> void:
	if not _touch_actions.has(id):
		return
	var action: String = _touch_actions[id]
	_touch_actions.erase(id)
	_set_action(action, false)


func _action_at(position: Vector2) -> String:
	if MENU_RECT.has_point(position):
		return "menu"
	if context == Context.REPLAY:
		return "replay" if REPLAY_EXIT_RECT.has_point(position) else ""
	if context == Context.GAME_OVER:
		if REPORT_RECT.has_point(position):
			return "report"
		if REPLAY_RECT.has_point(position):
			return "replay"
		if REMATCH_RECT.has_point(position):
			return "rematch"
		if _gm != null and (not _gm.online_mode \
				or (_gm.online_player == 0 and not _gm._online_waiting_rematch)):
			if LEVEL_PREV_RECT.has_point(position):
				return "level_previous"
			if LEVEL_NEXT_RECT.has_point(position):
				return "level_next"
		return ""
	if _in_circle(position, JUMP_CENTER, JUMP_RADIUS):
		return "jump"
	if _in_circle(position, STICK_CENTER, STICK_TOUCH_RADIUS):
		return "stick"
	if _in_circle(position, FIRE_CENTER, FIRE_RADIUS):
		return "charge"
	if context == Context.PLANNING:
		if UNDO_RECT.has_point(position):
			return "rollback"
		if RESET_RECT.has_point(position):
			return "reset"
		if SUPER_RECT.has_point(position):
			return "super"
		if LOCK_RECT.has_point(position):
			return "confirm"
	if AIM_ZONE.has_point(position):
		return "aim"
	return ""


func _set_action(action: String, pressed: bool) -> void:
	if pressed:
		_action_counts[action] = int(_action_counts.get(action, 0)) + 1
		if int(_action_counts[action]) == 1:
			_action_pressed(action)
	else:
		var remaining: int = maxi(0, int(_action_counts.get(action, 0)) - 1)
		if remaining == 0:
			_action_counts.erase(action)
			_action_released(action)
		else:
			_action_counts[action] = remaining
	_surface.queue_redraw()


func _action_pressed(action: String) -> void:
	match action:
		"jump": jump_held = true
		"charge": charge_held = true
		"aim":
			aim_active = true
			aim_latched = true
		"confirm": confirm_requested.emit()
		"rollback": rollback_requested.emit()
		"reset": reset_requested.emit()
		"super": super_requested.emit()
		"menu": menu_requested.emit()
		"rematch": rematch_requested.emit()
		"replay": replay_requested.emit()
		"report": report_requested.emit()
		"level_previous": level_previous_requested.emit()
		"level_next": level_next_requested.emit()


func _action_released(action: String) -> void:
	match action:
		"jump": jump_held = false
		"stick": _reset_stick()
		"charge": charge_held = false
		"aim": aim_active = false


func _release_all() -> void:
	_touch_actions.clear()
	_action_counts.clear()
	left_held = false
	right_held = false
	jump_held = false
	wait_held = false
	stick_vector = Vector2.ZERO
	charge_held = false
	aim_active = false
	aim_latched = false
	if _surface != null:
		_surface.queue_redraw()


func _in_circle(position: Vector2, center: Vector2, radius: float) -> bool:
	return position.distance_squared_to(center) <= radius * radius


func _active(action: String) -> bool:
	return int(_action_counts.get(action, 0)) > 0


func _update_stick(position: Vector2) -> void:
	stick_vector = (position - STICK_CENTER) / STICK_RADIUS
	if stick_vector.length_squared() > 1.0:
		stick_vector = stick_vector.normalized()
	left_held = stick_vector.x < -STICK_DEADZONE
	right_held = stick_vector.x > STICK_DEADZONE
	wait_held = context == Context.PLANNING and stick_vector.y > STICK_DEADZONE
	_surface.queue_redraw()


func _reset_stick() -> void:
	stick_vector = Vector2.ZERO
	left_held = false
	right_held = false
	wait_held = false


func _draw_overlay() -> void:
	if context == Context.REPLAY:
		_draw_rect_button(MENU_RECT, "MENU", "menu", SPECTRAL)
		_draw_rect_button(REPLAY_EXIT_RECT, "BACK TO RESULTS", "replay", VIOLET)
		return
	if context == Context.GAME_OVER:
		_draw_rect_button(MENU_RECT, "MENU", "menu", SPECTRAL)
		_draw_result_level_selector()
		_draw_rect_button(REPORT_RECT, "COPY REPORT", "report", SPECTRAL)
		_draw_rect_button(REPLAY_RECT, "WATCH REPLAY", "replay", VIOLET)
		_draw_rect_button(REMATCH_RECT, "REMATCH", "rematch", GOLD)
		return

	_draw_virtual_stick()
	_draw_round_button(JUMP_CENTER, JUMP_RADIUS, "JUMP", "jump", VIOLET, 15)
	_draw_round_button(FIRE_CENTER, FIRE_RADIUS, "DRAW", "charge", GOLD, 15)
	_draw_rect_button(MENU_RECT, "MENU", "menu", SPECTRAL)

	if context == Context.PLANNING:
		_draw_rect_button(UNDO_RECT, "UNDO", "rollback", SPECTRAL)
		_draw_rect_button(RESET_RECT, "RESET", "reset", SPECTRAL)
		_draw_rect_button(SUPER_RECT, "SUPER", "super", GOLD)
		_draw_rect_button(LOCK_RECT, "LOCK", "confirm", VIOLET)

	var aim_color := Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.72 if aim_active else 0.28)
	_surface.draw_line(Vector2(626.0, 584.0), Vector2(706.0, 584.0), aim_color, 2.0)
	_surface.draw_string(ThemeDB.fallback_font, Vector2(714.0, 590.0), "DRAG ARENA TO AIM",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(SPECTRAL.r, SPECTRAL.g, SPECTRAL.b, 0.44))
	if aim_active:
		_surface.draw_circle(aim_position, 18.0, Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.10))
		_surface.draw_arc(aim_position, 18.0, 0.0, TAU, 28, Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.78), 2.0)
		_surface.draw_line(aim_position - Vector2(26.0, 0.0), aim_position - Vector2(8.0, 0.0), aim_color, 2.0)
		_surface.draw_line(aim_position + Vector2(8.0, 0.0), aim_position + Vector2(26.0, 0.0), aim_color, 2.0)
		_surface.draw_line(aim_position - Vector2(0.0, 26.0), aim_position - Vector2(0.0, 8.0), aim_color, 2.0)
		_surface.draw_line(aim_position + Vector2(0.0, 8.0), aim_position + Vector2(0.0, 26.0), aim_color, 2.0)

	if _gm != null and charge_held:
		var who: int = _gm.online_player if _gm.online_mode else 0
		var power: float = _gm.players[who].plan.power if who >= 0 and who < _gm.players.size() else 0.0
		_surface.draw_arc(FIRE_CENTER, FIRE_RADIUS + 6.0, -PI * 0.5,
			-PI * 0.5 + TAU * power, 48, Color(1.0, 0.90, 0.42, 0.95), 4.0)


func _draw_virtual_stick() -> void:
	var is_active := _active("stick")
	var edge_alpha := 0.78 if is_active else 0.42
	var base_fill := Color(INK.r, INK.g, INK.b, 0.52 if is_active else 0.34)
	_surface.draw_circle(STICK_CENTER, STICK_RADIUS, base_fill)
	_surface.draw_circle(STICK_CENTER, STICK_RADIUS - 4.0,
		Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.13 if is_active else 0.07))
	_surface.draw_arc(STICK_CENTER, STICK_RADIUS, 0.0, TAU, 48,
		Color(VIOLET.r, VIOLET.g, VIOLET.b, edge_alpha), 2.5)
	_surface.draw_arc(STICK_CENTER, STICK_RADIUS * 0.52, 0.0, TAU, 36,
		Color(SPECTRAL.r, SPECTRAL.g, SPECTRAL.b, 0.18), 1.5)

	# Eight dial marks keep the stopped-clock signature without adding labels.
	for tick in 8:
		var direction := Vector2.from_angle(float(tick) * TAU / 8.0)
		var inner := STICK_RADIUS - (11.0 if tick % 2 == 0 else 7.0)
		_surface.draw_line(STICK_CENTER + direction * inner,
			STICK_CENTER + direction * (STICK_RADIUS - 2.0),
			Color(VIOLET.r, VIOLET.g, VIOLET.b, edge_alpha), 2.0)

	var knob_center := STICK_CENTER + stick_vector * STICK_KNOB_TRAVEL
	_surface.draw_circle(knob_center, 31.0, Color(INK.r, INK.g, INK.b, 0.72))
	_surface.draw_circle(knob_center, 27.0,
		Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.48 if is_active else 0.24))
	_surface.draw_arc(knob_center, 31.0, 0.0, TAU, 32,
		Color(SPECTRAL.r, SPECTRAL.g, SPECTRAL.b, 0.68 if is_active else 0.36), 2.0)


func _draw_result_level_selector() -> void:
	if _gm == null:
		return
	if not _gm.online_mode \
			or (_gm.online_player == 0 and not _gm._online_waiting_rematch):
		_draw_rect_button(LEVEL_PREV_RECT, "<", "level_previous", SPECTRAL)
		_draw_rect_button(LEVEL_NEXT_RECT, ">", "level_next", SPECTRAL)
	var level_caption := "LEVEL %d/%d" % [_gm.rematch_level_index + 1, Levels.count()]
	if _gm.online_mode:
		level_caption += "  HOST" if _gm.online_player == 0 \
			and not _gm._online_waiting_rematch else "  LOCKED"
	_surface.draw_string(ThemeDB.fallback_font, Vector2(314.0, 610.0), level_caption,
		HORIZONTAL_ALIGNMENT_CENTER, 112.0, 12, Color(SPECTRAL.r, SPECTRAL.g, SPECTRAL.b, 0.62))
	_surface.draw_string(ThemeDB.fallback_font, Vector2(314.0, 636.0), _gm.rematch_level_name,
		HORIZONTAL_ALIGNMENT_CENTER, 112.0, 14, Color(1.0, 0.92, 0.68, 0.88))


func _draw_round_button(center: Vector2, radius: float, label: String, action: String,
		accent: Color, font_size: int = 22) -> void:
	var is_active := _active(action)
	var fill_alpha := 0.48 if is_active else 0.16
	var edge_alpha := 0.92 if is_active else 0.48
	_surface.draw_circle(center, radius, Color(INK.r, INK.g, INK.b, 0.60))
	_surface.draw_circle(center, radius - 3.0, Color(accent.r, accent.g, accent.b, fill_alpha))
	_surface.draw_arc(center, radius, 0.0, TAU, 36, Color(accent.r, accent.g, accent.b, edge_alpha), 2.0)
	# Four clock ticks make the buttons belong to the stopped-time visual language.
	for quarter in 4:
		var direction := Vector2.from_angle(float(quarter) * PI * 0.5)
		_surface.draw_line(center + direction * (radius - 7.0), center + direction * (radius - 2.0),
			Color(accent.r, accent.g, accent.b, edge_alpha), 2.0)
	_surface.draw_string(ThemeDB.fallback_font, center + Vector2(-radius, float(font_size) * 0.34), label,
		HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, font_size,
		Color(1.0, 0.98, 0.90, 0.98 if is_active else 0.78))


func _draw_rect_button(rect: Rect2, label: String, action: String, accent: Color) -> void:
	var is_active := _active(action)
	_surface.draw_rect(rect, Color(INK.r, INK.g, INK.b, 0.70))
	_surface.draw_rect(rect.grow(-2.0), Color(accent.r, accent.g, accent.b, 0.42 if is_active else 0.13))
	_surface.draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.88 if is_active else 0.42), false, 2.0)
	_surface.draw_string(ThemeDB.fallback_font,
		Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5 + 5.0), label,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 14,
		Color(1.0, 0.98, 0.92, 0.96 if is_active else 0.70))
