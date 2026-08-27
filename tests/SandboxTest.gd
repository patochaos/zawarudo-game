extends SceneTree

## The title-screen sandbox is a deterministic test bench: it always enters the
## same baseline, then every loadout control mutates the running source game.

const MAIN_SCENE := preload("res://scenes/Main.tscn")
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game._transition.visible = false

	game._menu._activate(game._menu.ROW_SANDBOX)
	game._transition.visible = false
	_check(game.state == Phase.FREEPLAY and game.level_index == 0,
		"Sandbox must enter Arena 1 directly")
	_check(game.players.size() == 1 and game.player_weapons[0] == game.Weapon.KNIVES,
		"Sandbox must begin with one human Duelist and no target")
	_check(game._tuning.visible and game._tuning._sandbox_buttons.size() == 5,
		"Sandbox must expose the five live loadout controls")
	_check(game._tuning._sandbox_buttons[3].disabled \
		and game._tuning._sandbox_buttons[4].disabled,
		"CPU-only controls must communicate their unavailable state")

	game._tuning._sandbox_buttons[0].pressed.emit()
	_check(game.player_weapons[0] == game.Weapon.DASHBLADE,
		"P1 class button must cycle the running fighter")
	game._tuning._sandbox_buttons[1].pressed.emit()
	_check(game.level_index == 1,
		"Arena button must cycle and reset into the next authored level")

	game._tuning._sandbox_buttons[2].pressed.emit()
	_check(game.players.size() == 2 and game.sandbox_has_ai(),
		"Add CPU must create a real AI opponent")
	_check(not game._tuning._sandbox_buttons[3].disabled \
		and not game._tuning._sandbox_buttons[4].disabled,
		"adding a CPU must enable its class and skill controls")
	game._tuning._sandbox_buttons[3].pressed.emit()
	_check(game.player_weapons[1] == game.Weapon.DASHBLADE,
		"CPU class button must cycle the live opponent")
	game._tuning._sandbox_buttons[4].pressed.emit()
	_check(game.player_difficulty(1) == game.Difficulty.RUTHLESS,
		"CPU skill button must cycle the opponent's real AI preset")

	# SceneTree resumes listeners at the frame boundary before the manager's
	# physics callback, so allow one complete tick after that boundary.
	await physics_frame
	await physics_frame
	_check(game._sandbox_ai_search != null or game._sandbox_ai_exec_tick >= 0,
		"the sandbox CPU must enter the shipped AI planning/execution loop")

	game._tuning.handle_key(KEY_F1, false)
	_check(game.player_weapons[0] == game.Weapon.SHOCK,
		"F1 must share the class-cycle action used by the button")
	game._tuning.handle_key(KEY_F2, true)
	_check(game.level_index == 0,
		"Shift+F2 must cycle the arena backward")

	game._tuning._sandbox_buttons[2].pressed.emit()
	_check(game.players.size() == 1 and not game.sandbox_has_ai(),
		"Remove CPU must restore the solo sandbox")

	game._open_menu()
	game._transition.visible = false
	_check(game.state == Phase.MENU and not game._tuning.visible,
		"leaving the sandbox must restore the title and hide lab controls")

	root.remove_child(game)
	game.free()
	await process_frame
	if _failures == 0:
		print("Sandbox controls: all tests passed")
	else:
		push_error("Sandbox controls: %d test(s) failed" % _failures)
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
