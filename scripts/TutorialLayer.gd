extends CanvasLayer
class_name TutorialLayer

## Action-gated onboarding. The simulation stays authoritative; this layer only
## explains the current objective, reflects live progress and locks a completed
## practice plan so the player immediately sees cause become consequence.

const GOLD := Color(0.96, 0.69, 0.18)
const VIOLET := Color(0.72, 0.38, 0.95)
const INK := Color(0.025, 0.012, 0.045, 0.96)
const DIM := Color(0.68, 0.72, 0.82)

const STEPS := [
	{
		"kicker": "STEP 01 / 03  —  WRITE A PATH",
		"title": "MOVE THROUGH STOPPED TIME",
		"body": "Hold  A  or  D  until the stamina line is empty.",
		"hint": "The gold ghost shows where your real fighter will travel.",
	},
	{
		"kicker": "STEP 02 / 03  —  SHAPE THE PATH",
		"title": "ADD A JUMP",
		"body": "Hold  A / D  and press  SPACE. Use the full stamina line.",
		"hint": "You can jump again in the air; hold the key for extra height.",
	},
	{
		"kicker": "STEP 03 / 03  —  PLACE THE VOLLEY",
		"title": "AIM, DRAW, RELEASE",
		"body": "Aim with the  MOUSE. Hold  LMB  for power, then release.",
		"hint": "The line is intent, not certainty: the shared world can interfere.",
	},
]


class TutorialChrome:
	extends Control

	var completed_steps: int = 0
	var accent: Color = VIOLET

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()

	func set_state(done: int, color: Color) -> void:
		completed_steps = done
		accent = color
		queue_redraw()

	func _draw() -> void:
		var shape := PackedVector2Array([
			Vector2(0.0, 0.0), Vector2(378.0, 0.0), Vector2(404.0, 25.0),
			Vector2(404.0, 165.0), Vector2(18.0, 165.0), Vector2(0.0, 147.0),
		])
		draw_colored_polygon(shape, INK)
		draw_polyline(shape + PackedVector2Array([shape[0]]),
			Color(GOLD.r, GOLD.g, GOLD.b, 0.72), 1.5, true)
		draw_line(Vector2(18.0, 39.0), Vector2(378.0, 39.0),
			Color(accent.r, accent.g, accent.b, 0.62), 2.0)
		for i in 3:
			var center := Vector2(322.0 + float(i) * 23.0, 22.0)
			var pip := PackedVector2Array([
				center + Vector2(0.0, -5.0), center + Vector2(5.0, 0.0),
				center + Vector2(0.0, 5.0), center + Vector2(-5.0, 0.0),
			])
			draw_colored_polygon(pip, GOLD if i < completed_steps else Color(0.18, 0.16, 0.23))
			draw_polyline(pip + PackedVector2Array([pip[0]]), GOLD, 1.0, true)


var gm
var active: bool = false
var stage: int = 0
var timed_turns_started: bool = false
var _complete_time: float = 0.0
var _panel: Control
var _chrome: TutorialChrome
var _kicker: Label
var _title: Label
var _body: Label
var _hint: Label
var _progress_track: ColorRect
var _progress_fill: ColorRect


func _ready() -> void:
	layer = 7
	_panel = Control.new()
	_panel.position = Vector2(24.0, 164.0)
	_panel.size = Vector2(404.0, 165.0)
	add_child(_panel)

	_chrome = TutorialChrome.new()
	_chrome.size = _panel.size
	_panel.add_child(_chrome)

	_kicker = _label(Vector2(18.0, 10.0), Vector2(286.0, 22.0), 11, GOLD)
	_title = _label(Vector2(18.0, 49.0), Vector2(364.0, 26.0), 18, Color(0.96, 0.97, 1.0))
	_body = _label(Vector2(18.0, 79.0), Vector2(364.0, 38.0), 14, Color(0.86, 0.88, 0.95))
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint = _label(Vector2(18.0, 120.0), Vector2(364.0, 22.0), 11, DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_progress_track = ColorRect.new()
	_progress_track.position = Vector2(18.0, 150.0)
	_progress_track.size = Vector2(364.0, 4.0)
	_progress_track.color = Color(0.14, 0.12, 0.19, 0.96)
	_progress_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_progress_track)
	_progress_fill = ColorRect.new()
	_progress_fill.position = _progress_track.position
	_progress_fill.size = Vector2(0.0, 4.0)
	_progress_fill.color = VIOLET
	_progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_progress_fill)
	visible = false


func _label(pos: Vector2, dimensions: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = pos
	label.size = dimensions
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.92))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(label)
	return label


func start(manager) -> void:
	gm = manager
	active = true
	stage = 0
	timed_turns_started = false
	_complete_time = 0.0
	_panel.visible = true
	visible = true
	_refresh_step()


func stop() -> void:
	active = false
	visible = false


func _refresh_step() -> void:
	if stage >= STEPS.size():
		return
	var step: Dictionary = STEPS[stage]
	_kicker.text = step["kicker"]
	_title.text = step["title"]
	_body.text = step["body"]
	_hint.text = step["hint"]
	_chrome.set_state(stage, VIOLET)
	_update_progress()


func _update_progress() -> void:
	if gm == null or stage >= STEPS.size():
		return
	var amount := 0.0
	var plan: PlayerPlan = gm.players[0].plan
	match stage:
		0, 1:
			amount = 1.0 - clampf(gm.stamina[0] / maxf(gm.movement_budget, 0.001), 0.0, 1.0)
		2:
			amount = clampf(plan.power, 0.0, 1.0) if plan.has_shot() else 0.0
	_progress_fill.size.x = 364.0 * amount
	_progress_fill.color = GOLD if amount >= 0.99 else VIOLET


## Called immediately after recording input, before automatic ready checks can
## lock a plan. Returns true when this tick completed a step.
func observe_planning() -> bool:
	if not active or timed_turns_started or gm == null or gm.state != Phase.PLANNING:
		return false
	if stage >= STEPS.size():
		timed_turns_started = true
		_complete_time = 0.0
		_kicker.text = "TRAINING COMPLETE"
		_title.text = "THE CLOCK IS NOW RUNNING"
		_body.text = "Compose a path and volley before time reaches zero."
		_hint.text = "Press LEFT SHIFT to lock early. The execution needs no input."
		_progress_fill.size.x = 364.0
		_progress_fill.color = GOLD
		_chrome.set_state(STEPS.size(), GOLD)
		_panel.visible = true
		gm.start_tutorial_timed_turns()
		return false

	var plan: PlayerPlan = gm.players[0].plan
	var stamina_spent: bool = gm.stamina[0] <= 0.0 \
		or plan.recorded_ticks() >= gm.movement_tick_budget()
	var completed := false
	match stage:
		0:
			completed = stamina_spent and (plan.dirs.has(0) or plan.dirs.has(2))
		1:
			completed = stamina_spent and plan.jumps.has(1)
		2:
			completed = plan.has_shot()
	if not completed:
		return false

	stage += 1
	_chrome.set_state(stage, GOLD)
	_progress_fill.size.x = 364.0
	_progress_fill.color = GOLD
	gm._confirm(0)
	return true


func _process(delta: float) -> void:
	if not active or gm == null:
		return
	if gm.state in [Phase.MENU, Phase.ONLINE_LOBBY, Phase.FREEPLAY]:
		stop()
		return
	if timed_turns_started:
		_complete_time += delta
		if _complete_time >= 2.75:
			stop()
		return
	if gm.state == Phase.PLANNING and stage < STEPS.size():
		_refresh_step()
		_panel.visible = true
	else:
		_panel.visible = false
