extends SceneTree

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

	_check(game.state == Phase.MENU and game._menu.visible and not game._ui.visible,
		"boot must land on a focused title screen without match HUD noise")

	game._on_menu_tutorial()
	game._transition.visible = false
	_check(game.tutorial_mode and game.state == Phase.TUTORIAL and game._tutorial.visible,
		"How To Play must open directly into its screen-by-screen briefing")
	_check(game._tutorial.page == 0 and not game._ui.visible,
		"How To Play must start on page one without match HUD noise")

	game._open_menu()
	game._transition.visible = false
	_check(game.state == Phase.MENU and not game.tutorial_mode and not game._tutorial.visible,
		"leaving How To Play must cleanly restore the title state")

	game._on_menu_start(false, 2, 2)
	game._transition.visible = false
	_check(game.state == Phase.PLANNING and game.level_index == 2 and game.players.size() == 2,
		"a selected local arena must reach a two-player planning phase")
	_check(not game._menu.visible and game._ui.visible,
		"starting a match must trade the menu for the gameplay HUD")

	game.state = Phase.GAME_OVER
	game.winner = 0
	game.rematch_level_index = game.level_index
	game.rematch_level_name = game.level_name
	game._touch_controls.enabled = false
	game._ui.refresh()
	_check(game._ui._replay_button.visible and game._ui._rematch_button.visible \
		and game._ui._menu_button.visible and game._ui._report_button.visible,
		"desktop results must expose replay, rematch, menu and report actions")
	var frozen_level: int = game.level_index
	game._cycle_rematch_level(1)
	_check(game.level_index == frozen_level and game.rematch_level_index != frozen_level,
		"arena selection on results must not mutate the frozen winning frame")
	var rematch_level: int = game.rematch_level_index
	game._request_rematch()
	_check(game.state == Phase.PLANNING and game.level_index == rematch_level,
		"the result-screen rematch must apply the selected arena")

	game.state = Phase.GAME_OVER
	game._ui._leave_result()
	game._transition.visible = false
	_check(game.state == Phase.MENU and game._menu.visible,
		"the result screen must always provide a route back to the title")

	game._on_menu_online(1)
	game._transition.visible = false
	_check(game.state == Phase.ONLINE_LOBBY and game._online_lobby.visible,
		"Online must open its private-room lobby instead of entering an ambiguous match state")
	game._leave_online()
	game._transition.visible = false
	_check(game.state == Phase.MENU and not game._online_lobby.visible,
		"cancelling Online must disconnect and restore the menu")

	game._on_menu_freeplay(3)
	game._transition.visible = false
	_check(game.state == Phase.FREEPLAY and game.level_index == 3 \
		and game._tuning.visible and not game._ui.visible,
		"Free Play must reach its continuous sandbox with tuning visible")
	game._open_menu()
	game._transition.visible = false
	_check(game.state == Phase.MENU and not game._tuning.visible,
		"leaving Free Play must cleanly hide sandbox-only tuning")

	root.remove_child(game)
	game.free()
	await process_frame
	if _failures == 0:
		print("User journey: all tests passed")
	else:
		push_error("User journey: %d test(s) failed" % _failures)
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
