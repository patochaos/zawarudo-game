extends CanvasLayer
class_name TutorialLayer

## A deterministic, screen-by-screen briefing. Nothing in the match simulation
## runs while this is open: every page teaches one idea, shows the expected
## result, and lists equivalent keyboard, gamepad and touch controls.

const VIEW_SIZE := Vector2(1280.0, 720.0)
const GOLD := Color(0.96, 0.69, 0.18)
const VIOLET := Color(0.72, 0.38, 0.95)
const INK := Color(0.018, 0.010, 0.035, 0.985)
const PANEL := Color(0.045, 0.026, 0.072, 0.98)
const DIM := Color(0.68, 0.72, 0.82)
const PROMPTS := preload("res://scripts/InputPrompts.gd")

## Verified captures from the real match scene. Keeping these as authored game
## screenshots makes the tutorial's examples visually identical to play.
const GAME_IMAGES: Array[Texture2D] = [
	preload("res://assets/art/tutorial/tutorial-plan.png"),
	preload("res://assets/art/tutorial/tutorial-move.png"),
	preload("res://assets/art/tutorial/tutorial-jump.png"),
	preload("res://assets/art/tutorial/tutorial-attack.png"),
	preload("res://assets/art/tutorial/tutorial-lock.png"),
	preload("res://assets/art/tutorial/tutorial-result.png"),
]

const PAGES := [
	{
		"kicker": "COMBAT BRIEFING  01 / 06",
		"title": "PLAN FIRST.\nTHEN TIME MOVES.",
		"body": "Every turn has two states. During PLAN, the world is frozen while each fighter builds a short sequence. During EXECUTE, every locked sequence plays at the same time.\n\nYou give no input during EXECUTE — watch the result, then plan the next turn from the new frozen state.",
		"callout_title": "THE ONE RULE TO REMEMBER",
		"callout": "PLAN is your input. EXECUTE is the consequence.",
		"visual_title": "ONE TURN, FROM LEFT TO RIGHT",
		"visual_caption": "Your rival plans too. Neither plan changes the world until execution begins.",
		"rows": [
			["1  PLAN", "Build movement and place an attack"],
			["2  LOCK", "Finish early — or let the timer expire"],
			["3  EXECUTE", "Both fighters act together"],
		],
	},
	{
		"kicker": "COMBAT BRIEFING  02 / 06",
		"title": "TRACE WHERE\nYOU WILL MOVE.",
		"body": "Hold a direction during PLAN. The bright ghost moves while your real fighter stays frozen. The trail behind the ghost is the route you are recording.\n\nThe stamina bar is the amount of movement you can add this turn. Release the control whenever you want to stop adding movement and think.",
		"callout_title": "WHAT YOU SHOULD SEE",
		"callout": "A bright ghost at the route's end and a trail back to your real fighter.",
		"visual_title": "MOVEMENT BECOMES A TIMELINE",
		"visual_caption": "The real fighter waits at the start. The ghost previews each recorded moment.",
		"rows": [
			["KEYBOARD", "Hold  A / D"],
			["GAMEPAD", "Hold left stick or D-pad"],
			["TOUCH", "Hold the virtual stick"],
		],
	},
	{
		"kicker": "COMBAT BRIEFING  03 / 06",
		"title": "ADD HEIGHT —\nOR ADD WAITING.",
		"body": "Press jump while tracing the route. Keep holding a movement, jump, or wait control to record the airborne part of the arc.\n\nWaiting spends part of the route without steering. On a one-way platform, hold down and press jump to record a drop-through.",
		"callout_title": "NO SURPRISE AUTOPILOT",
		"callout": "The route advances only while you hold a planning control.",
		"visual_title": "JUMP AND WAIT ARE PART OF THE ROUTE",
		"visual_caption": "A jump adds an arc. Wait adds time at the current steering direction.",
		"rows": [
			["JUMP", "Space / W / ↑  ·  gamepad A  ·  touch JUMP"],
			["WAIT", "S  ·  stick/D-pad down  ·  touch stick down"],
			["DROP", "Hold WAIT, then press JUMP"],
		],
	},
	{
		"kicker": "COMBAT BRIEFING  04 / 06",
		"title": "PLACE THE ATTACK\nON YOUR ROUTE.",
		"body": "Aim from the ghost, then hold the attack control to build power and release it to place the attack. It will happen at that exact point in your recorded route.\n\nThe aim line is a prediction, not a promise. During EXECUTE, fighters, projectiles, and moving geometry can interfere.",
		"callout_title": "WHAT YOU SHOULD SEE",
		"callout": "The attack begins at the ghost — not at the frozen fighter you started from.",
		"visual_title": "AIM FROM THE FUTURE POSITION",
		"visual_caption": "Longer charge means more power. Each fighter turns this action into their own attack.",
		"rows": [
			["KEYBOARD", "Mouse aim  ·  hold/release LMB"],
			["GAMEPAD", "Right stick  ·  hold/release R2"],
			["TOUCH", "Drag arena to aim  ·  hold/release DRAW"],
		],
	},
	{
		"kicker": "COMBAT BRIEFING  05 / 06",
		"title": "CORRECT IT.\nTHEN LOCK IT.",
		"body": "If the attack is wrong, UNDO removes the placed attack but keeps the movement route. RESET clears the whole route and refills its stamina.\n\nLOCK submits exactly what is shown. You may lock a partial route or no attack at all. If time runs out, the current plan is submitted automatically.",
		"callout_title": "SAFE TO EXPERIMENT",
		"callout": "Nothing becomes real until execution. Edit freely while PLAN is visible.",
		"visual_title": "REVISE BEFORE THE CLOCK RELEASES",
		"visual_caption": "Undo the attack, reset the route, or lock the plan exactly as it stands.",
		"rows": [
			["UNDO ATTACK", "R / RMB  ·  gamepad B  ·  UNDO"],
			["RESET ROUTE", "F  ·  gamepad X  ·  RESET"],
			["LOCK PLAN", "Left Shift  ·  Start  ·  LOCK"],
		],
	},
	{
		"kicker": "COMBAT BRIEFING  06 / 06",
		"title": "READ THE RESULT.\nPLAN AGAIN.",
		"body": "A hit scores one life, then the struck fighter returns on a later turn. The first fighter — or team — to reach the selected Match Lives wins.\n\nProjectiles and damaged platforms can survive between turns. Each new PLAN starts from the world you just created, so adapt instead of repeating the same route.",
		"callout_title": "READY FOR A FIRST MATCH",
		"callout": "Choose PLAY → VS AI and leave Match Lives at 3 for the simplest start.",
		"visual_title": "THE LOOP CONTINUES FROM THE NEW WORLD",
		"visual_caption": "Observe what changed, then write the next short piece of the fight.",
		"rows": [
			["START EASY", "PLAY  →  VS AI  →  3 lives"],
			["DURING PLAN", "Trace  ·  jump  ·  aim  ·  attack"],
			["WHEN READY", "Lock and watch both plans collide"],
		],
	},
]


class TutorialArt:
	extends Control

	var page: int = 0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()

	func set_page(value: int) -> void:
		page = value
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), INK)
		draw_colored_polygon(PackedVector2Array([
			Vector2.ZERO, Vector2(530.0, 0.0), Vector2(470.0, 720.0), Vector2(0.0, 720.0),
		]), Color(0.30, 0.08, 0.47, 0.25))
		draw_colored_polygon(PackedVector2Array([
			Vector2(1060.0, 0.0), Vector2(1280.0, 0.0), Vector2(1280.0, 720.0), Vector2(900.0, 720.0),
		]), Color(0.70, 0.43, 0.08, 0.12))
		draw_rect(Rect2(34.0, 28.0, 1212.0, 660.0), PANEL)
		draw_rect(Rect2(34.0, 28.0, 1212.0, 660.0), Color(GOLD.r, GOLD.g, GOLD.b, 0.45), false, 1.5)
		draw_line(Vector2(494.0, 54.0), Vector2(466.0, 654.0), Color(GOLD.r, GOLD.g, GOLD.b, 0.26), 1.0)
		draw_line(Vector2(507.0, 54.0), Vector2(479.0, 654.0), Color(VIOLET.r, VIOLET.g, VIOLET.b, 0.34), 1.0)
		_draw_progress()
		var preview := Rect2(520.0, 140.0, 690.0, 382.0)
		draw_rect(preview, Color(0.020, 0.014, 0.038, 0.96))
		draw_rect(preview, Color(GOLD.r, GOLD.g, GOLD.b, 0.36), false, 1.0)

	func _draw_progress() -> void:
		for i in PAGES.size():
			var x := 553.0 + float(i) * 105.0
			var active_color := GOLD if i <= page else Color(0.18, 0.15, 0.23)
			draw_line(Vector2(x, 82.0), Vector2(x + 80.0, 82.0), active_color, 4.0)
			if i == page:
				draw_circle(Vector2(x + 40.0, 82.0), 5.0, Color(1.0, 0.90, 0.52))


class TutorialPromptArt:
	extends Control

	var page: int = 0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_page(value: int) -> void:
		page = value
		queue_redraw()

	func _draw() -> void:
		var rows: Array = _page_prompts()
		for row in rows.size():
			var ids: Array = rows[row]
			var icon_size := 18.0 if ids.size() >= 3 else 20.0
			var gap := 1.0 if ids.size() >= 3 else 3.0
			PROMPTS.draw_sequence(self, ids, Vector2(0.0, 3.0 + float(row) * 34.0),
				Color(0.92, 0.93, 1.0, 0.90), icon_size, gap)

	func _page_prompts() -> Array:
		match page:
			1:
				return [[&"key_a", &"key_d"], [&"pad_left"], [&"touch_move"]]
			2:
				return [[&"key_space", &"pad_a", &"touch_tap"],
					[&"key_s", &"pad_left_down", &"touch_down"],
					[&"key_s", &"key_space", &"touch_tap"]]
			3:
				return [[&"mouse_move", &"mouse_left"], [&"pad_right", &"pad_rt"],
					[&"touch_move", &"touch_hold"]]
			4:
				return [[&"key_r", &"pad_b", &"touch_tap"],
					[&"key_f", &"pad_x", &"touch_tap"],
					[&"key_shift", &"pad_menu", &"touch_tap"]]
			5:
				return [[&"key_enter", &"pad_a", &"touch_tap"], [], []]
			_:
				return [[], [], []]

var gm
var active: bool = false
var page: int = 0
## Compatibility signal for older HUD/test code. The walkthrough never starts
## a simulation, so timed turns always remain false.
var timed_turns_started: bool = false

var _art: TutorialArt
var _game_image: TextureRect
var _image_shade: ColorRect
var _kicker: Label
var _title: Label
var _body: Label
var _callout_title: Label
var _callout: Label
var _visual_title: Label
var _visual_caption: Label
var _row_keys: Array[Label] = []
var _row_details: Array[Label] = []
var _prompt_art: TutorialPromptArt
var _previous_button: Button
var _next_button: Button
var _close_button: Button


func _ready() -> void:
	layer = 9
	_art = TutorialArt.new()
	_art.size = VIEW_SIZE
	add_child(_art)
	_game_image = TextureRect.new()
	_game_image.position = Vector2(526.0, 146.0)
	_game_image.size = Vector2(678.0, 370.0)
	_game_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_game_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_game_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_game_image)
	_image_shade = ColorRect.new()
	_image_shade.position = Vector2(526.0, 146.0)
	_image_shade.size = Vector2(678.0, 76.0)
	_image_shade.color = Color(0.012, 0.008, 0.025, 0.82)
	_image_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_image_shade)

	_kicker = _label(Vector2(72.0, 58.0), Vector2(370.0, 24.0), 12, GOLD)
	_title = _label(Vector2(72.0, 118.0), Vector2(386.0, 96.0), 31, Color(0.96, 0.97, 1.0))
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body = _label(Vector2(72.0, 230.0), Vector2(382.0, 194.0), 16, Color(0.86, 0.88, 0.95))
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_callout_title = _label(Vector2(88.0, 451.0), Vector2(340.0, 20.0), 11, GOLD)
	_callout = _label(Vector2(88.0, 476.0), Vector2(340.0, 52.0), 14, Color(0.95, 0.92, 0.76))
	_callout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_visual_title = _label(Vector2(548.0, 158.0), Vector2(620.0, 24.0), 15, Color(0.96, 0.97, 1.0))
	_visual_caption = _label(Vector2(548.0, 185.0), Vector2(620.0, 28.0), 12, DIM)
	_visual_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	for i in 3:
		var y := 543.0 + float(i) * 34.0
		var key := _label(Vector2(548.0, y), Vector2(145.0, 28.0), 12, GOLD)
		var detail := _label(Vector2(782.0, y), Vector2(390.0, 28.0), 13, Color(0.86, 0.88, 0.95))
		_row_keys.append(key)
		_row_details.append(detail)
	_prompt_art = TutorialPromptArt.new()
	_prompt_art.position = Vector2(698.0, 540.0)
	_prompt_art.size = Vector2(78.0, 104.0)
	add_child(_prompt_art)

	_previous_button = _button(Vector2(548.0, 646.0), Vector2(150.0, 42.0), "←  PREVIOUS")
	_next_button = _button(Vector2(1010.0, 646.0), Vector2(172.0, 42.0), "NEXT  →")
	_close_button = _button(Vector2(1162.0, 46.0), Vector2(58.0, 38.0), "ESC")
	_previous_button.pressed.connect(_previous_page)
	_next_button.pressed.connect(_next_page)
	_close_button.pressed.connect(close)
	visible = false


func _label(pos: Vector2, dimensions: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = pos
	label.size = dimensions
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_font_override("font", PROMPTS.DISPLAY_FONT)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.86))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _button(pos: Vector2, dimensions: Vector2, text_value: String) -> Button:
	var button := Button.new()
	button.position = pos
	button.size = dimensions
	button.text = text_value
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_font_override("font", PROMPTS.DISPLAY_FONT)
	button.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.93, 0.62))
	button.add_theme_color_override("font_focus_color", Color(1.0, 0.93, 0.62))
	button.add_theme_stylebox_override("normal", _button_style(Color(0.07, 0.04, 0.10), Color(0.34, 0.25, 0.43)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.16, 0.08, 0.22), GOLD))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.24, 0.11, 0.34), GOLD))
	button.add_theme_stylebox_override("focus", _button_style(Color(0.12, 0.06, 0.18), GOLD, 2))
	button.add_theme_stylebox_override("disabled", _button_style(Color(0.035, 0.025, 0.05), Color(0.15, 0.13, 0.18)))
	add_child(button)
	return button


func _button_style(fill: Color, border: Color, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	return style


func start(manager) -> void:
	gm = manager
	active = true
	page = 0
	timed_turns_started = false
	visible = true
	_refresh_page()
	_next_button.grab_focus()


func stop() -> void:
	active = false
	visible = false


func close() -> void:
	if not active:
		return
	if gm != null:
		gm._open_menu()
	else:
		stop()


func handle_key(keycode: int) -> void:
	if not active:
		return
	match keycode:
		KEY_ESCAPE:
			close()
		KEY_LEFT, KEY_PAGEUP:
			_previous_page()
		KEY_RIGHT, KEY_PAGEDOWN, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_next_page()


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	var joy := event as InputEventJoypadButton
	if joy == null or not joy.pressed:
		return
	match joy.button_index:
		JOY_BUTTON_A, JOY_BUTTON_DPAD_RIGHT:
			_next_page()
		JOY_BUTTON_DPAD_LEFT:
			_previous_page()
		JOY_BUTTON_B:
			close()
	get_viewport().set_input_as_handled()


func advance() -> void:
	## Public, deterministic navigation used by the journey test.
	_next_page()


func _next_page() -> void:
	if not active:
		return
	if page >= PAGES.size() - 1:
		close()
		return
	page += 1
	_refresh_page()
	_next_button.grab_focus()


func _previous_page() -> void:
	if not active or page <= 0:
		return
	page -= 1
	_refresh_page()
	_previous_button.grab_focus()


func _refresh_page() -> void:
	var data: Dictionary = PAGES[page]
	_kicker.text = data["kicker"]
	_title.text = data["title"]
	_body.text = data["body"]
	_callout_title.text = data["callout_title"]
	_callout.text = data["callout"]
	_visual_title.text = data["visual_title"]
	_visual_caption.text = data["visual_caption"]
	var rows: Array = data["rows"]
	for i in 3:
		_row_keys[i].text = rows[i][0]
		_row_details[i].text = rows[i][1]
	_previous_button.disabled = page == 0
	_next_button.text = "DONE  ✓" if page == PAGES.size() - 1 else "NEXT  →"
	_game_image.texture = GAME_IMAGES[page]
	_art.set_page(page)
	_prompt_art.set_page(page)


func observe_planning() -> bool:
	## Compatibility no-op: the walkthrough intentionally has no action gates.
	return false
