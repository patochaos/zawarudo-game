extends CanvasLayer

## Title screen. Keyboard and mouse share the same selection/activation path so
## hovering, clicking and pressing Enter always produce identical results.
##
## Everything about a local match — the lineup on RosterLayer, then the rules and
## arena on MatchSetupLayer — is decided elsewhere. This screen only chooses which
## destination to open.

signal roster_requested
signal binding_changed(action: String, codes: Array)
signal bindings_reset
signal online_requested
signal tutorial_requested
signal option_changed(key: String, value: Variant)
signal ui_navigated
signal ui_accepted

const ROW_PLAY := 0
const ROW_TUTORIAL := 1
const ROW_ONLINE := 2
const ROW_CONTROLS := 3
const ROW_OPTIONS := 4
const ROW_QUIT := 5

## Enough physical rows for the longest page, which is the binding list.
const ROWS := 11

const OPTION_DISPLAY := 0
const OPTION_SFX := 1
const OPTION_VOICE := 2
const OPTION_HIT_FREEZE := 3
const OPTION_FLASHES := 4
const OPTION_PREVIEW_CONTRAST := 5
const OPTION_TELEMETRY := 6
const OPTION_BACK := 7
const SOUND_LEVELS := [0, 25, 50, 75, 100]
const DISPLAY_NAMES := [
	"WINDOW  1280 x 720", "WINDOW  1600 x 900", "WINDOW  1920 x 1080",
	"MAXIMIZED", "FULLSCREEN",
]

enum MenuPage { MAIN, CONTROLS, OPTIONS, BINDINGS }

## Player 1's rebindable actions, in the order they are listed. Aim and firing
## live on the mouse and are not part of this list.
const BINDABLE := [
	["left", "MOVE LEFT"],
	["right", "MOVE RIGHT"],
	["jump", "JUMP"],
	["wait", "WAIT"],
	["aim_up", "AIM UP"],
	["aim_down", "AIM DOWN"],
	["super", "SUPER"],
	["rollback", "UNDO"],
	["reset", "RESET PLAN"],
]
const BINDING_RESET_ROW := 9
const BINDING_BACK_ROW := 10

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

	func show_level(index: int) -> void:
		_level_data = Levels.build(index, 2)
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


class ControlsSheet:
	extends Control

	signal back_requested
	const PROMPTS := preload("res://scripts/InputPrompts.gd")
	signal rebind_requested

	var p1_body: Label
	var p2_body: Label
	var super_body: Label
	var shortcut_body: Label
	var bindings: Dictionary = {}

	func _ready() -> void:
		size = Vector2(814.0, 354.0)
		mouse_filter = Control.MOUSE_FILTER_PASS

		_add_text(Vector2(18.0, 10.0), Vector2(360.0, 24.0), 16,
			"PLAYER 1", GOLD)
		_add_text(Vector2(104.0, 13.0), Vector2(270.0, 20.0), 11,
			"KEYBOARD + MOUSE", Color(0.65, 0.69, 0.78))
		p1_body = _add_text(Vector2(18.0, 40.0), Vector2(360.0, 88.0), 10, "",
			Color(0.84, 0.87, 0.94))

		_add_text(Vector2(438.0, 10.0), Vector2(360.0, 24.0), 16,
			"PLAYER 2", GOLD)
		_add_text(Vector2(524.0, 13.0), Vector2(270.0, 20.0), 11,
			"CONNECTED GAMEPAD", Color(0.65, 0.69, 0.78))
		p2_body = _add_text(Vector2(438.0, 40.0), Vector2(360.0, 88.0), 10, "",
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
			"ROSTER    //  P1 owns the keyboard · a pad presses A to take an open slot · any slot can be a CPU\n" \
			+ "PLAYTEST  //  F8 fill P1 SUPER  ·  SHIFT + F8 fill P2 SUPER  ·  F7 activate 3-dagger volleys\n" \
			+ "GLOBAL    //  F9 restart  ·  F10 next arena  ·  M mute  ·  H control bar  ·  ESC menu",
			Color(0.72, 0.76, 0.84))

		var rebind := Button.new()
		rebind.position = Vector2(0.0, 318.0)
		rebind.size = Vector2(407.0, 36.0)
		rebind.flat = true
		rebind.focus_mode = Control.FOCUS_NONE
		rebind.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		rebind.pressed.connect(func(): rebind_requested.emit())
		add_child(rebind)
		var rebind_label := _add_text(Vector2(0.0, 323.0), Vector2(407.0, 26.0), 16,
			"REBIND KEYS", HOT)
		rebind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rebind_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var back := Button.new()
		back.position = Vector2(407.0, 318.0)
		back.size = Vector2(407.0, 36.0)
		back.flat = true
		back.focus_mode = Control.FOCUS_NONE
		back.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		back.pressed.connect(func(): back_requested.emit())
		add_child(back)
		var back_label := _add_text(Vector2(407.0, 323.0), Vector2(407.0, 26.0), 16,
			"‹  BACK", HOT)
		back_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		back_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()

	func show_bindings(next_bindings: Dictionary) -> void:
		bindings = next_bindings.duplicate(true)
		p1_body.text = ""
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
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
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
		draw_line(Vector2(194.0, 38.0), Vector2(194.0, 124.0),
			Color(border.r, border.g, border.b, 0.52), 1.0)
		draw_line(Vector2(614.0, 38.0), Vector2(614.0, 124.0),
			Color(border.r, border.g, border.b, 0.52), 1.0)
		var prompt_color := Color(0.90, 0.92, 1.0, 0.94)
		_draw_binding_row("MOVE", ["left", "right"], [&"key_a", &"key_d"],
			Vector2(18.0, 40.0), prompt_color)
		_draw_binding_row("JUMP", ["jump"], [&"key_space"],
			Vector2(18.0, 61.0), prompt_color)
		_draw_binding_row("WAIT", ["wait"], [&"key_s"],
			Vector2(18.0, 82.0), prompt_color)
		_draw_prompt_row("LOCK", [&"key_shift"], Vector2(18.0, 103.0), prompt_color)
		_draw_prompt_row("AIM", [&"mouse_move"], Vector2(204.0, 40.0), prompt_color, 44.0)
		_draw_prompt_row("DRAW", [&"mouse_left"], Vector2(204.0, 61.0), prompt_color, 44.0)
		_draw_binding_row("SUPER", ["super"], [&"key_t"],
			Vector2(204.0, 82.0), prompt_color, 44.0)
		_draw_binding_row("UNDO", ["rollback"], [&"key_r"],
			Vector2(204.0, 103.0), prompt_color, 44.0)
		PROMPTS.draw_sequence(self, [&"mouse_right"], Vector2(269.0, 103.0), prompt_color, 18.0)
		_draw_prompt_row("MOVE", [&"pad_left"], Vector2(438.0, 40.0), prompt_color)
		_draw_prompt_row("JUMP", [&"pad_a"], Vector2(438.0, 61.0), prompt_color)
		_draw_prompt_row("WAIT", [&"pad_left_down"], Vector2(438.0, 82.0), prompt_color)
		_draw_prompt_row("LOCK", [&"pad_menu"], Vector2(438.0, 103.0), prompt_color)
		_draw_prompt_row("AIM", [&"pad_right"], Vector2(624.0, 40.0), prompt_color, 44.0)
		_draw_prompt_row("DRAW", [&"pad_rt"], Vector2(624.0, 61.0), prompt_color, 44.0)
		_draw_prompt_row("FUSE", [&"pad_lb", &"pad_rb"], Vector2(624.0, 82.0), prompt_color, 44.0)
		_draw_prompt_row("SUPER", [&"pad_y"], Vector2(624.0, 103.0), prompt_color, 44.0)
		draw_rect(Rect2(0.0, 144.0, 814.0, 98.0), Color(0.055, 0.04, 0.09, 0.90))
		draw_line(Vector2(0.0, 144.0), Vector2(814.0, 144.0), GOLD, 2.0)
		draw_line(Vector2(258.0, 174.0), Vector2(270.0, 207.0), border, 2.0)
		draw_line(Vector2(526.0, 174.0), Vector2(538.0, 207.0), border, 2.0)
		draw_rect(Rect2(0.0, 250.0, 814.0, 58.0), panel)
		draw_rect(Rect2(0.0, 318.0, 403.0, 36.0), Color(0.30, 0.14, 0.46, 0.86))
		draw_rect(Rect2(407.0, 318.0, 407.0, 36.0), Color(0.45, 0.16, 0.67, 0.78))

	func _draw_prompt_row(label: String, ids: Array, origin: Vector2,
			color: Color, label_width: float = 52.0) -> void:
		draw_string(PROMPTS.HUD_FONT, origin + Vector2(0.0, 14.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, label_width, 10, Color(color.r, color.g, color.b, 0.72))
		PROMPTS.draw_sequence(self, ids, origin + Vector2(label_width, 0.0), color, 18.0, 3.0)

	func _draw_binding_row(label: String, actions: Array, fallback_ids: Array,
			origin: Vector2, color: Color, label_width: float = 52.0) -> void:
		draw_string(PROMPTS.HUD_FONT, origin + Vector2(0.0, 14.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, label_width, 10, Color(color.r, color.g, color.b, 0.72))
		var codes: Array = []
		for action in actions:
			codes.append_array(Array(bindings.get(action, [])))
		if codes.is_empty():
			PROMPTS.draw_sequence(self, fallback_ids, origin + Vector2(label_width, 0.0),
				color, 18.0, 3.0)
		else:
			PROMPTS.draw_key_sequence(self, codes, origin + Vector2(label_width, 0.0),
				color, 18.0, 3.0)

## Decorative only: which arena's mist drifts behind the title. The match's real
## arena is chosen on the roster screen.
var backdrop_level: int = 0

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
var _hint: Label
var _build_label: Label
var _controls_sheet: ControlsSheet
var _row_bgs: Array[Polygon2D] = []
var _row_buttons: Array[Button] = []
var _page: int = MenuPage.MAIN
## Which binding row is waiting for a key, or -1 when nothing is listening.
var _binding_row: int = -1
var _bindings: Dictionary = {}
var _sfx_percent: int = 100
var _voice_percent: int = 100
var _display_preset: int = 3
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

	for i in ROWS:
		var row_y := 184.0 + float(i) * 43.0
		var plate := Polygon2D.new()
		plate.position = Vector2(70.0, row_y)
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
		Vector2(12.0, 0.0), Vector2(500.0, 0.0), Vector2(488.0, 190.0), Vector2(0.0, 190.0),
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
	_footer_kicker.text = "COMMAND // SELECT"
	_context_title = _label(Vector2(734.0, 248.0), 438.0, 30, HOT)
	_context_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_context_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_context_title.size.y = 56.0

	_footer = _label(Vector2(734.0, 312.0), 438.0, 12, Color(0.62, 0.67, 0.76))
	_footer.size.y = 72.0
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer.vertical_alignment = VERTICAL_ALIGNMENT_TOP

	_controls_sheet = ControlsSheet.new()
	_controls_sheet.position = Vector2(232.0, 198.0)
	_controls_sheet.visible = false
	_controls_sheet.back_requested.connect(_close_controls)
	_controls_sheet.rebind_requested.connect(_open_bindings)
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
	# A shadow has to read as depth, not as a second copy of the word. At the
	# 11-16px sizes this helper is used at, a 3x4 offset is a third of the glyph
	# height and every menu row rendered doubled. The 31px title keeps its own.
	l.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.92))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	add_child(l)
	return l


func open() -> void:
	visible = true
	_page = MenuPage.MAIN
	_cursor = 0
	_refresh()


## Bindings are owned by the match, not by this screen; it only shows them and
## reports the key the player pressed.
func configure_bindings(bindings: Dictionary) -> void:
	_bindings = bindings.duplicate(true)
	if is_node_ready():
		_controls_sheet.show_bindings(_bindings)
		_refresh()


func _keys_text(action: String) -> String:
	var codes: Array = _bindings.get(action, [])
	if codes.is_empty():
		return "—"
	var names: Array[String] = []
	for code in codes:
		names.append(OS.get_keycode_string(int(code)).to_upper())
	return " / ".join(names)


func _open_bindings() -> void:
	ui_accepted.emit()
	_page = MenuPage.BINDINGS
	_cursor = 0
	_binding_row = -1
	_refresh()


func configure_options(settings: Dictionary) -> void:
	_sfx_percent = int(round(float(settings.get("sfx", 1.0)) * 100.0))
	_voice_percent = int(round(float(settings.get("voice", 1.0)) * 100.0))
	_display_preset = clampi(int(settings.get("display", 3)), 0, DISPLAY_NAMES.size() - 1)
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
	# Pages differ in length, so a cursor carried across one can outrun the
	# rows it now has to index.
	_cursor = clampi(_cursor, 0, maxi(names.size() - 1, 0))
	var controls_open := _page == MenuPage.CONTROLS
	_level_preview.show_level(backdrop_level)
	match _page:
		MenuPage.CONTROLS:
			_blurb.text = "CONTROLS · COMPOSE THE MOVE, THEN RELEASE IT"
		MenuPage.OPTIONS:
			_blurb.text = "OPTIONS · DISPLAY, SOUND AND ACCESSIBILITY"
		MenuPage.BINDINGS:
			_blurb.text = "CONTROLS · PLAYER 1 KEYS"
		_:
			_blurb.text = "STOP TIME · WRITE THE MOVE · RELEASE THE CONSEQUENCE"
	# The panel names whatever the cursor is on; only Options is an options list.
	_footer_kicker.text = "OPTIONS // DISPLAY, SOUND, ACCESSIBILITY" if _page == MenuPage.OPTIONS \
		else ("CONTROLS // PLAYER 1 KEYS" if _page == MenuPage.BINDINGS else "COMMAND // SELECT")
	_context_title.add_theme_font_size_override("font_size",
		30 if _page == MenuPage.MAIN else 20)
	_context_title.text = names[_cursor] if not names.is_empty() else ""
	_footer.text = _page_description()
	_controls_sheet.visible = controls_open
	_footer_plate.visible = not controls_open
	_footer_rule.visible = not controls_open
	_footer_kicker.visible = not controls_open
	_context_title.visible = not controls_open
	_footer.visible = not controls_open
	_hint.text = "ENTER / ESC return" if controls_open else ( \
		"W / S select      ENTER rebind      ESC back" if _page == MenuPage.BINDINGS \
		else ("W / S select      A / D adjust      ENTER adjust      ESC back" \
		if _page != MenuPage.MAIN \
		else "CLICK / TAP or W / S select      ENTER activate      ESC quit"))
	var pitch := 43.0 if names.size() <= 8 else 36.0
	var plate_h := pitch - 6.0
	var font_size := 18 if names.size() <= 8 else 15
	for slot in ROWS:
		var row_visible := not controls_open and slot < names.size()
		_rows[slot].visible = row_visible
		_row_bgs[slot].visible = row_visible
		_row_buttons[slot].visible = row_visible
		if not row_visible:
			continue
		var row_y := 184.0 + float(slot) * pitch
		_row_bgs[slot].position = Vector2(70.0, row_y)
		_row_bgs[slot].polygon = PackedVector2Array([
			Vector2(12.0, 0.0), Vector2(540.0, 0.0),
			Vector2(540.0 - plate_h * 0.38, plate_h), Vector2(0.0, plate_h),
		])
		_rows[slot].position = Vector2(98.0, row_y + (plate_h - 24.0) * 0.5)
		_rows[slot].add_theme_font_size_override("font_size", font_size)
		_row_buttons[slot].position = Vector2(70.0, row_y)
		_row_buttons[slot].size = Vector2(540.0, plate_h)
		var is_selected := slot == _cursor
		# ASCII markers remain crisp in the Web export's reduced fallback font.
		_rows[slot].text = ("◆  " + names[slot]) if is_selected else ("    " + names[slot])
		_rows[slot].add_theme_color_override("font_color", HOT if is_selected else DIM)
		_row_bgs[slot].color = Color(0.35, 0.10, 0.52, 0.84) if is_selected \
			else Color(0.045, 0.028, 0.070, 0.74)


func _activate(row: int) -> void:
	ui_accepted.emit()
	if _page == MenuPage.CONTROLS:
		_close_controls()
		return
	_select(row)
	if _page == MenuPage.BINDINGS:
		if row == BINDING_BACK_ROW:
			_page = MenuPage.CONTROLS
			_cursor = 0
			_binding_row = -1
		elif row == BINDING_RESET_ROW:
			_binding_row = -1
			bindings_reset.emit()
		else:
			_binding_row = row
		_refresh()
		return
	if _page == MenuPage.OPTIONS:
		if row == OPTION_BACK:
			_show_main_menu()
		else:
			_change_option(row, 1)
		return
	match row:
		ROW_PLAY:
			roster_requested.emit()
		ROW_TUTORIAL:
			tutorial_requested.emit()
		ROW_ONLINE:
			online_requested.emit()
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
	if _page == MenuPage.OPTIONS:
		return [
			"DISPLAY  ‹  %s  ›" % DISPLAY_NAMES[_display_preset],
			"EFFECTS VOLUME  ‹  %d%%  ›" % _sfx_percent,
			"VOICE VOLUME  ‹  %d%%  ›" % _voice_percent,
			"HIT FREEZE  %s" % ("ON" if _hit_freeze_enabled else "OFF"),
			"FLASHES  %s" % ("REDUCED" if _reduced_flashes else "FULL"),
			"PREVIEW CONTRAST  %s" % ("HIGH" if _high_contrast_previews else "NORMAL"),
			"PLAYTEST LOG  %s" % ("LOCAL" if _telemetry_enabled else "OFF"),
			"‹  BACK",
		]
	if _page == MenuPage.BINDINGS:
		var rows: Array[String] = []
		for i in BINDABLE.size():
			var action := str(BINDABLE[i][0])
			rows.append("%s   %s" % [str(BINDABLE[i][1]),
				"PRESS A KEY…" if _binding_row == i else _keys_text(action)])
		rows.append("RESET TO DEFAULTS")
		rows.append("‹  BACK")
		return rows
	if _page == MenuPage.CONTROLS:
		return ["‹  BACK"]
	return [
		"PLAY",
		"HOW TO PLAY",
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
				"Build the whole local match on one screen: mode, roster, arena and rules.",
				"Read the six-screen combat briefing. No inputs or live challenges required.",
				"Create or join a private room for a hidden-plan duel.",
				"See P1 keyboard + mouse, P2 gamepad, SUPER activation and playtest shortcuts.",
				"Tune sound, impact feedback, flashes, preview contrast and playtest logs.",
				"Close ZAWARUDO and return time to the ordinary world.",
			][_cursor]
		MenuPage.BINDINGS:
			if _cursor == BINDING_RESET_ROW:
				return "Put every Player 1 key back to the shipped layout."
			if _cursor == BINDING_BACK_ROW:
				return "Return to the controls reference."
			return "Press Enter, then press the key you want. " \
				+ "Taking a key from another action leaves that one unbound until you set it. " \
				+ "Escape cancels without changing anything."
		MenuPage.OPTIONS:
			return [
				"Choose the window size, or hand the whole screen over to the arena.",
				"Throws, impacts, breaking platforms and the freeze cues.",
				"The match-opening shout and the SUPER chant, on their own level.",
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


func _step_volume(percent: int, direction: int) -> int:
	var current := SOUND_LEVELS.find(percent)
	if current < 0:
		current = SOUND_LEVELS.size() - 1
	return SOUND_LEVELS[posmod(current + direction, SOUND_LEVELS.size())]


func _change_option(row: int, direction: int) -> void:
	match row:
		OPTION_DISPLAY:
			_display_preset = posmod(_display_preset + direction, DISPLAY_NAMES.size())
			option_changed.emit("display", _display_preset)
		OPTION_SFX:
			_sfx_percent = _step_volume(_sfx_percent, direction)
			option_changed.emit("sfx", float(_sfx_percent) / 100.0)
		OPTION_VOICE:
			_voice_percent = _step_volume(_voice_percent, direction)
			option_changed.emit("voice", float(_voice_percent) / 100.0)
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
	if _binding_row >= 0:
		var action := str(BINDABLE[_binding_row][0])
		_binding_row = -1
		# Escape is the universal way out of a menu, so it is never bindable.
		if code != KEY_ESCAPE:
			ui_accepted.emit()
			binding_changed.emit(action, [code])
		_refresh()
		return true
	if _page == MenuPage.BINDINGS:
		match code:
			KEY_W, KEY_UP: _select(_cursor - 1)
			KEY_S, KEY_DOWN: _select(_cursor + 1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: _activate(_cursor)
			KEY_ESCAPE:
				_page = MenuPage.CONTROLS
				_refresh()
			_: return false
		return true
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
			if _page == MenuPage.OPTIONS and _cursor != OPTION_BACK:
				_change_option(_cursor, -1)
		KEY_D, KEY_RIGHT:
			if _page == MenuPage.OPTIONS and _cursor != OPTION_BACK:
				_change_option(_cursor, 1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_activate(_cursor)
		KEY_ESCAPE:
			if _page == MenuPage.OPTIONS:
				_show_main_menu()
			else:
				get_tree().quit()
		_:
			return false
	return true
