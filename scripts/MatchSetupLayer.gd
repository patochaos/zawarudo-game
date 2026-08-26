extends CanvasLayer
class_name MatchSetupLayer

## The rules screen, second and last stop before a local match. The lineup
## arrives already decided from RosterLayer; everything chosen here is a rule
## the whole table shares — the mode, the arena, and how long the match runs.
##
## The arena is picked next to a scale drawing of its actual layout, because a
## name alone never told anyone whether a level wraps or where the cover is.

signal match_confirmed(config: Dictionary)
signal canceled
signal ui_navigated
signal ui_accepted

enum BattleMode { VS, TEAM_BATTLE, FREE_PLAY }

const MODE_NAMES := ["VS", "TEAM BATTLE", "FREE PLAY"]
const MODE_NOTES := [
	"EVERY FIGHTER SCORES FOR THEMSELVES.",
	"CRIMSON AND AZURE ALTERNATE BY SLOT.",
	"NO SCORE — A SANDBOX WITH TRAINING DUMMIES.",
]
const MATCH_LIFE_OPTIONS := [3, 5, 7]
const TEAM_NAMES := ["CRIMSON", "AZURE"]
const DIFFICULTY_NAMES := ["NOVICE", "STANDARD", "RUTHLESS"]

const ROW_MODE := 0
const ROW_ARENA := 1
const ROW_LIVES := 2
const ROW_START := 3
const ROW_TOTAL := 4

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

const FRAME := Rect2(34.0, 20.0, 1212.0, 680.0)
const RULE_X := 60.0
const RULE_W := 540.0
const RULE_YS := [132.0, 218.0, 304.0]
const RULE_H := 74.0
const ARROW_W := 42.0
const LINEUP := Rect2(60.0, 404.0, 540.0, 174.0)
## 1280 x 720 scaled by 0.45, so the drawing is the arena and nothing else.
const PLAN := Rect2(640.0, 132.0, 576.0, 324.0)
const PLAN_SCALE := 0.45
const START_X := 939.0
const START_Y := 620.0
const START_W := 281.0
const START_H := 44.0
const BACK_X := 60.0
const BACK_Y := 620.0
const BACK_W := 200.0
const BACK_H := 44.0


## The arena, drawn to scale. Indestructible geometry, breakable cover, spawn
## sockets and hazards each read differently, so the shape of a level is a
## decision the player can make from the menu.
class ArenaPlan:
	extends Control

	var layout: Dictionary = {}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func show_level(index: int, player_count: int) -> void:
		layout = Levels.build(index, player_count)
		queue_redraw()

	func _draw() -> void:
		draw_rect(PLAN, Color(0.045, 0.030, 0.075, 1.0))
		if layout.is_empty():
			return
		for i in 5:
			var y := PLAN.position.y + PLAN.size.y * (float(i) + 1.0) / 6.0
			draw_line(Vector2(PLAN.position.x, y), Vector2(PLAN.end.x, y),
				Color(0.20, 0.15, 0.30, 0.35), 1.0)

		for pf: Dictionary in layout["platforms"]:
			var rect := _to_plan(pf["rect"])
			if rect.size.x <= 0.0 or rect.size.y <= 0.0:
				continue
			var breakable: bool = pf["hp"] >= 0
			var body := Color(0.62, 0.44, 0.14, 0.90) if breakable \
				else Color(0.40, 0.24, 0.58, 0.95)
			draw_rect(rect, body)
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, minf(2.0, rect.size.y))),
				Color(0.98, 0.79, 0.38, 0.85) if breakable else Color(0.74, 0.56, 0.95, 0.80))
			if pf.has("motion"):
				# A sweeping piece is drawn at both ends of its travel, because
				# where a ledge will be is part of choosing the arena.
				var travel: Vector2 = pf["motion"].get("axis", Vector2.ZERO) \
					* float(pf["motion"].get("travel", 0.0))
				draw_rect(Rect2(rect.position + travel * PLAN_SCALE, rect.size),
					Color(body.r, body.g, body.b, 0.28))

		var spawns: Array = layout.get("spawns", [])
		for i in spawns.size():
			var point := _to_plan_point(spawns[i])
			var accent: Color = ACCENTS[i % ACCENTS.size()]
			draw_circle(point, 9.0, Color(accent.r, accent.g, accent.b, 0.22))
			draw_circle(point, 4.0, accent)
		for point: Vector2 in layout.get("core_spawns", []):
			var core := _to_plan_point(point)
			draw_colored_polygon(PackedVector2Array([
				core + Vector2(0.0, -7.0), core + Vector2(7.0, 0.0),
				core + Vector2(0.0, 7.0), core + Vector2(-7.0, 0.0),
			]), Color(0.92, 0.86, 0.58, 0.75))
		for hazard: Dictionary in layout.get("hazards", []):
			var orb := _to_plan_point(hazard.get("home", Vector2.ZERO))
			draw_arc(orb, 7.0, 0.0, TAU, 18, Color(1.0, 0.42, 0.36, 0.90), 2.0)

		draw_rect(PLAN, Color(0.91, 0.66, 0.22, 0.55), false, 1.5)

	func _to_plan(rect: Rect2) -> Rect2:
		var clipped := rect.intersection(Rect2(0.0, 0.0, Levels.ARENA_W, Levels.ARENA_H))
		return Rect2(PLAN.position + clipped.position * PLAN_SCALE, clipped.size * PLAN_SCALE)

	func _to_plan_point(point: Vector2) -> Vector2:
		return PLAN.position + point * PLAN_SCALE


## Plates, borders and the confirm bar. Text stays on Labels so the Web
## export's fallback font lays out the same way it does natively.
class SetupArt:
	extends Control

	var model: Dictionary = {}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func apply(next_model: Dictionary) -> void:
		model = next_model
		queue_redraw()

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
		var focus: int = model.get("row", -1)
		for i in RULE_YS.size():
			_draw_rule(Rect2(RULE_X, RULE_YS[i], RULE_W, RULE_H), i == focus,
				bool(model.get("rule_live_%d" % i, true)))
		draw_rect(LINEUP, Color(0.062, 0.040, 0.11, 0.94))
		draw_rect(LINEUP, Color(0.24, 0.18, 0.34, 1.0), false, 1.0)
		draw_rect(Rect2(LINEUP.position, Vector2(LINEUP.size.x, 2.0)), GOLD)
		for chip: Dictionary in model.get("chips", []):
			draw_rect(chip["rect"], chip["color"])
		_draw_bar(Rect2(BACK_X, BACK_Y, BACK_W, BACK_H), false, false)
		_draw_bar(Rect2(START_X, START_Y, START_W, START_H), true, focus == ROW_START)

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
		draw_rect(FRAME, Color(0.91, 0.66, 0.22, 0.40), false, 1.5)
		draw_line(Vector2(60.0, 100.0), Vector2(1220.0, 100.0),
			Color(0.91, 0.66, 0.22, 0.62), 1.6)

	func _draw_rule(rect: Rect2, lit: bool, live: bool) -> void:
		var plate := _shear(rect, 9.0)
		draw_colored_polygon(plate, Color(0.16, 0.085, 0.26, 0.92) if lit \
			else Color(0.078, 0.050, 0.135, 0.92))
		_outline(plate, Color(0.91, 0.66, 0.22, 0.90 if lit else 0.30), 2.2 if lit else 1.0)
		if not live:
			return
		var mid := rect.position.y + rect.size.y * 0.5
		var left := rect.position.x + 26.0
		var right := rect.end.x - 26.0
		var color := HOT if lit else Color(0.48, 0.41, 0.58)
		draw_polyline(PackedVector2Array([
			Vector2(left + 7.0, mid - 9.0), Vector2(left - 4.0, mid),
			Vector2(left + 7.0, mid + 9.0),
		]), color, 2.2, true)
		draw_polyline(PackedVector2Array([
			Vector2(right - 7.0, mid - 9.0), Vector2(right + 4.0, mid),
			Vector2(right - 7.0, mid + 9.0),
		]), color, 2.2, true)

	func _draw_bar(rect: Rect2, primary: bool, lit: bool) -> void:
		var plate := _shear(rect, 10.0)
		if primary:
			draw_colored_polygon(plate, Color(0.48, 0.28, 0.06, 0.94) if lit \
				else Color(0.22, 0.13, 0.035, 0.90))
			_outline(plate, Color(0.91, 0.66, 0.22, 0.95), 2.4 if lit else 1.4)
			return
		draw_colored_polygon(plate, Color(0.085, 0.055, 0.145, 0.90))
		_outline(plate, Color(0.55, 0.42, 0.22, 0.55), 1.2)


var battle_mode: int = BattleMode.VS
var level: int = 0
var match_lives: int = 5
var row: int = ROW_MODE

var _lineup: Dictionary = {}
var _art: SetupArt
var _plan: ArenaPlan
var _labels: Dictionary = {}


func _ready() -> void:
	layer = 15
	_art = SetupArt.new()
	_art.size = Vector2(1280.0, 720.0)
	add_child(_art)
	_plan = ArenaPlan.new()
	_plan.size = Vector2(1280.0, 720.0)
	add_child(_plan)

	_text("title", Vector2(60.0, 34.0), Vector2(400.0, 40.0), 29, Color(0.96, 0.76, 0.31))
	_text("breadcrumb", Vector2(292.0, 40.0), Vector2(396.0, 24.0), 11, DIM)
	_text("tally", Vector2(760.0, 40.0), Vector2(460.0, 24.0), 10, FAINT,
		HORIZONTAL_ALIGNMENT_RIGHT)

	var labels := ["MODE", "ARENA", "MATCH LENGTH"]
	for i in RULE_YS.size():
		var y: float = RULE_YS[i]
		_text("rule_label_%d" % i, Vector2(RULE_X + 44.0, y + 12.0), Vector2(300.0, 18.0), 9,
			Color(0.69, 0.52, 0.19))
		_text("rule_value_%d" % i, Vector2(RULE_X + 42.0, y + 26.0), Vector2(RULE_W - 84.0, 30.0),
			22, HOT, HORIZONTAL_ALIGNMENT_CENTER)
		_text("rule_note_%d" % i, Vector2(RULE_X + 42.0, y + 54.0), Vector2(RULE_W - 84.0, 18.0),
			9, FAINT, HORIZONTAL_ALIGNMENT_CENTER)
		_labels["rule_label_%d" % i].text = labels[i]
		var plate := _button(Rect2(RULE_X + ARROW_W, y, RULE_W - ARROW_W * 2.0, RULE_H))
		plate.mouse_entered.connect(_focus.bind(i))
		plate.pressed.connect(_click_rule.bind(i, 1))
		var back := _button(Rect2(RULE_X, y, ARROW_W, RULE_H))
		back.mouse_entered.connect(_focus.bind(i))
		back.pressed.connect(_click_rule.bind(i, -1))
		var forward := _button(Rect2(RULE_X + RULE_W - ARROW_W, y, ARROW_W, RULE_H))
		forward.mouse_entered.connect(_focus.bind(i))
		forward.pressed.connect(_click_rule.bind(i, 1))

	_text("lineup_kicker", Vector2(LINEUP.position.x + 20.0, LINEUP.position.y + 10.0),
		Vector2(300.0, 18.0), 9, GOLD)
	for i in 4:
		var y: float = LINEUP.position.y + 34.0 + float(i) * 33.0
		_text("lineup_tag_%d" % i, Vector2(LINEUP.position.x + 34.0, y), Vector2(116.0, 22.0),
			13, HOT)
		_text("lineup_name_%d" % i, Vector2(LINEUP.position.x + 152.0, y), Vector2(200.0, 22.0),
			14, Color(0.93, 0.90, 0.97))
		_text("lineup_owner_%d" % i, Vector2(LINEUP.position.x + 340.0, y + 2.0),
			Vector2(184.0, 20.0), 9, DIM, HORIZONTAL_ALIGNMENT_RIGHT)

	_text("arena_name", Vector2(PLAN.position.x, PLAN.end.y + 12.0), Vector2(400.0, 30.0), 22, HOT)
	_text("arena_wrap", Vector2(PLAN.end.x - 260.0, PLAN.end.y + 18.0), Vector2(260.0, 22.0), 12,
		GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_text("arena_feature", Vector2(PLAN.position.x, PLAN.end.y + 44.0), Vector2(576.0, 44.0), 11,
		DIM)
	_text("plan_legend", Vector2(PLAN.position.x, PLAN.position.y - 20.0), Vector2(576.0, 18.0),
		9, FAINT, HORIZONTAL_ALIGNMENT_RIGHT)

	_text("back", Vector2(BACK_X, BACK_Y + 14.0), Vector2(BACK_W, 22.0), 12, Color(0.72, 0.62, 0.44),
		HORIZONTAL_ALIGNMENT_CENTER)
	_text("start", Vector2(START_X, START_Y + 14.0), Vector2(START_W, 22.0), 13, HOT,
		HORIZONTAL_ALIGNMENT_CENTER)
	_text("hint", Vector2(280.0, 632.0), Vector2(640.0, 20.0), 10, FAINT)

	var back_button := _button(Rect2(BACK_X, BACK_Y, BACK_W, BACK_H))
	back_button.pressed.connect(cancel)
	var start_button := _button(Rect2(START_X, START_Y, START_W, START_H))
	start_button.mouse_entered.connect(_focus.bind(ROW_START))
	start_button.pressed.connect(_start_match)

	visible = false
	_refresh()


func open(lineup: Dictionary) -> void:
	configure(lineup)
	visible = true
	row = ROW_MODE
	_refresh()


## The lineup is taken as given; this screen never edits who is fighting.
func configure(lineup: Dictionary) -> void:
	_lineup = lineup.duplicate(true)
	if is_node_ready():
		_refresh()


func close() -> void:
	visible = false


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
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_SHIFT:
			_activate()


func handle_joy_button(_device: int, button: int) -> void:
	match button:
		JOY_BUTTON_DPAD_UP:
			_step_row(-1)
		JOY_BUTTON_DPAD_DOWN:
			_step_row(1)
		JOY_BUTTON_DPAD_LEFT:
			_adjust(-1)
		JOY_BUTTON_DPAD_RIGHT:
			_adjust(1)
		JOY_BUTTON_A, JOY_BUTTON_START:
			_activate()
		JOY_BUTTON_B:
			cancel()


func cancel() -> void:
	ui_accepted.emit()
	close()
	canceled.emit()


func player_count() -> int:
	return clampi(int(_lineup.get("player_count", 2)), 2, RosterLayer.MAX_SLOTS)


## The one configuration a local match is built from: the lineup that arrived
## from the roster screen, plus every rule chosen here.
func build_config() -> Dictionary:
	var count := player_count()
	var roles: Array = []
	var teams: Array = []
	var lineup_roles: Array = _lineup.get("roles", [])
	var difficulties: Array = _lineup.get("difficulties", [])
	for i in count:
		var role: String = str(lineup_roles[i]) if i < lineup_roles.size() else "AI"
		# Free play has nothing to score, so every seat nobody holds becomes a
		# training dummy instead of a fighter that shoots back.
		if role == "AI" and battle_mode == BattleMode.FREE_PLAY:
			role = "DUMMY"
		roles.append(role)
		teams.append(i % 2 if battle_mode == BattleMode.TEAM_BATTLE else -1)
	var first_ai: int = 1
	for i in count:
		if roles[i] != "HUMAN" and i < difficulties.size():
			first_ai = int(difficulties[i])
			break
	return {
		"mode": battle_mode,
		"player_count": count,
		"roles": roles,
		"devices": _lineup.get("devices", []).duplicate(),
		"teams": teams,
		"weapons": _lineup.get("weapons", []).duplicate(),
		"level": level,
		"match_lives": match_lives,
		"difficulty": first_ai,
		"difficulties": difficulties.duplicate(),
	}


func _step_row(direction: int) -> void:
	row = posmod(row + direction, ROW_TOTAL)
	ui_navigated.emit()
	_refresh()


func _focus(next_row: int) -> void:
	if row == next_row:
		return
	row = next_row
	ui_navigated.emit()
	_refresh()


func _adjust(direction: int) -> void:
	if direction == 0:
		return
	match row:
		ROW_MODE:
			battle_mode = posmod(battle_mode + direction, MODE_NAMES.size())
		ROW_ARENA:
			level = posmod(level + direction, Levels.count())
		ROW_LIVES:
			# Free play keeps no score, so the length chip has nothing to say.
			if battle_mode == BattleMode.FREE_PLAY:
				return
			var current := MATCH_LIFE_OPTIONS.find(match_lives)
			match_lives = MATCH_LIFE_OPTIONS[posmod(current + direction,
				MATCH_LIFE_OPTIONS.size())]
		_:
			return
	ui_navigated.emit()
	_refresh()


func _activate() -> void:
	if row == ROW_START:
		_start_match()
		return
	ui_accepted.emit()
	_adjust(1)


func _click_rule(index: int, direction: int) -> void:
	row = index
	_adjust(direction)


func _start_match() -> void:
	ui_accepted.emit()
	var config := build_config()
	close()
	match_confirmed.emit(config)


func _owner_text(index: int) -> String:
	var roles: Array = _lineup.get("roles", [])
	var devices: Array = _lineup.get("devices", [])
	var difficulties: Array = _lineup.get("difficulties", [])
	if index < roles.size() and str(roles[index]) == "HUMAN":
		var device: int = int(devices[index]) if index < devices.size() else -1
		return "KEYBOARD + MOUSE" if device == -2 else "GAMEPAD %d" % (device + 1)
	if battle_mode == BattleMode.FREE_PLAY:
		return "TRAINING DUMMY"
	var skill: int = int(difficulties[index]) if index < difficulties.size() else 1
	return "CPU · %s" % DIFFICULTY_NAMES[clampi(skill, 0, DIFFICULTY_NAMES.size() - 1)]


func _refresh() -> void:
	var count := player_count()
	var free_play := battle_mode == BattleMode.FREE_PLAY
	var layout := Levels.build(level, count)
	_plan.show_level(level, count)

	_write("title", "ZAWARUDO")
	_write("breadcrumb", "// SET THE RULES")
	_write("tally", "%d FIGHTERS ON THE BOARD" % count)

	_write("rule_value_0", "%s" % MODE_NAMES[battle_mode])
	_write("rule_note_0", MODE_NOTES[battle_mode])
	_write("rule_value_1", str(layout["name"]))
	_write("rule_note_1", "%d OF %d" % [level + 1, Levels.count()])
	_write("rule_value_2", "NO SCORE" if free_play else "FIRST TO %d" % match_lives)
	_write("rule_note_2", "FREE PLAY KEEPS NO SCORE" if free_play else "")
	_tint("rule_value_2", Color(0.55, 0.51, 0.62) if free_play else HOT)

	_write("lineup_kicker", "LINEUP" if not team_mode() else "LINEUP · CRIMSON VS AZURE")
	var weapons: Array = _lineup.get("weapons", [])
	for i in 4:
		var live := i < count
		_show("lineup_tag_%d" % i, live)
		_show("lineup_name_%d" % i, live)
		_show("lineup_owner_%d" % i, live)
		if not live:
			continue
		var tag := "P%d" % (i + 1)
		if team_mode():
			tag = "P%d · %s" % [i + 1, TEAM_NAMES[i % 2]]
		_write("lineup_tag_%d" % i, tag)
		_tint("lineup_tag_%d" % i, ACCENTS[i])
		_write("lineup_name_%d" % i, Roster.full_name(int(weapons[i]) if i < weapons.size() \
			else Roster.DUELIST))
		_write("lineup_owner_%d" % i, _owner_text(i))

	_write("arena_name", str(layout["name"]))
	_write("arena_wrap", Levels.wrap_label(layout))
	_write("arena_feature", str(layout.get("feature", "")))
	_write("plan_legend", "VIOLET SOLID  ·  GOLD BREAKABLE  ·  DOTS SPAWNS")

	_write("back", "‹  BACK TO FIGHTERS")
	_write("start", "START FREE PLAY" if free_play else "START MATCH")
	_write("hint", "↑ / ↓  RULE   ·   ← / →  CHANGE   ·   ENTER  START   ·   ESC  BACK")

	var chips: Array = []
	for i in count:
		chips.append({
			"rect": Rect2(LINEUP.position.x + 20.0, LINEUP.position.y + 32.0 + float(i) * 33.0,
				5.0, 22.0),
			"color": ACCENTS[i],
		})

	_art.apply({
		"row": row,
		"chips": chips,
		"rule_live_0": true,
		"rule_live_1": true,
		"rule_live_2": not free_play,
	})


func team_mode() -> bool:
	return battle_mode == BattleMode.TEAM_BATTLE


func _text(key: String, pos: Vector2, box: Vector2, font_size: int, color: Color,
		align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.position = pos
	label.size = box
	label.horizontal_alignment = align
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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


func _show(key: String, value: bool) -> void:
	var label: Label = _labels.get(key)
	if label != null:
		label.visible = value


func _button(rect: Rect2) -> Button:
	var button := Button.new()
	button.position = rect.position
	button.size = rect.size
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_child(button)
	return button
