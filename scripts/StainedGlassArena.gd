extends "res://scripts/Arena.gd"

## Foreground terrain rendered as load-bearing leadwork filled with dark glass.
## Mechanical categories remain readable: gold is HARD, violet moves, warm red
## breaks. Only presentation changes; Arena continues to own the same data.

const GLASS_INK := Color(0.006, 0.007, 0.015, 0.98)
const GLASS_FACE := Color(0.035, 0.050, 0.105, 0.96)
const GOLD := Color(0.98, 0.70, 0.19)
const VIOLET := Color(0.72, 0.38, 1.0)
const CYAN := Color(0.42, 0.92, 1.0)
const BREAK_RED := Color(0.92, 0.22, 0.16)


func _draw() -> void:
	for pf: Dictionary in platforms:
		var r: Rect2 = pf["rect"]
		if r.position.x < -1.0 or r.position.x >= 1280.0:
			continue
		if int(pf["hp"]) == INDESTRUCTIBLE:
			_draw_glass_solid(r, pf.get("motion", {}))
		else:
			_draw_glass_breakable(r, int(pf["hp"]), int(pf.get("max_hp", pf["hp"])))
	if wrap_x:
		_draw_horizontal_portals()
	else:
		_draw_glass_boundaries()
	if wrap_y:
		_draw_vertical_portal()


func _draw_glass_solid(r: Rect2, motion: Dictionary) -> void:
	var moving := not motion.is_empty()
	var accent := VIOLET if moving else GOLD
	_draw_platform_shell(r, accent, GLASS_FACE)
	_draw_facets(r, Color(0.17, 0.24, 0.48, 0.30), Color(0.30, 0.12, 0.43, 0.24))
	_draw_central_gem(r, accent)
	if moving:
		_draw_travel_marks(r, motion)


func _draw_glass_breakable(r: Rect2, hp: int, max_hp: int) -> void:
	var wear := 1.0 - float(hp) / float(maxi(max_hp, 1))
	var accent := GOLD.lerp(BREAK_RED, wear)
	_draw_platform_shell(r, accent, Color(0.20, 0.075, 0.095, 0.96))
	_draw_facets(r, Color(0.55, 0.13, 0.17, 0.34), Color(0.80, 0.32, 0.10, 0.24))
	_draw_central_gem(r, accent)
	var crack_count := 1 + int(round(wear * 4.0))
	for i in crack_count:
		var x := r.position.x + r.size.x * (float(i) + 0.5) / float(crack_count)
		draw_polyline(PackedVector2Array([
			Vector2(x - 3.0, r.position.y + 5.0), Vector2(x + 4.0, r.position.y + r.size.y * 0.48),
			Vector2(x - 2.0, r.end.y - 2.0),
		]), Color(GLASS_INK.r, GLASS_INK.g, GLASS_INK.b, 0.82), 2.0, true)
	_draw_hp_gems(r, hp, max_hp)


func _draw_platform_shell(r: Rect2, accent: Color, face: Color) -> void:
	draw_rect(Rect2(r.position + Vector2(7.0, 9.0), r.size), Color(0.0, 0.0, 0.01, 0.72))
	draw_rect(r, GLASS_INK)
	var inside := r.grow(-3.0)
	if inside.size.x > 0.0 and inside.size.y > 0.0:
		draw_rect(inside, face)
	draw_rect(Rect2(r.position + Vector2(2.0, 2.0), Vector2(maxf(0.0, r.size.x - 4.0), 5.0)), accent)
	draw_line(r.position + Vector2(3.0, 8.0), Vector2(r.end.x - 3.0, r.position.y + 8.0),
		accent.lightened(0.30), 1.0)
	draw_rect(r, GLASS_INK, false, 4.0)


func _draw_facets(r: Rect2, a: Color, b: Color) -> void:
	if r.size.x < 34.0 or r.size.y < 12.0:
		return
	var top := r.position.y + 9.0
	var bottom := r.end.y - 3.0
	var quarter := r.size.x * 0.25
	var points := [
		Vector2(r.position.x + quarter, top),
		Vector2(r.position.x + quarter * 2.0, bottom),
		Vector2(r.position.x + quarter * 3.0, top),
	]
	draw_colored_polygon(PackedVector2Array([
		Vector2(r.position.x + 3.0, top), points[0], points[1], Vector2(r.position.x + 3.0, bottom),
	]), a)
	draw_colored_polygon(PackedVector2Array([
		points[1], points[2], Vector2(r.end.x - 3.0, top), Vector2(r.end.x - 3.0, bottom),
	]), b)
	for point: Vector2 in points:
		draw_line(point, Vector2(point.x + quarter * 0.45, bottom if point.y == top else top),
			Color(GLASS_INK.r, GLASS_INK.g, GLASS_INK.b, 0.72), 1.5)


func _draw_central_gem(r: Rect2, accent: Color) -> void:
	if r.size.x < 54.0 or r.size.y < 10.0:
		return
	var c := Vector2(r.get_center().x, r.position.y + minf(11.0, r.size.y * 0.5))
	var radius := minf(4.0, r.size.y * 0.24)
	var gem := PackedVector2Array([
		c + Vector2(0.0, -radius), c + Vector2(radius, 0.0),
		c + Vector2(0.0, radius), c + Vector2(-radius, 0.0),
	])
	draw_colored_polygon(gem, accent.lightened(0.25))
	draw_polyline(gem + PackedVector2Array([gem[0]]), GLASS_INK, 1.2, true)


func _draw_hp_gems(r: Rect2, hp: int, max_hp: int) -> void:
	var spacing := 8.0
	var start := r.get_center().x - float(max_hp - 1) * spacing * 0.5
	for i in max_hp:
		var c := Vector2(start + float(i) * spacing, r.position.y - 7.0)
		var col := Color(1.0, 0.74, 0.24) if i < hp else Color(0.25, 0.15, 0.20, 0.62)
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(0.0, -3.0), c + Vector2(3.0, 0.0),
			c + Vector2(0.0, 3.0), c + Vector2(-3.0, 0.0),
		]), col)


func _draw_glass_boundaries() -> void:
	for x in [0.0, 1268.0]:
		draw_rect(Rect2(x, 188.0, 12.0, 532.0), GLASS_INK)
		draw_line(Vector2(x + 6.0, 196.0), Vector2(x + 6.0, 712.0), GOLD, 2.0)
		for y in range(212, 710, 42):
			draw_colored_polygon(PackedVector2Array([
				Vector2(x + 6.0, float(y) - 5.0), Vector2(x + 11.0, float(y)),
				Vector2(x + 6.0, float(y) + 5.0), Vector2(x + 1.0, float(y)),
			]), Color(0.34, 0.16, 0.48, 0.82))
