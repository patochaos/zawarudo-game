extends CanvasLayer

## Title screen. Keyboard and mouse share the same selection/activation path so
## hovering, clicking and pressing Enter always produce identical results.

signal start_requested(vs_ai: bool, level: int, player_count: int)
signal freeplay_requested(level: int)
signal online_requested(level: int)

const ROW_MODE_AI_A := 0
const ROW_MODE_AI_B := 1
const ROW_MODE_4P_AI := 2
const ROW_MODE_2P := 3
const ROW_FREEPLAY := 4
const ROW_HOW_TO := 5
const ROW_QUIT := 6
const ROWS := 7

enum Ruleset { ORIGINAL, CAMERA_PROTOTYPE }
enum MenuPage { MAIN, VERSION_A_LEVELS }

const DIM := Color(0.55, 0.60, 0.70)
const HOT := Color(1.0, 0.93, 0.60)
const GOLD := Color(0.91, 0.66, 0.22)
const VIOLET := Color(0.45, 0.16, 0.67)


class MangaMenuArt:
	extends Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()

	func _draw() -> void:
		# Deep offset frame and diagonal color fields create a printed-cover
		# composition while leaving the centre calm enough for menu copy.
		draw_rect(Rect2(35.0, 31.0, 1210.0, 654.0), Color(0.0, 0.0, 0.015, 0.72))
		draw_colored_polygon(PackedVector2Array([
			Vector2(0.0, 0.0), Vector2(430.0, 0.0), Vector2(250.0, 720.0), Vector2(0.0, 720.0),
		]), Color(0.31, 0.095, 0.48, 0.34))
		draw_colored_polygon(PackedVector2Array([
			Vector2(1030.0, 0.0), Vector2(1280.0, 0.0), Vector2(1280.0, 720.0), Vector2(850.0, 720.0),
		]), Color(0.68, 0.43, 0.10, 0.16))
		var origin := Vector2(1020.0, 365.0)
		for i in 19:
			var a: float = -2.2 + float(i) * 0.16
			var d := Vector2.from_angle(a)
			draw_line(origin + d * 110.0, origin + d * 430.0,
				Color(0.95, 0.70, 0.26, 0.055 + float(i % 3) * 0.015), 2.0)
		for row in 10:
			for col in 9:
				var p := Vector2(72.0 + float(col) * 25.0, 360.0 + float(row) * 24.0)
				draw_circle(p, 1.5 + float((row + col) % 2), Color(0.86, 0.58, 1.0, 0.10))
		draw_rect(Rect2(34.0, 30.0, 1210.0, 654.0), Color(0.91, 0.66, 0.22, 0.55), false, 2.0)
		draw_line(Vector2(170.0, 164.0), Vector2(1110.0, 164.0), Color(0.91, 0.66, 0.22, 0.72), 2.0)
		draw_line(Vector2(220.0, 171.0), Vector2(1060.0, 171.0), Color(0.55, 0.21, 0.75, 0.48), 1.0)


class LevelMistPreview:
	extends Control

	var _level_data: Dictionary = {}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func show_level(index: int, ruleset: int = 0) -> void:
		match ruleset:
			1: _level_data = Levels.build_prototype()
			_: _level_data = Levels.build(index)
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

var level: int = 0
var ruleset: int = Ruleset.ORIGINAL

var _bg: ColorRect
var _level_preview: LevelMistPreview
var _rows: Array[Label] = []
var _title: Label
var _blurb: Label
var _hint: Label
var _row_bgs: Array[Polygon2D] = []
var _row_buttons: Array[Button] = []
var _how_items: Array[CanvasItem] = []
var _showing_how: bool = false
var _page: int = MenuPage.MAIN


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

	_title = _label(Vector2(240.0, 96.0), 800.0, 62, Color(0.92, 0.95, 1.0))
	_title.text = "ZAWARUDO"
	_title.add_theme_color_override("font_color", Color(0.98, 0.76, 0.28))
	_title.add_theme_color_override("font_outline_color", Color(0.10, 0.02, 0.16))
	_title.add_theme_constant_override("outline_size", 8)
	_title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_title.add_theme_constant_override("shadow_offset_x", 7)
	_title.add_theme_constant_override("shadow_offset_y", 8)

	_blurb = _label(Vector2(240.0, 184.0), 800.0, 17, Color(0.52, 0.58, 0.68))
	_blurb.text = "Suspend the world · compose 0.75 seconds of movement and one knife volley\n" \
		+ "lock fate · then watch every plan collide"

	for i in ROWS:
		var row_y := 238.0 + float(i) * 43.0
		var plate := Polygon2D.new()
		plate.position = Vector2(226.0, row_y)
		plate.polygon = PackedVector2Array([
			Vector2(18.0, 0.0), Vector2(814.0, 0.0), Vector2(792.0, 39.0), Vector2(0.0, 39.0),
		])
		plate.color = Color(0.055, 0.04, 0.09, 0.64)
		add_child(plate)
		_row_bgs.append(plate)
		_rows.append(_label(Vector2(240.0, row_y + 4.0), 800.0, 28, DIM))

		var hit := Button.new()
		hit.position = Vector2(226.0, row_y)
		hit.size = Vector2(814.0, 39.0)
		hit.flat = true
		hit.focus_mode = Control.FOCUS_NONE
		hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		hit.mouse_entered.connect(_select.bind(i))
		hit.pressed.connect(_activate.bind(i))
		add_child(hit)
		_row_buttons.append(hit)

	_hint = _label(Vector2(240.0, 558.0), 800.0, 15, Color(0.42, 0.47, 0.56))
	_hint.text = "CLICK / TAP or W / S select      ENTER activate      ESC quit"

	_build_how_to()

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
	_set_how_visible(false)
	_refresh()


func close() -> void:
	visible = false


func _select(i: int) -> void:
	_cursor = posmod(i, _page_row_count())
	_refresh()


func _refresh() -> void:
	var names := _page_names()
	var visible_rows := names.size()
	if _page == MenuPage.VERSION_A_LEVELS and _cursor < Levels.count():
		level = _cursor
	var preview_ruleset := Ruleset.CAMERA_PROTOTYPE \
		if _page == MenuPage.MAIN and _cursor == ROW_MODE_AI_B else Ruleset.ORIGINAL
	_level_preview.show_level(level, preview_ruleset)
	_blurb.text = "VERSION A · CHOOSE ARENA" if _page == MenuPage.VERSION_A_LEVELS \
		else "Suspend the world · compose 0.75 seconds of movement and one knife volley\n" \
			+ "lock fate · then watch every plan collide"
	_hint.text = "CLICK / TAP or W / S select      ENTER choose      ESC back" \
		if _page == MenuPage.VERSION_A_LEVELS \
		else "CLICK / TAP or W / S select      ENTER activate      ESC quit"
	for i in ROWS:
		var row_visible := i < visible_rows
		_rows[i].visible = row_visible
		_row_bgs[i].visible = row_visible
		_row_buttons[i].visible = row_visible
		if not row_visible:
			continue
		_rows[i].text = ("▸  " + names[i] + "  ◂") if i == _cursor else names[i]
		_rows[i].add_theme_color_override("font_color", HOT if i == _cursor else DIM)
		_row_bgs[i].color = Color(0.45, 0.16, 0.67, 0.78) if i == _cursor \
			else Color(0.055, 0.04, 0.09, 0.64)


func _activate(row: int) -> void:
	_select(row)
	if _page == MenuPage.VERSION_A_LEVELS:
		if row < Levels.count():
			level = row
			ruleset = Ruleset.ORIGINAL
			start_requested.emit(true, level, 2)
		else:
			_show_main_menu()
		return
	match row:
		ROW_MODE_AI_A:
			_page = MenuPage.VERSION_A_LEVELS
			_cursor = level
			_refresh()
		ROW_MODE_AI_B:
			ruleset = Ruleset.CAMERA_PROTOTYPE
			start_requested.emit(true, level, 2)
		ROW_MODE_4P_AI:
			ruleset = Ruleset.ORIGINAL
			start_requested.emit(true, level, 4)
		ROW_MODE_2P:
			ruleset = Ruleset.ORIGINAL
			start_requested.emit(false, level, 2)
		ROW_FREEPLAY:
			ruleset = Ruleset.ORIGINAL
			freeplay_requested.emit(level)
		ROW_HOW_TO:
			_set_how_visible(true)
		ROW_QUIT:
			get_tree().quit()


func _page_names() -> Array[String]:
	if _page == MenuPage.VERSION_A_LEVELS:
		var level_names: Array[String] = []
		for i in Levels.count():
			level_names.append(Levels.build(i)["name"])
		level_names.append("‹  BACK")
		return level_names
	return [
		"VS AI (1v1) - VERSION A",
		"VS AI (1v1) - VERSION B",
		"4 PLAYERS",
		"VS HUMAN (LOCAL)",
		"FREE PLAY",
		"HOW TO PLAY",
		"QUIT",
	]


func _page_row_count() -> int:
	return Levels.count() + 1 if _page == MenuPage.VERSION_A_LEVELS else ROWS


func _show_main_menu() -> void:
	_page = MenuPage.MAIN
	_cursor = ROW_MODE_AI_A
	_refresh()


func _build_how_to() -> void:
	var panel := ColorRect.new()
	panel.position = Vector2(220.0, 188.0)
	panel.size = Vector2(840.0, 390.0)
	panel.color = Color(0.035, 0.022, 0.065, 0.97)
	add_child(panel)
	_how_items.append(panel)

	var heading := _label(Vector2(260.0, 212.0), 760.0, 34, HOT)
	heading.text = "HOW TO PLAY"
	_how_items.append(heading)

	var copy := _label(Vector2(270.0, 272.0), 740.0, 19, Color(0.78, 0.82, 0.90))
	copy.text = "PLAN  —  Pilot your ghost, aim and charge one knife volley.\n\n" \
		+ "LOCK  —  Confirm; all plans execute together for 0.75 seconds.\n\n" \
		+ "SURVIVE  —  Only knives hurt, and they persist between turns.\n\n" \
		+ "CORE  —  Claim it for full SUPER. When ready, toggle SUPER, then fire.\n" \
		+ "WIN  —  First player to land 3 hits."
	copy.size = Vector2(740.0, 240.0)
	_how_items.append(copy)

	var back := Button.new()
	back.position = Vector2(520.0, 526.0)
	back.size = Vector2(240.0, 42.0)
	back.text = "‹  BACK"
	back.focus_mode = Control.FOCUS_NONE
	back.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back.add_theme_font_size_override("font_size", 20)
	back.add_theme_color_override("font_color", HOT)
	back.add_theme_color_override("font_hover_color", Color.WHITE)
	back.pressed.connect(func(): _set_how_visible(false))
	add_child(back)
	_how_items.append(back)

	_set_how_visible(false)


func _set_how_visible(show: bool) -> void:
	_showing_how = show
	_blurb.visible = not show
	_hint.visible = not show
	for i in ROWS:
		_rows[i].visible = not show
		_row_bgs[i].visible = not show
		_row_buttons[i].visible = not show
	for item in _how_items:
		item.visible = show


## Returns true when the key was consumed.
func handle_key(code: int) -> bool:
	if _showing_how:
		if code in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_BACKSPACE]:
			_set_how_visible(false)
		return true
	match code:
		KEY_W, KEY_UP:
			_select(_cursor - 1)
		KEY_S, KEY_DOWN:
			_select(_cursor + 1)
		KEY_A, KEY_LEFT:
			if _page == MenuPage.VERSION_A_LEVELS:
				_select(_cursor - 1)
		KEY_D, KEY_RIGHT:
			if _page == MenuPage.VERSION_A_LEVELS:
				_select(_cursor + 1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_activate(_cursor)
		KEY_ESCAPE:
			if _page == MenuPage.VERSION_A_LEVELS:
				_show_main_menu()
			else:
				get_tree().quit()
		_:
			return false
	return true
