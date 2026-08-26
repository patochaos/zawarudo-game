extends SceneTree

## Player 1's keys are data, not source. These checks pin that a rebind reaches
## the live planning input, that a key can only ever drive one action, and that
## the stored layout survives a reload without freezing out actions added later.

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const TEST_SETTINGS := "user://key-binding-test-settings.cfg"
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	var legacy := ConfigFile.new()
	legacy.set_value("options", "sound", 0.25)
	legacy.set_value("options", "maximized", false)
	_check(legacy.save(TEST_SETTINGS) == OK,
		"the binding suite must be able to create its isolated settings file")
	var game = MAIN_SCENE.instantiate()
	game.settings_path = TEST_SETTINGS
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	_check(is_equal_approx(float(game._settings["sfx"]), 0.25) \
			and is_equal_approx(float(game._settings["voice"]), 0.25),
		"the former master volume must migrate to both new sound channels")
	_check(game._settings["display"] == game.DISPLAY_720,
		"the former windowed preference must migrate to the 720p window preset")

	_check(game.key_bindings["left"] == [KEY_A] and game.key_bindings["jump"] == [
			KEY_SPACE, KEY_W, KEY_UP],
		"the shipped layout must be what an untouched install plays with")
	_check(game._input_map_for(0) == game.key_bindings,
		"the keyboard seat must read the live bindings, not a frozen copy")

	game._on_binding_changed("left", [KEY_J])
	_check(game.key_bindings["left"] == [KEY_J],
		"a rebound action must take the key immediately")
	_check(game._input_map_for(0)["left"] == [KEY_J],
		"the planning input must see the rebind without a restart")

	# Exclusivity: taking a key leaves whichever action held it empty, rather
	# than quietly driving two things from one press.
	game._on_binding_changed("wait", [KEY_J])
	_check(game.key_bindings["wait"] == [KEY_J] and game.key_bindings["left"] == [],
		"a key taken from another action must leave that action unbound")
	_check(game._menu._keys_text("left") == "—",
		"an unbound action must say so instead of showing a stale key")

	# A multi-key default collapses to the single key the player pressed.
	game._on_binding_changed("jump", [KEY_K])
	_check(game.key_bindings["jump"] == [KEY_K],
		"rebinding must replace every alternate, not append to them")

	game._on_binding_changed("nonsense", [KEY_L])
	_check(not game.key_bindings.has("nonsense"),
		"an action the game does not have must not be invented by a rebind")

	# Reload from the stored settings the way a fresh launch does.
	var stored: Dictionary = game._settings["bindings"].duplicate(true)
	_check(stored.has("left") and stored.has("wait") and stored.has("jump"),
		"every change must be persisted, including the action that lost a key")
	game.key_bindings.clear()
	game._apply_bindings()
	_check(game.key_bindings["wait"] == [KEY_J] and game.key_bindings["jump"] == [KEY_K] \
			and game.key_bindings["left"] == [],
		"a stored layout must come back exactly as it was left")
	_check(game.key_bindings["right"] == [KEY_D] and game.key_bindings["super"] == [KEY_T],
		"actions the stored layout never mentions must keep their shipped default")

	game._on_bindings_reset()
	_check(game.key_bindings == game.DEFAULT_BINDINGS \
			and game._settings["bindings"].is_empty(),
		"reset must restore the shipped layout and forget the overrides")

	# Escape stays out of reach: it is the one key every screen needs.
	game._menu._activate(game._menu.ROW_CONTROLS)
	game._menu._open_bindings()
	game._menu._activate(0)
	game._menu.handle_key(KEY_ESCAPE)
	_check(game.key_bindings["left"] == [KEY_A],
		"Escape must never become a movement key")

	if _failures == 0:
		print("Key bindings: all tests passed")
	else:
		push_error("Key bindings: %d test(s) failed" % _failures)
	game._ai_searches.fill(null)
	game.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
