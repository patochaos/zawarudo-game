extends Camera2D
class_name DuelCamera

## PROTOTYPE. Disposable — see `prototype_mode` in GameManager.
##
## The question this is here to answer: does the duel read better if the camera
## behaves like the time stop does? It pushes in and settles while the world is
## frozen — the planning phase becomes an intimate, close reading of a small
## piece of the arena — and snaps back out the instant time resumes, so the
## execution is watched whole, at arena scale, with both fighters and every
## knife in frame.
##
## It is deliberately NOT a follow camera. It frames the contested region once
## per freeze and then holds still, because a drifting viewport during planning
## would fight the stillness the whole phase depends on.
##
## When a wrapping seam splits the subjects across both screen edges, the camera
## falls back to the full arena. A pushed-in viewport cannot render a second
## visual copy of the world, and hiding one side would make seam traversal feel
## like a blind teleport.

const ARENA := Vector2(1280.0, 720.0)
## How far in the planning phase pushes. Above ~1.4 a lobbed arc leaves frame.
const PLANNING_ZOOM := 1.30
const EXECUTION_ZOOM := 1.0
## The HUD is a fixed overlay owning the top ~190px of the SCREEN, so a pushed-in
## frame has to sit low enough that the arena's ceiling is not parked underneath
## it. This is the clearest cost the experiment has surfaced: the HUD was laid
## out for a viewport that never moves.
const HUD_BIAS := Vector2(0.0, 60.0)

var gm

var _target_centre: Vector2 = ARENA * 0.5
var _target_zoom: float = EXECUTION_ZOOM
var _settled: bool = false


func _ready() -> void:
	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	position = ARENA * 0.5
	zoom = Vector2.ONE
	_target_centre = position


func _process(delta: float) -> void:
	if gm == null or not enabled:
		return
	_retarget()
	# Two speeds on purpose: the push-in is slow enough to feel like the world
	# settling, the pull-out is fast enough to be part of the impact of time
	# restarting rather than a transition you wait through.
	var rate: float = 3.2 if _target_zoom > EXECUTION_ZOOM else 11.0
	var t: float = clampf(delta * rate, 0.0, 1.0)
	position = position.lerp(_target_centre, t)
	zoom = zoom.lerp(Vector2.ONE * _target_zoom, t)


func _retarget() -> void:
	var planning: bool = gm.state == Phase.PLANNING or gm.state == Phase.COMMITTING
	if not planning:
		_settled = false
		_target_zoom = EXECUTION_ZOOM
		_target_centre = ARENA * 0.5
		return

	# Frame once per freeze. Re-framing every tick as a ghost is piloted would
	# turn the planning phase into a slow drift.
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


## Keeps the viewport inside the arena so a push-in never reveals dead space
## beyond the walls.
func _clamp_to_arena(centre: Vector2, at_zoom: float) -> Vector2:
	var half: Vector2 = ARENA * 0.5 / at_zoom
	return Vector2(
		clampf(centre.x, half.x, ARENA.x - half.x),
		clampf(centre.y, half.y, ARENA.y - half.y))
