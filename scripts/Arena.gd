extends Node2D
class_name Arena

## Renders the platform set. Layouts live in Levels.gd; damage state lives in
## GameManager. Terrain never damages a player — only arrows do.
##
## Indestructible geometry uses cool dressed surfaces; breakable geometry is warm, carries
## hit pips, and reddens and cracks as it takes damage. Moving geometry keeps the
## permanent silhouette but swaps its top edge for violet and wears chevrons
## pointing along its rail. That three-way colour split is the only thing a player
## has to learn to read the arena — and the moving read has to survive execution,
## when every planning overlay is stripped away.

const INDESTRUCTIBLE := -1
const STAGE_TOP := Levels.STAGE_TOP
const OBSERVATORY_SOLID := preload("res://assets/art/arenas/pendulum/solid.png")
const OBSERVATORY_MOVING := preload("res://assets/art/arenas/pendulum/moving.png")
const OBSERVATORY_BREAKABLE := preload("res://assets/art/arenas/pendulum/breakable.png")
const SOLID_TEXTURES := [
	preload("res://assets/art/arenas/crosshair-court/solid.png"),
	preload("res://assets/art/arenas/endless-descent/solid.png"),
	OBSERVATORY_SOLID,
	preload("res://assets/art/arenas/pulse-chamber/solid.png"),
	preload("res://assets/art/arenas/shattered-sanctum/solid.png"),
	preload("res://assets/art/arenas/foundry/solid.png"),
	preload("res://assets/art/arenas/collision-course/solid.png"),
]

const HARD_INK := Color(0.72, 0.92, 1.0)
const HARD_ACCENTS := [
	Color(0.95, 0.78, 0.28), Color(0.38, 0.80, 1.0), Color(0.72, 0.60, 1.0),
	Color(0.30, 1.0, 0.92), Color(0.95, 0.58, 0.30), Color(1.0, 0.35, 0.22),
	Color(0.92, 0.45, 1.0),
]

const MOVER_TOP := Color(0.66, 0.55, 0.95)
const MOVER_MARK := Color(0.80, 0.72, 1.0, 0.75)

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
	_draw_material_platform(r, OBSERVATORY_MOVING if moving else SOLID_TEXTURES[level_theme],
		MOVER_TOP if moving else Color(0.51, 0.60, 0.70))
	if moving:
		_draw_travel_marks(r, motion)


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
	var tall := r.size.y > r.size.x * 2.0
	if tall:
		span = r.size.y
	var count: int = clampi(int(span / 64.0), 1, 8)
	for i in count:
		var t: float = (float(i) + 0.5) / float(count)
		var at: Vector2 = r.position + Vector2(r.size.x * t, minf(13.0, r.size.y * 0.55)) \
			if absf(along.x) > absf(along.y) \
			else r.position + Vector2(r.size.x * 0.5, r.size.y * t)
		if tall:
			at = r.position + Vector2(r.size.x * 0.5, r.size.y * t)
		var wing: Vector2 = d.orthogonal() * 5.0
		draw_line(at - wing - d * 4.0, at + d * 4.0, MOVER_MARK, 1.6, true)
		draw_line(at + wing - d * 4.0, at + d * 4.0, MOVER_MARK, 1.6, true)


func _draw_breakable(r: Rect2, hp: int, max_hp: int) -> void:
	var wear: float = 1.0 - float(hp) / float(maxi(max_hp, 1))
	_draw_material_platform(r, OBSERVATORY_BREAKABLE,
		BREAK_TOP.lerp(BREAK_TOP_BROKEN, wear), Color.WHITE.lerp(Color(1.0, 0.40, 0.30), wear))

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


func _draw_material_platform(r: Rect2, texture: Texture2D, lip: Color,
		tint: Color = Color.WHITE) -> void:
	# Art stays inside collision. Deep bases get quiet masonry below one ledge;
	# end caps retain their physical width on every authored platform length.
	var moving: bool = texture == OBSERVATORY_MOVING
	var base := Color("302217") if texture == OBSERVATORY_BREAKABLE else Color("141b29")
	draw_rect(r, base * tint)
	if moving and r.size.y > 32.0:
		# Tall shutters need a mechanical face and full-height motion identity.
		for x in [r.position.x + 2.0, r.end.x - 3.0]:
			draw_line(Vector2(x, r.position.y + 2), Vector2(x, r.end.y - 2),
				Color(MOVER_TOP, 0.65), 2.0)
		for y in range(int(r.position.y) + 22, int(r.end.y) - 2, 22):
			draw_line(Vector2(r.position.x + 6, y), Vector2(r.end.x - 6, y),
				Color("293047"), 2.0)
	elif r.size.y > 20.0 and level_theme == 1:
		# Descent bulkheads use riveted steel cassettes, not masonry courses.
		for x in range(int(r.position.x) + 6, int(r.end.x) - 4, 46):
			var panel_width := minf(40.0, r.end.x - float(x) - 4.0)
			if panel_width <= 0.0: continue
			draw_rect(Rect2(x, r.position.y + 18, panel_width, r.size.y - 20), Color("182630"))
			draw_line(Vector2(x, r.position.y + 19), Vector2(x, r.end.y - 3), Color("28424b"), 1.0)
			for y in range(int(r.position.y) + 26, int(r.end.y) - 5, 55):
				draw_circle(Vector2(x + 4, y), 1.2, Color("60706d"))
				draw_line(Vector2(x + 10, y + 6), Vector2(x + panel_width - 4, y + 6), Color("0c141e"), 2.0)
	elif r.size.y > 20.0:
		for row_index in range(1, ceili(r.size.y / 24.0)):
			var seam_y := minf(r.end.y - 1, r.position.y + float(row_index) * 24.0)
			draw_line(Vector2(r.position.x, seam_y), Vector2(r.end.x, seam_y),
				Color("0a101d"), 2.0)
			for column in range(ceili(r.size.x / 72.0)):
				var seam_x := r.position.x + float(column) * 72.0 + (36.0 if row_index % 2 else 0.0)
				if seam_x < r.end.x:
					draw_line(Vector2(seam_x, maxf(r.position.y + 16, seam_y - 24)),
						Vector2(seam_x, seam_y), Color("0a101d"), 2.0)
	var y := r.position.y
	if y < r.end.y:
		var height := minf(16.0, r.end.y - y)
		var row := Rect2(r.position.x, y, r.size.x, height)
		var cap := minf(12.0, r.size.x * 0.25)
		draw_texture_rect_region(texture, Rect2(row.position, Vector2(cap, height)),
			Rect2(0, 0, 24, 32), tint)
		draw_texture_rect_region(texture,
			Rect2(row.position + Vector2(cap, 0), Vector2(row.size.x - cap * 2, height)),
			Rect2(24, 0, 208, 32), tint)
		draw_texture_rect_region(texture,
			Rect2(row.end.x - cap, y, cap, height), Rect2(232, 0, 24, 32), tint)
	draw_line(r.position, Vector2(r.end.x, r.position.y), lip, 2.0)
	draw_line(Vector2(r.position.x, r.end.y - 1), r.end - Vector2(0, 1),
		Color("080b13"), 2.0)


## A non-wrapping side is an explicit steel bulkhead, never an invisible rule.
func _draw_hard_side_boundaries() -> void:
	var accent: Color = HARD_ACCENTS[level_theme]
	for x in [0.0, 1268.0]:
		draw_rect(Rect2(x, STAGE_TOP, 12.0, 720.0 - STAGE_TOP),
			Color(0.025, 0.055, 0.085, 0.98))
		draw_rect(Rect2(x, STAGE_TOP, 12.0, 720.0 - STAGE_TOP), accent, false, 2.0)
		for y in range(int(STAGE_TOP) + 15, 710, 34):
			draw_line(Vector2(x + 2.0, float(y)), Vector2(x + 10.0, float(y) + 10.0),
				HARD_INK, 2.0)


## Cyan dashed seams appear only where both horizontal edges are actually open.
## Solid side architecture interrupts the seam, so the cue never promises a
## portal through a wall that collision will reject.
func _draw_horizontal_portals() -> void:
	for y in range(int(STAGE_TOP), 621, 12):
		if _point_blocked(Vector2(1.0, float(y))) \
				or _point_blocked(Vector2(1279.0, float(y))):
			continue
		var glow := Color(0.28, 0.95, 1.0, 0.78)
		draw_line(Vector2(1.0, float(y)), Vector2(8.0, float(y)), glow, 3.0)
		draw_line(Vector2(1272.0, float(y)), Vector2(1279.0, float(y)), glow, 3.0)
		if y % 24 == 0:
			draw_line(Vector2(4.0, float(y) - 4.0), Vector2(9.0, float(y)), glow, 1.5)
			draw_line(Vector2(1276.0, float(y) - 4.0), Vector2(1271.0, float(y)), glow, 1.5)


## Vertical wrap is marked as one paired aperture: only x positions open at the
## authored ceiling AND floor receive the matching top/bottom portal rail.
func _draw_vertical_portal() -> void:
	for x in range(16, 1265, 12):
		if _point_blocked(Vector2(float(x), STAGE_TOP + 1.0)) \
				or _point_blocked(Vector2(float(x), 621.0)):
			continue
		var glow := Color(0.30, 0.96, 1.0, 0.82)
		draw_line(Vector2(float(x), STAGE_TOP),
			Vector2(float(x) + 8.0, STAGE_TOP), glow, 3.0)
		draw_line(Vector2(float(x), 716.0), Vector2(float(x) + 8.0, 716.0), glow, 3.0)
		if x % 24 == 16:
			draw_line(Vector2(float(x) + 2.0, STAGE_TOP + 5.0),
				Vector2(float(x) + 6.0, STAGE_TOP), glow, 1.5)
			draw_line(Vector2(float(x) + 2.0, 721.0), Vector2(float(x) + 6.0, 716.0), glow, 1.5)


func _point_blocked(point: Vector2) -> bool:
	for pf: Dictionary in platforms:
		var r: Rect2 = pf["rect"]
		if r.position.x < 0.0 or r.position.x >= 1280.0:
			continue
		if r.has_point(point):
			return true
	return false
