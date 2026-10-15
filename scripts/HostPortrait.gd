extends Control
class_name HostPortrait

## In-engine bust of the tutorial host: the one who stops time. Swept-back
## blond spikes, a heart-clasped headband, a high-collared gold coat and a grin
## with one fang, framed by the same suspended-time rings the arena shows.
## Drawn in a 132 x 132 box and scaled to the control's size, so it needs no
## texture. When a painted portrait exists at PAINTED_PATH it is shown on top.

const PAINTED_PATH := "res://assets/art/portraits/host-portrait-v1.png"
const BOX := 132.0
const GOLD := Color(0.96, 0.69, 0.18)
const SKIN := Color(0.95, 0.80, 0.66)
const SKIN_SHADE := Color(0.82, 0.62, 0.48)
const HAIR := Color(0.98, 0.85, 0.35)
const HAIR_SHADE := Color(0.84, 0.64, 0.18)
const COAT := Color(0.93, 0.74, 0.20)
const COAT_SHADE := Color(0.72, 0.52, 0.10)
const BAND := Color(0.07, 0.30, 0.26)
const LINE := Color(0.10, 0.05, 0.08)
const IRIS := Color(0.95, 0.36, 0.18)
const HEART := Color(0.86, 0.14, 0.26)
const JADE := Color(0.22, 0.82, 0.46)


var _painted := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_painted = ResourceLoader.exists(PAINTED_PATH)
	if _painted:
		var painted := TextureRect.new()
		# Expand mode first: otherwise the texture's own size becomes the
		# control's minimum and the size below is clamped to 1254 px.
		painted.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		painted.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		painted.texture = load(PAINTED_PATH)
		painted.size = size
		painted.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(painted)


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, size / BOX)
	var box := Rect2(Vector2.ZERO, Vector2(BOX, BOX))
	draw_rect(box, Color(0.030, 0.018, 0.055, 0.98))
	draw_colored_polygon(PackedVector2Array([
		Vector2(0.0, 132.0), Vector2(132.0, 132.0), Vector2(132.0, 60.0), Vector2(0.0, 96.0),
	]), Color(0.30, 0.08, 0.47, 0.30))
	var ring_center := Vector2(66.0, 58.0)
	draw_arc(ring_center, 56.0, 0.0, TAU, 48, Color(GOLD.r, GOLD.g, GOLD.b, 0.30), 1.0, true)
	draw_arc(ring_center, 46.0, 0.0, TAU, 48, Color(GOLD.r, GOLD.g, GOLD.b, 0.18), 1.0, true)
	for i in 12:
		var dir := Vector2.from_angle(TAU * float(i) / 12.0)
		draw_line(ring_center + dir * 50.0, ring_center + dir * 56.0,
			Color(GOLD.r, GOLD.g, GOLD.b, 0.40), 1.0, true)
	if not _painted:
		_draw_coat()
		_draw_head()
	draw_rect(box, Color(GOLD.r, GOLD.g, GOLD.b, 0.55), false, 1.5)


func _draw_coat() -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(4.0, 132.0), Vector2(128.0, 132.0), Vector2(118.0, 104.0),
		Vector2(96.0, 90.0), Vector2(36.0, 90.0), Vector2(14.0, 104.0),
	]), COAT)
	draw_colored_polygon(PackedVector2Array([
		Vector2(66.0, 96.0), Vector2(84.0, 132.0), Vector2(48.0, 132.0),
	]), COAT_SHADE)
	# The neck sits under the collar wings.
	draw_colored_polygon(PackedVector2Array([
		Vector2(55.0, 76.0), Vector2(77.0, 76.0), Vector2(79.0, 98.0), Vector2(53.0, 98.0),
	]), SKIN_SHADE)
	for side: float in [-1.0, 1.0]:
		var cx := 66.0 + side * 14.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx, 98.0), Vector2(cx + side * 30.0, 70.0),
			Vector2(cx + side * 34.0, 100.0), Vector2(cx + side * 6.0, 112.0),
		]), LINE)
		draw_polyline(PackedVector2Array([
			Vector2(cx, 98.0), Vector2(cx + side * 30.0, 70.0), Vector2(cx + side * 34.0, 100.0),
		]), Color(GOLD.r, GOLD.g, GOLD.b, 0.9), 1.5, true)
	_draw_heart(Vector2(66.0, 116.0), 7.0, JADE)


func _draw_head() -> void:
	# Back hair first, then the face, then the fringe and band over it.
	draw_colored_polygon(PackedVector2Array([
		Vector2(36.0, 50.0), Vector2(38.0, 26.0), Vector2(50.0, 12.0), Vector2(66.0, 6.0),
		Vector2(86.0, 10.0), Vector2(100.0, 20.0), Vector2(108.0, 36.0), Vector2(104.0, 54.0),
		Vector2(96.0, 44.0), Vector2(90.0, 34.0), Vector2(78.0, 26.0), Vector2(64.0, 26.0),
		Vector2(50.0, 32.0), Vector2(44.0, 42.0),
	]), HAIR_SHADE)
	draw_colored_polygon(PackedVector2Array([
		Vector2(44.0, 48.0), Vector2(50.0, 30.0), Vector2(66.0, 24.0), Vector2(82.0, 30.0),
		Vector2(88.0, 48.0), Vector2(86.0, 66.0), Vector2(78.0, 82.0), Vector2(66.0, 88.0),
		Vector2(54.0, 82.0), Vector2(46.0, 66.0),
	]), SKIN)
	draw_colored_polygon(PackedVector2Array([
		Vector2(78.0, 82.0), Vector2(86.0, 66.0), Vector2(84.0, 76.0), Vector2(74.0, 86.0),
	]), SKIN_SHADE)
	# Spikes swept up and to the right.
	for spike: Array in [
		[Vector2(60.0, 10.0), Vector2(70.0, -2.0), Vector2(76.0, 12.0)],
		[Vector2(82.0, 12.0), Vector2(96.0, 0.0), Vector2(94.0, 20.0)],
		[Vector2(98.0, 22.0), Vector2(116.0, 14.0), Vector2(108.0, 36.0)],
		[Vector2(104.0, 40.0), Vector2(122.0, 40.0), Vector2(108.0, 52.0)],
		[Vector2(42.0, 20.0), Vector2(34.0, 6.0), Vector2(52.0, 12.0)],
	]:
		draw_colored_polygon(PackedVector2Array(spike), HAIR)
	draw_colored_polygon(PackedVector2Array([
		Vector2(40.0, 44.0), Vector2(42.0, 26.0), Vector2(54.0, 14.0), Vector2(68.0, 10.0),
		Vector2(86.0, 14.0), Vector2(98.0, 26.0), Vector2(100.0, 42.0), Vector2(88.0, 36.0),
		Vector2(80.0, 40.0), Vector2(72.0, 34.0), Vector2(60.0, 40.0), Vector2(50.0, 36.0),
	]), HAIR)
	# Headband with the heart clasp.
	draw_colored_polygon(PackedVector2Array([
		Vector2(43.0, 42.0), Vector2(90.0, 38.0), Vector2(92.0, 47.0), Vector2(45.0, 50.0),
	]), BAND)
	draw_line(Vector2(43.0, 42.0), Vector2(90.0, 38.0), Color(0.16, 0.56, 0.46), 1.0, true)
	_draw_heart(Vector2(66.0, 43.0), 5.0, HEART)
	# Brows angle inward: the look of someone who already knows your plan.
	draw_line(Vector2(48.0, 51.0), Vector2(62.0, 55.0), LINE, 2.6, true)
	draw_line(Vector2(70.0, 55.0), Vector2(84.0, 51.0), LINE, 2.6, true)
	for eye: Array in [
		[Vector2(51.0, 57.0), Vector2(62.0, 56.0), Vector2(62.0, 62.0), Vector2(52.0, 63.0)],
		[Vector2(70.0, 56.0), Vector2(81.0, 57.0), Vector2(80.0, 63.0), Vector2(70.0, 62.0)],
	]:
		draw_colored_polygon(PackedVector2Array(eye), Color(0.97, 0.95, 0.92))
	for center: Vector2 in [Vector2(57.5, 59.5), Vector2(75.5, 59.5)]:
		draw_circle(center, 2.8, IRIS)
		draw_circle(center, 1.1, LINE)
	draw_polyline(PackedVector2Array([Vector2(66.0, 62.0), Vector2(63.0, 71.0), Vector2(67.0, 72.0)]),
		SKIN_SHADE, 1.4, true)
	# A grin that leans to one side, with a single fang.
	draw_polyline(PackedVector2Array([Vector2(54.0, 76.0), Vector2(66.0, 79.5), Vector2(80.0, 73.0)]),
		LINE, 2.0, true)
	draw_colored_polygon(PackedVector2Array([
		Vector2(72.0, 75.5), Vector2(76.5, 74.0), Vector2(74.5, 80.5),
	]), Color(0.98, 0.98, 0.95))


func _draw_heart(at: Vector2, radius: float, color: Color) -> void:
	draw_circle(at + Vector2(-radius * 0.5, -radius * 0.25), radius * 0.55, color)
	draw_circle(at + Vector2(radius * 0.5, -radius * 0.25), radius * 0.55, color)
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(-radius, -radius * 0.1), at + Vector2(radius, -radius * 0.1),
		at + Vector2(0.0, radius),
	]), color)
