extends CanvasLayer
class_name RosterLayer

## The lineup screen: four slots, each one independently a human seat, a CPU or
## an open seat. Nothing about the match is decided here except who is fighting
## and as whom — rules and arena live on MatchSetupLayer, the screen after this.
##
## A fighter is cycled inside its own slot rather than given a column of its
## own, so the cast can grow past four without the screen changing shape. Each
## joined device drives only its own slot, so a four-player table picks at once.

signal lineup_confirmed(lineup: Dictionary)
signal canceled
signal ui_navigated
signal ui_accepted

## Fighter identity, portraits and kit copy all live in Roster so this screen
## and the online lobby can never describe the same fighter differently.
const DUELIST := Roster.DUELIST
const DASHBLADE := Roster.DASHBLADE
const CHAKRAM := Roster.CHAKRAM
const SHOCK := Roster.SHOCK
const ROSTER := Roster.ORDER

const MAX_SLOTS := 4
const MIN_FIGHTERS := 2
const KEYBOARD_DEVICE := -2
const NO_DEVICE := -1

enum SlotKind { OPEN, PLAYER, CPU }

const DIFFICULTY_NAMES := ["NOVICE", "STANDARD", "RUTHLESS"]

## A slot's control tile walks one list — the human seat, the three CPU presets,
## then the open seat. Who holds a slot and how hard they play is a single
## decision, so there is no second control to go hunting for.
const ROLE_PLAYER := 0
const ROLE_CPU_FIRST := 1
const ROLE_OPEN := 4
const ROLE_TOTAL := 5

## Rows inside the focused column, plus the confirm bar under all of them.
const ROW_FIGHTER := 0
const ROW_ROLE := 1
const ROW_NEXT := 2
const ROW_TOTAL := 3

const ACCENTS := [
	Color(0.96, 0.69, 0.18),
	Color(0.76, 0.30, 1.00),
	Color(0.18, 0.82, 0.92),
	Color(1.00, 0.32, 0.42),
]
const GOLD := Color(0.91, 0.66, 0.22)
const HOT := Color(1.0, 0.89, 0.64)
const DIM := Color(0.58, 0.62, 0.72)
const FAINT := Color(0.40, 0.44, 0.54)
const INK := Color(0.035, 0.022, 0.058)
const VACANT := Color(0.38, 0.35, 0.47)

# Layout. One 1280x720 frame; every slot and every control visible at once.
const FRAME := Rect2(34.0, 20.0, 1212.0, 680.0)
const COL_XS := [60.0, 353.0, 646.0, 939.0]
const COL_W := 281.0
const HEAD_Y := 88.0
const HEAD_H := 28.0
const CARD_Y := 126.0
const CARD_H := 300.0
const CARD_CUT := 20.0
const ARROW_W := 32.0
const ROLE_Y := 436.0
const ROLE_H := 52.0
const READY_Y := 496.0
const READY_H := 28.0
const STRIP_Y := 540.0
const STRIP_H := 66.0
const NEXT_X := 939.0
const NEXT_Y := 626.0
const NEXT_W := 281.0
const NEXT_H := 40.0


## Draws every plate, portrait and border. Text is left to Labels so the Web
## export's reduced fallback font still lays out the same way it does natively.
class RosterArt:
	extends Control

	var model: Dictionary = {}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func apply(next_model: Dictionary) -> void:
		model = next_model
		queue_redraw()

	func _cut(rect: Rect2, cut: float) -> PackedVector2Array:
		return PackedVector2Array([
			Vector2(rect.position.x + cut, rect.position.y),
			Vector2(rect.end.x, rect.position.y),
			Vector2(rect.end.x, rect.end.y - cut),
			Vector2(rect.end.x - cut, rect.end.y),
			Vector2(rect.position.x, rect.end.y),
			Vector2(rect.position.x, rect.position.y + cut),
		])

	func _shear(rect: Rect2, slant: float) -> PackedVector2Array:
		return PackedVector2Array([
			Vector2(rect.position.x + slant, rect.position.y),
			Vector2(rect.end.x, rect.position.y),
			Vector2(rect.end.x - slant, rect.end.y),
			Vector2(rect.position.x, rect.end.y),
		])

	func _outline(points: PackedVector2Array, color: Color, width: float) -> void:
		draw_polyline(points + PackedVector2Array([points[0]]), color, width, true)

	func _draw() -> void:
		_draw_ground()
		if model.is_empty():
			return
		for column: Dictionary in model.get("columns", []):
			_draw_column(column)
		_draw_strip()
		_draw_next()

	func _draw_ground() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.035, 0.020, 0.058, 0.985))
		draw_colored_polygon(PackedVector2Array([
			Vector2(0.0, 0.0), Vector2(690.0, 0.0), Vector2(610.0, 720.0), Vector2(0.0, 720.0),
		]), Color(0.29, 0.09, 0.48, 0.30))
		draw_colored_polygon(PackedVector2Array([
			Vector2(1090.0, 0.0), Vector2(1280.0, 0.0),
			Vector2(1280.0, 720.0), Vector2(900.0, 720.0),
		]), Color(0.54, 0.34, 0.06, 0.16))
		for i in 3:
			var x := 1120.0 + float(i) * 60.0
			draw_line(Vector2(x, 60.0), Vector2(x - 165.0, 700.0),
				Color(0.91, 0.66, 0.22, 0.075), 1.6)
			draw_line(Vector2(90.0 + float(i) * 91.0, 0.0),
				Vector2(10.0 + float(i) * 87.0, 700.0), Color(0.71, 0.51, 0.94, 0.10), 1.4)
		draw_rect(FRAME, Color(0.91, 0.66, 0.22, 0.40), false, 1.5)
		draw_line(Vector2(60.0, 74.0), Vector2(1220.0, 74.0), Color(0.91, 0.66, 0.22, 0.62), 1.6)

	func _draw_column(column: Dictionary) -> void:
		var accent: Color = column["accent"]
		var occupied: bool = column["occupied"]

		var head := _shear(column["head_rect"], 6.0)
		draw_colored_polygon(head, Color(0.16, 0.09, 0.26, 0.94) if occupied \
			else Color(0.075, 0.052, 0.12, 0.90))
		_outline(head, Color(accent.r, accent.g, accent.b, 0.85 if occupied else 0.30), 1.4)

		var rect: Rect2 = column["card_rect"]
		var card := _cut(rect, CARD_CUT)
		draw_colored_polygon(card, Color(0.06, 0.045, 0.10, 1.0))
		var portrait: Texture2D = column["portrait"]
		if portrait != null:
			# Drawn as a textured polygon rather than a rect so the art stops at
			# the plate's cut corners instead of squaring them off.
			draw_colored_polygon(card, Color.WHITE,
				_cover_uvs(card, rect, portrait.get_size()), portrait)
		var veil: float = column["veil"]
		if veil > 0.0:
			draw_colored_polygon(card, Color(0.031, 0.016, 0.055, veil))
		if not occupied:
			_draw_vacancy(rect)
		_draw_name_floor(rect)
		if bool(column["card_focused"]):
			_dashed(card, accent, 3.0)
		else:
			_outline(card, accent, 2.6 if occupied else 1.2)
		if bool(column["arrows"]):
			_draw_arrows(rect, accent)

		var role: Rect2 = column["role_rect"]
		var role_lit: bool = column["role_focused"]
		draw_rect(role, Color(0.10, 0.065, 0.17, 1.0) if role_lit \
			else Color(0.075, 0.048, 0.135, 1.0))
		draw_rect(role, accent if role_lit else Color(0.24, 0.18, 0.34, 1.0), false,
			2.0 if role_lit else 1.0)
		draw_rect(Rect2(role.position, Vector2(role.size.x, 3.0)),
			accent if occupied else Color(0.24, 0.18, 0.34, 1.0))
		_draw_chevrons(role, accent if role_lit else Color(0.44, 0.38, 0.56))

		var ready_rect: Rect2 = column["ready_rect"]
		var badge := _shear(ready_rect, 6.0)
		if bool(column["ready"]):
			draw_colored_polygon(badge, accent)
		else:
			draw_colored_polygon(badge, Color(0.078, 0.050, 0.13, 0.92))
			_outline(badge, Color(accent.r, accent.g, accent.b, 0.55 if occupied else 0.25), 1.3)

	## An empty seat is drawn, not merely left blank, so a four-slot screen never
	## reads as three broken tiles beside one working one.
	func _draw_vacancy(rect: Rect2) -> void:
		var mid := rect.position + rect.size * Vector2(0.5, 0.42)
		draw_circle(mid + Vector2(0.0, -34.0), 34.0, Color(0.15, 0.11, 0.23, 1.0))
		draw_colored_polygon(PackedVector2Array([
			mid + Vector2(-56.0, 74.0), mid + Vector2(-40.0, 6.0),
			mid + Vector2(40.0, 6.0), mid + Vector2(56.0, 74.0),
		]), Color(0.15, 0.11, 0.23, 1.0))
		for step in 7:
			var y := rect.position.y + 26.0 + float(step) * 38.0
			draw_line(Vector2(rect.position.x + 10.0, y),
				Vector2(rect.end.x - 10.0, y), Color(0.20, 0.15, 0.30, 0.30), 1.0)

	func _draw_arrows(rect: Rect2, accent: Color) -> void:
		var mid := rect.position.y + rect.size.y * 0.44
		var left := rect.position.x + 13.0
		var right := rect.end.x - 13.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(left - 7.0, mid), Vector2(left + 6.0, mid - 13.0),
			Vector2(left + 6.0, mid + 13.0),
		]), accent)
		draw_colored_polygon(PackedVector2Array([
			Vector2(right + 7.0, mid), Vector2(right - 6.0, mid - 13.0),
			Vector2(right - 6.0, mid + 13.0),
		]), accent)

	func _draw_chevrons(rect: Rect2, color: Color) -> void:
		var mid := rect.position.y + rect.size.y * 0.5
		var left := rect.position.x + 14.0
		var right := rect.end.x - 14.0
		draw_polyline(PackedVector2Array([
			Vector2(left + 5.0, mid - 7.0), Vector2(left - 3.0, mid),
			Vector2(left + 5.0, mid + 7.0),
		]), color, 2.0, true)
		draw_polyline(PackedVector2Array([
			Vector2(right - 5.0, mid - 7.0), Vector2(right + 3.0, mid),
			Vector2(right - 5.0, mid + 7.0),
		]), color, 2.0, true)

	## Cover-fit: the square portraits keep their proportions and lose their
	## edges, rather than being stretched into the taller tile.
	func _cover_uvs(points: PackedVector2Array, rect: Rect2,
			texture_size: Vector2) -> PackedVector2Array:
		var scale := maxf(rect.size.x / texture_size.x, rect.size.y / texture_size.y)
		var drawn := texture_size * scale
		var origin := rect.position + (rect.size - drawn) * 0.5
		var uvs := PackedVector2Array()
		for point: Vector2 in points:
			uvs.append((point - origin) / drawn)
		return uvs

	## A dark floor under the portrait so the fighter's name always outranks the
	## art. Each band follows the plate's cut so nothing spills past the border.
	func _draw_name_floor(rect: Rect2) -> void:
		var height := 150.0
		var steps := 16
		for step in steps:
			var t0 := float(step) / float(steps)
			var t1 := float(step + 1) / float(steps)
			var y0 := rect.end.y - height + t0 * height
			var y1 := rect.end.y - height + t1 * height
			draw_colored_polygon(PackedVector2Array([
				Vector2(_left_at(rect, y0), y0), Vector2(_right_at(rect, y0), y0),
				Vector2(_right_at(rect, y1), y1), Vector2(_left_at(rect, y1), y1),
			]), Color(0.028, 0.014, 0.050, _floor_alpha((t0 + t1) * 0.5)))

	func _floor_alpha(t: float) -> float:
		return lerpf(0.0, 0.64, t / 0.46) if t < 0.46 \
			else lerpf(0.64, 0.98, (t - 0.46) / 0.54)

	func _left_at(rect: Rect2, y: float) -> float:
		return rect.position.x + maxf(0.0, rect.position.y + CARD_CUT - y)

	func _right_at(rect: Rect2, y: float) -> float:
		return rect.end.x - maxf(0.0, y - (rect.end.y - CARD_CUT))

	## The focused/unfocused difference has to survive a colour-blind player and
	## a phone screen, so the live cursor is dashed as well as brighter.
	func _dashed(points: PackedVector2Array, color: Color, width: float) -> void:
		var loop := points + PackedVector2Array([points[0]])
		for i in loop.size() - 1:
			var from: Vector2 = loop[i]
			var to: Vector2 = loop[i + 1]
			var span := from.distance_to(to)
			var dir := (to - from).normalized()
			var travelled := 0.0
			while travelled < span:
				var dash := minf(14.0, span - travelled)
				draw_line(from + dir * travelled, from + dir * (travelled + dash), color, width)
				travelled += 21.0

	func _draw_strip() -> void:
		var rect := Rect2(60.0, STRIP_Y, 1160.0, STRIP_H)
		draw_rect(rect, Color(0.078, 0.048, 0.135, 0.94))
		draw_rect(Rect2(60.0, STRIP_Y, 1160.0, 2.0), model.get("strip_accent", GOLD))
		for x: float in [330.0, 640.0, 950.0]:
			draw_line(Vector2(x, STRIP_Y + 13.0), Vector2(x, STRIP_Y + 53.0),
				Color(0.24, 0.18, 0.34, 1.0))

	func _draw_next() -> void:
		var rect := Rect2(NEXT_X, NEXT_Y, NEXT_W, NEXT_H)
		var plate := _shear(rect, 9.0)
		var ready := bool(model.get("next_ready", false))
		var lit := bool(model.get("next_focused", false))
		draw_colored_polygon(plate, Color(0.48, 0.28, 0.06, 0.92) if ready and lit \
			else (Color(0.20, 0.12, 0.03, 0.90) if ready else Color(0.10, 0.07, 0.16, 0.90)))
		_outline(plate, Color(0.91, 0.66, 0.22, 0.95 if ready else 0.35),
			2.4 if ready and lit else 1.2)


var kinds: Array[int] = [SlotKind.PLAYER, SlotKind.CPU, SlotKind.OPEN, SlotKind.OPEN]
var weapons: Array[int] = [DUELIST, DASHBLADE, SHOCK, CHAKRAM]
var difficulties: Array[int] = [1, 1, 1, 1]
var devices: Array[int] = [KEYBOARD_DEVICE, NO_DEVICE, NO_DEVICE, NO_DEVICE]
var ready_slots: Array[bool] = [false, false, false, false]
## Which column the keyboard and mouse are pointing at, and which of its rows.
var cursor_slot: int = 0
var row: int = ROW_FIGHTER

## Test and capture seam: pads that are not physically present. Headless CI has
## no controllers, so joining and leaving have to be expressible without one.
var _debug_pads: Array[int] = []

var _art: RosterArt
var _labels: Dictionary = {}


func _ready() -> void:
	layer = 15
	_art = RosterArt.new()
	_art.size = Vector2(1280.0, 720.0)
	add_child(_art)

	_text("title", Vector2(60.0, 34.0), Vector2(360.0, 40.0), 29, Color(0.96, 0.76, 0.31))
	_text("breadcrumb", Vector2(228.0, 40.0), Vector2(460.0, 24.0), 11, DIM)
	_text("tally", Vector2(760.0, 40.0), Vector2(460.0, 24.0), 10, FAINT,
		HORIZONTAL_ALIGNMENT_RIGHT)

	for i in MAX_SLOTS:
		var x: float = COL_XS[i]
		_text("head_tag_%d" % i, Vector2(x + 14.0, HEAD_Y + 5.0), Vector2(120.0, 20.0), 13, HOT)
		_text("card_name_%d" % i, Vector2(x, CARD_Y + CARD_H - 58.0), Vector2(COL_W, 30.0), 22,
			HOT, HORIZONTAL_ALIGNMENT_CENTER)
		_text("card_kit_%d" % i, Vector2(x, CARD_Y + CARD_H - 28.0), Vector2(COL_W, 20.0), 9,
			DIM, HORIZONTAL_ALIGNMENT_CENTER)
		_text("role_label_%d" % i, Vector2(x + 30.0, ROLE_Y + 8.0), Vector2(COL_W - 60.0, 16.0),
			9, Color(0.69, 0.52, 0.19), HORIZONTAL_ALIGNMENT_CENTER)
		_text("role_value_%d" % i, Vector2(x + 30.0, ROLE_Y + 24.0), Vector2(COL_W - 60.0, 22.0),
			14, HOT, HORIZONTAL_ALIGNMENT_CENTER)
		_text("ready_%d" % i, Vector2(x, READY_Y + 6.0), Vector2(COL_W, 20.0), 10, DIM,
			HORIZONTAL_ALIGNMENT_CENTER)

		var card := _button(Rect2(x + ARROW_W, CARD_Y, COL_W - ARROW_W * 2.0, CARD_H))
		card.mouse_entered.connect(_focus.bind(i, ROW_FIGHTER))
		card.pressed.connect(_click_card.bind(i))
		var card_left := _button(Rect2(x, CARD_Y, ARROW_W, CARD_H))
		card_left.mouse_entered.connect(_focus.bind(i, ROW_FIGHTER))
		card_left.pressed.connect(_click_arrow.bind(i, ROW_FIGHTER, -1))
		var card_right := _button(Rect2(x + COL_W - ARROW_W, CARD_Y, ARROW_W, CARD_H))
		card_right.mouse_entered.connect(_focus.bind(i, ROW_FIGHTER))
		card_right.pressed.connect(_click_arrow.bind(i, ROW_FIGHTER, 1))

		var role := _button(Rect2(x + ARROW_W, ROLE_Y, COL_W - ARROW_W * 2.0, ROLE_H))
		role.mouse_entered.connect(_focus.bind(i, ROW_ROLE))
		role.pressed.connect(_click_arrow.bind(i, ROW_ROLE, 1))
		var role_left := _button(Rect2(x, ROLE_Y, ARROW_W, ROLE_H))
		role_left.mouse_entered.connect(_focus.bind(i, ROW_ROLE))
		role_left.pressed.connect(_click_arrow.bind(i, ROW_ROLE, -1))
		var role_right := _button(Rect2(x + COL_W - ARROW_W, ROLE_Y, ARROW_W, ROLE_H))
		role_right.mouse_entered.connect(_focus.bind(i, ROW_ROLE))
		role_right.pressed.connect(_click_arrow.bind(i, ROW_ROLE, 1))

	_text("strip_kicker", Vector2(80.0, STRIP_Y + 9.0), Vector2(240.0, 18.0), 9, GOLD)
	_text("strip_name", Vector2(80.0, STRIP_Y + 22.0), Vector2(250.0, 30.0), 22, HOT)
	_text("strip_movement", Vector2(80.0, STRIP_Y + 48.0), Vector2(250.0, 18.0), 9, FAINT)
	for i in 3:
		var column := 356.0 + float(i) * 310.0
		_text("ability_name_%d" % i, Vector2(column, STRIP_Y + 13.0), Vector2(290.0, 18.0), 10, HOT)
		_text("ability_body_%d" % i, Vector2(column, STRIP_Y + 32.0), Vector2(290.0, 22.0), 12, DIM)

	_text("hint", Vector2(60.0, 638.0), Vector2(860.0, 40.0), 10, FAINT)
	_text("next", Vector2(NEXT_X, NEXT_Y + 12.0), Vector2(NEXT_W, 22.0), 12, GOLD,
		HORIZONTAL_ALIGNMENT_CENTER)
	var next_button := _button(Rect2(NEXT_X, NEXT_Y, NEXT_W, NEXT_H))
	next_button.mouse_entered.connect(func(): _focus(cursor_slot, ROW_NEXT))
	next_button.pressed.connect(_activate)

	visible = false
	_normalize()
	_refresh()


## Reopening keeps the lineup the table already built; only the cursor returns
## home, so stepping back from the rules screen costs nobody their pick.
func open() -> void:
	visible = true
	cursor_slot = 0
	row = ROW_FIGHTER
	_normalize()
	_refresh()


func close() -> void:
	visible = false


## A pad that vanishes hands its slot back rather than leaving a dead cursor.
func debug_join_device(device: int) -> void:
	if device not in _debug_pads:
		_debug_pads.append(device)
	handle_joy_button(device, JOY_BUTTON_A)


func _connected_pads() -> Array:
	var pads: Array = Input.get_connected_joypads()
	for pad: int in _debug_pads:
		if pad not in pads:
			pads.append(pad)
	return pads


func refresh_connections() -> void:
	_normalize()
	if is_node_ready():
		_refresh()


func handle_key(keycode: int) -> void:
	match keycode:
		KEY_ESCAPE:
			cancel()
		KEY_W, KEY_UP:
			_step_row(-1)
		KEY_S, KEY_DOWN:
			_step_row(1)
		KEY_A, KEY_LEFT:
			_adjust(-1)
		KEY_D, KEY_RIGHT:
			_adjust(1)
		KEY_TAB:
			_step_slot(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_SHIFT:
			_activate()


func handle_joy_button(device: int, button: int) -> void:
	var slot := _slot_for_device(device)
	if slot < 0:
		if button in [JOY_BUTTON_A, JOY_BUTTON_START]:
			_join(device)
		return
	match button:
		JOY_BUTTON_DPAD_LEFT:
			_cycle_fighter(slot, -1)
		JOY_BUTTON_DPAD_RIGHT:
			_cycle_fighter(slot, 1)
		JOY_BUTTON_A, JOY_BUTTON_START:
			if ready_slots[slot] and _can_advance():
				_confirm()
			else:
				_set_ready(slot, true)
		JOY_BUTTON_B:
			if ready_slots[slot]:
				_set_ready(slot, false)
			else:
				_release(slot)


func cancel() -> void:
	ui_accepted.emit()
	close()
	canceled.emit()


## The lineup, packed down to the seats that are actually fighting. Open slots
## leave no hole behind them, so slot three alone becomes Player 2 in play.
func build_lineup() -> Dictionary:
	var roles: Array = []
	var out_devices: Array = []
	var out_weapons: Array = []
	var out_difficulties: Array = []
	for i in MAX_SLOTS:
		if kinds[i] == SlotKind.OPEN:
			continue
		roles.append("HUMAN" if kinds[i] == SlotKind.PLAYER else "AI")
		out_devices.append(devices[i])
		out_weapons.append(weapons[i])
		out_difficulties.append(difficulties[i])
	return {
		"player_count": roles.size(),
		"roles": roles,
		"devices": out_devices,
		"weapons": out_weapons,
		"difficulties": out_difficulties,
	}


func filled_slots() -> int:
	var total := 0
	for i in MAX_SLOTS:
		if kinds[i] != SlotKind.OPEN:
			total += 1
	return total


func _slot_for_device(device: int) -> int:
	for i in MAX_SLOTS:
		if kinds[i] == SlotKind.PLAYER and devices[i] == device:
			return i
	return -1


## Devices are held by exactly one slot. The keyboard is offered first because
## it is the one input that is always present.
func _free_device() -> int:
	if _slot_for_device(KEYBOARD_DEVICE) < 0:
		return KEYBOARD_DEVICE
	for pad: int in _connected_pads():
		if _slot_for_device(pad) < 0:
			return pad
	return NO_DEVICE


## Everything derived is derived here, once: a seat nobody holds is not a
## player, a fighter outside the roster falls back to the first one, and only a
## seated human can be ready.
func _normalize() -> void:
	var connected := _connected_pads()
	for i in MAX_SLOTS:
		if weapons[i] not in ROSTER:
			weapons[i] = ROSTER[i % ROSTER.size()]
		difficulties[i] = clampi(difficulties[i], 0, DIFFICULTY_NAMES.size() - 1)
		if kinds[i] != SlotKind.PLAYER:
			devices[i] = NO_DEVICE
			ready_slots[i] = false
		elif devices[i] >= 0 and devices[i] not in connected:
			# The pad that held this seat is gone; the seat stays in the match
			# as a CPU rather than collapsing the lineup mid-decision.
			kinds[i] = SlotKind.CPU
			devices[i] = NO_DEVICE
			ready_slots[i] = false
	if filled_slots() < MIN_FIGHTERS:
		for i in MAX_SLOTS:
			if kinds[i] == SlotKind.OPEN:
				kinds[i] = SlotKind.CPU
			if filled_slots() >= MIN_FIGHTERS:
				break
	cursor_slot = clampi(cursor_slot, 0, MAX_SLOTS - 1)
	row = clampi(row, 0, ROW_TOTAL - 1)


func _role_index(slot: int) -> int:
	match kinds[slot]:
		SlotKind.PLAYER: return ROLE_PLAYER
		SlotKind.CPU: return ROLE_CPU_FIRST + difficulties[slot]
		_: return ROLE_OPEN


func _set_role(slot: int, index: int) -> void:
	if index == ROLE_OPEN:
		_release(slot)
		return
	ready_slots[slot] = false
	if index == ROLE_PLAYER:
		kinds[slot] = SlotKind.PLAYER
		if devices[slot] == NO_DEVICE:
			devices[slot] = _free_device()
	else:
		kinds[slot] = SlotKind.CPU
		devices[slot] = NO_DEVICE
		difficulties[slot] = clampi(index - ROLE_CPU_FIRST, 0, DIFFICULTY_NAMES.size() - 1)
	ui_accepted.emit()
	_normalize()
	_refresh()


func _cycle_role(slot: int, direction: int) -> void:
	if direction == 0:
		return
	var index := _role_index(slot)
	for _step in ROLE_TOTAL:
		index = posmod(index + direction, ROLE_TOTAL)
		# Emptying the last-but-one seat would leave nothing to fight, so the
		# open option is simply skipped rather than offered and refused.
		if index == ROLE_OPEN and filled_slots() <= MIN_FIGHTERS:
			continue
		_set_role(slot, index)
		return


func _cycle_fighter(slot: int, direction: int) -> void:
	if kinds[slot] == SlotKind.OPEN or ready_slots[slot] or direction == 0:
		return
	weapons[slot] = Roster.step(weapons[slot], direction)
	ui_navigated.emit()
	_refresh()


func _set_ready(slot: int, value: bool) -> void:
	if kinds[slot] != SlotKind.PLAYER or devices[slot] == NO_DEVICE \
			or ready_slots[slot] == value:
		return
	ready_slots[slot] = value
	ui_accepted.emit()
	# Committing the last fighter puts the host on the confirm bar, so the
	# screen ends where it is already looking.
	if value and _can_advance():
		cursor_slot = slot
		row = ROW_NEXT
	_refresh()


## Backing out frees the device. The seat only empties when the match can
## afford to lose it; otherwise it stays in as a CPU.
func _release(slot: int) -> void:
	kinds[slot] = SlotKind.CPU if filled_slots() <= MIN_FIGHTERS else SlotKind.OPEN
	devices[slot] = NO_DEVICE
	ready_slots[slot] = false
	ui_accepted.emit()
	_normalize()
	_refresh()


## A pad takes the first open seat, or the first human seat still waiting for a
## device — which is how the host hands a controller to a specific column.
func _join(device: int) -> void:
	var target := -1
	for i in MAX_SLOTS:
		if kinds[i] == SlotKind.PLAYER and devices[i] == NO_DEVICE:
			target = i
			break
	if target < 0:
		for i in MAX_SLOTS:
			if kinds[i] == SlotKind.OPEN:
				target = i
				break
	if target < 0:
		return
	kinds[target] = SlotKind.PLAYER
	devices[target] = device
	ready_slots[target] = false
	ui_accepted.emit()
	_normalize()
	_refresh()


func _can_advance() -> bool:
	if filled_slots() < MIN_FIGHTERS:
		return false
	for i in MAX_SLOTS:
		if kinds[i] != SlotKind.PLAYER:
			continue
		if devices[i] == NO_DEVICE or not ready_slots[i]:
			return false
	return true


func _confirm() -> void:
	if not _can_advance():
		return
	ui_accepted.emit()
	var lineup := build_lineup()
	close()
	lineup_confirmed.emit(lineup)


func _focus(slot: int, next_row: int) -> void:
	if cursor_slot == slot and row == next_row:
		return
	cursor_slot = slot
	row = next_row
	ui_navigated.emit()
	_refresh()


func _step_row(direction: int) -> void:
	row = posmod(row + direction, ROW_TOTAL)
	ui_navigated.emit()
	_refresh()


func _step_slot(direction: int) -> void:
	cursor_slot = posmod(cursor_slot + direction, MAX_SLOTS)
	if row == ROW_NEXT:
		row = ROW_FIGHTER
	ui_navigated.emit()
	_refresh()


func _adjust(direction: int) -> void:
	match row:
		ROW_FIGHTER:
			_cycle_fighter(cursor_slot, direction)
		ROW_ROLE:
			_cycle_role(cursor_slot, direction)
		ROW_NEXT:
			return


func _activate() -> void:
	match row:
		ROW_FIGHTER:
			# An empty column is filled by pressing it, so adding a bot costs
			# one press rather than a walk through the control tile.
			if kinds[cursor_slot] == SlotKind.OPEN:
				_set_role(cursor_slot, ROLE_CPU_FIRST + difficulties[cursor_slot])
			else:
				_set_ready(cursor_slot, not ready_slots[cursor_slot])
		ROW_ROLE:
			_cycle_role(cursor_slot, 1)
		ROW_NEXT:
			_confirm()


func _click_card(slot: int) -> void:
	cursor_slot = slot
	row = ROW_FIGHTER
	_activate()


func _click_arrow(slot: int, target_row: int, direction: int) -> void:
	cursor_slot = slot
	row = target_row
	_adjust(direction)


func _role_label(slot: int) -> String:
	match kinds[slot]:
		SlotKind.PLAYER:
			if devices[slot] == KEYBOARD_DEVICE:
				return "KEYBOARD + MOUSE"
			if devices[slot] >= 0:
				return "GAMEPAD %d" % (devices[slot] + 1)
			return "AWAITING A PAD"
		SlotKind.CPU:
			return "CPU · %s" % DIFFICULTY_NAMES[difficulties[slot]]
		_:
			return "OPEN SLOT"


func _ready_label(slot: int) -> String:
	match kinds[slot]:
		SlotKind.PLAYER:
			if devices[slot] == NO_DEVICE:
				return "PRESS  A  ON A PAD"
			if ready_slots[slot]:
				return "READY"
			return "ENTER TO READY" if devices[slot] == KEYBOARD_DEVICE else "A TO READY"
		SlotKind.CPU:
			return "CPU READY"
		_:
			return "PRESS  A  TO JOIN"


func _refresh() -> void:
	var filled := filled_slots()
	_write("title", "ZAWARUDO")
	_write("breadcrumb", "// PICK YOUR FIGHTERS")
	_write("tally", "%d FIGHTERS" % filled)

	var columns: Array = []
	for i in MAX_SLOTS:
		var occupied := kinds[i] != SlotKind.OPEN
		var accent: Color = ACCENTS[i] if occupied else VACANT
		var card_focused := cursor_slot == i and row == ROW_FIGHTER
		var role_focused := cursor_slot == i and row == ROW_ROLE
		var fighter: Dictionary = Roster.entry(weapons[i])
		columns.append({
			"head_rect": Rect2(COL_XS[i], HEAD_Y, COL_W, HEAD_H),
			"card_rect": Rect2(COL_XS[i], CARD_Y, COL_W, CARD_H),
			"role_rect": Rect2(COL_XS[i], ROLE_Y, COL_W, ROLE_H),
			"ready_rect": Rect2(COL_XS[i] + 40.0, READY_Y, COL_W - 80.0, READY_H),
			"accent": accent,
			"occupied": occupied,
			"portrait": Roster.portrait(weapons[i]) if occupied else null,
			"veil": 0.0 if card_focused else (0.22 if occupied else 0.86),
			"card_focused": card_focused,
			"role_focused": role_focused,
			"arrows": occupied and not ready_slots[i],
			"ready": ready_slots[i] or kinds[i] == SlotKind.CPU,
		})
		_write("head_tag_%d" % i, "PLAYER %d" % (i + 1) if occupied else "SLOT %d" % (i + 1))
		_tint("head_tag_%d" % i, accent if occupied else VACANT)
		_write("card_name_%d" % i, str(fighter["name"]) if occupied else "OPEN")
		_write("card_kit_%d" % i, str(fighter["kit"]) if occupied else "ADD A PLAYER OR A CPU")
		_tint("card_name_%d" % i, HOT if occupied else VACANT)
		_tint("card_kit_%d" % i, accent.lightened(0.25) if occupied else FAINT)
		_write("role_label_%d" % i, "CONTROL")
		_write("role_value_%d" % i, _role_label(i))
		_tint("role_value_%d" % i, HOT if occupied else Color(0.62, 0.58, 0.70))
		_write("ready_%d" % i, _ready_label(i))
		var badge_ready := ready_slots[i] or kinds[i] == SlotKind.CPU
		_tint("ready_%d" % i, INK if badge_ready else (accent if occupied else FAINT))
		# Dark text on a bright badge needs no dark offset; at this size the
		# ordinary label shadow reads as a second copy of READY.
		_shadow("ready_%d" % i, Color.TRANSPARENT if badge_ready \
			else Color(0.0, 0.0, 0.0, 0.92))

	var shown: Dictionary = Roster.entry(weapons[cursor_slot])
	var cursor_open := kinds[cursor_slot] == SlotKind.OPEN
	_write("strip_kicker", "SLOT %d" % (cursor_slot + 1) if cursor_open \
		else "PLAYER %d" % (cursor_slot + 1))
	_write("strip_name", "OPEN SLOT" if cursor_open else str(shown["name"]))
	_write("strip_movement", "NOBODY IS FIGHTING FROM HERE" if cursor_open \
		else str(shown["movement"]))
	_tint("strip_name", VACANT if cursor_open else ACCENTS[cursor_slot].lightened(0.35))
	var abilities: Array = shown["abilities"]
	for i in 3:
		_write("ability_name_%d" % i, "" if cursor_open else str(abilities[i][0]))
		_write("ability_body_%d" % i, "" if cursor_open else str(abilities[i][1]))

	var ready := _can_advance()
	_write("next", "MATCH SETUP  ›" if ready else _blocking_reason())
	_tint("next", HOT if ready else Color(0.56, 0.47, 0.28))
	_write("hint", "← / →  CHANGE   ·   ↑ / ↓  FIGHTER · CONTROL · CONTINUE   " \
		+ "·   TAB  NEXT SLOT   ·   ENTER  READY\n" \
		+ "PAD  ·   A  JOIN / READY   ·   B  BACK OUT   ·   D-PAD  CHANGE FIGHTER   " \
		+ "·   ESC  TITLE")

	_art.apply({
		"columns": columns,
		"strip_accent": VACANT if cursor_open else ACCENTS[cursor_slot],
		"next_ready": ready,
		"next_focused": row == ROW_NEXT,
	})


func _blocking_reason() -> String:
	for i in MAX_SLOTS:
		if kinds[i] == SlotKind.PLAYER and devices[i] == NO_DEVICE:
			return "PLAYER %d NEEDS A PAD" % (i + 1)
	var waiting := 0
	for i in MAX_SLOTS:
		if kinds[i] == SlotKind.PLAYER and not ready_slots[i]:
			waiting += 1
	return "%d PLAYER%s NOT READY" % [waiting, "" if waiting == 1 else "S"]


func _text(key: String, pos: Vector2, box: Vector2, font_size: int, color: Color,
		align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.position = pos
	label.size = box
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.92))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(label)
	_labels[key] = label
	return label


func _write(key: String, value: String) -> void:
	var label: Label = _labels.get(key)
	if label != null:
		label.text = value


func _tint(key: String, color: Color) -> void:
	var label: Label = _labels.get(key)
	if label != null:
		label.add_theme_color_override("font_color", color)


func _shadow(key: String, color: Color) -> void:
	var label: Label = _labels.get(key)
	if label != null:
		label.add_theme_color_override("font_shadow_color", color)


func _button(rect: Rect2) -> Button:
	var button := Button.new()
	button.position = rect.position
	button.size = rect.size
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_child(button)
	return button
