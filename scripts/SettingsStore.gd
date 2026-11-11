extends RefCounted
class_name SettingsStore

## Player options and key bindings, split out of GameManager: loading and
## saving `settings_path`, applying each option to the running game, and the
## controls screen's rebinding. GameManager owns one instance as
## `_settings_store`; `gm` is that GameManager.

## Window presets, in the order the options row cycles them.
const DISPLAY_720 := 0
const DISPLAY_900 := 1
const DISPLAY_1080 := 2
const DISPLAY_MAXIMIZED := 3
const DISPLAY_FULLSCREEN := 4
const DISPLAY_SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]

var gm
var _settings: Dictionary = {
	"sfx": 1.0,
	"voice": 1.0,
	"hit_freeze": true,
	"reduced_flashes": false,
	"high_contrast_previews": true,
	"display": DISPLAY_MAXIMIZED,
	"bindings": {},
	"telemetry": true,
	## Rungs of the Start Duel opponent ladder beaten so far.
	"ladder_progress": 0,
	## Nickname registered with online rooms; empty shows the seat number.
	"nickname": "",
}
## Tests can point persistence at a disposable file without touching the
## player's actual preferences.
var settings_path: String = "user://settings.cfg"


func _init(owner) -> void:
	gm = owner


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) == OK:
		for key in _settings.keys():
			_settings[key] = cfg.get_value("options", key, _settings[key])
		# Preserve preferences written before effects/voice and the display preset
		# became separate options. Saving once after the next change retires these
		# legacy keys naturally.
		if not cfg.has_section_key("options", "sfx") \
				and cfg.has_section_key("options", "sound"):
			_settings["sfx"] = cfg.get_value("options", "sound", 1.0)
		if not cfg.has_section_key("options", "voice") \
				and cfg.has_section_key("options", "sound"):
			_settings["voice"] = cfg.get_value("options", "sound", 1.0)
		if not cfg.has_section_key("options", "display") \
				and cfg.has_section_key("options", "maximized"):
			_settings["display"] = DISPLAY_MAXIMIZED \
				if bool(cfg.get_value("options", "maximized", true)) else DISPLAY_720
	_apply_settings()


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in _settings.keys():
		cfg.set_value("options", key, _settings[key])
	var error := cfg.save(settings_path)
	if error != OK:
		push_warning("Could not save options (error %d)" % error)


func _on_option_changed(key: String, value: Variant) -> void:
	if not _settings.has(key):
		return
	_settings[key] = value
	_apply_setting(key)
	_save_settings()


## A stored layout only replaces the actions it actually names, so a binding
## added later still arrives with its shipped default rather than unbound.
func _apply_bindings() -> void:
	gm._player_input.key_bindings = gm._player_input.DEFAULT_BINDINGS.duplicate(true)
	var stored: Dictionary = _settings.get("bindings", {})
	for action in stored.keys():
		if action in gm._player_input.key_bindings:
			gm._player_input.key_bindings[action] = Array(stored[action])
	if gm._menu != null:
		gm._menu.configure_bindings(gm._player_input.key_bindings)


## Rebinding is exclusive: a key can drive exactly one action, so taking it
## leaves whichever action held it empty until the player sets that one too.
func _on_binding_changed(action: String, codes: Array) -> void:
	if action not in gm._player_input.DEFAULT_BINDINGS:
		return
	var stored: Dictionary = _settings.get("bindings", {}).duplicate(true)
	for other in gm._player_input.key_bindings.keys():
		if other == action:
			continue
		var kept: Array = []
		for code in gm._player_input.key_bindings[other]:
			if code not in codes:
				kept.append(code)
		if kept.size() != gm._player_input.key_bindings[other].size():
			stored[other] = kept
	stored[action] = codes.duplicate()
	_on_option_changed("bindings", stored)


func _on_bindings_reset() -> void:
	_on_option_changed("bindings", {})


func _apply_settings() -> void:
	for key in _settings:
		_apply_setting(str(key))


func _apply_setting(key: String) -> void:
	match key:
		"sfx":
			if gm._sfx != null:
				gm._sfx.set_sfx_volume(float(_settings["sfx"]))
		"voice":
			if gm._sfx != null:
				gm._sfx.set_voice_volume(float(_settings["voice"]))
		"hit_freeze":
			gm.hit_freeze_enabled = bool(_settings["hit_freeze"])
		"reduced_flashes":
			gm.reduced_flashes = bool(_settings["reduced_flashes"])
			if gm._time_stop != null:
				gm._time_stop.reduced_flashes = gm.reduced_flashes
			if gm._event_direction != null:
				gm._event_direction.reduced_flashes = gm.reduced_flashes
			if gm._effects != null:
				gm._effects.reduced_flashes = gm.reduced_flashes
		"high_contrast_previews":
			if gm._preview != null:
				gm._preview.high_contrast = bool(_settings["high_contrast_previews"])
				gm._preview.queue_redraw()
		"telemetry":
			if gm._telemetry != null:
				gm._telemetry.enabled = bool(_settings["telemetry"])
		"bindings":
			_apply_bindings()
		"display":
			if DisplayServer.get_name() != "headless":
				_apply_display(int(_settings["display"]))


## One row owns the whole window decision, so a size and a mode can never
## disagree about what the player asked for.
func _apply_display(preset: int) -> void:
	var desired := DisplayServer.WINDOW_MODE_WINDOWED
	if preset == DISPLAY_MAXIMIZED:
		desired = DisplayServer.WINDOW_MODE_MAXIMIZED
	elif preset == DISPLAY_FULLSCREEN:
		desired = DisplayServer.WINDOW_MODE_FULLSCREEN
	if DisplayServer.window_get_mode() != desired:
		DisplayServer.window_set_mode(desired)
	if preset >= DISPLAY_SIZES.size():
		return
	var size: Vector2i = DISPLAY_SIZES[preset]
	if DisplayServer.window_get_size() != size:
		DisplayServer.window_set_size(size)
		# Resizing from the top-left corner walks the window off screen over a few
		# changes, so it is re-centred on the screen it already lives on.
		var screen := DisplayServer.window_get_current_screen()
		DisplayServer.window_set_position(
			DisplayServer.screen_get_position(screen)
			+ (DisplayServer.screen_get_size(screen) - size) / 2)
