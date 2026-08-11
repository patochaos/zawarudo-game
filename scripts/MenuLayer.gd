extends CanvasLayer

## Title screen. Keyboard and mouse share the same selection/activation path so
## hovering, clicking and pressing Enter always produce identical results.

signal start_requested(vs_ai: bool, level: int, player_count: int)
signal freeplay_requested(level: int)
signal online_requested(level: int)
signal tutorial_requested
signal option_changed(key: String, value: Variant)

const ROW_PLAY := 0
const ROW_TUTORIAL := 1
const ROW_ONLINE := 2
const ROW_OPTIONS := 3
const ROW_QUIT := 4

const LOCAL_AI_WIDE := 0
const LOCAL_AI_CLOSE := 1
const LOCAL_HUMAN := 2
const LOCAL_4P_AI := 3
const LOCAL_FREEPLAY := 4
const LOCAL_BACK := 5
const ROWS := 6

const OPTION_SOUND := 0
const OPTION_HIT_FREEZE := 1
const OPTION_FLASHES := 2
const OPTION_MAXIMIZED := 3
const OPTION_TELEMETRY := 4
const OPTION_BACK := 5
const SOUND_LEVELS := [0, 25, 50, 75, 100]

enum Ruleset { ORIGINAL, CAMERA_PROTOTYPE }
enum MenuPage { MAIN, LOCAL_PLAY, WIDE_LEVELS, OPTIONS }

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
var _footer_plate: Polygon2D
var _footer_kicker: Label
var _footer: Label
var _hint: Label
var _build_label: Label
var _row_bgs: Array[Polygon2D] = []
var _row_buttons: Array[Button] = []
var _page: int = MenuPage.MAIN
var _sound_percent: int = 100
var _hit_freeze_enabled: bool = true
var _reduced_flashes: bool = false
var _maximized: bool = true
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
		var row_y := 220.0 + float(i) * 38.0
		var plate := Polygon2D.new()
		plate.position = Vector2(226.0, row_y)
		plate.polygon = PackedVector2Array([
			Vector2(18.0, 0.0), Vector2(814.0, 0.0), Vector2(792.0, 39.0), Vector2(0.0, 39.0),
		])
		plate.color = Color(0.055, 0.04, 0.09, 0.64)
		add_child(plate)
		_row_bgs.append(plate)
		_rows.append(_label(Vector2(240.0, row_y + 4.0), 800.0, 24, DIM))

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

	# Context footer: a quiet manga-caption strip that explains the highlighted
	# choice without adding another column or making every row verbose.
	_footer_plate = Polygon2D.new()
	_footer_plate.position = Vector2(226.0, 482.0)
	_footer_plate.polygon = PackedVector2Array([
		Vector2(10.0, 0.0), Vector2(814.0, 0.0), Vector2(798.0, 76.0), Vector2(0.0, 76.0),
	])
	_footer_plate.color = Color(0.035, 0.025, 0.065, 0.88)
	add_child(_footer_plate)
	var footer_rule := ColorRect.new()
	footer_rule.position = Vector2(236.0, 482.0)
	footer_rule.size = Vector2(794.0, 2.0)
	footer_rule.color = Color(0.91, 0.66, 0.22, 0.72)
	add_child(footer_rule)
	_footer_kicker = _label(Vector2(246.0, 489.0), 770.0, 11, GOLD)
	_footer_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_footer_kicker.text = "SELECTED // FIELD NOTE"
	_footer = _label(Vector2(246.0, 510.0), 770.0, 15, Color(0.76, 0.80, 0.88))
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_hint = _label(Vector2(240.0, 578.0), 800.0, 14, Color(0.42, 0.47, 0.56))
	_hint.text = "CLICK / TAP or W / S select      ENTER activate      ESC quit"
	_build_label = _label(Vector2(240.0, 645.0), 800.0, 12, Color(0.38, 0.42, 0.50))
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
	_refresh()


func configure_options(settings: Dictionary) -> void:
	_sound_percent = int(round(float(settings.get("sound", 1.0)) * 100.0))
	_hit_freeze_enabled = bool(settings.get("hit_freeze", true))
	_reduced_flashes = bool(settings.get("reduced_flashes", false))
	_maximized = bool(settings.get("maximized", true))
	_telemetry_enabled = bool(settings.get("telemetry", true))
	if is_node_ready():
		_refresh()


func close() -> void:
	visible = false


func _select(i: int) -> void:
	_cursor = posmod(i, _page_row_count())
	_refresh()


func _refresh() -> void:
	var names := _page_names()
	var visible_rows := names.size()
	if _page == MenuPage.WIDE_LEVELS and _cursor < Levels.count():
		level = _cursor
	var preview_ruleset := Ruleset.CAMERA_PROTOTYPE \
		if _page == MenuPage.LOCAL_PLAY and _cursor == LOCAL_AI_CLOSE else Ruleset.ORIGINAL
	_level_preview.show_level(level, preview_ruleset)
	match _page:
		MenuPage.LOCAL_PLAY:
			_blurb.text = "LOCAL PLAY · CHOOSE THE SHAPE OF THE FIGHT"
		MenuPage.WIDE_LEVELS:
			_blurb.text = "WIDE DUEL · CHOOSE ARENA"
		MenuPage.OPTIONS:
			_blurb.text = "OPTIONS · PLAYTEST ACCESSIBILITY"
		_:
			_blurb.text = "STOP TIME · WRITE THE MOVE · RELEASE THE CONSEQUENCE"
	_footer.text = _page_description()
	_hint.text = "CLICK / TAP or W / S select      ENTER choose      ESC back" \
		if _page != MenuPage.MAIN \
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
	if _page == MenuPage.WIDE_LEVELS:
		if row < Levels.count():
			level = row
			ruleset = Ruleset.ORIGINAL
			start_requested.emit(true, level, 2)
		else:
			_show_local_menu()
		return
	if _page == MenuPage.OPTIONS:
		if row == OPTION_BACK:
			_show_main_menu()
		else:
			_change_option(row, 1)
		return
	if _page == MenuPage.LOCAL_PLAY:
		match row:
			LOCAL_AI_WIDE:
				_page = MenuPage.WIDE_LEVELS
				_cursor = level
				_refresh()
			LOCAL_AI_CLOSE:
				ruleset = Ruleset.CAMERA_PROTOTYPE
				start_requested.emit(true, level, 2)
			LOCAL_HUMAN:
				ruleset = Ruleset.ORIGINAL
				start_requested.emit(false, level, 2)
			LOCAL_4P_AI:
				ruleset = Ruleset.ORIGINAL
				start_requested.emit(true, level, 4)
			LOCAL_FREEPLAY:
				ruleset = Ruleset.ORIGINAL
				freeplay_requested.emit(level)
			LOCAL_BACK:
				_show_main_menu()
		return
	match row:
		ROW_PLAY:
			_show_local_menu()
		ROW_TUTORIAL:
			tutorial_requested.emit()
		ROW_ONLINE:
			online_requested.emit(level)
		ROW_OPTIONS:
			_page = MenuPage.OPTIONS
			_cursor = 0
			_refresh()
		ROW_QUIT:
			get_tree().quit()


func _page_names() -> Array[String]:
	if _page == MenuPage.LOCAL_PLAY:
		return [
			"VS AI — WIDE",
			"VS AI — CLOSE",
			"VS HUMAN",
			"4 PLAYERS",
			"FREE PLAY",
			"‹  BACK",
		]
	if _page == MenuPage.WIDE_LEVELS:
		var level_names: Array[String] = []
		for i in Levels.count():
			level_names.append(Levels.build(i)["name"])
		level_names.append("‹  BACK")
		return level_names
	if _page == MenuPage.OPTIONS:
		return [
			"SOUND  %d%%" % _sound_percent,
			"HIT FREEZE  %s" % ("ON" if _hit_freeze_enabled else "OFF"),
			"FLASHES  %s" % ("REDUCED" if _reduced_flashes else "FULL"),
			"MAXIMIZED  %s" % ("ON" if _maximized else "OFF"),
			"PLAYTEST LOG  %s" % ("LOCAL" if _telemetry_enabled else "OFF"),
			"‹  BACK",
		]
	return [
		"PLAY",
		"TUTORIAL",
		"ONLINE",
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
				"Tune sound, impact feedback, flashes, window mode and playtest logs.",
				"Close ZAWARUDO and return time to the ordinary world.",
			][_cursor]
		MenuPage.LOCAL_PLAY:
			return [
				"Fight the AI across the full arena. Choose the battleground next.",
				"Fight the AI in the tighter experimental camera and fixed Knife Court.",
				"Two players share one machine and compose their plans simultaneously.",
				"One human faces three independent AI rivals in a local free-for-all.",
				"No turns and no score: move continuously and test knife behavior.",
				"Return to the title choices.",
			][_cursor]
		MenuPage.WIDE_LEVELS:
			if _cursor >= Levels.count():
				return "Return to the local play modes."
			var level_descriptions := [
				"A layered horizontal-wrap shrine with breakable stairs and a solid crown.",
				"A full-wrap vertical loop: fall through the floor and return from above.",
				"Opposed lifts and drifting pulse orbs reshape the arena while time flows.",
				"A sweeping shutter alternately seals each half of the direct firing lane.",
			]
			return level_descriptions[_cursor]
		MenuPage.OPTIONS:
			return [
				"Set the master sound level for music, throws, impacts and time effects.",
				"Add a brief freeze on impact so successful hits land with more weight.",
				"Reduce bright screen flashes while preserving gameplay information.",
				"Choose whether the desktop build opens as a maximized window.",
				"Store anonymous match events locally for playtest bug reports.",
				"Return to the title choices.",
			][_cursor]
	return ""


func _show_main_menu() -> void:
	_page = MenuPage.MAIN
	_cursor = ROW_PLAY
	_refresh()


func _show_local_menu() -> void:
	_page = MenuPage.LOCAL_PLAY
	_cursor = LOCAL_AI_WIDE
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
		OPTION_MAXIMIZED:
			_maximized = not _maximized
			option_changed.emit("maximized", _maximized)
		OPTION_TELEMETRY:
			_telemetry_enabled = not _telemetry_enabled
			option_changed.emit("telemetry", _telemetry_enabled)
	_refresh()


## Returns true when the key was consumed.
func handle_key(code: int) -> bool:
	match code:
		KEY_W, KEY_UP:
			_select(_cursor - 1)
		KEY_S, KEY_DOWN:
			_select(_cursor + 1)
		KEY_A, KEY_LEFT:
			if _page == MenuPage.WIDE_LEVELS:
				_select(_cursor - 1)
			elif _page == MenuPage.OPTIONS and _cursor != OPTION_BACK:
				_change_option(_cursor, -1)
		KEY_D, KEY_RIGHT:
			if _page == MenuPage.WIDE_LEVELS:
				_select(_cursor + 1)
			elif _page == MenuPage.OPTIONS and _cursor != OPTION_BACK:
				_change_option(_cursor, 1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_activate(_cursor)
		KEY_ESCAPE:
			if _page == MenuPage.WIDE_LEVELS:
				_show_local_menu()
			elif _page != MenuPage.MAIN:
				_show_main_menu()
			else:
				get_tree().quit()
		_:
			return false
	return true
