extends Node2D
class_name Effects

## Short-lived execution feedback: impact sparks, platform shatters, kill bursts.
## Purely cosmetic — nothing here touches the simulation, and it is driven by
## real time so it does not consume execution ticks.

enum Kind { SPARK, SHATTER, KILL, CLASH, AFTERMATH, EXPLOSION }

const LIFE := {Kind.SPARK: 0.35, Kind.SHATTER: 0.55, Kind.KILL: 0.9,
	Kind.CLASH: 0.42, Kind.AFTERMATH: 0.72, Kind.EXPLOSION: 0.68}
const TEX_SPARK := preload("res://assets/kenney/vfx/spark.png")
const TEX_SLASH := preload("res://assets/kenney/vfx/slash.png")
const TEX_CIRCLE := preload("res://assets/kenney/vfx/temporal-circle.png")
const TEX_MAGIC := preload("res://assets/kenney/vfx/temporal-magic.png")
const TEX_SMOKE := preload("res://assets/kenney/vfx/smoke.png")
const TEX_RING := preload("res://assets/kenney/vfx/ring-mask.png")
const TEX_INK_SPLAT := preload("res://assets/kenney/vfx/ink-splat.png")
const TEX_SONIC_RING := preload("res://assets/kenney/vfx/sonic-ring.png")
const HUD_FONT := preload("res://assets/kenney/fonts/kenney-future-narrow.ttf")

var _fx: Array = []   # [{kind, pos, col, t, seed, scale}]
var _remembered: Array = []   # important execution events, revealed on refreeze
var _seq: int = 0
var reduced_flashes: bool = false


func add(kind: int, pos: Vector2, col: Color, scale: float = 1.0) -> void:
	_seq += 1
	_fx.append({"kind": kind, "pos": pos, "col": col, "t": 0.0, "seed": _seq,
		"scale": maxf(scale, 0.1)})


func clear_all() -> void:
	_fx.clear()
	_remembered.clear()
	queue_redraw()


## Preserve only a handful of causes from the execution burst. They reappear as
## restrained world-space echoes when planning begins, so the player can parse
## what changed without a replay or combat log.
func remember(label: String, pos: Vector2, col: Color) -> void:
	if _remembered.size() >= 4:
		_remembered.pop_front()
	_remembered.append({"label": label, "pos": pos, "col": col})


func reveal_aftermath() -> void:
	for event in _remembered:
		_seq += 1
		_fx.append({"kind": Kind.AFTERMATH, "pos": event["pos"], "col": event["col"],
			"t": 0.0, "seed": _seq, "label": event["label"]})
	_remembered.clear()
	queue_redraw()


func _process(delta: float) -> void:
	if _fx.is_empty():
		return
	var alive: Array = []
	for f in _fx:
		f["t"] += delta
		if f["t"] < LIFE[f["kind"]]:
			alive.append(f)
	_fx = alive
	queue_redraw()


func _draw() -> void:
	for f in _fx:
		var k: int = f["kind"]
		var u: float = clampf(f["t"] / LIFE[k], 0.0, 1.0)
		match k:
			Kind.SPARK:
				_burst(f, u, 6, 26.0, 2.0)
				_sprite(f, TEX_SPARK, 28.0 + 18.0 * u, (1.0 - u) * 0.44,
					float(f["seed"]) * 0.71)
			Kind.SHATTER:
				_burst(f, u, 11, 58.0, 3.0)
				_sprite(f, TEX_SLASH, 62.0 + 26.0 * u, (1.0 - u) * 0.30,
					float(f["seed"]) * 0.43)
				_sprite(f, TEX_SMOKE, 44.0 + 48.0 * u, (1.0 - u) * 0.16)
				draw_arc(f["pos"], 6.0 + 34.0 * u, 0.0, TAU, 20,
					Color(f["col"].r, f["col"].g, f["col"].b, (1.0 - u) * 0.55), 2.0)
			Kind.KILL:
				var c: Color = f["col"]
				_sprite(f, TEX_INK_SPLAT, 94.0 + 72.0 * u, (1.0 - u) * 0.16,
					float(f["seed"]) * 0.31, Color(1.0, 0.30, 0.32))
				_sprite(f, TEX_MAGIC, 82.0 + 100.0 * u, (1.0 - u) * 0.28,
					-float(f["seed"]) * 0.19, Color(1.0, 0.42, 0.35))
				_sprite(f, TEX_RING, 110.0 + 120.0 * u, (1.0 - u) * 0.15)
				draw_arc(f["pos"], 10.0 + 90.0 * u, 0.0, TAU, 28,
					Color(1.0, 0.35, 0.32, (1.0 - u) * 0.8), 3.0 * (1.0 - u) + 1.0)
				_burst(f, u, 16, 120.0, 3.0)
				draw_circle(f["pos"], 26.0 * (1.0 - u), Color(c.r, c.g, c.b, (1.0 - u) * 0.35))
			Kind.CLASH:
				var c: Color = f["col"]
				_burst(f, u, 10, 52.0, 2.4)
				_sprite(f, TEX_SLASH, 54.0 + 36.0 * u, (1.0 - u) * 0.40,
					float(f["seed"]) * 0.83)
				_sprite(f, TEX_SPARK, 46.0 + 24.0 * u, (1.0 - u) * 0.30,
					-float(f["seed"]) * 0.37, Color(1.0, 0.94, 0.65))
				draw_arc(f["pos"], 5.0 + 28.0 * u, 0.0, TAU, 8,
					Color(c.r, c.g, c.b, (1.0 - u) * 0.9), 2.5 * (1.0 - u) + 0.5)
				for ray in 4:
					var angle: float = PI * 0.25 + float(ray) * PI * 0.5
					var reach: float = 34.0 * (1.0 - pow(1.0 - u, 2.0))
					draw_line(f["pos"] - Vector2.from_angle(angle) * reach,
						f["pos"] + Vector2.from_angle(angle) * reach,
						Color(1.0, 0.94, 0.65, 1.0 - u), 2.0)
			Kind.AFTERMATH:
				var c: Color = f["col"]
				var alpha: float = pow(1.0 - u, 1.6)
				_sprite(f, TEX_CIRCLE, 42.0 + 38.0 * u, alpha * 0.16)
				draw_arc(f["pos"], 13.0 + 24.0 * u, 0.0, TAU, 24,
					Color(c.r, c.g, c.b, alpha * 0.78), 2.0)
				for corner in 4:
					var a: float = PI * 0.25 + float(corner) * PI * 0.5
					var d := Vector2.from_angle(a)
					draw_line(f["pos"] + d * 9.0, f["pos"] + d * (16.0 + 8.0 * u),
						Color(c.r, c.g, c.b, alpha), 1.5)
				draw_string(HUD_FONT, f["pos"] + Vector2(-30.0, -22.0),
					f["label"], HORIZONTAL_ALIGNMENT_CENTER, 60.0, 11,
					Color(c.r, c.g, c.b, alpha * 0.9))
			Kind.EXPLOSION:
				var c: Color = f["col"]
				var hot: Color = c.lightened(0.55)
				var scale: float = float(f.get("scale", 1.0))
				_sprite(f, TEX_SONIC_RING, (88.0 + 146.0 * u) * scale,
					(1.0 - u) * 0.20, float(f["seed"]) * 0.07, hot)
				_sprite(f, TEX_MAGIC, (78.0 + 124.0 * u) * scale,
					(1.0 - u) * 0.24, float(f["seed"]) * 0.23, hot)
				_sprite(f, TEX_SMOKE, (62.0 + 130.0 * u) * scale,
					(1.0 - u) * 0.13, -float(f["seed"]) * 0.11)
				_burst(f, u, 20, 112.0 * scale, 4.0 * sqrt(scale))
				draw_circle(f["pos"], 34.0 * scale * pow(1.0 - u, 1.8),
					Color(hot.r, hot.g, hot.b, (1.0 - u) * 0.70))
				draw_arc(f["pos"], (12.0 + 96.0 * u) * scale, 0.0, TAU, 42,
					Color(c.r, c.g, c.b, (1.0 - u) * 0.90), 5.0 * (1.0 - u) + 1.0)


func _sprite(f: Dictionary, texture: Texture2D, diameter: float, alpha: float,
		rotation: float = 0.0, tint_override: Color = Color(-1.0, -1.0, -1.0)) -> void:
	var source: Color = f["col"] if tint_override.r < 0.0 else tint_override
	var accessibility_scale := 0.50 if reduced_flashes else 1.0
	var tint := Color(source.r, source.g, source.b, alpha * accessibility_scale)
	draw_set_transform(f["pos"], rotation)
	draw_texture_rect(texture, Rect2(Vector2(-diameter, -diameter) * 0.5,
		Vector2(diameter, diameter)), false, tint)
	draw_set_transform(Vector2.ZERO)


## Deterministic radial scatter — the seed keeps each effect stable frame to
## frame without needing a random call during _draw.
func _burst(f: Dictionary, u: float, n: int, reach: float, size: float) -> void:
	var base: float = float(f["seed"]) * 0.7391
	for i in n:
		var a: float = base + TAU * float(i) / float(n) + sin(base + float(i)) * 0.35
		var speed: float = reach * (0.55 + 0.45 * fposmod(base * float(i + 3), 1.0))
		var d: float = speed * (1.0 - pow(1.0 - u, 2.0))
		var p: Vector2 = f["pos"] + Vector2(cos(a), sin(a)) * d + Vector2(0.0, d * d * 0.004)
		draw_circle(p, size * (1.0 - u), Color(f["col"].r, f["col"].g, f["col"].b, 1.0 - u))
