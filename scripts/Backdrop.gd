extends Node2D

## Static scenery behind everything. Deliberately low-contrast and desaturated:
## the preview lines drawn on top of it are the information that matters, so the
## backdrop's only job is to give depth without competing for attention.

const W := 1280.0
const H := 720.0

const SKY_TOP := Color(0.025, 0.018, 0.055)
const SKY_BOT := Color(0.12, 0.055, 0.17)
const HILL_FAR := Color(0.065, 0.045, 0.105)
const HILL_NEAR := Color(0.095, 0.065, 0.14)

var horizon: float = 620.0
var _stars: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	# Fixed layout — no Math.random at draw time, so the scene is reproducible.
	var seeded := RandomNumberGenerator.new()
	seeded.seed = 20260808
	for i in 90:
		_stars.append(Vector2(seeded.randf() * W, seeded.randf() * 420.0))


func _draw() -> void:
	# sky gradient, banded (cheap and looks intentional at this fidelity)
	var bands := 24
	for i in bands:
		var t: float = float(i) / float(bands - 1)
		var y: float = t * horizon
		draw_rect(Rect2(0.0, y, W, horizon / float(bands) + 1.0), SKY_TOP.lerp(SKY_BOT, t * t))

	# Oversized eclipsed moon: one readable aristocratic landmark shared by all
	# arenas, held low enough in contrast not to compete with trajectories.
	var moon := Vector2(930.0, 325.0)
	for ring in 7:
		draw_circle(moon, 116.0 + float(6 - ring) * 10.0,
			Color(0.72, 0.43, 0.95, 0.010 + float(ring) * 0.004))
	draw_circle(moon, 112.0, Color(0.74, 0.58, 0.29, 0.085))
	draw_circle(moon + Vector2(-28.0, -12.0), 105.0, Color(0.035, 0.022, 0.07, 0.78))
	draw_arc(moon, 112.0, -1.25, 1.85, 64, Color(0.91, 0.68, 0.28, 0.18), 2.0)

	# Sparse halftone field, a manga texture rather than naturalistic fog.
	for row in 7:
		for col in 15:
			var dot := Vector2(760.0 + float(col) * 31.0, 170.0 + float(row) * 28.0)
			var alpha: float = 0.025 + float((row + col) % 3) * 0.012
			draw_circle(dot, 1.2 + float(row % 2) * 0.4, Color(0.95, 0.72, 0.32, alpha))

	for s in _stars:
		var a: float = 0.10 + 0.22 * fposmod(s.x * 0.013 + s.y * 0.007, 1.0)
		draw_circle(s, 1.0, Color(0.75, 0.82, 1.0, a))

	# two silhouette ridges for depth
	_ridge(horizon, 150.0, 210.0, HILL_FAR)
	_ridge(horizon, 95.0, 330.0, HILL_NEAR)
	_draw_ruins()

	# glow along the horizon so the play area reads as the lit zone
	for i in 10:
		var t: float = float(i) / 9.0
		draw_rect(Rect2(0.0, horizon - 90.0 * (1.0 - t), W, 10.0),
			Color(0.35, 0.45, 0.70, 0.020 * t))


func _ridge(base: float, height: float, period: float, col: Color) -> void:
	var pts := PackedVector2Array()
	pts.append(Vector2(0.0, base))
	var x := 0.0
	while x <= W:
		var h: float = height * (0.55 + 0.45 * sin(x / period) * cos(x / (period * 0.43)))
		pts.append(Vector2(x, base - h))
		x += 20.0
	pts.append(Vector2(W, base))
	draw_colored_polygon(pts, col)


func _draw_ruins() -> void:
	var col := Color(0.035, 0.025, 0.065, 0.72)
	var edge := Color(0.62, 0.42, 0.18, 0.12)
	for x in [72.0, 1168.0]:
		draw_rect(Rect2(x - 34.0, 300.0, 68.0, 320.0), col)
		draw_rect(Rect2(x - 44.0, 292.0, 88.0, 12.0), col)
		draw_line(Vector2(x - 27.0, 305.0), Vector2(x - 27.0, 610.0), edge, 2.0)
		draw_line(Vector2(x + 27.0, 305.0), Vector2(x + 27.0, 610.0), edge, 2.0)
	# A broken triangular pediment keeps the horizon angular and theatrical.
	draw_colored_polygon(PackedVector2Array([
		Vector2(450.0, 620.0), Vector2(640.0, 465.0), Vector2(830.0, 620.0),
	]), Color(0.045, 0.03, 0.075, 0.50))
	draw_line(Vector2(480.0, 604.0), Vector2(640.0, 482.0), edge, 2.0)
	draw_line(Vector2(640.0, 482.0), Vector2(800.0, 604.0), edge, 2.0)
