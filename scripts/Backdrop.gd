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

const SKY_BOTTOMS := [
	Color(0.10, 0.060, 0.15),  # Crosshair Court — neutral violet
	Color(0.045, 0.085, 0.16), # Endless Descent — cold vertical void
	Color(0.085, 0.055, 0.18), # Pendulum — observatory violet
	Color(0.040, 0.115, 0.16), # Pulse Chamber — charged cyan
	Color(0.12, 0.055, 0.17),  # Shattered Sanctum — royal violet
	Color(0.17, 0.050, 0.075), # Foundry — banked furnace heat
	Color(0.105, 0.045, 0.16), # Collision Course — deep clock violet
]

var horizon: float = 620.0
var _stars: PackedVector2Array = PackedVector2Array()
var level_theme: int = 0


func _ready() -> void:
	# Fixed layout — no Math.random at draw time, so the scene is reproducible.
	var seeded := RandomNumberGenerator.new()
	seeded.seed = 20260808
	for i in 90:
		_stars.append(Vector2(seeded.randf() * W, seeded.randf() * 420.0))


func show_level(index: int) -> void:
	level_theme = posmod(index, SKY_BOTTOMS.size())
	queue_redraw()


func _draw() -> void:
	# sky gradient, banded (cheap and looks intentional at this fidelity)
	var bands := 24
	for i in bands:
		var t: float = float(i) / float(bands - 1)
		var y: float = t * horizon
		draw_rect(Rect2(0.0, y, W, horizon / float(bands) + 1.0),
			SKY_TOP.lerp(SKY_BOTTOMS[level_theme], t * t))

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
	match level_theme:
		0:
			_draw_crosshair_court()
		1:
			_draw_descent_towers()
		2:
			_draw_observatory()
		3:
			_draw_pulse_reactor()
		4:
			_draw_ruins()
		5:
			_draw_foundry()
		6:
			_draw_collision_works()

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


func _draw_crosshair_court() -> void:
	var ink := Color(0.025, 0.035, 0.065, 0.76)
	var line := Color(0.96, 0.76, 0.30, 0.105)
	# A measured range grid makes the first arena feel like the neutral training
	# standard against which every later visual rule is compared.
	for x in range(80, 1280, 80):
		draw_line(Vector2(float(x), 220.0), Vector2(float(x), 620.0), line, 1.0)
	for y in range(260, 621, 60):
		draw_line(Vector2(0.0, float(y)), Vector2(1280.0, float(y)), line, 1.0)
	var centre := Vector2(640.0, 430.0)
	for radius in [70.0, 138.0, 210.0]:
		draw_circle(centre, radius + 10.0, Color(ink, 0.12))
		draw_arc(centre, radius, 0.0, TAU, 64, line, 2.0)
	draw_line(Vector2(390.0, centre.y), Vector2(890.0, centre.y), line, 2.0)
	draw_line(Vector2(centre.x, 235.0), Vector2(centre.x, 615.0), line, 2.0)


func _draw_pulse_reactor() -> void:
	var cyan := Color(0.30, 0.96, 1.0, 0.11)
	var dark := Color(0.015, 0.055, 0.085, 0.72)
	# Concentric capacitors echo the public blast radii without pretending to be
	# live hazards; their broken arcs and cables distinguish this room at a glance.
	for centre in [Vector2(260.0, 430.0), Vector2(640.0, 455.0), Vector2(1020.0, 430.0)]:
		draw_circle(centre, 86.0, dark)
		for radius in [38.0, 60.0, 84.0]:
			draw_arc(centre, radius, -2.7, 2.35, 40, cyan, 2.0)
		for spoke in 8:
			var d := Vector2.from_angle(TAU * float(spoke) / 8.0)
			draw_line(centre + d * 63.0, centre + d * 82.0, cyan, 2.0)
	draw_line(Vector2(260.0, 430.0), Vector2(640.0, 455.0), cyan, 3.0)
	draw_line(Vector2(640.0, 455.0), Vector2(1020.0, 430.0), cyan, 3.0)


func _draw_collision_works() -> void:
	var rail := Color(0.86, 0.47, 1.0, 0.11)
	var node := Color(0.96, 0.72, 0.26, 0.10)
	# Crossing rails and offset timing wheels create a denser final-arena
	# silhouette while remaining behind all real mover rails and trajectories.
	for y in [280.0, 380.0, 480.0, 580.0]:
		draw_line(Vector2(120.0, y), Vector2(1160.0, 640.0 - y * 0.35), rail, 3.0)
		draw_line(Vector2(1160.0, y), Vector2(120.0, 640.0 - y * 0.35), rail, 3.0)
	for centre in [Vector2(360.0, 440.0), Vector2(640.0, 365.0), Vector2(920.0, 440.0)]:
		draw_circle(centre, 72.0, Color(0.025, 0.02, 0.07, 0.58))
		draw_arc(centre, 72.0, 0.0, TAU, 40, node, 2.0)
		for tooth in 12:
			var d := Vector2.from_angle(TAU * float(tooth) / 12.0)
			draw_line(centre + d * 62.0, centre + d * 78.0, node, 2.0)


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


func _draw_descent_towers() -> void:
	var stone := Color(0.025, 0.035, 0.075, 0.84)
	var edge := Color(0.34, 0.62, 0.90, 0.10)
	# Tall rails continue beyond the frame and make vertical wrapping feel like
	# one impossible shaft rather than an arbitrary teleport.
	for x in [118.0, 214.0, 1066.0, 1162.0]:
		draw_rect(Rect2(x - 24.0, 190.0, 48.0, 430.0), stone)
		draw_line(Vector2(x - 16.0, 205.0), Vector2(x - 16.0, 610.0), edge, 2.0)
		draw_line(Vector2(x + 16.0, 205.0), Vector2(x + 16.0, 610.0), edge, 2.0)
		for rung in 8:
			var y := 226.0 + float(rung) * 48.0
			draw_line(Vector2(x - 13.0, y), Vector2(x + 13.0, y), edge, 1.0)
	for y in [270.0, 370.0, 470.0]:
		draw_arc(Vector2(640.0, y), 54.0, 0.15, PI - 0.15, 26,
			Color(0.62, 0.82, 1.0, 0.045), 2.0)


func _draw_observatory() -> void:
	var ink := Color(0.030, 0.020, 0.072, 0.76)
	var brass := Color(0.82, 0.61, 0.22, 0.10)
	var centre := Vector2(640.0, 500.0)
	# A quiet astronomical mechanism echoes the level's moving platforms while
	# remaining clearly behind every trajectory and fighter silhouette.
	draw_circle(centre, 154.0, ink)
	for radius in [94.0, 126.0, 154.0]:
		draw_arc(centre, radius, 0.0, TAU, 64, brass, 1.5)
	for tick in 16:
		var d := Vector2.from_angle(TAU * float(tick) / 16.0)
		draw_line(centre + d * 137.0, centre + d * 154.0, brass, 2.0)
	draw_line(Vector2(640.0, 180.0), centre - Vector2(55.0, 6.0), brass, 3.0)
	draw_circle(centre - Vector2(55.0, 6.0), 24.0, Color(0.11, 0.065, 0.16, 0.72))
	draw_arc(centre - Vector2(55.0, 6.0), 24.0, 0.0, TAU, 32, brass, 2.0)


func _draw_foundry() -> void:
	var iron := Color(0.055, 0.025, 0.055, 0.88)
	var ember := Color(1.0, 0.30, 0.12, 0.075)
	# Furnace stacks and restrained heat bands distinguish the foundry without
	# turning the background into false hazards.
	for x in [104.0, 224.0, 1056.0, 1176.0]:
		var top := 265.0 if int(x) % 200 < 100 else 330.0
		draw_rect(Rect2(x - 30.0, top, 60.0, 620.0 - top), iron)
		draw_rect(Rect2(x - 37.0, top - 10.0, 74.0, 12.0), iron)
		draw_line(Vector2(x - 22.0, top + 18.0), Vector2(x - 22.0, 608.0),
			Color(0.70, 0.25, 0.15, 0.12), 2.0)
	for band in 6:
		var y := 500.0 + float(band) * 18.0
		draw_rect(Rect2(300.0, y, 680.0, 5.0),
			Color(ember.r, ember.g, ember.b, ember.a * (1.0 - float(band) / 7.0)))
	for x in range(420, 900, 80):
		draw_rect(Rect2(float(x), 560.0, 34.0, 24.0), Color(0.22, 0.055, 0.05, 0.25))
		draw_rect(Rect2(float(x) + 5.0, 565.0, 24.0, 14.0), ember)
