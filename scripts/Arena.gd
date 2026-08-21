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

const SOLID_FILL := Color(0.105, 0.15, 0.21)
const SOLID_FACE := Color(0.055, 0.085, 0.13)
const SOLID_EDGE := Color(0.015, 0.025, 0.045)
const HARD_INK := Color(0.72, 0.92, 1.0)
const HARD_ACCENTS := [
	Color(0.95, 0.78, 0.28), Color(0.38, 0.80, 1.0), Color(0.72, 0.60, 1.0),
	Color(0.30, 1.0, 0.92), Color(0.95, 0.58, 0.30), Color(1.0, 0.35, 0.22),
	Color(0.92, 0.45, 1.0),
]

const MOVER_TOP := Color(0.66, 0.55, 0.95)
const MOVER_MARK := Color(0.80, 0.72, 1.0, 0.75)

const BREAK_FILL := Color(0.42, 0.20, 0.075)
const BREAK_BROKEN := Color(0.55, 0.075, 0.055)
const BREAK_TOP := Color(1.0, 0.67, 0.16)
const BREAK_TOP_BROKEN := Color(1.0, 0.20, 0.12)

var platforms: Array = []
var level_theme: int = 0
var wrap_x: bool = false
var wrap_y: bool = false


func configure_level(index: int, horizontal_wrap: bool, vertical_wrap: bool) -> void:
	level_theme = posmod(index, HARD_ACCENTS.size())
	wrap_x = horizontal_wrap
	wrap_y = vertical_wrap
	queue_redraw()


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
	if wrap_x:
		_draw_horizontal_portals()
	else:
		_draw_hard_side_boundaries()
	if wrap_y:
		_draw_vertical_portal()


func _draw_solid(r: Rect2, motion: Dictionary = {}) -> void:
	var moving: bool = not motion.is_empty()
	var accent: Color = HARD_ACCENTS[level_theme]
	draw_rect(Rect2(r.position + Vector2(7.0, 9.0), r.size), Color(0.01, 0.0, 0.025, 0.62))
	draw_rect(r, SOLID_FILL)
	draw_rect(Rect2(r.position + Vector2(0.0, 8.0), Vector2(r.size.x, maxf(0.0, r.size.y - 8.0))), SOLID_FACE)
	# HARD always reads as cold metal with a bright double rail. Movers retain
	# that material identity and add violet motion chevrons.
	draw_rect(Rect2(r.position, Vector2(r.size.x, 5.0)), MOVER_TOP if moving else accent)
	draw_line(r.position + Vector2(8.0, 10.0), Vector2(r.end.x - 8.0, r.position.y + 10.0),
		MOVER_MARK if moving else Color(HARD_INK, 0.72), 1.5)
	draw_rect(r, SOLID_EDGE, false, 2.0)
	if moving:
		_draw_travel_marks(r, motion)
	else:
		_draw_hard_rivets(r, accent)
	_draw_material_label(r, "HARD // MOVE" if moving else "HARD", HARD_INK)


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
	_draw_break_stripes(r)
	_draw_material_label(r, "BREAK", Color(1.0, 0.84, 0.42))

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


func _draw_hard_rivets(r: Rect2, accent: Color) -> void:
	if r.size.x < 44.0 or r.size.y < 12.0:
		return
	for x in range(int(r.position.x) + 12, int(r.end.x) - 5, 42):
		draw_circle(Vector2(float(x), r.position.y + minf(11.0, r.size.y * 0.55)),
			2.2, accent.lightened(0.35))


func _draw_break_stripes(r: Rect2) -> void:
	if r.size.y < 10.0:
		return
	for x in range(int(r.position.x) - int(r.size.y), int(r.end.x), 24):
		var a := Vector2(float(x), r.end.y - 2.0)
		var b := Vector2(float(x) + r.size.y, r.position.y + 5.0)
		draw_line(a, b, Color(1.0, 0.48, 0.10, 0.55), 3.0)


func _draw_material_label(r: Rect2, text: String, col: Color) -> void:
	if r.size.x < 86.0 or r.size.y < 13.0 or r.position.x < 0.0:
		return
	draw_string(ThemeDB.fallback_font, r.position + Vector2(9.0, minf(13.0, r.size.y - 2.0)),
		text, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 18.0, 8, Color(col, 0.82))


## A non-wrapping side is an explicit steel bulkhead, never an invisible rule.
func _draw_hard_side_boundaries() -> void:
	var accent: Color = HARD_ACCENTS[level_theme]
	for x in [0.0, 1268.0]:
		draw_rect(Rect2(x, 190.0, 12.0, 530.0), Color(0.025, 0.055, 0.085, 0.98))
		draw_rect(Rect2(x, 190.0, 12.0, 530.0), accent, false, 2.0)
		for y in range(205, 710, 34):
			draw_line(Vector2(x + 2.0, float(y)), Vector2(x + 10.0, float(y) + 10.0),
				HARD_INK, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(16.0, 208.0), "NO PASS // HARD WALL",
		HORIZONTAL_ALIGNMENT_LEFT, 150.0, 9, Color(HARD_INK, 0.88))
	draw_string(ThemeDB.fallback_font, Vector2(1114.0, 208.0), "HARD WALL // NO PASS",
		HORIZONTAL_ALIGNMENT_RIGHT, 150.0, 9, Color(HARD_INK, 0.88))


## Cyan dashed seams appear only where both horizontal edges are actually open.
## Solid side architecture interrupts the seam, so the cue never promises a
## portal through a wall that collision will reject.
func _draw_horizontal_portals() -> void:
	for y in range(216, 621, 12):
		if _point_blocked(Vector2(1.0, float(y))) \
				or _point_blocked(Vector2(1279.0, float(y))):
			continue
		var glow := Color(0.28, 0.95, 1.0, 0.78)
		draw_line(Vector2(1.0, float(y)), Vector2(8.0, float(y)), glow, 3.0)
		draw_line(Vector2(1272.0, float(y)), Vector2(1279.0, float(y)), glow, 3.0)
		if y % 24 == 0:
			draw_line(Vector2(4.0, float(y) - 4.0), Vector2(9.0, float(y)), glow, 1.5)
			draw_line(Vector2(1276.0, float(y) - 4.0), Vector2(1271.0, float(y)), glow, 1.5)
	draw_string(ThemeDB.fallback_font, Vector2(14.0, 208.0), "WRAP →",
		HORIZONTAL_ALIGNMENT_LEFT, 80.0, 9, Color(0.45, 0.98, 1.0, 0.9))
	draw_string(ThemeDB.fallback_font, Vector2(1186.0, 208.0), "← WRAP",
		HORIZONTAL_ALIGNMENT_RIGHT, 80.0, 9, Color(0.45, 0.98, 1.0, 0.9))


## Vertical wrap is marked as one paired aperture: only x positions open at the
## authored ceiling AND floor receive the matching top/bottom portal rail.
func _draw_vertical_portal() -> void:
	for x in range(16, 1265, 12):
		if _point_blocked(Vector2(float(x), 217.0)) \
				or _point_blocked(Vector2(float(x), 621.0)):
			continue
		var glow := Color(0.30, 0.96, 1.0, 0.82)
		draw_line(Vector2(float(x), 216.0), Vector2(float(x) + 8.0, 216.0), glow, 3.0)
		draw_line(Vector2(float(x), 716.0), Vector2(float(x) + 8.0, 716.0), glow, 3.0)
		if x % 24 == 16:
			draw_line(Vector2(float(x) + 2.0, 211.0), Vector2(float(x) + 6.0, 216.0), glow, 1.5)
			draw_line(Vector2(float(x) + 2.0, 721.0), Vector2(float(x) + 6.0, 716.0), glow, 1.5)
	draw_string(ThemeDB.fallback_font, Vector2(590.0, 208.0), "WRAP ↑ / ↓",
		HORIZONTAL_ALIGNMENT_CENTER, 100.0, 9, Color(0.45, 0.98, 1.0, 0.9))


func _point_blocked(point: Vector2) -> bool:
	for pf: Dictionary in platforms:
		var r: Rect2 = pf["rect"]
		if r.position.x < 0.0 or r.position.x >= 1280.0:
			continue
		if r.has_point(point):
			return true
	return false
