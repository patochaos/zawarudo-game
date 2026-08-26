extends CanvasLayer
class_name CharacterSelectLayer

const HUD_FONT := preload("res://assets/kenney/fonts/kenney-future-narrow.ttf")

## Shared local roster screen. A two-human duel keeps independent controls;
## modes with bots or a training dummy let P1 configure the whole formation.

signal selection_confirmed(weapons: Array)
signal canceled
signal ui_navigated
signal ui_accepted

const DUELIST := 0
## Weapon id 1 remains the retired Grenadier prototype in GameManager, but it
## is deliberately absent from the playable roster.
const DASHBLADE := 2
const CHAKRAM := 3
const SHOCK := 4
## Append-only presentation order: Broodtail is the fourth selectable fighter
## even though its stable weapon id predates the Static Witch.
const ROSTER := [DUELIST, DASHBLADE, SHOCK, CHAKRAM]
const MAX_SLOTS := 4
const DUELIST_PORTRAIT := preload("res://assets/art/portraits/duelist-portrait-intense-v2.png")
const DASHBLADE_PORTRAIT := preload("res://assets/art/portraits/dashblade-portrait-v1.png")
const CHAKRAM_PORTRAIT := preload("res://assets/art/portraits/broodtail-portrait-v1.png")
const SHOCK_PORTRAIT := preload("res://assets/art/portraits/shockwitch-portrait-v1.png")
const ACCENTS := [
	Color(0.96, 0.69, 0.18),
	Color(0.76, 0.30, 1.0),
	Color(0.18, 0.82, 0.92),
	Color(1.0, 0.32, 0.42),
]


class SelectBackdrop:
	extends Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.018, 0.010, 0.035, 0.985))
		for i in 17:
			var x := 50.0 + float(i) * 82.0
			draw_line(Vector2(x, 110.0), Vector2(x - 240.0, 720.0),
				Color(0.55, 0.20, 0.82, 0.055), 2.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(0.0, 0.0), Vector2(380.0, 0.0), Vector2(250.0, 720.0), Vector2(0.0, 720.0),
		]), Color(0.56, 0.12, 0.10, 0.13))
		draw_colored_polygon(PackedVector2Array([
			Vector2(900.0, 0.0), Vector2(1280.0, 0.0), Vector2(1280.0, 720.0), Vector2(1030.0, 720.0),
		]), Color(0.25, 0.08, 0.43, 0.18))
		draw_line(Vector2(80.0, 126.0), Vector2(1200.0, 126.0),
			Color(0.91, 0.66, 0.22, 0.58), 2.0)


class CharacterCard:
	extends Control

	var player_index: int = 0
	var weapon: int = DUELIST
	var locked: bool = false
	var active: bool = false
	var compact: bool = false
	var role: String = "HUMAN"
	var accent := Color.WHITE
	var portrait: Texture2D

	func configure(index: int, selected_weapon: int, is_locked: bool,
			slot_role: String, is_active: bool, is_compact: bool) -> void:
		player_index = index
		weapon = selected_weapon
		locked = is_locked
		role = slot_role
		active = is_active
		compact = is_compact
		accent = ACCENTS[index]
		portrait = _portrait_for(weapon)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()

	func _draw() -> void:
		if compact:
			_draw_compact()
		else:
			_draw_large()

	func _panel(width: float, height: float) -> PackedVector2Array:
		return PackedVector2Array([
			Vector2(22.0, 0.0), Vector2(width - 24.0, 0.0), Vector2(width, 24.0),
			Vector2(width, height - 24.0), Vector2(width - 24.0, height),
			Vector2(0.0, height), Vector2(0.0, 22.0),
		])

	func _draw_shell(panel: PackedVector2Array) -> void:
		var border := accent.lightened(0.22) if locked else Color(accent.r, accent.g, accent.b, 0.68)
		if active and not locked:
			border = accent.lightened(0.34)
		draw_colored_polygon(panel, Color(0.035, 0.025, 0.060, 0.96))
		draw_polyline(panel + PackedVector2Array([panel[0]]), border,
			3.0 if locked or active else 1.5, true)
		if active or locked:
			draw_rect(Rect2(8.0, 8.0, size.x - 16.0, size.y - 16.0),
				Color(accent.r, accent.g, accent.b, 0.05))

	func _draw_large() -> void:
		var panel := _panel(450.0, 462.0)
		_draw_shell(panel)
		var font := HUD_FONT
		draw_string(font, Vector2(24.0, 31.0), "PLAYER %d · %s" % [player_index + 1, role],
			HORIZONTAL_ALIGNMENT_LEFT, 230.0, 14, accent.lightened(0.28))
		draw_string(font, Vector2(260.0, 31.0), "LOCKED" if locked else "SELECTING",
			HORIZONTAL_ALIGNMENT_RIGHT, 165.0, 12,
			Color(1.0, 0.94, 0.60) if locked else Color(0.58, 0.62, 0.72))
		var portrait_rect := Rect2(55.0, 50.0, 340.0, 300.0)
		_draw_portrait(portrait_rect)
		var fighter_name := _name_for(weapon)
		var attack := _attack_for(weapon)
		var rule := _rule_for(weapon)
		draw_string(font, Vector2(24.0, 382.0), fighter_name,
			HORIZONTAL_ALIGNMENT_CENTER, 402.0, 25, Color(0.96, 0.94, 0.88))
		draw_string(font, Vector2(24.0, 410.0), attack,
			HORIZONTAL_ALIGNMENT_CENTER, 402.0, 12, accent.lightened(0.25))
		draw_string(font, Vector2(24.0, 438.0), rule,
			HORIZONTAL_ALIGNMENT_CENTER, 402.0, 12, Color(0.65, 0.69, 0.78))

	func _draw_compact() -> void:
		var panel := _panel(580.0, 210.0)
		_draw_shell(panel)
		var font := HUD_FONT
		draw_string(font, Vector2(20.0, 28.0), "P%d · %s" % [player_index + 1, role],
			HORIZONTAL_ALIGNMENT_LEFT, 210.0, 14, accent.lightened(0.28))
		draw_string(font, Vector2(392.0, 28.0), "LOCKED" if locked else ("ACTIVE" if active else "STANDBY"),
			HORIZONTAL_ALIGNMENT_RIGHT, 165.0, 11,
			Color(1.0, 0.94, 0.60) if locked else Color(0.64, 0.68, 0.78))
		var portrait_rect := Rect2(20.0, 42.0, 150.0, 150.0)
		_draw_portrait(portrait_rect)
		var fighter_name := _name_for(weapon)
		var attack := _attack_for(weapon)
		var rule := _rule_for(weapon)
		draw_string(font, Vector2(200.0, 74.0), fighter_name,
			HORIZONTAL_ALIGNMENT_LEFT, 330.0, 22, Color(0.96, 0.94, 0.88))
		draw_string(font, Vector2(200.0, 102.0), attack,
			HORIZONTAL_ALIGNMENT_LEFT, 330.0, 12, accent.lightened(0.25))
		draw_string(font, Vector2(200.0, 128.0), rule,
			HORIZONTAL_ALIGNMENT_LEFT, 330.0, 11, Color(0.65, 0.69, 0.78))

	func _draw_portrait(rect: Rect2) -> void:
		if portrait != null:
			draw_texture_rect(portrait, rect, false, Color.WHITE)
		draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.58), false, 1.5)

	func _portrait_for(value: int) -> Texture2D:
		match value:
			DASHBLADE: return DASHBLADE_PORTRAIT
			CHAKRAM: return CHAKRAM_PORTRAIT
			SHOCK: return SHOCK_PORTRAIT
			_: return DUELIST_PORTRAIT

	func _name_for(value: int) -> String:
		match value:
			DASHBLADE: return "THE VELOCITY"
			CHAKRAM: return "BROODTAIL"
			SHOCK: return "THE STATIC WITCH"
			_: return "DAGGER DUELIST"

	func _attack_for(value: int) -> String:
		match value:
			DASHBLADE: return "NO JUMP · 90% WALK · FAST FALL"
			CHAKRAM: return "HIGH + DOUBLE JUMP · 105% WALK"
			SHOCK: return "FLOATY SINGLE JUMP · 90% WALK"
			_: return "BALANCED WALK · DOUBLE JUMP"

	func _rule_for(value: int) -> String:
		match value:
			DASHBLADE: return "MOVE · CUT TO END · FRONT GUARD"
			CHAKRAM: return "FLY · HOLD · THIRD-TURN RETURN"
			SHOCK: return "FAST MOVE · RMB ADD ORB"
			_: return "CLASH · HARD RICOCHET"


var selections: Array[int] = [DUELIST, DUELIST, DUELIST, DUELIST]
var locked: Array[bool] = [false, false, false, false]
var roles: Array[String] = ["HUMAN", "HUMAN", "AI", "AI"]
var participant_count: int = 2
var roster_mode: bool = false
var independent_mode: bool = false
var owner_roles: Array[String] = ["HUMAN", "HUMAN", "AI", "AI"]
var active_slot: int = 0
var _cards: Array = []
var _left_buttons: Array[Button] = []
var _right_buttons: Array[Button] = []
var _confirm_buttons: Array[Button] = []
var _title: Label
var _subtitle: Label
var _primary_hint: Label
var _secondary_hint: Label
var _back_hint: Label


func _ready() -> void:
	layer = 15
	var backdrop := SelectBackdrop.new()
	backdrop.size = Vector2(1280.0, 720.0)
	add_child(backdrop)

	_title = _label(Vector2(140.0, 34.0), Vector2(1000.0, 62.0), 42, Color(0.98, 0.76, 0.28))
	_title.text = "CHOOSE YOUR FATE"
	_subtitle = _label(Vector2(180.0, 94.0), Vector2(920.0, 28.0), 14, Color(0.58, 0.62, 0.72))
	_title.z_index = 5
	_subtitle.z_index = 5

	for i in MAX_SLOTS:
		var card := CharacterCard.new()
		add_child(card)
		_cards.append(card)
		var left := _button(Vector2.ZERO, Vector2(44.0, 76.0), "‹")
		left.pressed.connect(_cycle.bind(i, -1))
		_left_buttons.append(left)
		var right := _button(Vector2.ZERO, Vector2(44.0, 76.0), "›")
		right.pressed.connect(_cycle.bind(i, 1))
		_right_buttons.append(right)
		var confirm := _button(Vector2.ZERO, Vector2(238.0, 42.0), "LOCK")
		confirm.pressed.connect(_confirm.bind(i))
		_confirm_buttons.append(confirm)

	_primary_hint = _label(Vector2(72.0, 650.0), Vector2(560.0, 24.0), 12, ACCENTS[0])
	_secondary_hint = _label(Vector2(648.0, 650.0), Vector2(560.0, 24.0), 12, ACCENTS[1])
	_back_hint = _label(Vector2(500.0, 690.0), Vector2(280.0, 20.0), 11, Color(0.48, 0.52, 0.62))
	_back_hint.text = "ESC / PAD B  BACK"
	visible = false
	_refresh()


func open(initial: Array = [DUELIST, DUELIST], count: int = 2,
		slot_roles: Array = ["HUMAN", "HUMAN"], independent: bool = false,
		slot_owners: Array = []) -> void:
	participant_count = clampi(count, 2, MAX_SLOTS)
	independent_mode = independent
	for i in MAX_SLOTS:
		var requested := int(initial[i]) if i < initial.size() else DUELIST
		selections[i] = requested if requested in ROSTER else DUELIST
		roles[i] = str(slot_roles[i]) if i < slot_roles.size() else "AI"
		owner_roles[i] = str(slot_owners[i]) if i < slot_owners.size() else \
			("HUMAN" if "HUMAN" in roles[i] else "AI")
		locked[i] = independent_mode and owner_roles[i] == "AI"
	roster_mode = participant_count != 2 or roles[1] != "HUMAN"
	active_slot = _first_unlocked_slot()
	visible = true
	_refresh()


func close() -> void:
	visible = false


func handle_key(keycode: Key) -> void:
	if independent_mode:
		handle_key_for_slot(_first_human_slot(), keycode)
		return
	if roster_mode:
		match keycode:
			KEY_ESCAPE:
				cancel()
			KEY_A, KEY_LEFT:
				_cycle(active_slot, -1)
			KEY_D, KEY_RIGHT:
				_cycle(active_slot, 1)
			KEY_W, KEY_UP:
				_move_active(-1)
			KEY_S, KEY_DOWN:
				_move_active(1)
			KEY_SHIFT, KEY_ENTER, KEY_KP_ENTER:
				_confirm(active_slot)
		return
	match keycode:
		KEY_ESCAPE:
			cancel()
		KEY_A:
			_cycle(0, -1)
		KEY_D:
			_cycle(0, 1)
		KEY_SHIFT:
			_confirm(0)
		KEY_LEFT:
			_cycle(1, -1)
		KEY_RIGHT:
			_cycle(1, 1)
		KEY_ENTER, KEY_KP_ENTER:
			_confirm(1)


func handle_joy_button(button: int) -> void:
	if independent_mode:
		handle_joy_button_for_slot(_first_human_slot(), button)
		return
	if button == JOY_BUTTON_B:
		cancel()
		return
	if roster_mode:
		match button:
			JOY_BUTTON_DPAD_LEFT:
				_cycle(active_slot, -1)
			JOY_BUTTON_DPAD_RIGHT:
				_cycle(active_slot, 1)
			JOY_BUTTON_DPAD_UP:
				_move_active(-1)
			JOY_BUTTON_DPAD_DOWN:
				_move_active(1)
			JOY_BUTTON_START, JOY_BUTTON_A:
				_confirm(active_slot)
		return
	match button:
		JOY_BUTTON_DPAD_LEFT:
			_cycle(1, -1)
		JOY_BUTTON_DPAD_RIGHT:
			_cycle(1, 1)
		JOY_BUTTON_START, JOY_BUTTON_A:
			_confirm(1)


func handle_key_for_slot(slot: int, keycode: Key) -> void:
	if slot < 0 or slot >= participant_count or owner_roles[slot] != "HUMAN":
		return
	match keycode:
		KEY_ESCAPE:
			cancel()
		KEY_A, KEY_LEFT:
			_cycle(slot, -1)
		KEY_D, KEY_RIGHT:
			_cycle(slot, 1)
		KEY_SHIFT, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_confirm(slot)


func handle_joy_button_for_slot(slot: int, button: int) -> void:
	if slot < 0 or slot >= participant_count or owner_roles[slot] != "HUMAN":
		return
	match button:
		JOY_BUTTON_B:
			if locked[slot]:
				_confirm(slot)
			else:
				cancel()
		JOY_BUTTON_DPAD_LEFT:
			_cycle(slot, -1)
		JOY_BUTTON_DPAD_RIGHT:
			_cycle(slot, 1)
		JOY_BUTTON_START, JOY_BUTTON_A:
			_confirm(slot)


func cancel() -> void:
	ui_accepted.emit()
	close()
	canceled.emit()


func _cycle(player: int, direction: int) -> void:
	if player < 0 or player >= participant_count or locked[player]:
		return
	if independent_mode and owner_roles[player] != "HUMAN":
		return
	active_slot = player
	var roster_index: int = ROSTER.find(selections[player])
	if roster_index < 0:
		roster_index = 0
	selections[player] = ROSTER[posmod(roster_index + direction, ROSTER.size())]
	ui_navigated.emit()
	_refresh()


func _confirm(player: int) -> void:
	if player < 0 or player >= participant_count:
		return
	if independent_mode and owner_roles[player] != "HUMAN":
		return
	active_slot = player
	if locked[player]:
		locked[player] = false
		ui_navigated.emit()
		_refresh()
		return
	locked[player] = true
	ui_accepted.emit()
	if _all_locked():
		_refresh()
		selection_confirmed.emit(selections.slice(0, participant_count))
		return
	_advance_active()
	_refresh()


func _move_active(direction: int) -> void:
	active_slot = posmod(active_slot + direction, participant_count)
	ui_navigated.emit()
	_refresh()


func _advance_active() -> void:
	for offset in range(1, participant_count + 1):
		var candidate := (active_slot + offset) % participant_count
		if not locked[candidate]:
			active_slot = candidate
			return


func _all_locked() -> bool:
	for i in participant_count:
		if not locked[i]:
			return false
	return true


func _first_human_slot() -> int:
	for i in participant_count:
		if owner_roles[i] == "HUMAN":
			return i
	return -1


func _first_unlocked_slot() -> int:
	for i in participant_count:
		if not locked[i]:
			return i
	return 0


func _refresh() -> void:
	var compact := participant_count > 2
	_subtitle.text = "TEAM ROSTER // EACH HUMAN DEVICE LOCKS ITS OWN FIGHTER" if independent_mode else \
		("LOCAL DUEL // EACH PLAYER LOCKS A FIGHTER" if not roster_mode else \
		("FREEPLAY LOADOUT // ARM PLAYER AND DUMMY" if roles[1] == "DUMMY" else \
		"BUILD THE ROSTER // CONFIGURE HUMAN AND AI FIGHTERS"))
	for i in MAX_SLOTS:
		var enabled := i < participant_count
		_cards[i].visible = enabled
		_left_buttons[i].visible = enabled
		_right_buttons[i].visible = enabled
		_confirm_buttons[i].visible = enabled
		if not enabled:
			continue
		_layout_slot(i, compact)
		_cards[i].configure(i, selections[i], locked[i], roles[i],
			(not independent_mode and roster_mode and i == active_slot) or \
			(independent_mode and owner_roles[i] == "HUMAN" and not locked[i]), compact)
		_left_buttons[i].disabled = independent_mode and owner_roles[i] != "HUMAN"
		_right_buttons[i].disabled = independent_mode and owner_roles[i] != "HUMAN"
		_confirm_buttons[i].disabled = independent_mode and owner_roles[i] != "HUMAN"
		_confirm_buttons[i].text = "CPU READY" if independent_mode and owner_roles[i] == "AI" else \
			("UNLOCK" if locked[i] else \
			("LOCK SLOT" if roster_mode else ("LEFT SHIFT  LOCK" if i == 0 else "ENTER / START  LOCK"))
			)
	if roster_mode:
		_primary_hint.position = Vector2(72.0, 650.0)
		_secondary_hint.position = Vector2(648.0, 650.0)
		_primary_hint.text = "A / D  FIGHTER     SHIFT  LOCK" if independent_mode else \
			"A / D  FIGHTER     W / S  SLOT     SHIFT  LOCK"
		_secondary_hint.text = "EACH PAD  D-PAD FIGHTER     A / START LOCK" if independent_mode else \
			"D-PAD  FIGHTER / SLOT     A / START  LOCK"
	else:
		_primary_hint.position = Vector2(92.0, 674.0)
		_secondary_hint.position = Vector2(688.0, 674.0)
		_primary_hint.text = "P1  A / D SELECT"
		_secondary_hint.text = "P2  ← / → OR D-PAD SELECT"


func _layout_slot(i: int, compact: bool) -> void:
	if not compact:
		var x := 120.0 if i == 0 else 710.0
		_cards[i].position = Vector2(x, 148.0)
		_cards[i].size = Vector2(450.0, 462.0)
		_left_buttons[i].position = Vector2(x - 50.0, 342.0)
		_left_buttons[i].size = Vector2(44.0, 76.0)
		_right_buttons[i].position = Vector2(x + 456.0, 342.0)
		_right_buttons[i].size = Vector2(44.0, 76.0)
		_confirm_buttons[i].position = Vector2(x + 106.0, 621.0)
		_confirm_buttons[i].size = Vector2(238.0, 42.0)
		return
	var column := i % 2
	var row := i / 2
	var origin := Vector2(42.0 + float(column) * 618.0, 142.0 + float(row) * 236.0)
	_cards[i].position = origin
	_cards[i].size = Vector2(580.0, 210.0)
	_left_buttons[i].position = origin + Vector2(188.0, 88.0)
	_left_buttons[i].size = Vector2(38.0, 42.0)
	_right_buttons[i].position = origin + Vector2(528.0, 88.0)
	_right_buttons[i].size = Vector2(38.0, 42.0)
	_confirm_buttons[i].position = origin + Vector2(272.0, 151.0)
	_confirm_buttons[i].size = Vector2(210.0, 35.0)


func _label(pos: Vector2, label_size: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = pos
	label.size = label_size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.01, 0.04, 0.96))
	label.add_theme_constant_override("outline_size", 3)
	add_child(label)
	return label


func _button(pos: Vector2, button_size: Vector2, text: String) -> Button:
	var button := Button.new()
	button.position = pos
	button.size = button_size
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", Color(0.94, 0.88, 0.70))
	add_child(button)
	return button
