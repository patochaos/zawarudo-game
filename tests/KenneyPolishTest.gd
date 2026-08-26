extends SceneTree

const PROMPTS := preload("res://scripts/InputPrompts.gd")
const SFX_SCRIPT := preload("res://scripts/Sfx.gd")
const EFFECTS_SCRIPT := preload("res://scripts/Effects.gd")
const TOUCH_SCRIPT := preload("res://scripts/TouchControls.gd")

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

	var sfx = SFX_SCRIPT.new()
	root.add_child(sfx)
	await process_frame
	for event in ["shoot", "hit", "clash", "break", "orb", "core", "freeze", "resume",
			"ui_move", "ui_accept"]:
		_check(sfx._layers.has(event) and not sfx._layers[event].is_empty(),
			"%s must retain a quiet imported support layer" % event)
	_check(sfx._players.size() == sfx.VOICES and sfx.VOICES >= 16,
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
