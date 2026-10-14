extends Node2D

## Baked architecture and quiet cosmetic air. Never supplies simulation state.
const W := 1280.0
const H := 720.0
const PENDULUM_GEAR_LEFT := preload("res://assets/art/arenas/pendulum/gear-left.png")
const PENDULUM_GEAR_RIGHT := preload("res://assets/art/arenas/pendulum/gear-right.png")
const PENDULUM_HAND_LONG := preload("res://assets/art/arenas/pendulum/hand-long.png")
const PENDULUM_HAND_SHORT := preload("res://assets/art/arenas/pendulum/hand-short.png")
const PENDULUM_WEIGHT_LEFT := preload("res://assets/art/arenas/pendulum/weight-left.png")
const PENDULUM_WEIGHT_RIGHT := preload("res://assets/art/arenas/pendulum/weight-right.png")
const BACKDROPS := [
	preload("res://assets/art/arenas/crosshair-court/backdrop.png"),
	preload("res://assets/art/arenas/endless-descent/backdrop.png"),
	preload("res://assets/art/arenas/pendulum/observatory.png"),
	preload("res://assets/art/arenas/pulse-chamber/backdrop.png"),
	preload("res://assets/art/arenas/shattered-sanctum/backdrop.png"),
	preload("res://assets/art/arenas/foundry/backdrop.png"),
	preload("res://assets/art/arenas/collision-course/backdrop.png"),
	# Twist arenas reuse existing backdrops with their own grade.
	preload("res://assets/art/arenas/foundry/backdrop.png"),
	preload("res://assets/art/arenas/shattered-sanctum/backdrop.png"),
	preload("res://assets/art/arenas/crosshair-court/backdrop.png"),
]
const GRADES := [
	Color(0.39, 0.38, 0.45), Color(0.31, 0.42, 0.53),
	Color(0.38, 0.40, 0.51), Color(0.29, 0.44, 0.49),
	Color(0.39, 0.34, 0.47), Color(0.44, 0.34, 0.33),
	Color(0.38, 0.32, 0.48),
	Color(0.30, 0.44, 0.40), Color(0.34, 0.30, 0.50), Color(0.44, 0.38, 0.30),
]
const AIR_COLORS := [
	Color(0.80, 0.72, 0.48), Color(0.42, 0.62, 0.80),
	Color(0.80, 0.72, 0.48), Color(0.30, 0.72, 0.77),
	Color(0.65, 0.58, 0.77), Color(0.95, 0.40, 0.16),
	Color(0.67, 0.47, 0.77),
	Color(0.40, 0.90, 0.70), Color(0.70, 0.55, 0.95), Color(0.95, 0.72, 0.36),
]
const PATTERN_TEXTURES := [
	preload("res://assets/kenney/patterns/crosshair-court.png"),
	preload("res://assets/kenney/patterns/endless-descent.png"),
	preload("res://assets/kenney/patterns/pendulum.png"),
	preload("res://assets/kenney/patterns/pulse-chamber.png"),
	preload("res://assets/kenney/patterns/shattered-sanctum.png"),
	preload("res://assets/kenney/patterns/foundry.png"),
	preload("res://assets/kenney/patterns/collision-course.png"),
	preload("res://assets/kenney/patterns/foundry.png"),
	preload("res://assets/kenney/patterns/shattered-sanctum.png"),
	preload("res://assets/kenney/patterns/crosshair-court.png"),
]

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
	if level_theme in [1, 2]:
		queue_redraw()


func show_level(index: int) -> void:
	level_theme = posmod(index, BACKDROPS.size())
	atmosphere_time = 0.0
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, W, H), Color("090b16"))
	draw_texture_rect(BACKDROPS[level_theme], Rect2(0, 0, W, H), false, GRADES[level_theme])
	if level_theme == 2:
		_draw_pendulum_machinery()
	if level_theme == 1:
		_draw_descent_air()
	# Two recessed corner motifs replace the former full-screen wallpaper.
	if level_theme not in [1, 2]:
		for x in [60.0, 1076.0]:
			draw_texture_rect(PATTERN_TEXTURES[level_theme], Rect2(x, 90, 144, 144),
				false, Color(AIR_COLORS[level_theme], 0.018))
	if level_theme in [0, 2, 4]:
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


func counterweight_position(right: bool) -> Vector2:
	var travel := sin(machinery_time() * TAU / 8.0) * 28.0
	return Vector2(964.0, 420.0 - travel) if right else Vector2(318.0, 590.0 + travel)


func _draw_pendulum_machinery() -> void:
	var t := machinery_time()
	# Separate transparent Blender layers retain the baked wall's scale/grade.
	_machinery_sprite(PENDULUM_GEAR_LEFT, Vector2(300, 185), t * 0.30)
	_machinery_sprite(PENDULUM_GEAR_RIGHT, Vector2(977, 525), -t * 0.26)
	_machinery_sprite(PENDULUM_HAND_LONG, Vector2(640, 340), t * 0.14)
	_machinery_sprite(PENDULUM_HAND_SHORT, Vector2(640, 340), t * 0.045)
	for right in [false, true]:
		var at := counterweight_position(right)
		# Subdued suspension cables terminate inside each weight's top collar.
		for offset in [-8.0, 8.0]:
			draw_line(Vector2(at.x + offset, 76.0), Vector2(at.x + offset, at.y - 29.0),
				Color(0.075, 0.062, 0.045), 1.5, true)
		_machinery_sprite(PENDULUM_WEIGHT_RIGHT if right else PENDULUM_WEIGHT_LEFT, at)


func _machinery_sprite(texture: Texture2D, at: Vector2, angle: float = 0.0) -> void:
	draw_set_transform(at, angle)
	draw_texture(texture, -Vector2(texture.get_size()) * 0.5, GRADES[2])
	draw_set_transform(Vector2.ZERO)


func observatory_mote_position(index: int) -> Vector2:
	var seed_x := fposmod(float(index) * 173.31, 1200.0)
	var seed_y := fposmod(float(index) * 97.73, 520.0)
	var drift := -1.0 if level_theme == 5 else 1.0
	return Vector2(40.0 + fposmod(seed_x + atmosphere_time * (2.0 + float(index % 3)), 1200.0),
		100.0 + fposmod(seed_y + drift * atmosphere_time * (3.0 + float(index % 4)), 520.0))
