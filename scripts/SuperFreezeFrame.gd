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
## The kicker sets the beat, the two title lines are the chant.
const KICKER := "THE WORLD HOLDS ITS BREATH"
const TITLE_LINES := ["MUDA MUDA", "MUDA MUDA"]
## The temporal dial is a 24-frame rotation sheet (tools/blender/build_combat_art.py):
## 6x4 cells of 384 px, DIAL_STEP radians apart, frame 12 upright. The cut-in
## picks the frame nearest its drift angle instead of turning one render, so
## the facets catch the baked lights as the dial moves. Reduced flashes holds
## frame 12 flat, as the drawn rotation was disabled before.
const SUPER_DIAL := preload("res://assets/art/combat/super-dial.png")
const DIAL_FRAMES := 24
const DIAL_COLUMNS := 6
const DIAL_CELL := 384.0
const DIAL_STEP := 0.011
const DIAL_UPRIGHT := 12
## Five rendered accent chips, one per wave, 64 px cells in a row.
const SUPER_ACCENTS := preload("res://assets/art/combat/super-accents.png")
const ACCENT_CELL := 64.0
const DUELIST_PORTRAIT := preload("res://assets/art/portraits/duelist-portrait-v1.png")
const ROOK_PORTRAIT := preload("res://assets/art/portraits/rook-portrait-v1.png")
const ECLIPSE_PORTRAIT := preload("res://assets/art/portraits/eclipse-portrait-v1.png")
const PULSE_PORTRAIT := preload("res://assets/art/portraits/pulse-portrait-v1.png")


class CutInArt:
	extends Control

	var owner_index: int = 0
	var owner_color: Color = Color.WHITE
	var elapsed: float = 0.0
	var duration: float = DURATION
	var playing: bool = false
	var reduced_flashes: bool = false
	var portrait: Texture2D = DUELIST_PORTRAIT
	var _tone_texture: ImageTexture

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(W, H)
		_tone_texture = _build_tone_texture()
		visible = false
		set_process(true)

	func begin(who: int, tint: Color, fighter: Variant = 0, length: float = DURATION) -> void:
		owner_index = who
		owner_color = tint
		duration = maxf(0.1, length)
		match int(fighter):
			2: portrait = ROOK_PORTRAIT
			3: portrait = ECLIPSE_PORTRAIT
			4: portrait = PULSE_PORTRAIT
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
		# The frame is ink but not opaque: the collapsed two-value world the
		# event direction grades sits behind the panel for the anticipation beat.
		var ink := Color(0.018, 0.008, 0.035, alpha * 0.66)

		# Release: in the last beat the whole panel tears away along the thrower's
		# facing and combat resumes on the sound transient.
		var face_dir: float = 1.0 if owner_index == 0 else -1.0
		var tear: float = clampf((u - 0.92) / 0.08, 0.0, 1.0)
		var slide := Vector2(face_dir * ease(tear, 2.2) * 1500.0, 0.0)
		draw_rect(Rect2(0.0, 0.0, W, H), ink)
		var shake := Vector2.ZERO if reduced_flashes else Vector2(sin(elapsed * 74.0), cos(elapsed * 61.0)) * (4.0 * (1.0 - intro))
		shake += slide
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
		# Anticipation: the blade dial appears first. Portrait and title strike
		# together, then five accents sweep toward release within the same pause.
		var strike := clampf((u - 0.12) / 0.10, 0.0, 1.0)
		var release := clampf((u - 0.70) / 0.30, 0.0, 1.0)
		var dial_size := lerpf(420.0, 490.0, intro) + release * 38.0
		var dial_angle: float = 0.0 if reduced_flashes else (-0.12 + u * 0.18) * face
		var dial_frame: int = clampi(DIAL_UPRIGHT + int(round(dial_angle / DIAL_STEP)),
			0, DIAL_FRAMES - 1)
		draw_set_transform(Vector2(portrait_x, H * 0.5) + slide)
		draw_texture_rect_region(SUPER_DIAL,
			Rect2(Vector2.ONE * -dial_size * 0.5, Vector2.ONE * dial_size),
			Rect2(float(dial_frame % DIAL_COLUMNS) * DIAL_CELL,
				float(dial_frame / DIAL_COLUMNS) * DIAL_CELL, DIAL_CELL, DIAL_CELL),
			Color(accent.r, accent.g, accent.b, alpha * 0.7))
		draw_set_transform(Vector2.ZERO)
		_draw_portrait(Vector2(portrait_x - face * (1.0 - strike) * 24.0,
			H * 0.5 + 34.0) + shake, face, accent, alpha * strike, u)
		_draw_copy(top, panel_h, accent, alpha * strike, shake)
		var copy_x := 600.0 if owner_index == 0 else 80.0
		# Five rendered accent impacts, each a blade chip with one more splinter
		# than the last, strike in turn toward release. Each grows slightly as
		# it lights; without reduced flashes the strike itself adds a brief
		# white pop that peaks halfway through the 0.06 beat.
		for wave in 5:
			var lit := clampf((u - 0.44 - float(wave) * 0.065) / 0.06, 0.0, 1.0)
			var at := Vector2(copy_x + 180.0 + float(wave) * 46.0, top + panel_h - 72.0)
			var centre := at + Vector2(9.5, -6.0)
			var chip := 44.0 * (0.82 + 0.18 * lit)
			var cell := Rect2(float(wave) * ACCENT_CELL, 0.0, ACCENT_CELL, ACCENT_CELL)
			draw_texture_rect_region(SUPER_ACCENTS,
				Rect2(centre - Vector2.ONE * chip * 0.5, Vector2.ONE * chip), cell,
				Color(accent.r, accent.g, accent.b, alpha * strike * (0.16 + lit * 0.7)))
			var pop := 0.0 if reduced_flashes else lit * (1.0 - lit) * 4.0
			if pop > 0.0:
				draw_texture_rect_region(SUPER_ACCENTS,
					Rect2(centre - Vector2.ONE * chip * 0.6, Vector2.ONE * chip * 1.2), cell,
					Color(1.0, 0.98, 0.92, alpha * strike * pop * 0.5))

		# A narrow entry glint marks the cut without a full-screen white flash.
		var flash: float = maxf(0.0, 1.0 - u / 0.055)
		if flash > 0.0 and not reduced_flashes:
			draw_rect(Rect2(0.0, H * 0.5 - 2.0, W, 4.0), Color(1.0, 0.98, 0.88, flash * 0.65))

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
			KICKER, HORIZONTAL_ALIGNMENT_CENTER, 590.0, 24,
			Color(0.98, 0.96, 0.88, 0.88 * alpha))
		# Bounded title stays clear of the portrait in either player orientation.
		for line in TITLE_LINES.size():
			draw_string(ThemeDB.fallback_font,
				Vector2(copy_x, top + panel_h * (0.49 + float(line) * 0.22)) + shake,
				TITLE_LINES[line], HORIZONTAL_ALIGNMENT_CENTER, 590.0, 55,
				Color(accent.r, accent.g, accent.b, alpha))
		draw_string(ThemeDB.fallback_font, Vector2(copy_x, top + panel_h - 30.0) + shake,
			"PLAYER %d  //  SUPER" % (owner_index + 1), HORIZONTAL_ALIGNMENT_CENTER, 590.0, 18,
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


func play(who: int, tint: Color, fighter: Variant = 0, reduce_flashes: bool = false,
		length: float = DURATION) -> void:
	_art.reduced_flashes = reduce_flashes
	_art.begin(who, tint, fighter, length)


func cancel() -> void:
	if _art != null:
		_art.cancel()


func is_active() -> bool:
	return _art != null and _art.playing
