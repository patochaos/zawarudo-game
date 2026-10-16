extends Node2D

## Baked architecture and quiet cosmetic air. Never supplies simulation state.
##
## Each arena is two Blender layers plus their warm-light passes. The far layer
## slides a few pixels behind the main set as the fight's centre moves, and the
## warm passes are added only while time runs, so planning reads cold and still
## and the room lights up when execution begins.
const W := 1280.0
const H := 720.0
## Indexed by arena: Crosshair Court, Clockwork Gallery (foundry scenery),
## Stilled Hall (sanctum scenery), Pulse Chamber, Endless Descent.
const FAR := [
	preload("res://assets/art/arenas/crosshair-court/far.png"),
	preload("res://assets/art/arenas/foundry/far.png"),
	preload("res://assets/art/arenas/shattered-sanctum/far.png"),
	preload("res://assets/art/arenas/pulse-chamber/far.png"),
	preload("res://assets/art/arenas/endless-descent/far.png"),
]
const MID := [
	preload("res://assets/art/arenas/crosshair-court/mid.png"),
	preload("res://assets/art/arenas/foundry/mid.png"),
	preload("res://assets/art/arenas/shattered-sanctum/mid.png"),
	preload("res://assets/art/arenas/pulse-chamber/mid.png"),
	preload("res://assets/art/arenas/endless-descent/mid.png"),
]
const FAR_WARM := [
	preload("res://assets/art/arenas/crosshair-court/far-warm.png"),
	preload("res://assets/art/arenas/foundry/far-warm.png"),
	preload("res://assets/art/arenas/shattered-sanctum/far-warm.png"),
	preload("res://assets/art/arenas/pulse-chamber/far-warm.png"),
	preload("res://assets/art/arenas/endless-descent/far-warm.png"),
]
const MID_WARM := [
	preload("res://assets/art/arenas/crosshair-court/mid-warm.png"),
	preload("res://assets/art/arenas/foundry/mid-warm.png"),
	preload("res://assets/art/arenas/shattered-sanctum/mid-warm.png"),
	preload("res://assets/art/arenas/pulse-chamber/mid-warm.png"),
	preload("res://assets/art/arenas/endless-descent/mid-warm.png"),
]
## The layers carry bleed (rendered at 100 px per scene unit) so a slide never
## exposes an edge: far 32 x 18 px, mid 16 x 9 px.
const FAR_RECT := Rect2(-32.0, -18.0, 1344.0, 756.0)
const MID_RECT := Rect2(-16.0, -9.0, 1312.0, 738.0)
## Pixels of slide per pixel the fight's centre sits from the arena centre. The
## far layer moves at most about 11 px, the mid layer about 4 px.
const FAR_PARALLAX := 0.017
const MID_PARALLAX := 0.006
const PARALLAX_RATE := 2.5
## Execution adds the warm bounce at this gain; planning shows the cold pass only.
const WARM_GAIN := 1.35
const WARM_RISE_RATE := 3.0
const WARM_FALL_RATE := 1.6
const FAR_HAZE := Color(0.92, 0.94, 1.0)
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
const LIVE_STATES := [Phase.EXECUTING, Phase.FREEPLAY, Phase.REPLAY]

var level_theme: int = 0
var gm
var atmosphere_time: float = 0.0
## Smoothed offset of the fight's centre from the arena centre, in pixels.
var parallax: Vector2 = Vector2.ZERO
## 0 while time is stopped, 1 while it runs; drives the additive warm passes.
var warm: float = 0.0

var _warm_layer: Node2D
var _air_layer: Node2D


func _ready() -> void:
	# Children draw after the parent: warm light adds over the architecture,
	# then the cosmetic air and side trim sit on top of both.
	_warm_layer = Node2D.new()
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_warm_layer.material = additive
	_warm_layer.draw.connect(_draw_warm)
	add_child(_warm_layer)
	_air_layer = Node2D.new()
	_air_layer.draw.connect(_draw_air)
	add_child(_air_layer)


func _process(delta: float) -> void:
	if gm == null:
		return
	var live: bool = gm.state in LIVE_STATES
	# Air stays in exactly the same place during planning and online waiting.
	if gm.state in [Phase.EXECUTING, Phase.FREEPLAY]:
		atmosphere_time += delta
		_air_layer.queue_redraw()
	# Replay restores world_tick directly. Redraw also when scrubbing a paused
	# frame; never integrate a second combat clock for the machinery.
	if level_theme == DESCENT:
		_air_layer.queue_redraw()
	# The slide follows the simulation's positions and only moves while time
	# runs, so a planning freeze holds the room as still as the fighters.
	if live:
		var blend: float = 1.0 - exp(-delta * PARALLAX_RATE)
		var next_parallax: Vector2 = parallax.lerp(fight_offset(), blend)
		if next_parallax.distance_squared_to(parallax) > 0.0001:
			parallax = next_parallax
			queue_redraw()
			_warm_layer.queue_redraw()
	var warm_target: float = 1.0 if live else 0.0
	var rate: float = WARM_RISE_RATE if warm_target > warm else WARM_FALL_RATE
	var next_warm: float = move_toward(warm, warm_target, delta * rate)
	if next_warm != warm:
		warm = next_warm
		_warm_layer.queue_redraw()


func show_level(index: int) -> void:
	level_theme = posmod(index, MID.size())
	atmosphere_time = 0.0
	parallax = Vector2.ZERO
	warm = 0.0
	queue_redraw()
	if _warm_layer != null:
		_warm_layer.queue_redraw()
		_air_layer.queue_redraw()


## Where the live fighters sit relative to the arena centre. Read from the
## simulation, never written to it; replay therefore restores the same slide.
func fight_offset() -> Vector2:
	if gm == null:
		return Vector2.ZERO
	var total := Vector2.ZERO
	var count := 0
	for p in gm.players:
		if p.alive:
			total += p.position
			count += 1
	if count == 0:
		return Vector2.ZERO
	return total / float(count) - Vector2(W, H) * 0.5


func _layer_rect(base: Rect2, factor: float) -> Rect2:
	return Rect2(base.position + parallax * factor, base.size)


func _draw() -> void:
	draw_rect(Rect2(0, 0, W, H), Color("090b16"))
	var grade: Color = GRADES[level_theme]
	draw_texture_rect(FAR[level_theme], _layer_rect(FAR_RECT, FAR_PARALLAX), false,
		grade * FAR_HAZE)
	draw_texture_rect(MID[level_theme], _layer_rect(MID_RECT, MID_PARALLAX), false, grade)


func _draw_warm() -> void:
	if warm <= 0.0:
		return
	var grade: Color = GRADES[level_theme]
	var gain: float = warm * WARM_GAIN
	var far_tint := Color(grade.r * gain, grade.g * gain, grade.b * gain, 1.0) * FAR_HAZE
	var mid_tint := Color(grade.r * gain, grade.g * gain, grade.b * gain, 1.0)
	_warm_layer.draw_texture_rect(FAR_WARM[level_theme],
		_layer_rect(FAR_RECT, FAR_PARALLAX), false, far_tint)
	_warm_layer.draw_texture_rect(MID_WARM[level_theme],
		_layer_rect(MID_RECT, MID_PARALLAX), false, mid_tint)


func _draw_air() -> void:
	var canvas: CanvasItem = _air_layer
	if level_theme == DESCENT:
		_draw_descent_air(canvas)
	# Two recessed corner motifs replace the former full-screen wallpaper.
	if level_theme != DESCENT:
		for x in [60.0, 1076.0]:
			canvas.draw_texture_rect(PATTERN_TEXTURES[level_theme], Rect2(x, 90, 144, 144),
				false, Color(AIR_COLORS[level_theme], 0.018))
	if level_theme in [0, 2]:
		for i in 12:
			var x := 190.0 + float(i) * 7.0
			canvas.draw_colored_polygon(PackedVector2Array([
				Vector2(x, 75), Vector2(x + 45, 75),
				Vector2(x + 275, 620), Vector2(x + 130, 620),
			]), Color(0.40, 0.49, 0.75, 0.006))
	for i in 32:
		var p := observatory_mote_position(i)
		var tint := Color(AIR_COLORS[level_theme], 0.14 + float(i % 3) * 0.035)
		canvas.draw_circle(p, 0.7 + float(i % 3) * 0.25, tint)
		if i % 7 == 0:
			canvas.draw_line(p, p + Vector2(2.0, -1.0), tint, 1.0)
	# Foreground trim is restricted to the sides; wrap openings remain clear.
	for x in [16.0, 1240.0]:
		canvas.draw_rect(Rect2(x, 76, 24, 644), Color(0.018, 0.020, 0.037, 0.80))


## Combat, hit pauses, SUPER and replay all follow the authoritative clock.
## Free play has no ticking world clock, so use its existing cosmetic air time.
func machinery_time() -> float:
	if gm == null:
		return 0.0
	if gm.state == Phase.FREEPLAY:
		return atmosphere_time
	return float(gm.world_tick) * gm.tick_dt()


func _draw_descent_air(canvas: CanvasItem) -> void:
	# Recessed light shafts frame the routes; the central knife lane stays dark.
	for side in [-1.0, 1.0]:
		var x: float = 640.0 + side * 410.0
		for band in 8:
			var spread := 12.0 + float(band) * 7.0
			canvas.draw_colored_polygon(PackedVector2Array([
				Vector2(x - 5, 80), Vector2(x + 5, 80),
				Vector2(x + spread, 615), Vector2(x - spread, 615)]),
				Color(0.18, 0.48, 0.58, 0.004))
	var clock := machinery_time()
	for i in 24:
		var x := 400.0 + fposmod(float(i) * 137.3, 480.0)
		var y := 86.0 + fposmod(float(i) * 83.7 + clock * (11.0 + float(i % 4) * 3.0), 550.0)
		canvas.draw_line(Vector2(x, y), Vector2(x, y + 2.5), Color(0.24, 0.48, 0.56, 0.14), 1.0)


func observatory_mote_position(index: int) -> Vector2:
	var seed_x := fposmod(float(index) * 173.31, 1200.0)
	var seed_y := fposmod(float(index) * 97.73, 520.0)
	var drift := -1.0 if level_theme == 1 else 1.0
	return Vector2(40.0 + fposmod(seed_x + atmosphere_time * (2.0 + float(index % 3)), 1200.0),
		100.0 + fposmod(seed_y + drift * atmosphere_time * (3.0 + float(index % 4)), 520.0))
