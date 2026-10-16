extends Camera2D
class_name DuelCamera

## Close Camera mode frames the contested region once per planning freeze, then
## holds still. Execution always pulls back to the complete 1280x720 arena so
## every consequence remains visible.

const ARENA := Vector2(1280.0, 720.0)
const PLANNING_ZOOM := 1.30
const EXECUTION_ZOOM := 1.0
const HUD_BIAS := Vector2(0.0, 60.0)

var gm
var _target_centre: Vector2 = ARENA * 0.5
var _target_zoom: float = EXECUTION_ZOOM
var _settled: bool = false
## Kill push-in: real seconds left, the victim's position and its zoom. Outside
## Close Camera the camera is enabled only for this beat and then switches off.
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
	var rate: float = 3.2 if _target_zoom > EXECUTION_ZOOM else 11.0
	if _focus_left > 0.0:
		rate = 9.0
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
	_settled = false
	_focus_left = 0.0


func _retarget() -> void:
	if _focus_left > 0.0:
		_target_zoom = _focus_zoom
		_target_centre = _clamp_to_arena(_focus_at, _focus_zoom)
		return
	if _focus_only:
		_target_zoom = EXECUTION_ZOOM
		_target_centre = ARENA * 0.5
		return
	var planning: bool = gm.state == Phase.PLANNING or gm.state == Phase.COMMITTING
	if not planning:
		_settled = false
		_target_zoom = EXECUTION_ZOOM
		_target_centre = ARENA * 0.5
		return
	if _settled:
		return
	_settled = true
	_target_zoom = PLANNING_ZOOM

	var points := PackedVector2Array()
	for p in gm.players:
		if p.alive:
			points.append(p.position)
	for a in gm.arrows:
		points.append(a.position)
	if points.is_empty():
		_target_centre = ARENA * 0.5
		return
	if gm.wrap_x:
		var min_x := points[0].x
		var max_x := points[0].x
		for point in points:
			min_x = minf(min_x, point.x)
			max_x = maxf(max_x, point.x)
		if max_x - min_x > ARENA.x * 0.5:
			_target_zoom = EXECUTION_ZOOM
			_target_centre = ARENA * 0.5
			return

	var box := Rect2(points[0], Vector2.ZERO)
	for point in points:
		box = box.expand(point)
	_target_centre = _clamp_to_arena(box.get_center() + HUD_BIAS, _target_zoom)


func _clamp_to_arena(centre: Vector2, at_zoom: float) -> Vector2:
	var half: Vector2 = ARENA * 0.5 / at_zoom
	return Vector2(
		clampf(centre.x, half.x, ARENA.x - half.x),
		clampf(centre.y, half.y, ARENA.y - half.y))
