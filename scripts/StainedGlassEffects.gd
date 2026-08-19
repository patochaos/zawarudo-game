extends "res://scripts/Effects.gd"

## Impacts release angular glass pieces instead of soft circular particles.


func _draw() -> void:
	for f: Dictionary in _fx:
		var kind := int(f["kind"])
		var u := clampf(float(f["t"]) / float(LIFE[kind]), 0.0, 1.0)
		match kind:
			Kind.SPARK:
				_draw_shards(f, u, 5, 28.0, 3.0)
			Kind.SHATTER:
				_draw_shards(f, u, 12, 72.0, 5.0)
				_draw_crack_rose(f["pos"], f["col"], u, 30.0)
			Kind.KILL:
				_draw_shards(f, u, 18, 126.0, 7.0)
				_draw_crack_rose(f["pos"], Color(1.0, 0.30, 0.25), u, 88.0)
			Kind.CLASH:
				_draw_shards(f, u, 8, 56.0, 4.0)
				_draw_crack_rose(f["pos"], f["col"], u, 38.0)
			Kind.AFTERMATH:
				var alpha := pow(1.0 - u, 1.6)
				_draw_crack_rose(f["pos"], Color(f["col"], alpha), u, 28.0)
				draw_string(ThemeDB.fallback_font, f["pos"] + Vector2(-34.0, -26.0),
					str(f.get("label", "")), HORIZONTAL_ALIGNMENT_CENTER, 68.0, 11,
					Color(Color(f["col"]).r, Color(f["col"]).g, Color(f["col"]).b, alpha))
			Kind.EXPLOSION:
				_draw_shards(f, u, 22, 132.0, 8.0)
				_draw_crack_rose(f["pos"], Color(f["col"]).lightened(0.38), u, 104.0)


func _draw_shards(f: Dictionary, u: float, count: int, reach: float, size: float) -> void:
	var base := float(f["seed"]) * 0.7391
	var col: Color = f["col"]
	for i in count:
		var angle := base + TAU * float(i) / float(count) + sin(base + float(i)) * 0.28
		var distance := reach * (0.45 + 0.55 * fposmod(base * float(i + 2), 1.0)) \
			* (1.0 - pow(1.0 - u, 2.0))
		var centre: Vector2 = f["pos"] + Vector2.from_angle(angle) * distance
		centre.y += distance * distance * 0.0025
		var d := Vector2.from_angle(angle)
		var side := d.orthogonal()
		var fade := 1.0 - u
		var shard := PackedVector2Array([
			centre + d * size * fade * 1.8,
			centre - d * size * fade + side * size * fade * 0.65,
			centre - d * size * fade - side * size * fade * 0.65,
		])
		draw_colored_polygon(shard, Color(col.r, col.g, col.b, fade))
		draw_polyline(shard + PackedVector2Array([shard[0]]), Color(0.02, 0.01, 0.03, fade), 1.0, true)


func _draw_crack_rose(at: Vector2, col: Color, u: float, reach: float) -> void:
	var alpha := (1.0 - u) * col.a
	var radius := 6.0 + reach * (1.0 - pow(1.0 - u, 2.0))
	for ray in 8:
		var d := Vector2.from_angle(PI * 0.125 + TAU * float(ray) / 8.0)
		draw_line(at + d * 5.0, at + d * radius,
			Color(col.r, col.g, col.b, alpha), 2.2 if ray % 2 == 0 else 1.2)
	draw_arc(at, radius * 0.42, 0.0, TAU, 16, Color(col.r, col.g, col.b, alpha * 0.72), 2.0)
