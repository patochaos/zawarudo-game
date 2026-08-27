extends SceneTree

const PROMPTS := preload("res://scripts/InputPrompts.gd")
const SFX_SCRIPT := preload("res://scripts/Sfx.gd")
const EFFECTS_SCRIPT := preload("res://scripts/Effects.gd")
const TOUCH_SCRIPT := preload("res://scripts/TouchControls.gd")
const BACKDROP_SCRIPT := preload("res://scripts/Backdrop.gd")
const PREVIEW_SCRIPT := preload("res://scripts/PreviewLayer.gd")
const CURSOR_SCRIPT := preload("res://scripts/CursorTheme.gd")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for id: StringName in [&"key_a", &"mouse_left", &"pad_a", &"pad_rt", &"touch_tap"]:
		_check(PROMPTS.icon(id) != null, "prompt %s must resolve to an imported texture" % id)
	_check(PROMPTS.DISPLAY_FONT != null and PROMPTS.HUD_FONT != null,
		"both Kenney typography roles must resolve")
	_check(str(ProjectSettings.get_setting("gui/theme/custom_font", "")).ends_with(
		"kenney-future.ttf"), "the project theme must use the selected display font")

	_check(BACKDROP_SCRIPT.PATTERN_TEXTURES.size() == 7,
		"every arena must own a Kenney pattern motif")
	for texture: Texture2D in BACKDROP_SCRIPT.PATTERN_TEXTURES:
		_check(texture != null, "every arena pattern must resolve to an imported texture")
	var reticles := [PREVIEW_SCRIPT.RETICLE_DUELIST, PREVIEW_SCRIPT.RETICLE_ROOK,
		PREVIEW_SCRIPT.RETICLE_ECLIPSE, PREVIEW_SCRIPT.RETICLE_PULSE]
	var reticle_paths := {}
	for texture: Texture2D in reticles:
		_check(texture != null, "every fighter reticle must resolve")
		_check(not reticle_paths.has(texture.resource_path),
			"fighter reticles must use distinct Kenney silhouettes")
		reticle_paths[texture.resource_path] = true
	for texture: Texture2D in [CURSOR_SCRIPT.POINTER, CURSOR_SCRIPT.POINTING_HAND,
		CURSOR_SCRIPT.DISABLED, CURSOR_SCRIPT.BUSY]:
		_check(texture != null, "every menu cursor role must resolve")
	_check(EFFECTS_SCRIPT.TEX_INK_SPLAT != null and EFFECTS_SCRIPT.TEX_SONIC_RING != null,
		"kill and explosion effects must resolve their Kenney masks")

	var sfx = SFX_SCRIPT.new()
	root.add_child(sfx)
	await process_frame
	for event in ["knife_throw", "fighter_hit", "knife_impact", "platform_break",
			"knife_clash", "time_freeze", "time_resume", "ui_move", "ui_accept"]:
		_check(sfx._layers.has(event) and not sfx._layers[event].is_empty(),
			"%s must retain a quiet imported support layer" % event)
	var class_events := {
		"DUELIST": ["knife_throw", "knife_super", "knife_impact", "knife_ricochet",
			"knife_clash", "knife_hit"],
		"ROOK": ["dash", "dash_super", "dash_guard", "dash_wall", "dash_hit"],
		"ECLIPSE": ["chakram_throw", "chakram_recall", "chakram_bounce",
			"chakram_stick", "chakram_clash", "chakram_break", "chakram_super",
			"chakram_hit"],
		"PULSE": ["plasma", "plasma_impact", "plasma_hit", "orb_cast",
			"orb_deflect", "orb_pop", "orb_combo", "shock_super"],
	}
	var owned_paths := {}
	for fighter: String in class_events:
		for event: String in class_events[fighter]:
			_check(sfx._streams.has(event), "%s must own the %s event" % [fighter, event])
			var path := _imported_path_for(sfx, event)
			_check(not path.is_empty(), "%s must resolve to an imported Kenney cue" % event)
			_check(not owned_paths.has(path), "%s and %s must not reuse %s" % [
				event, owned_paths.get(path, "another event"), path])
			owned_paths[path] = event
	for event in ["hazard_blast", "core_collect", "super_ready", "match_start", "victory"]:
		_check(sfx._streams.has(event), "%s must resolve to a cleared Kenney cue" % event)
	for retired in ["shoot", "hit", "thud", "break", "clash", "explosion", "orb", "core",
			"freeze", "resume"]:
		_check(not sfx._streams.has(retired), "%s is too generic for the event taxonomy" % retired)
	_check("match_start" in sfx.VOICE_CUES and "victory" in sfx.VOICE_CUES,
		"announcer cues must follow the voice-volume channel")
	_check(sfx._players.size() == sfx.VOICES and sfx.VOICES >= 24,
		"the audio pool must have room for procedural and imported layers")

	var effects = EFFECTS_SCRIPT.new()
	root.add_child(effects)
	for kind in [Effects.Kind.SPARK, Effects.Kind.SHATTER, Effects.Kind.KILL,
			Effects.Kind.CLASH, Effects.Kind.EXPLOSION]:
		effects.add(kind, Vector2(100.0 + float(kind) * 80.0, 220.0), Color(0.8, 0.5, 1.0))
	_check(effects._fx.size() == 5, "each imported effect family must remain cosmetic and queueable")
	effects.reduced_flashes = true
	_check(effects.reduced_flashes, "reduced-flash settings must reach imported texture layers")

	var touch = TOUCH_SCRIPT.new()
	root.add_child(touch)
	await process_frame
	for action in ["jump", "charge", "confirm", "menu", "rollback", "reset", "super"]:
		_check(touch._button_icon(action) != null, "%s must expose a mobile action glyph" % action)

	touch.queue_free()
	effects.queue_free()
	sfx.queue_free()
	await process_frame
	if _failures == 0:
		print("Kenney polish: all tests passed")
	else:
		push_error("Kenney polish: %d test(s) failed" % _failures)
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)


func _imported_path_for(sfx, event: String) -> String:
	var stream: AudioStream = sfx._streams.get(event)
	if stream != null and not stream.resource_path.is_empty():
		return stream.resource_path
	for layer: Dictionary in sfx._layers.get(event, []):
		var direct: AudioStream = layer.get("stream")
		if direct != null and not direct.resource_path.is_empty():
			return direct.resource_path
		var variants: Array = layer.get("variants", [])
		if not variants.is_empty():
			return variants[0].resource_path
	return ""
