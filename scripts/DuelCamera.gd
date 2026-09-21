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


func _ready() -> void:
	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	reset_view()


func _process(delta: float) -> void:
	if gm == null or not enabled:
		return
	_retarget()
	var rate: float = 3.2 if _target_zoom > EXECUTION_ZOOM else 11.0
	var t: float = clampf(delta * rate, 0.0, 1.0)
	position = position.lerp(_target_centre, t)
	zoom = zoom.lerp(Vector2.ONE * _target_zoom, t)


func reset_view() -> void:
	position = ARENA * 0.5
	zoom = Vector2.ONE
	_target_centre = position
	_target_zoom = EXECUTION_ZOOM
	_settled = false


func _retarget() -> void:
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
