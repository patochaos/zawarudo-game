extends CanvasLayer
class_name SuperFreezeFrame

## Full-screen comic cut-in shown immediately before the first wave of a SUPER.
## GameManager owns the actual simulation pause; this layer uses ordinary frame
## time so its animation keeps moving while the deterministic combat clock does
## not.

const W := 1280.0
const H := 720.0
const DURATION := 1.45
const PANEL_MAX_H := 430.0
const DUELIST_PORTRAIT := preload("res://assets/art/portraits/duelist-portrait-intense-v2.png")
const DASHBLADE_PORTRAIT := preload("res://assets/art/portraits/dashblade-portrait-v1.png")
const CHAKRAM_PORTRAIT := preload("res://assets/art/portraits/broodtail-portrait-v1.png")
const SHOCK_PORTRAIT := preload("res://assets/art/portraits/shockwitch-portrait-v1.png")


class CutInArt:
	extends Control

	var owner_index: int = 0
	var owner_color: Color = Color.WHITE
	var elapsed: float = 0.0
	var duration: float = DURATION
	var playing: bool = false
	var portrait: Texture2D = DUELIST_PORTRAIT
	var _tone_texture: ImageTexture

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(W, H)
		_tone_texture = _build_tone_texture()
		visible = false
		set_process(true)

	func begin(who: int, tint: Color, fighter: Variant = 0) -> void:
		owner_index = who
		owner_color = tint
		match int(fighter):
			2: portrait = DASHBLADE_PORTRAIT
			3: portrait = CHAKRAM_PORTRAIT
			4: portrait = SHOCK_PORTRAIT
			_: portrait = DUELIST_PORTRAIT
		elapsed = 0.0
		playing = true
		visible = true
		queue_redraw()

	func cancel() -> void:
		playing = false
		visible = false
		elapsed = 0.0

	func _process(delta: float) -> void:
		if not playing:
			return
		elapsed += delta
		if elapsed >= duration:
			cancel()
			return
		queue_redraw()

	func _draw() -> void:
		if not playing:
			return
		var u: float = clampf(elapsed / duration, 0.0, 1.0)
		var intro: float = clampf(u / 0.14, 0.0, 1.0)
		var outro: float = clampf((1.0 - u) / 0.16, 0.0, 1.0)
		var alpha: float = minf(intro, outro)
		var accent: Color = owner_color.lightened(0.16)
		var deep: Color = owner_color.darkened(0.68)
		var ink := Color(0.018, 0.008, 0.035, alpha)

		# The cut-in snaps on as a hard black frame, then the central manga panel
		# expands vertically. The slight horizontal shake is deterministic.
		draw_rect(Rect2(0.0, 0.0, W, H), ink)
		var shake := Vector2(sin(elapsed * 74.0), cos(elapsed * 61.0)) * (4.0 * (1.0 - intro))
		var panel_h: float = lerpf(18.0, PANEL_MAX_H, ease(intro, 0.45))
		var top: float = H * 0.5 - panel_h * 0.5
		var panel := PackedVector2Array([
			Vector2(-45.0, top + 42.0) + shake,
			Vector2(W + 45.0, top - 22.0) + shake,
			Vector2(W + 45.0, top + panel_h - 42.0) + shake,
			Vector2(-45.0, top + panel_h + 22.0) + shake,
		])
		draw_colored_polygon(panel, Color(deep.r, deep.g, deep.b, alpha))
		draw_polyline(panel, Color(accent.r, accent.g, accent.b, 0.95 * alpha), 6.0, true)

		# The 403 screen-tone dots used to be individual draw calls every frame,
		# which visibly stuttered in the WebGL build. They are rasterised once at
		# startup, then cropped as the panel opens so the animation stays identical.
		if _tone_texture != null:
			var visible_tone_h := minf(panel_h, PANEL_MAX_H)
			draw_texture_rect_region(_tone_texture,
				Rect2(shake.x, top + shake.y, W, visible_tone_h),
				Rect2(0.0, 0.0, W, visible_tone_h),
				Color(accent.r, accent.g, accent.b, 0.12 * alpha))
		# Converging speed lines keep the portrait lively even though gameplay
		# itself is genuinely stopped.
		var vanishing := Vector2(330.0 if owner_index == 0 else 950.0, H * 0.5) + shake
		for i in 22:
			var edge_y: float = top + float(i) / 21.0 * panel_h
			var edge_x: float = W + 80.0 if owner_index == 0 else -80.0
			draw_line(vanishing, Vector2(edge_x, edge_y) + shake,
				Color(accent.r, accent.g, accent.b, (0.07 + float(i % 3) * 0.025) * alpha), 2.0)

		var portrait_x: float = 330.0 if owner_index == 0 else 950.0
		var face: float = 1.0 if owner_index == 0 else -1.0
		_draw_portrait(Vector2(portrait_x, H * 0.5 + 34.0) + shake, face, accent, alpha, u)
		_draw_copy(top, panel_h, accent, alpha, shake)

		# A one-frame white impact flash makes the transition read immediately.
		var flash: float = maxf(0.0, 1.0 - u / 0.055)
		if flash > 0.0:
			draw_rect(Rect2(0.0, 0.0, W, H), Color(1.0, 0.98, 0.88, flash * 0.82))

	func _build_tone_texture() -> ImageTexture:
		var image := Image.create(int(W), int(PANEL_MAX_H), false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		for row in 13:
			for col in 31:
				var centre := Vector2(22.0 + float(col) * 42.0, 15.0 + float(row) * 31.0)
				_stamp_circle(image, centre, 1.3 + float((row + col) % 3) * 0.55)
		return ImageTexture.create_from_image(image)

	func _stamp_circle(image: Image, centre: Vector2, radius: float) -> void:
		var reach := int(ceil(radius + 0.5))
		for y in range(maxi(0, int(centre.y) - reach),
			mini(image.get_height(), int(centre.y) + reach + 1)):
			for x in range(maxi(0, int(centre.x) - reach),
				mini(image.get_width(), int(centre.x) + reach + 1)):
				var distance := Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(centre)
				var coverage := clampf(radius + 0.5 - distance, 0.0, 1.0)
				if coverage > 0.0:
					image.set_pixel(x, y, Color(1.0, 1.0, 1.0, coverage))

	func _draw_copy(top: float, panel_h: float, accent: Color, alpha: float, shake: Vector2) -> void:
		var copy_x: float = 600.0 if owner_index == 0 else 80.0
		draw_string(ThemeDB.fallback_font, Vector2(copy_x, top + 76.0) + shake,
			"IT'S ALL USELESS", HORIZONTAL_ALIGNMENT_CENTER, 590.0, 24,
			Color(0.98, 0.96, 0.88, 0.88 * alpha))
		# Six calls split evenly across two bounded lines: the fixed 590px width
		# keeps the chant clear of both the portrait and the panel edge.
		for line in 2:
			draw_string(ThemeDB.fallback_font,
				Vector2(copy_x, top + panel_h * (0.49 + float(line) * 0.22)) + shake,
				"MUDA MUDA MUDA", HORIZONTAL_ALIGNMENT_CENTER, 590.0, 55,
				Color(accent.r, accent.g, accent.b, alpha))
		draw_line(Vector2(copy_x + 34.0, top + panel_h * 0.78) + shake,
			Vector2(copy_x + 556.0, top + panel_h * 0.78 - 20.0) + shake,
			Color(0.98, 0.90, 0.54, 0.82 * alpha), 5.0)
		draw_string(ThemeDB.fallback_font, Vector2(copy_x + 4.0, top + panel_h - 30.0) + shake,
			"PLAYER %d  //  SUPER" % (owner_index + 1), HORIZONTAL_ALIGNMENT_LEFT, 540.0, 18,
			Color(0.78, 0.80, 0.88, 0.86 * alpha))

	func _draw_portrait(at: Vector2, face: float, accent: Color, alpha: float, u: float) -> void:
		var portrait_rect := Rect2(-300.0, -300.0, 600.0, 600.0)
		var trail: float = maxf(0.0, 1.0 - u / 0.20)
		draw_set_transform(at, 0.0, Vector2(face, 1.0))
		# A short palette-coloured afterimage ties the neutral portrait to the
		# active player's gold/violet panel as it slams into place.
		if trail > 0.0:
			draw_texture_rect(portrait,
				Rect2(portrait_rect.position + Vector2(-26.0, 0.0), portrait_rect.size), false,
				Color(accent.r, accent.g, accent.b, trail * 0.34 * alpha))
		# Hard offset shadow keeps the detailed raster as graphic as the surrounding
		# procedural ink work, then the clean alpha portrait sits on top.
		draw_texture_rect(portrait,
			Rect2(portrait_rect.position + Vector2(12.0, 14.0), portrait_rect.size), false,
			Color(0.015, 0.008, 0.025, 0.78 * alpha))
		draw_texture_rect(portrait, portrait_rect, false, Color(1.0, 1.0, 1.0, alpha))
		draw_set_transform(Vector2.ZERO)


var _art: CutInArt
var _portrait_warmup: TextureRect


func _ready() -> void:
	layer = 40
	# Force the large portrait onto the GPU during startup instead of paying the
	# texture-upload cost on the first SUPER. One almost-transparent pixel is
	# rendered for two frames and is imperceptible behind the opening scene.
	_portrait_warmup = TextureRect.new()
	_portrait_warmup.texture = DUELIST_PORTRAIT
	_portrait_warmup.position = Vector2.ZERO
	_portrait_warmup.size = Vector2.ONE
	_portrait_warmup.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_warmup.stretch_mode = TextureRect.STRETCH_SCALE
	_portrait_warmup.modulate = Color(1.0, 1.0, 1.0, 0.001)
	_portrait_warmup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait_warmup)
	_art = CutInArt.new()
	add_child(_art)
	# A deferred free still presents the texture once, but does not leave a
	# coroutine waiting on a SuperFreezeFrame that a short headless test may free.
	_portrait_warmup.call_deferred("queue_free")


func play(who: int, tint: Color, fighter: Variant = 0) -> void:
	_art.begin(who, tint, fighter)


func cancel() -> void:
	if _art != null:
		_art.cancel()


func is_active() -> bool:
	return _art != null and _art.playing
