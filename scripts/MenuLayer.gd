extends CanvasLayer

## Title screen. Keyboard and mouse share the same selection/activation path so
## hovering, clicking and pressing Enter always produce identical results.

signal start_requested(vs_ai: bool, level: int, player_count: int)
signal freeplay_requested(level: int)
signal online_requested(level: int)
signal tutorial_requested
signal character_select_requested
signal team_battle_requested
signal roster_select_requested(player_count: int, freeplay: bool)
signal configured_match_requested(config: Dictionary)
signal option_changed(key: String, value: Variant)
signal ui_navigated
signal ui_accepted

const ROW_PLAY := 0
const ROW_TUTORIAL := 1
const ROW_ONLINE := 2
const ROW_CONTROLS := 3
const ROW_OPTIONS := 4
const ROW_QUIT := 5

const ROWS := 9

const MATCH_LIFE_OPTIONS := [3, 5, 7]

const OPTION_SOUND := 0
const OPTION_HIT_FREEZE := 1
const OPTION_FLASHES := 2
const OPTION_PREVIEW_CONTRAST := 3
const OPTION_TELEMETRY := 4
const OPTION_BACK := 5
const SOUND_LEVELS := [0, 25, 50, 75, 100]

enum Ruleset { ORIGINAL, CAMERA_PROTOTYPE }
enum BattleMode { VS, TEAM_BATTLE, FREE_PLAY }
enum MenuPage { MAIN, SETUP, CONTROLS, OPTIONS }

const SETUP_MODE := 0
const SETUP_PLAYERS := 1
const SETUP_FIRST_FIGHTER := 2
## Stable ids are not presentation order: Chakram remains id 3 but is appended
## after Static Witch so it appears as the fourth roster character.
const WEAPON_ROSTER := [0, 2, 4, 3]

## Weapon selection is deliberately local-only for now. GameManager reads this
## when the selected arena starts; online and AI-controlled fighters stay on
## the established knife ruleset.
var human_weapon: int = 0

const DIM := Color(0.55, 0.60, 0.70)
const HOT := Color(1.0, 0.93, 0.60)
const GOLD := Color(0.91, 0.66, 0.22)
const VIOLET := Color(0.45, 0.16, 0.67)
const DUELIST_PORTRAIT := preload("res://assets/art/portraits/duelist-portrait-intense-v2.png")
const DASHBLADE_PORTRAIT := preload("res://assets/art/portraits/dashblade-portrait-v1.png")
const SHOCK_PORTRAIT := preload("res://assets/art/portraits/shockwitch-portrait-v1.png")
const CHAKRAM_PORTRAIT := preload("res://assets/art/portraits/broodtail-portrait-v1.png")


class MangaMenuArt:
	extends Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()

	func _draw() -> void:
		# A command dossier rather than a floating list: navigation occupies the
		# left ink field, while the selected fate is explained on the right.
		draw_rect(Rect2(34.0, 28.0, 1212.0, 660.0), Color(0.0, 0.0, 0.015, 0.78))
		draw_colored_polygon(PackedVector2Array([
			Vector2(0.0, 0.0), Vector2(690.0, 0.0), Vector2(610.0, 720.0), Vector2(0.0, 720.0),
		]), Color(0.31, 0.095, 0.48, 0.27))
		draw_colored_polygon(PackedVector2Array([
			Vector2(1120.0, 0.0), Vector2(1280.0, 0.0), Vector2(1280.0, 720.0), Vector2(920.0, 720.0),
		]), Color(0.68, 0.43, 0.10, 0.14))
		var origin := Vector2(1050.0, 360.0)
		for i in 19:
			var a: float = -2.2 + float(i) * 0.16
			var d := Vector2.from_angle(a)
			draw_line(origin + d * 110.0, origin + d * 430.0,
				Color(0.95, 0.70, 0.26, 0.055 + float(i % 3) * 0.015), 2.0)
		for row in 11:
			for col in 18:
				var p := Vector2(742.0 + float(col) * 25.0, 382.0 + float(row) * 24.0)
				draw_circle(p, 1.5 + float((row + col) % 2), Color(0.86, 0.58, 1.0, 0.10))
		draw_rect(Rect2(34.0, 28.0, 1212.0, 660.0), Color(0.91, 0.66, 0.22, 0.44), false, 1.5)
		draw_line(Vector2(70.0, 158.0), Vector2(1210.0, 158.0), Color(0.91, 0.66, 0.22, 0.68), 2.0)
		draw_line(Vector2(660.0, 176.0), Vector2(626.0, 622.0), Color(0.91, 0.66, 0.22, 0.30), 1.5)
		draw_line(Vector2(674.0, 176.0), Vector2(640.0, 622.0), Color(0.55, 0.21, 0.75, 0.38), 1.0)


class LevelMistPreview:
	extends Control

	var _level_data: Dictionary = {}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func show_level(index: int, ruleset: int = 0) -> void:
		match ruleset:
			1: _level_data = Levels.build_prototype()
			_: _level_data = Levels.build(index, 2)
		queue_redraw()

	func _draw() -> void:
		if _level_data.is_empty():
			return

		# Broad translucent echoes give the layout a soft, out-of-focus presence.
		# The sharper centre remains faint enough that menu copy always wins.
		for pf in _level_data["platforms"]:
			var rect: Rect2 = pf["rect"].intersection(Rect2(Vector2.ZERO, size))
			if rect.size.x <= 0.0 or rect.size.y <= 0.0:
				continue
			var breakable: bool = pf["hp"] >= 0
			var haze := Color(0.91, 0.66, 0.22, 0.050) if breakable \
				else Color(0.55, 0.21, 0.75, 0.044)
			draw_rect(rect.grow(18.0), Color(haze.r, haze.g, haze.b, haze.a * 0.45))
			draw_rect(rect.grow(8.0), haze)
			draw_rect(rect, Color(haze.r, haze.g, haze.b, 0.19 if breakable else 0.15))
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, minf(3.0, rect.size.y))),
				Color(0.98, 0.79, 0.38, 0.20))

		# Spawn and Core sockets communicate the level's playable rhythm without
		# turning the menu background into a second HUD.
		var spawn_colors := [
			Color(0.96, 0.69, 0.18, 0.16), Color(0.76, 0.30, 1.0, 0.16),
			Color(0.18, 0.82, 0.92, 0.16), Color(1.0, 0.32, 0.42, 0.16),
		]
		var spawns: Array = _level_data.get("spawns", [])
		for i in spawns.size():
			var p: Vector2 = spawns[i]
			var spawn_color: Color = spawn_colors[i % spawn_colors.size()]
			draw_circle(p, 25.0,
				Color(spawn_color.r, spawn_color.g, spawn_color.b, 0.025))
			draw_circle(p, 10.0, spawn_color)
		for p: Vector2 in _level_data.get("core_spawns", []):
			draw_colored_polygon(PackedVector2Array([
				p + Vector2(0.0, -8.0), p + Vector2(8.0, 0.0),
				p + Vector2(0.0, 8.0), p + Vector2(-8.0, 0.0),
			]), Color(0.92, 0.86, 0.58, 0.10))


class ArenaDossierPreview:
	extends Control

	var _level_data: Dictionary = {}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func show_level(index: int, player_count: int) -> void:
		_level_data = Levels.build(index, player_count)
		queue_redraw()

	func _draw() -> void:
		if _level_data.is_empty():
			return
		var frame := Rect2(Vector2.ZERO, size)
		draw_rect(frame, Color(0.012, 0.010, 0.026, 0.94))
		draw_rect(frame, Color(0.91, 0.66, 0.22, 0.34), false, 1.0)

		# Crop to the playable band so the thumbnail reads like a map instead of
		# wasting half its height on empty sky.
		var source := Rect2(0.0, 180.0, Levels.ARENA_W, 460.0)
		var scale_factor := minf((size.x - 16.0) / source.size.x,
			(size.y - 16.0) / source.size.y)
		var drawn_size := source.size * scale_factor
		var offset := (size - drawn_size) * 0.5
		var map_rect := Rect2(offset, drawn_size)
		draw_rect(map_rect, Color(0.09, 0.065, 0.13, 0.72))

		for platform: Dictionary in _level_data.get("platforms", []):
			var rect: Rect2 = platform["rect"].intersection(source)
			if rect.size.x <= 0.0 or rect.size.y <= 0.0:
				continue
			var local_rect := Rect2(offset + (rect.position - source.position) * scale_factor,
				rect.size * scale_factor)
			var motion: Dictionary = platform.get("motion", {})
			if not motion.is_empty():
				var travel: Vector2 = Vector2(motion.get("axis", Vector2.ZERO)) \
					* float(motion.get("travel", 0.0)) * scale_factor
				draw_line(local_rect.get_center(), local_rect.get_center() + travel,
					Color(0.18, 0.82, 0.92, 0.42), 2.0)
			var breakable := int(platform.get("hp", -1)) >= 0
			draw_rect(local_rect, Color(0.91, 0.66, 0.22, 0.92) if breakable \
				else Color(0.54, 0.31, 0.72, 0.92))

		var spawn_colors := [
			Color(0.96, 0.69, 0.18), Color(0.76, 0.30, 1.0),
			Color(0.18, 0.82, 0.92), Color(1.0, 0.32, 0.42),
		]
		for i in _level_data.get("spawns", []).size():
			var spawn: Vector2 = _level_data["spawns"][i]
			if not source.has_point(spawn):
				continue
			var at := offset + (spawn - source.position) * scale_factor
			draw_circle(at, 5.0, spawn_colors[i % spawn_colors.size()])
			draw_circle(at, 8.0, Color(spawn_colors[i % spawn_colors.size()], 0.35), false, 1.0)
		for hazard: Dictionary in _level_data.get("hazards", []):
			var home: Vector2 = hazard.get("home", Vector2.ZERO)
			if not source.has_point(home):
				continue
			var at := offset + (home - source.position) * scale_factor
			var radius := float(hazard.get("blast_radius", 0.0)) * scale_factor
			draw_circle(at, radius, Color(1.0, 0.32, 0.42, 0.10))
			draw_circle(at, radius, Color(1.0, 0.42, 0.48, 0.70), false, 1.0)

		var wrap_x := bool(_level_data.get("wrap_x", false))
		var wrap_y := bool(_level_data.get("wrap_y", false))
		if wrap_x:
			draw_line(Vector2(map_rect.position.x, map_rect.position.y + 6.0),
				Vector2(map_rect.position.x, map_rect.end.y - 6.0), Color(0.18, 0.82, 0.92), 2.0)
			draw_line(Vector2(map_rect.end.x, map_rect.position.y + 6.0),
				Vector2(map_rect.end.x, map_rect.end.y - 6.0), Color(0.18, 0.82, 0.92), 2.0)
		if wrap_y:
			draw_line(Vector2(map_rect.position.x + 8.0, map_rect.position.y),
				Vector2(map_rect.end.x - 8.0, map_rect.position.y), Color(0.18, 0.82, 0.92), 2.0)


class ControlsSheet:
	extends Control

	signal back_requested

	var p1_body: Label
	var p2_body: Label
	var super_body: Label
	var shortcut_body: Label

	func _ready() -> void:
		size = Vector2(814.0, 354.0)
		mouse_filter = Control.MOUSE_FILTER_PASS

		_add_text(Vector2(18.0, 10.0), Vector2(360.0, 24.0), 16,
			"PLAYER 1", GOLD)
		_add_text(Vector2(104.0, 13.0), Vector2(270.0, 20.0), 11,
			"KEYBOARD + MOUSE", Color(0.65, 0.69, 0.78))
		p1_body = _add_text(Vector2(18.0, 40.0), Vector2(360.0, 88.0), 13,
			"MOVE  A / D\nJUMP  SPACE\nWAIT  S\nCONFIRM  LEFT SHIFT",
			Color(0.84, 0.87, 0.94))
		_add_text(Vector2(202.0, 40.0), Vector2(180.0, 88.0), 12,
			"AIM  MOUSE\nDRAW / FIRE  LMB\nSUPER  T\nUNDO R/RMB*  ·  RESET F\n*WITCH: RMB ORB",
			Color(0.84, 0.87, 0.94))

		_add_text(Vector2(438.0, 10.0), Vector2(360.0, 24.0), 16,
			"PLAYER 2", GOLD)
		_add_text(Vector2(524.0, 13.0), Vector2(270.0, 20.0), 11,
			"CONNECTED GAMEPAD", Color(0.65, 0.69, 0.78))
		p2_body = _add_text(Vector2(438.0, 40.0), Vector2(360.0, 88.0), 13,
			"MOVE  LEFT STICK / D-PAD\nJUMP  A\nWAIT  STICK DOWN\nCONFIRM  START",
			Color(0.84, 0.87, 0.94))
		_add_text(Vector2(642.0, 40.0), Vector2(154.0, 88.0), 12,
			"AIM  RIGHT STICK\nDRAW / FIRE  R2\nFUSE  L1 / R1\nSUPER  Y\nUNDO B/SELECT · RESET X",
			Color(0.84, 0.87, 0.94))

		_add_text(Vector2(18.0, 149.0), Vector2(240.0, 22.0), 14,
			"HOW TO ACTIVATE SUPER", GOLD)
		_add_text(Vector2(20.0, 178.0), Vector2(220.0, 18.0), 12,
			"01  EARN", HOT)
		_add_text(Vector2(20.0, 197.0), Vector2(220.0, 36.0), 11,
			"Clash knives while moving,\nor collect the Temporal Core.", DIM)
		_add_text(Vector2(290.0, 178.0), Vector2(210.0, 18.0), 12,
			"02  ARM", HOT)
		_add_text(Vector2(290.0, 197.0), Vector2(210.0, 36.0), 11,
			"When the meter is full:\nP1 press T  ·  P2 press Y.", DIM)
		_add_text(Vector2(558.0, 178.0), Vector2(236.0, 18.0), 12,
			"03  DRAW + RELEASE", HOT)
		super_body = _add_text(Vector2(558.0, 197.0), Vector2(236.0, 36.0), 11,
			"Aim and fire normally. The meter\nis spent when the first wave launches.", DIM)

		shortcut_body = _add_text(Vector2(18.0, 251.0), Vector2(778.0, 64.0), 11,
			"BATTLE SETUP // P1 keyboard · first connected pad owns P2 · remaining slots become CPU\n" \
			+ "PLAYTEST  //  F8 fill P1 SUPER  ·  SHIFT + F8 fill P2 SUPER  ·  F7 activate 3-dagger volleys\n" \
			+ "GLOBAL    //  F9 restart  ·  F10 next arena  ·  M mute  ·  H control bar  ·  ESC menu",
			Color(0.72, 0.76, 0.84))

		var back := Button.new()
		back.position = Vector2(0.0, 318.0)
		back.size = Vector2(814.0, 36.0)
		back.flat = true
		back.focus_mode = Control.FOCUS_NONE
		back.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		back.pressed.connect(func(): back_requested.emit())
		add_child(back)
		var back_label := _add_text(Vector2(0.0, 323.0), Vector2(814.0, 26.0), 16,
			"‹  BACK", HOT)
		back_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		back_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()

	func _add_text(pos: Vector2, dimensions: Vector2, font_size: int,
			text: String, color: Color) -> Label:
		var label := Label.new()
		label.position = pos
		label.size = dimensions
		label.text = text
		label.add_theme_font_size_override("font_size", font_size)
		label.add_theme_color_override("font_color", color)
		label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.88))
		label.add_theme_constant_override("shadow_offset_x", 2)
		label.add_theme_constant_override("shadow_offset_y", 2)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
		return label

	func _draw() -> void:
		var panel := Color(0.035, 0.025, 0.065, 0.88)
		var border := Color(0.91, 0.66, 0.22, 0.30)
		draw_rect(Rect2(0.0, 0.0, 394.0, 132.0), panel)
		draw_rect(Rect2(420.0, 0.0, 394.0, 132.0), panel)
		draw_rect(Rect2(0.0, 0.0, 394.0, 132.0), border, false, 1.0)
		draw_rect(Rect2(420.0, 0.0, 394.0, 132.0), border, false, 1.0)
		draw_rect(Rect2(0.0, 144.0, 814.0, 98.0), Color(0.055, 0.04, 0.09, 0.90))
		draw_line(Vector2(0.0, 144.0), Vector2(814.0, 144.0), GOLD, 2.0)
		draw_line(Vector2(258.0, 174.0), Vector2(270.0, 207.0), border, 2.0)
		draw_line(Vector2(526.0, 174.0), Vector2(538.0, 207.0), border, 2.0)
		draw_rect(Rect2(0.0, 250.0, 814.0, 58.0), panel)
		draw_rect(Rect2(0.0, 318.0, 814.0, 36.0), Color(0.45, 0.16, 0.67, 0.78))

var level: int = 0
var ruleset: int = Ruleset.ORIGINAL
var match_lives: int = 5
var battle_mode: int = BattleMode.VS
var battle_player_count: int = 2
var battle_roles: Array[String] = ["HUMAN", "AI"]
var battle_devices: Array[int] = [-2, -1]
var battle_teams: Array[int] = [-1, -1]
var battle_weapons: Array = [0, 0, 0, 0]

var _bg: ColorRect
var _level_preview: LevelMistPreview
var _rows: Array[Label] = []
var _title: Label
var _blurb: Label
var _footer_plate: Polygon2D
var _footer_rule: ColorRect
var _footer_kicker: Label
var _context_title: Label
var _footer: Label
var _match_card: Label
var _portrait_preview: TextureRect
var _arena_dossier: ArenaDossierPreview
var _context_meta: Label
var _step_rail: Label
var _hint: Label
var _build_label: Label
var _controls_sheet: ControlsSheet
var _row_bgs: Array[Polygon2D] = []
var _row_buttons: Array[Button] = []
var _page: int = MenuPage.MAIN
var _sound_percent: int = 100
var _hit_freeze_enabled: bool = true
var _reduced_flashes: bool = false
var _high_contrast_previews: bool = false
var _telemetry_enabled: bool = true


func _ready() -> void:
	layer = 10

	_bg = ColorRect.new()
	_bg.size = Vector2(1280.0, 720.0)
	_bg.color = Color(0.04, 0.05, 0.08, 0.82)
	add_child(_bg)

	_level_preview = LevelMistPreview.new()
	_level_preview.size = Vector2(1280.0, 720.0)
	add_child(_level_preview)

	var art := MangaMenuArt.new()
	art.size = Vector2(1280.0, 720.0)
	add_child(art)

	_title = _label(Vector2(72.0, 48.0), 560.0, 54, Color(0.92, 0.95, 1.0))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.text = "ZAWARUDO"
	_title.add_theme_color_override("font_color", Color(0.98, 0.76, 0.28))
	_title.add_theme_color_override("font_outline_color", Color(0.10, 0.02, 0.16))
	_title.add_theme_constant_override("outline_size", 8)
	_title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_title.add_theme_constant_override("shadow_offset_x", 7)
	_title.add_theme_constant_override("shadow_offset_y", 8)

	_blurb = _label(Vector2(74.0, 116.0), 1120.0, 14, Color(0.52, 0.58, 0.68))
	_blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_blurb.text = "Suspend the world · compose 0.75 seconds of movement and one knife volley\n" \
		+ "lock fate · then watch every plan collide"
	_step_rail = _label(Vector2(706.0, 166.0), 500.0, 11, Color(0.58, 0.62, 0.72))
	_step_rail.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	for i in ROWS:
		var row_y := 184.0 + float(i) * 43.0
		var plate := Polygon2D.new()
		plate.position = Vector2(70.0, row_y)
		plate.polygon = PackedVector2Array([
			Vector2(12.0, 0.0), Vector2(540.0, 0.0), Vector2(526.0, 37.0), Vector2(0.0, 37.0),
		])
		plate.color = Color(0.055, 0.04, 0.09, 0.64)
		add_child(plate)
		_row_bgs.append(plate)
		var row_label := _label(Vector2(98.0, row_y + 4.0), 472.0, 18, DIM)
		row_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_rows.append(row_label)

		var hit := Button.new()
		hit.position = Vector2(70.0, row_y)
		hit.size = Vector2(540.0, 37.0)
		hit.flat = true
		hit.focus_mode = Control.FOCUS_NONE
		hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		hit.mouse_entered.connect(_select.bind(i))
		hit.pressed.connect(_activate.bind(i))
		add_child(hit)
		_row_buttons.append(hit)

	# Context footer: a quiet manga-caption strip that explains the highlighted
	# choice without adding another column or making every row verbose.
	_footer_plate = Polygon2D.new()
	_footer_plate.position = Vector2(706.0, 198.0)
	_footer_plate.polygon = PackedVector2Array([
		Vector2(12.0, 0.0), Vector2(500.0, 0.0), Vector2(474.0, 410.0), Vector2(0.0, 410.0),
	])
	_footer_plate.color = Color(0.035, 0.025, 0.065, 0.88)
	add_child(_footer_plate)
	_footer_rule = ColorRect.new()
	_footer_rule.position = Vector2(718.0, 198.0)
	_footer_rule.size = Vector2(474.0, 2.0)
	_footer_rule.color = Color(0.91, 0.66, 0.22, 0.72)
	add_child(_footer_rule)
	_footer_kicker = _label(Vector2(734.0, 220.0), 438.0, 11, GOLD)
	_footer_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_footer_kicker.text = "FIGHT DOSSIER // CONTEXT"
	_context_title = _label(Vector2(734.0, 251.0), 438.0, 30, HOT)
	_context_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_context_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_context_title.size.y = 40.0

	_portrait_preview = TextureRect.new()
	_portrait_preview.position = Vector2(734.0, 292.0)
	_portrait_preview.size = Vector2(182.0, 182.0)
	_portrait_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait_preview)
	_arena_dossier = ArenaDossierPreview.new()
	_arena_dossier.position = Vector2(734.0, 292.0)
	_arena_dossier.size = Vector2(438.0, 182.0)
	add_child(_arena_dossier)
	_context_meta = _label(Vector2(932.0, 292.0), 240.0, 12, Color(0.86, 0.88, 0.92))
	_context_meta.size.y = 182.0
	_context_meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_context_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_context_meta.vertical_alignment = VERTICAL_ALIGNMENT_TOP

	_match_card = _label(Vector2(734.0, 292.0), 438.0, 13, Color(0.86, 0.88, 0.92))
	_match_card.size.y = 286.0
	_match_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_match_card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_match_card.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_footer = _label(Vector2(734.0, 490.0), 438.0, 12, Color(0.62, 0.67, 0.76))
	_footer.size.y = 102.0
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer.vertical_alignment = VERTICAL_ALIGNMENT_TOP

	_controls_sheet = ControlsSheet.new()
	_controls_sheet.position = Vector2(232.0, 198.0)
	_controls_sheet.visible = false
	_controls_sheet.back_requested.connect(_close_controls)
	add_child(_controls_sheet)

	_hint = _label(Vector2(72.0, 626.0), 1136.0, 12, Color(0.48, 0.52, 0.62))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hint.text = "CLICK / TAP or W / S select      ENTER activate      ESC quit"
	_build_label = _label(Vector2(900.0, 660.0), 300.0, 11, Color(0.38, 0.42, 0.50))
	_build_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_build_label.text = "PLAYTEST %s" % str(ProjectSettings.get_setting(
		"application/config/version", "DEV"))

	_select(0)
	_refresh()


var _cursor: int = 0


func _label(pos: Vector2, w: float, size: int, col: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(w, 120.0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.92))
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 4)
	add_child(l)
	return l


func open() -> void:
	visible = true
	_page = MenuPage.MAIN
	_cursor = 0
	_rebuild_roster_assignments()
	_refresh()


func refresh_controller_assignments() -> void:
	_rebuild_roster_assignments()
	if is_node_ready() and _page == MenuPage.SETUP:
		_cursor = mini(_cursor, _page_row_count() - 1)
		_refresh()


func configure_options(settings: Dictionary) -> void:
	_sound_percent = int(round(float(settings.get("sound", 1.0)) * 100.0))
	_hit_freeze_enabled = bool(settings.get("hit_freeze", true))
	_reduced_flashes = bool(settings.get("reduced_flashes", false))
	_high_contrast_previews = bool(settings.get("high_contrast_previews", false))
	_telemetry_enabled = bool(settings.get("telemetry", true))
	if is_node_ready():
		_refresh()


func close() -> void:
	visible = false


func _select(i: int) -> void:
	var next_cursor := posmod(i, _page_row_count())
	if next_cursor != _cursor:
		ui_navigated.emit()
	_cursor = next_cursor
	_refresh()


func _refresh() -> void:
	var names := _page_names()
	var controls_open := _page == MenuPage.CONTROLS
	var visible_rows := 0 if controls_open else names.size()
	_level_preview.show_level(level, Ruleset.ORIGINAL)
	match _page:
		MenuPage.SETUP:
			_blurb.text = "LOCAL MATCH · BUILD THE WHOLE FIGHT WITHOUT LEAVING THIS SCREEN"
		MenuPage.CONTROLS:
			_blurb.text = "CONTROLS · COMPOSE THE MOVE, THEN RELEASE IT"
		MenuPage.OPTIONS:
			_blurb.text = "OPTIONS · PLAYTEST ACCESSIBILITY"
		_:
			_blurb.text = "STOP TIME · WRITE THE MOVE · RELEASE THE CONSEQUENCE"
	_refresh_context_dossier(names)
	_step_rail.text = _step_rail_text()
	_controls_sheet.visible = controls_open
	_footer_plate.visible = not controls_open
	_footer_rule.visible = not controls_open
	_footer_kicker.visible = not controls_open
	_context_title.visible = not controls_open
	_step_rail.visible = _is_setup_page()
	_footer.visible = not controls_open
	_hint.text = "ENTER / ESC return" if controls_open else ( \
		"W / S select      A / D adjust      ENTER adjust / start      ESC back" \
		if _page != MenuPage.MAIN \
		else "CLICK / TAP or W / S select      ENTER activate      ESC quit")
	for i in ROWS:
		var row_visible := i < visible_rows
		_rows[i].visible = row_visible
		_row_bgs[i].visible = row_visible
		_row_buttons[i].visible = row_visible
		if not row_visible:
			continue
		# ASCII markers remain crisp in the Web export's reduced fallback font.
		_rows[i].text = ("◆  " + names[i]) if i == _cursor else ("    " + names[i])
		_rows[i].add_theme_color_override("font_color", HOT if i == _cursor else DIM)
		_row_bgs[i].color = Color(0.35, 0.10, 0.52, 0.84) if i == _cursor \
			else Color(0.045, 0.028, 0.070, 0.74)


func _activate(row: int) -> void:
	ui_accepted.emit()
	if _page == MenuPage.CONTROLS:
		_close_controls()
		return
	_select(row)
	if _page == MenuPage.OPTIONS:
		if row == OPTION_BACK:
			_show_main_menu()
		else:
			_change_option(row, 1)
		return
	if _page == MenuPage.SETUP:
		if row == _setup_start_row():
			configured_match_requested.emit(_build_setup_config())
		else:
			_change_setup_value(row, 1)
		return
	match row:
		ROW_PLAY:
			_show_local_menu()
		ROW_TUTORIAL:
			tutorial_requested.emit()
		ROW_ONLINE:
			online_requested.emit(level)
		ROW_CONTROLS:
			_page = MenuPage.CONTROLS
			_cursor = 0
			_refresh()
		ROW_OPTIONS:
			_page = MenuPage.OPTIONS
			_cursor = 0
			_refresh()
		ROW_QUIT:
			get_tree().quit()


func _page_names() -> Array[String]:
	if _page == MenuPage.SETUP:
		var setup_rows: Array[String] = [
			"MODE  ‹  %s  ›" % _mode_name(),
			"FIGHTERS  ‹  %d  ›" % battle_player_count,
		]
		for i in battle_player_count:
			setup_rows.append(_fighter_setup_row(i))
		setup_rows.append("ARENA  ‹  %s  ›" % str(Levels.build(level)["name"]))
		setup_rows.append("MATCH LIVES  —  OFF" if battle_mode == BattleMode.FREE_PLAY else \
			"MATCH LIVES  ‹  %d  ›" % match_lives)
		setup_rows.append("START FREE PLAY" if battle_mode == BattleMode.FREE_PLAY else "START MATCH")
		return setup_rows
	if _page == MenuPage.OPTIONS:
		return [
			"SOUND  %d%%" % _sound_percent,
			"HIT FREEZE  %s" % ("ON" if _hit_freeze_enabled else "OFF"),
			"FLASHES  %s" % ("REDUCED" if _reduced_flashes else "FULL"),
			"PREVIEW CONTRAST  %s" % ("HIGH" if _high_contrast_previews else "NORMAL"),
			"PLAYTEST LOG  %s" % ("LOCAL" if _telemetry_enabled else "OFF"),
			"‹  BACK",
		]
	if _page == MenuPage.CONTROLS:
		return ["‹  BACK"]
	return [
		"PLAY",
		"TUTORIAL",
		"ONLINE",
		"CONTROLS",
		"OPTIONS",
		"QUIT",
	]


func _page_row_count() -> int:
	return _page_names().size()


func _page_description() -> String:
	match _page:
		MenuPage.MAIN:
			return [
				"Local duels, AI fights and the free-play sandbox live here.",
				"Learn movement, stamina, jumping and throwing without an opponent.",
				"Create or join a private room for a hidden-plan duel.",
				"See P1 keyboard + mouse, P2 gamepad, SUPER activation and playtest shortcuts.",
				"Tune sound, impact feedback, flashes, preview contrast and playtest logs.",
				"Close ZAWARUDO and return time to the ordinary world.",
			][_cursor]
		MenuPage.SETUP:
			if _cursor == SETUP_MODE:
				return "VS is every fighter for themselves. Team Battle shares scores. Free Play removes turns and scoring."
			if _cursor == SETUP_PLAYERS:
				return "Choose 2, 3 or 4 active fighter slots. The roster updates immediately."
			if _cursor >= SETUP_FIRST_FIGHTER and _cursor < _setup_arena_row():
				var slot := _cursor - SETUP_FIRST_FIGHTER
				return _controller_description(slot) + "  Choose this fighter's class with left or right."
			if _cursor == _setup_arena_row():
				return str(Levels.build(level, battle_player_count).get(
					"feature", "Read the suspended danger before committing."))
			if _cursor == _setup_lives_row():
				return "Free Play has no score or win condition." if battle_mode == BattleMode.FREE_PLAY else \
					"First fighter—or team—to land this many scoring hits wins."
			return "The complete match is visible now. Enter the arena when everyone is ready."
		MenuPage.OPTIONS:
			return [
				"Set the master sound level for music, throws, impacts and time effects.",
				"Add a brief freeze on impact so successful hits land with more weight.",
				"Reduce bright screen flashes while preserving gameplay information.",
				"Strengthen planning lines, labels and player-color separation.",
				"Store anonymous match events locally for playtest bug reports.",
				"Return to the title choices.",
			][_cursor]
	return ""


func _show_main_menu() -> void:
	_page = MenuPage.MAIN
	_cursor = ROW_PLAY
	_refresh()


func _close_controls() -> void:
	_page = MenuPage.MAIN
	_cursor = ROW_CONTROLS
	_refresh()


func _show_local_menu() -> void:
	_page = MenuPage.SETUP
	_cursor = SETUP_MODE
	_rebuild_roster_assignments()
	_refresh()


func _is_setup_page() -> bool:
	return _page == MenuPage.SETUP


func _step_rail_text() -> String:
	return "FOCUS A CHOICE   ·   THE DOSSIER EXPLAINS ITS EFFECT" if _is_setup_page() else ""


func _refresh_context_dossier(names: Array[String]) -> void:
	_portrait_preview.visible = false
	_arena_dossier.visible = false
	_context_meta.visible = false
	_match_card.visible = false
	_footer.visible = _page != MenuPage.CONTROLS
	_footer.position = Vector2(734.0, 490.0)
	_footer.size = Vector2(438.0, 102.0)
	_footer.text = ""
	_context_title.text = names[_cursor] if not names.is_empty() else ""
	_context_title.add_theme_font_size_override("font_size", 22 if _is_setup_page() else 30)
	_footer_kicker.text = "FIGHT DOSSIER // CONTEXT"

	if _page != MenuPage.SETUP:
		_footer.position.y = 330.0
		_footer.size.y = 250.0
		_footer.text = _page_description()
		return
	if _cursor >= SETUP_FIRST_FIGHTER and _cursor < _setup_arena_row():
		var slot := _cursor - SETUP_FIRST_FIGHTER
		var weapon := int(battle_weapons[slot])
		_footer_kicker.text = "FIGHTER DOSSIER // P%d" % (slot + 1)
		_context_title.text = _fighter_title(weapon)
		_portrait_preview.texture = _fighter_portrait(weapon)
		_portrait_preview.visible = true
		_context_meta.text = _fighter_abilities(weapon)
		_context_meta.visible = true
		_footer.text = "LORE\n%s\n\n%s" % [_fighter_lore(weapon), _fighter_control_note(slot)]
		return
	if _cursor == _setup_arena_row():
		var arena := Levels.build(level, battle_player_count)
		_footer_kicker.text = "ARENA DOSSIER // LAYOUT"
		_context_title.text = str(arena["name"])
		_arena_dossier.show_level(level, battle_player_count)
		_arena_dossier.visible = true
		var wrap := "HORIZONTAL + VERTICAL" if arena.get("wrap_y", false) else \
			("HORIZONTAL" if arena.get("wrap_x", false) else "CLOSED WALLS")
		_footer.position.y = 484.0
		_footer.size.y = 112.0
		_footer.text = "LAYOUT READ\n%s\n\nBOUNDARIES  //  %s\nGOLD = BREAKABLE   ·   CYAN = MOTION / HAZARD" % [
			str(arena.get("feature", "Read the suspended danger before committing.")), wrap]
		return

	_match_card.visible = true
	match _cursor:
		SETUP_MODE:
			_footer_kicker.text = "RULE DOSSIER // MODE"
			_context_title.text = "CHOOSE THE KIND OF FIGHT"
			_match_card.text = "VS\nEvery fighter scores for themselves. Last rival standing wins the exchange.\n\nTEAM BATTLE\nCrimson and Azure share hits. Teammates win and lose together.\n\nFREE PLAY\nNo turns, score, or victory screen. Extra slots become training dummies."
		SETUP_PLAYERS:
			_footer_kicker.text = "RULE DOSSIER // FIGHTERS"
			_context_title.text = "%d ACTIVE FIGHTERS" % battle_player_count
			_match_card.text = "2 FIGHTERS\nFast, readable duel.\n\n3 FIGHTERS\nFree-for-all pressure or uneven teams. P3 is CPU-controlled.\n\n4 FIGHTERS\nFull arena chaos or 2v2. P3 and P4 are CPU-controlled.\n\nP1 is keyboard. P2 becomes human when a gamepad is detected."
		_:
			if _cursor == _setup_lives_row():
				_footer_kicker.text = "RULE DOSSIER // MATCH LIVES"
				_context_title.text = "NO SCORE" if battle_mode == BattleMode.FREE_PLAY else \
					"FIRST TO %d HITS" % match_lives
				_match_card.text = _match_card_text() + ("\n\nFREE PLAY\nLives are disabled; practice continues until you leave." \
					if battle_mode == BattleMode.FREE_PLAY else \
					"\n\n3 LIVES  //  quick set\n5 LIVES  //  standard set\n7 LIVES  //  longer adaptation set")
			else:
				_footer_kicker.text = "MATCH DOSSIER // READY"
				_context_title.text = "ENTER THE ARENA"
				_match_card.text = _match_card_text()
				_footer.text = "All choices are locked into one match configuration. Press Enter to start; Escape returns without losing the setup."


func _fighter_portrait(value: int) -> Texture2D:
	match value:
		2: return DASHBLADE_PORTRAIT
		3: return CHAKRAM_PORTRAIT
		4: return SHOCK_PORTRAIT
		_: return DUELIST_PORTRAIT


func _fighter_title(value: int) -> String:
	match value:
		2: return "THE VELOCITY"
		3: return "BROODTAIL"
		4: return "THE STATIC WITCH"
		_: return "DAGGER DUELIST"


func _fighter_abilities(value: int) -> String:
	match value:
		2:
			return "ABILITIES\nCUT TO END\nDash through the planned line.\nLOST FRAMES\nSlow movement banks dash distance.\nFRONT GUARD\nParry shots during the dash."
		3:
			return "ABILITIES\nCHAKRAM\nOne throw follows the exact aim.\nHOLD\nWalls pin it; a midair throw also waits.\nRECALL\nIt returns on its third turn."
		4:
			return "ABILITIES\nPLASMA LANCE\nFast, direct pressure.\nSHOCK ORB\nPlace persistent field traps.\nDETONATION\nPlasma + orb redirects weapons."
		_:
			return "ABILITIES\nTWIN DAGGERS\nReliable direct volleys.\nFAN THROW\nPressure several routes.\nHARD RICOCHET\nBank steel off arena cover."


func _fighter_lore(value: int) -> String:
	match value:
		2:
			return "She surrenders every fourth step to time, then spends the stolen distance in one impossible cut."
		3:
			return "A feral arena hunter whose curled companion leaves the hand as a living blade, banks through danger, and always finds the way home."
		4:
			return "A storm-reader who leaves charged moments hanging in the arena, waiting for one spark to rewrite every trajectory."
		_:
			return "A disciplined survivor of frozen duels who trusts geometry, timing, and two blades more than prophecy."


func _fighter_control_note(slot: int) -> String:
	if battle_devices[slot] == -2:
		return "CONTROL  //  HUMAN · KEYBOARD + MOUSE"
	if battle_devices[slot] >= 0:
		return "CONTROL  //  HUMAN · CONNECTED GAMEPAD"
	if slot == 1:
		return "CONTROL  //  CPU · CONNECT A GAMEPAD TO CLAIM P2"
	return "CONTROL  //  CPU · P1 CHOOSES THIS CLASS"


func _mode_name() -> String:
	match battle_mode:
		BattleMode.TEAM_BATTLE: return "TEAM BATTLE"
		BattleMode.FREE_PLAY: return "FREE PLAY"
		_: return "VS"


func _weapon_name(value: int) -> String:
	match value:
		2: return "VELOCITY"
		3: return "BROODTAIL"
		4: return "STATIC WITCH"
		_: return "DUELIST"


func _match_card_text() -> String:
	if not _is_setup_page():
		return ""
	var lines: Array[String] = ["%s  ·  %d FIGHTERS" % [_mode_name(), battle_player_count]]
	for i in battle_player_count:
		var owner := "KEYBOARD" if battle_devices[i] == -2 else \
			("CPU" if battle_devices[i] < 0 else "GAMEPAD")
		var fighter := _weapon_name(int(battle_weapons[i]))
		var side := ""
		if battle_mode == BattleMode.TEAM_BATTLE:
			side = ("CRIMSON · " if battle_teams[i] == 0 else "AZURE · ")
		lines.append("P%d  %s%s  //  %s" % [i + 1, side, owner, fighter])
	lines.append("%s  ·  NO SCORE" % str(Levels.build(level)["name"]) \
		if battle_mode == BattleMode.FREE_PLAY else \
		"%s  ·  FIRST TO %d HITS" % [str(Levels.build(level)["name"]), match_lives])
	return "\n".join(lines)


func _fighter_setup_row(slot: int) -> String:
	var side := ""
	if battle_mode == BattleMode.TEAM_BATTLE:
		side = ("CRIMSON · " if battle_teams[slot] == 0 else "AZURE · ")
	var owner := battle_roles[slot]
	if battle_devices[slot] == -2:
		owner = "KEYBOARD"
	elif battle_devices[slot] >= 0:
		owner = "GAMEPAD"
	elif battle_roles[slot] == "AI":
		owner = "CPU"
	return "P%d  %s%s   ‹  %s  ›" % [
		slot + 1, side, owner, _weapon_name(int(battle_weapons[slot])),
	]


func _controller_description(slot: int) -> String:
	if battle_devices[slot] == -2:
		return "P1 is always human-controlled with keyboard and mouse."
	if battle_devices[slot] >= 0:
		return "A detected controller automatically owns P2 for this prototype."
	if slot == 1:
		return "No controller detected, so P2 is CPU-controlled. Connect a pad to claim this slot."
	return "Extra prototype slots are CPU-controlled; P1 chooses their classes here."


func _setup_arena_row() -> int:
	return SETUP_FIRST_FIGHTER + battle_player_count


func _setup_lives_row() -> int:
	return _setup_arena_row() + 1


func _setup_start_row() -> int:
	return _setup_arena_row() + 2


func _change_setup_value(row: int, direction: int) -> void:
	if direction == 0:
		return
	if row == SETUP_MODE:
		battle_mode = posmod(battle_mode + direction, 3)
		_rebuild_roster_assignments()
	elif row == SETUP_PLAYERS:
		battle_player_count = posmod(battle_player_count - 2 + direction, 3) + 2
		_rebuild_roster_assignments()
	elif row >= SETUP_FIRST_FIGHTER and row < _setup_arena_row():
		var slot := row - SETUP_FIRST_FIGHTER
		var current := WEAPON_ROSTER.find(int(battle_weapons[slot]))
		battle_weapons[slot] = WEAPON_ROSTER[posmod(current + direction, WEAPON_ROSTER.size())]
	elif row == _setup_arena_row():
		level = posmod(level + direction, Levels.count())
	elif row == _setup_lives_row() and battle_mode != BattleMode.FREE_PLAY:
		var current_lives := MATCH_LIFE_OPTIONS.find(match_lives)
		match_lives = MATCH_LIFE_OPTIONS[posmod(current_lives + direction, MATCH_LIFE_OPTIONS.size())]
	else:
		return
	ui_navigated.emit()
	_refresh()


func _rebuild_roster_assignments() -> void:
	var pads := Input.get_connected_joypads()
	battle_roles.clear()
	battle_devices.clear()
	battle_teams.clear()
	for i in battle_player_count:
		var role := "AI"
		var device := -1
		if i == 0:
			role = "HUMAN"
			device = -2
		elif i == 1 and not pads.is_empty():
			role = "HUMAN"
			device = int(pads[0])
		elif battle_mode == BattleMode.FREE_PLAY:
			role = "DUMMY"
		battle_roles.append(role)
		battle_devices.append(device)
		battle_teams.append(i % 2 if battle_mode == BattleMode.TEAM_BATTLE else -1)


func _build_setup_config() -> Dictionary:
	return {
		"mode": battle_mode,
		"player_count": battle_player_count,
		"roles": battle_roles.duplicate(),
		"devices": battle_devices.duplicate(),
		"teams": battle_teams.duplicate(),
		"weapons": battle_weapons.slice(0, battle_player_count),
		"level": level,
		"match_lives": match_lives,
	}


func _change_match_lives(direction: int) -> void:
	var current := MATCH_LIFE_OPTIONS.find(match_lives)
	if current < 0:
		current = MATCH_LIFE_OPTIONS.find(5)
	match_lives = MATCH_LIFE_OPTIONS[posmod(current + direction, MATCH_LIFE_OPTIONS.size())]
	ui_navigated.emit()
	_refresh()


func _change_option(row: int, direction: int) -> void:
	match row:
		OPTION_SOUND:
			var current := SOUND_LEVELS.find(_sound_percent)
			if current < 0:
				current = SOUND_LEVELS.size() - 1
			_sound_percent = SOUND_LEVELS[posmod(current + direction, SOUND_LEVELS.size())]
			option_changed.emit("sound", float(_sound_percent) / 100.0)
		OPTION_HIT_FREEZE:
			_hit_freeze_enabled = not _hit_freeze_enabled
			option_changed.emit("hit_freeze", _hit_freeze_enabled)
		OPTION_FLASHES:
			_reduced_flashes = not _reduced_flashes
			option_changed.emit("reduced_flashes", _reduced_flashes)
		OPTION_PREVIEW_CONTRAST:
			_high_contrast_previews = not _high_contrast_previews
			option_changed.emit("high_contrast_previews", _high_contrast_previews)
		OPTION_TELEMETRY:
			_telemetry_enabled = not _telemetry_enabled
			option_changed.emit("telemetry", _telemetry_enabled)
	_refresh()


## Returns true when the key was consumed.
func handle_key(code: int) -> bool:
	if _page == MenuPage.CONTROLS:
		if code in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE]:
			_close_controls()
			return true
		return false
	match code:
		KEY_W, KEY_UP:
			_select(_cursor - 1)
		KEY_S, KEY_DOWN:
			_select(_cursor + 1)
		KEY_A, KEY_LEFT:
			if _page == MenuPage.SETUP:
				_change_setup_value(_cursor, -1)
			elif _page == MenuPage.OPTIONS and _cursor != OPTION_BACK:
				_change_option(_cursor, -1)
		KEY_D, KEY_RIGHT:
			if _page == MenuPage.SETUP:
				_change_setup_value(_cursor, 1)
			elif _page == MenuPage.OPTIONS and _cursor != OPTION_BACK:
				_change_option(_cursor, 1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_activate(_cursor)
		KEY_ESCAPE:
			match _page:
				MenuPage.SETUP: _show_main_menu()
				MenuPage.OPTIONS: _show_main_menu()
				_: get_tree().quit()
		_:
			return false
	return true
