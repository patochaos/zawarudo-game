extends Node2D
class_name Arena

## Renders the platform set. Layouts live in Levels.gd; damage state lives in
## GameManager. Terrain never damages a player — only arrows do.
##
## Indestructible geometry is cool and flat; breakable geometry is warm, carries
## hit pips, and reddens and cracks as it takes damage. Moving geometry keeps the
## permanent silhouette but swaps its gold cap for a violet one and wears chevrons
## pointing along its rail. That three-way colour split is the only thing a player
## has to learn to read the arena — and the moving read has to survive execution,
## when every planning overlay is stripped away.

const INDESTRUCTIBLE := -1

const SOLID_FILL := Color(0.12, 0.10, 0.18)
const SOLID_FACE := Color(0.075, 0.055, 0.12)
const SOLID_TOP := Color(0.63, 0.48, 0.18)
const SOLID_EDGE := Color(0.035, 0.025, 0.06)

const MOVER_TOP := Color(0.66, 0.55, 0.95)
const MOVER_MARK := Color(0.80, 0.72, 1.0, 0.75)

const BREAK_FILL := Color(0.29, 0.20, 0.13)
const BREAK_BROKEN := Color(0.42, 0.12, 0.13)
const BREAK_TOP := Color(0.79, 0.58, 0.21)
const BREAK_TOP_BROKEN := Color(1.0, 0.31, 0.25)

var platforms: Array = []


func setup(p: Array) -> void:
	platforms = p
	queue_redraw()


func _draw() -> void:
	for pf in platforms:
		var r: Rect2 = pf["rect"]
		if r.position.x < -1.0 or r.position.x >= 1280.0:
			continue  # walls stay invisible
		if pf["hp"] == INDESTRUCTIBLE:
			_draw_solid(r, pf.get("motion", {}))
		else:
			_draw_breakable(r, pf["hp"], pf.get("max_hp", pf["hp"]))


func _draw_solid(r: Rect2, motion: Dictionary = {}) -> void:
	var moving: bool = not motion.is_empty()
	draw_rect(Rect2(r.position + Vector2(7.0, 9.0), r.size), Color(0.01, 0.0, 0.025, 0.62))
	draw_rect(r, SOLID_FILL)
	draw_rect(Rect2(r.position + Vector2(0.0, 8.0), Vector2(r.size.x, maxf(0.0, r.size.y - 8.0))), SOLID_FACE)
	# A gold cap and inset line make every platform feel like carved stagework;
	# a violet cap says this piece of stagework is on rails.
	draw_rect(Rect2(r.position, Vector2(r.size.x, 5.0)), MOVER_TOP if moving else SOLID_TOP)
	draw_line(r.position + Vector2(8.0, 10.0), Vector2(r.end.x - 8.0, r.position.y + 10.0),
		Color(0.50, 0.42, 0.78, 0.45) if moving else Color(0.58, 0.38, 0.16, 0.42), 1.0)
	draw_rect(r, SOLID_EDGE, false, 2.0)
	if moving:
		_draw_travel_marks(r, motion)
	else:
		_draw_ornaments(r, Color(0.72, 0.51, 0.18, 0.52))


## Chevrons along the axis of travel. They say "this moves, and along here" while
## the piece is drawn on its own, which is the only cue available once execution
## strips the planning overlays.
func _draw_travel_marks(r: Rect2, motion: Dictionary) -> void:
	var axis: Vector2 = motion.get("axis", Vector2.DOWN)
	if axis.is_zero_approx():
		return
	var d: Vector2 = axis.normalized()
	var along: Vector2 = d.orthogonal() if absf(d.y) > absf(d.x) else d
	var span: float = r.size.x if absf(along.x) > absf(along.y) else r.size.y
	var count: int = clampi(int(span / 64.0), 1, 8)
	for i in count:
		var t: float = (float(i) + 0.5) / float(count)
		var at: Vector2 = r.position + Vector2(r.size.x * t, minf(13.0, r.size.y * 0.55)) \
			if absf(along.x) > absf(along.y) \
			else r.position + Vector2(r.size.x * 0.5, r.size.y * t)
		var wing: Vector2 = d.orthogonal() * 5.0
		draw_line(at - wing - d * 4.0, at + d * 4.0, MOVER_MARK, 1.6, true)
		draw_line(at + wing - d * 4.0, at + d * 4.0, MOVER_MARK, 1.6, true)


func _draw_breakable(r: Rect2, hp: int, max_hp: int) -> void:
	var wear: float = 1.0 - float(hp) / float(maxi(max_hp, 1))
	draw_rect(Rect2(r.position + Vector2(7.0, 9.0), r.size), Color(0.01, 0.0, 0.025, 0.62))
	draw_rect(r, BREAK_FILL.lerp(BREAK_BROKEN, wear))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 5.0)), BREAK_TOP.lerp(BREAK_TOP_BROKEN, wear))
	draw_rect(r, SOLID_EDGE, false, 2.0)
	_draw_ornaments(r, Color(0.92, 0.57, 0.18, 0.45))

	# cracks deepen with damage
	if wear > 0.01:
		var n := int(round(wear * 3.0)) + 1
		for i in n:
			var t: float = (float(i) + 0.5) / float(n)
			var cx: float = r.position.x + r.size.x * t
			draw_line(Vector2(cx - 4.0, r.position.y + 2.0), Vector2(cx + 3.0, r.end.y - 1.0),
				Color(0.04, 0.03, 0.04, 0.8), 1.5)
			draw_line(Vector2(cx + 3.0, r.position.y + r.size.y * 0.5),
				Vector2(cx + 9.0, r.end.y - 1.0), Color(0.04, 0.03, 0.04, 0.5), 1.0)

	# remaining hits, as pips above the piece
	var pip := 5.0
	var gap := 3.0
	var total: float = float(max_hp) * pip + float(max_hp - 1) * gap
	var x: float = r.position.x + (r.size.x - total) * 0.5
	for i in max_hp:
		var filled: bool = i < hp
		draw_rect(Rect2(Vector2(x, r.position.y - 7.0), Vector2(pip, 3.0)),
			Color(0.98, 0.86, 0.52) if filled else Color(0.40, 0.31, 0.31, 0.55))
		x += pip + gap


func _draw_ornaments(r: Rect2, col: Color) -> void:
	if r.size.x < 54.0 or r.size.y < 13.0:
		return
	var count := clampi(int(r.size.x / 92.0), 1, 8)
	for i in count:
		var x: float = r.position.x + r.size.x * (float(i) + 0.5) / float(count)
		var y: float = r.position.y + minf(13.0, r.size.y * 0.55)
		var d := 3.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, y - d), Vector2(x + d, y), Vector2(x, y + d), Vector2(x - d, y),
		]), col)
