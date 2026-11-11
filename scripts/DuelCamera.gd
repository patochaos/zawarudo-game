extends Camera2D
class_name DuelCamera

## Kill push-in camera. It stays disabled, leaving the complete 1280x720 arena on
## screen, and is switched on only to push in on a fresh kill and ease back out.

const ARENA := Vector2(1280.0, 720.0)
const EXECUTION_ZOOM := 1.0

var gm
var _target_centre: Vector2 = ARENA * 0.5
var _target_zoom: float = EXECUTION_ZOOM
## Kill push-in: real seconds left, the victim's position and its zoom. The
## camera is enabled only for this beat and then switches off.
var _focus_left: float = 0.0
var _focus_at: Vector2 = ARENA * 0.5
var _focus_zoom: float = EXECUTION_ZOOM
var _focus_only: bool = false


func _ready() -> void:
	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	reset_view()


func _process(delta: float) -> void:
	if gm == null or not enabled:
		return
	# Slow motion scales `delta`; the push-in itself should stay brisk.
	var real_delta: float = delta / maxf(Engine.time_scale, 0.001)
	_focus_left = maxf(0.0, _focus_left - real_delta)
	if _focus_only and _focus_left <= 0.0 and _release_focus_only():
		return
	_retarget()
	var rate: float = 9.0 if _focus_left > 0.0 else 11.0
	var t: float = clampf(real_delta * rate, 0.0, 1.0)
	position = position.lerp(_target_centre, t)
	zoom = zoom.lerp(Vector2.ONE * _target_zoom, t)


## Pushes in on a fresh kill for `seconds` of real time.
func focus_kill(at: Vector2, at_zoom: float, seconds: float) -> void:
	if not enabled:
		reset_view()
		enabled = true
		_focus_only = true
	_focus_at = at
	_focus_zoom = at_zoom
	_focus_left = seconds


func is_focusing() -> bool:
	return _focus_left > 0.0


## After a borrowed kill push-in, ease back out and switch the camera off. Planning
## aims in screen space, so it never starts under a leftover zoom.
func _release_focus_only() -> bool:
	var planning: bool = gm.state == Phase.PLANNING or gm.state == Phase.COMMITTING
	if planning or zoom.x <= EXECUTION_ZOOM + 0.01:
		reset_view()
		enabled = false
		_focus_only = false
		return true
	return false


func reset_view() -> void:
	position = ARENA * 0.5
	zoom = Vector2.ONE
	_target_centre = position
	_target_zoom = EXECUTION_ZOOM
	_focus_left = 0.0


func _retarget() -> void:
	if _focus_left > 0.0:
		_target_zoom = _focus_zoom
		_target_centre = _clamp_to_arena(_focus_at, _focus_zoom)
		return
	_target_zoom = EXECUTION_ZOOM
	_target_centre = ARENA * 0.5


func _clamp_to_arena(centre: Vector2, at_zoom: float) -> Vector2:
	var half: Vector2 = ARENA * 0.5 / at_zoom
	return Vector2(
		clampf(centre.x, half.x, ARENA.x - half.x),
		clampf(centre.y, half.y, ARENA.y - half.y))
