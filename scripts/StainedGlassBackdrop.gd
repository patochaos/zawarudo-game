extends Node2D

## A deliberately recessed cathedral window. The glass carries the game's
## identity, while a navy veil keeps trajectories, fighters and terrain in the
## foreground. Everything is procedural so every authored arena can reuse it.

const W := 1280.0
const H := 720.0
const PLAYFIELD_TOP := 188.0
const PLAYFIELD_BOTTOM := 632.0
const LEAD := Color(0.008, 0.010, 0.022, 0.78)
const VEIL := Color(0.012, 0.020, 0.050, 0.18)
const CATHEDRAL_GLASS := preload("res://assets/art/backgrounds/stained-glass-cathedral-v1.png")

const PALETTES := [
	[Color(0.16, 0.23, 0.55), Color(0.32, 0.12, 0.42), Color(0.58, 0.30, 0.12)],
	[Color(0.09, 0.29, 0.52), Color(0.17, 0.17, 0.43), Color(0.18, 0.43, 0.48)],
	[Color(0.20, 0.16, 0.52), Color(0.43, 0.12, 0.45), Color(0.58, 0.36, 0.10)],
	[Color(0.07, 0.34, 0.42), Color(0.12, 0.18, 0.45), Color(0.36, 0.13, 0.45)],
	[Color(0.21, 0.18, 0.52), Color(0.47, 0.10, 0.30), Color(0.56, 0.29, 0.11)],
	[Color(0.36, 0.10, 0.18), Color(0.20, 0.12, 0.40), Color(0.58, 0.25, 0.07)],
	[Color(0.30, 0.11, 0.48), Color(0.12, 0.22, 0.52), Color(0.45, 0.28, 0.10)],
]

var level_theme: int = 0


func show_level(index: int) -> void:
	level_theme = posmod(index, PALETTES.size())
	queue_redraw()


func _draw() -> void:
	var palette: Array = PALETTES[level_theme]
	_draw_night_gradient(palette)
	# The generated plate supplies real glass grain and medium-scale leadwork.
	# It contains no gameplay objects, so every arena can safely reuse it.
	draw_texture_rect(CATHEDRAL_GLASS, Rect2(0.0, 0.0, W, H), false,
		Color(0.88, 0.90, 1.0, 0.82))
	# A faint per-arena tint keeps level cycling visible without replacing the
	# approved background hierarchy or multiplying production textures.
	var theme_tint: Color = palette[level_theme % palette.size()]
	draw_rect(Rect2(0.0, 0.0, W, H), Color(theme_tint.r, theme_tint.g, theme_tint.b, 0.055))
	# The approved hierarchy: the stained glass remains richly constructed, but
	# lives behind a translucent atmospheric layer instead of competing with play.
	draw_rect(Rect2(0.0, PLAYFIELD_TOP, W, PLAYFIELD_BOTTOM - PLAYFIELD_TOP), VEIL)
	draw_rect(Rect2(0.0, 0.0, W, H), Color(0.0, 0.0, 0.018, 0.16))


func _draw_night_gradient(palette: Array) -> void:
	var top := Color(0.007, 0.009, 0.027)
	var bottom: Color = Color(palette[0]).darkened(0.72)
	for band in 28:
		var t := float(band) / 27.0
		draw_rect(Rect2(0.0, t * H, W, H / 27.0 + 1.0), top.lerp(bottom, t * t))


func _draw_cathedral_bays(palette: Array) -> void:
	var bay_width := W / 5.0
	for bay in 5:
		var left := float(bay) * bay_width
		var right := left + bay_width
		var centre := (left + right) * 0.5
		var apex := 76.0 + float(abs(bay - 2)) * 24.0
		var shoulder := 222.0
		var bottom := PLAYFIELD_BOTTOM
		var base: Color = palette[bay % palette.size()]
		var alternate: Color = palette[(bay + 1) % palette.size()]
		var pane_alpha := 0.25 if bay == 2 else 0.20

		# Broad panes establish the quiet hierarchy; diagonal subdivisions supply
		# the stained-glass read without turning the playfield into confetti.
		var panes := [
			PackedVector2Array([Vector2(left + 12.0, bottom), Vector2(left + 12.0, shoulder),
				Vector2(centre, apex), Vector2(centre - 26.0, bottom)]),
			PackedVector2Array([Vector2(centre, apex), Vector2(right - 12.0, shoulder),
				Vector2(right - 12.0, bottom), Vector2(centre - 26.0, bottom)]),
		]
		draw_colored_polygon(panes[0], Color(base.r, base.g, base.b, pane_alpha))
		draw_colored_polygon(panes[1], Color(alternate.r, alternate.g, alternate.b, pane_alpha))
		for pane: PackedVector2Array in panes:
			draw_polyline(pane + PackedVector2Array([pane[0]]), LEAD, 5.0, true)

		for y in [300.0, 438.0, 555.0]:
			var offset := 24.0 if int(y) % 2 == 0 else -18.0
			draw_line(Vector2(left + 15.0, y), Vector2(right - 15.0, y + offset),
				Color(LEAD.r, LEAD.g, LEAD.b, 0.52), 3.0)
		draw_line(Vector2(centre, apex), Vector2(centre - 26.0, bottom),
			Color(LEAD.r, LEAD.g, LEAD.b, 0.64), 4.0)

	# Heavy mullions read as architecture and frame each bay.
	for x in range(0, 1281, 256):
		draw_rect(Rect2(float(x) - 5.0, 142.0, 10.0, 498.0), Color(0.005, 0.006, 0.014, 0.90))


func _draw_clock_rose(centre: Vector2, radius: float, palette: Array) -> void:
	draw_circle(centre, radius + 18.0, Color(0.004, 0.006, 0.014, 0.74))
	for ring in [radius, radius * 0.68, radius * 0.35]:
		draw_arc(centre, ring, 0.0, TAU, 72, Color(0.68, 0.47, 0.18, 0.30), 4.0)
	for spoke in 16:
		var a := -PI * 0.5 + TAU * float(spoke) / 16.0
		var d := Vector2.from_angle(a)
		var side := d.orthogonal()
		var inner := radius * (0.35 if spoke % 2 == 0 else 0.68)
		var col: Color = palette[spoke % palette.size()]
		var pane := PackedVector2Array([
			centre + d * inner,
			centre + d * (radius - 5.0) + side * 14.0,
			centre + d * (radius - 5.0) - side * 14.0,
		])
		draw_colored_polygon(pane, Color(col.r, col.g, col.b, 0.29))
		draw_polyline(pane + PackedVector2Array([pane[0]]), LEAD, 3.0, true)


func _draw_lower_glass(palette: Array) -> void:
	var y0 := PLAYFIELD_BOTTOM
	var y1 := H
	for cell in 8:
		var x0 := float(cell) * W / 8.0
		var x1 := float(cell + 1) * W / 8.0
		var mid := (x0 + x1) * 0.5
		var col: Color = palette[cell % palette.size()]
		var pane := PackedVector2Array([
			Vector2(x0, y1), Vector2(x0, y0), Vector2(mid, y0 + 38.0), Vector2(x1, y0), Vector2(x1, y1),
		])
		draw_colored_polygon(pane, Color(col.r, col.g, col.b, 0.30))
		draw_polyline(pane + PackedVector2Array([pane[0]]), LEAD, 5.0, true)
