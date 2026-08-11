extends CanvasLayer
class_name TutorialLayer

## Three action-gated practice turns. The ordinary planning and execution code
## remains in charge; this layer only recognizes the requested action and locks
## that short plan so the player immediately sees its result.

const MESSAGES := [
	"Usa A/D para moverte\nUsa toda la barra de stamina",
	"Usa space para saltar\nUsa toda la barra de stamina",
	"Dispara con el mouse",
]

var gm
var active: bool = false
var stage: int = 0
var timed_turns_started: bool = false
var _complete_time: float = 0.0
var _panel: Panel
var _message: Label


func _ready() -> void:
	layer = 7
	_panel = Panel.new()
	_panel.position = Vector2(340.0, 182.0)
	_panel.size = Vector2(600.0, 98.0)
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.035, 0.018, 0.065, 0.96)
	frame.border_color = Color(1.0, 0.72, 0.25, 0.95)
	frame.set_border_width_all(3)
	frame.set_corner_radius_all(8)
	_panel.add_theme_stylebox_override("panel", frame)
	add_child(_panel)

	_message = Label.new()
	_message.position = Vector2(18.0, 10.0)
	_message.size = Vector2(564.0, 78.0)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message.add_theme_font_size_override("font_size", 24)
	_message.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0))
	_message.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	_message.add_theme_constant_override("shadow_offset_x", 2)
	_message.add_theme_constant_override("shadow_offset_y", 3)
	_panel.add_child(_message)
	visible = false


func start(manager) -> void:
	gm = manager
	active = true
	stage = 0
	timed_turns_started = false
	_complete_time = 0.0
	_panel.visible = true
	_message.text = MESSAGES[stage]
	visible = true


func stop() -> void:
	active = false
	visible = false


## Called immediately after recording input, before automatic ready checks can
## lock a plan. Returns true when this tick completed a step.
func observe_planning() -> bool:
	if not active or timed_turns_started or gm == null or gm.state != Phase.PLANNING:
		return false
	if stage >= MESSAGES.size():
		timed_turns_started = true
		_complete_time = 0.0
		_message.text = "Ahora los turnos tienen tiempo"
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
		if _complete_time >= 2.25:
			stop()
		return
	if gm.state == Phase.PLANNING and stage < MESSAGES.size():
		_message.text = MESSAGES[stage]
		_panel.visible = true
	else:
		_panel.visible = false
