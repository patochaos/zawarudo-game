extends Node2D

## Baked architecture and quiet cosmetic air. Never supplies simulation state.
const W := 1280.0
const H := 720.0
## Indexed by arena: Crosshair Court, Clockwork Gallery (foundry scenery),
## Stilled Hall (sanctum scenery), Pulse Chamber, Endless Descent.
const BACKDROPS := [
	preload("res://assets/art/arenas/crosshair-court/backdrop.png"),
	preload("res://assets/art/arenas/foundry/backdrop.png"),
	preload("res://assets/art/arenas/shattered-sanctum/backdrop.png"),
	preload("res://assets/art/arenas/pulse-chamber/backdrop.png"),
	preload("res://assets/art/arenas/endless-descent/backdrop.png"),
]
const GRADES := [
	Color(0.39, 0.38, 0.45), Color(0.30, 0.44, 0.40), Color(0.34, 0.30, 0.50),
	Color(0.29, 0.44, 0.49), Color(0.31, 0.42, 0.53),
]
const AIR_COLORS := [
	Color(0.80, 0.72, 0.48), Color(0.40, 0.90, 0.70), Color(0.70, 0.55, 0.95),
	Color(0.30, 0.72, 0.77), Color(0.42, 0.62, 0.80),
]
const PATTERN_TEXTURES := [
	preload("res://assets/kenney/patterns/crosshair-court.png"),
	preload("res://assets/kenney/patterns/foundry.png"),
	preload("res://assets/kenney/patterns/shattered-sanctum.png"),
	preload("res://assets/kenney/patterns/pulse-chamber.png"),
	preload("res://assets/kenney/patterns/endless-descent.png"),
]
const DESCENT := 4

var level_theme: int = 0
var gm
var atmosphere_time: float = 0.0


func _process(delta: float) -> void:
	if gm == null:
		return
	# Air stays in exactly the same place during planning and online waiting.
	if gm.state in [Phase.EXECUTING, Phase.FREEPLAY]:
		atmosphere_time += delta
		queue_redraw()
	# Replay restores world_tick directly. Redraw also when scrubbing a paused
	# frame; never integrate a second combat clock for the machinery.
	if level_theme == DESCENT:
		queue_redraw()


func show_level(index: int) -> void:
	level_theme = posmod(index, BACKDROPS.size())
	atmosphere_time = 0.0
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, W, H), Color("090b16"))
	draw_texture_rect(BACKDROPS[level_theme], Rect2(0, 0, W, H), false, GRADES[level_theme])
	if level_theme == DESCENT:
		_draw_descent_air()
	# Two recessed corner motifs replace the former full-screen wallpaper.
	if level_theme != DESCENT:
		for x in [60.0, 1076.0]:
			draw_texture_rect(PATTERN_TEXTURES[level_theme], Rect2(x, 90, 144, 144),
				false, Color(AIR_COLORS[level_theme], 0.018))
	if level_theme in [0, 2]:
		for i in 12:
			var x := 190.0 + float(i) * 7.0
			draw_colored_polygon(PackedVector2Array([
				Vector2(x, 75), Vector2(x + 45, 75),
				Vector2(x + 275, 620), Vector2(x + 130, 620),
			]), Color(0.40, 0.49, 0.75, 0.006))
	for i in 32:
		var p := observatory_mote_position(i)
		var tint := Color(AIR_COLORS[level_theme], 0.14 + float(i % 3) * 0.035)
		draw_circle(p, 0.7 + float(i % 3) * 0.25, tint)
		if i % 7 == 0:
			draw_line(p, p + Vector2(2.0, -1.0), tint, 1.0)
	# Foreground trim is restricted to the sides; wrap openings remain clear.
	for x in [16.0, 1240.0]:
		draw_rect(Rect2(x, 76, 24, 644), Color(0.018, 0.020, 0.037, 0.80))


## Combat, hit pauses, SUPER and replay all follow the authoritative clock.
## Free play has no ticking world clock, so use its existing cosmetic air time.
func machinery_time() -> float:
	if gm == null:
		return 0.0
	if gm.state == Phase.FREEPLAY:
		return atmosphere_time
	return float(gm.world_tick) * gm.tick_dt()


func _draw_descent_air() -> void:
	# Recessed light shafts frame the routes; the central knife lane stays dark.
	for side in [-1.0, 1.0]:
		var x: float = 640.0 + side * 410.0
		for band in 8:
			var spread := 12.0 + float(band) * 7.0
			draw_colored_polygon(PackedVector2Array([
				Vector2(x - 5, 80), Vector2(x + 5, 80),
				Vector2(x + spread, 615), Vector2(x - spread, 615)]),
				Color(0.18, 0.48, 0.58, 0.004))
	var clock := machinery_time()
	for i in 24:
		var x := 400.0 + fposmod(float(i) * 137.3, 480.0)
		var y := 86.0 + fposmod(float(i) * 83.7 + clock * (11.0 + float(i % 4) * 3.0), 550.0)
		draw_line(Vector2(x, y), Vector2(x, y + 2.5), Color(0.24, 0.48, 0.56, 0.14), 1.0)


func observatory_mote_position(index: int) -> Vector2:
	var seed_x := fposmod(float(index) * 173.31, 1200.0)
	var seed_y := fposmod(float(index) * 97.73, 520.0)
	var drift := -1.0 if level_theme == 1 else 1.0
	return Vector2(40.0 + fposmod(seed_x + atmosphere_time * (2.0 + float(index % 3)), 1200.0),
		100.0 + fposmod(seed_y + drift * atmosphere_time * (3.0 + float(index % 4)), 520.0))
