extends SceneTree

const MENU_SCRIPT := preload("res://scripts/MenuLayer.gd")
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var menu = MENU_SCRIPT.new()
	root.add_child(menu)
	await process_frame

	_check(menu._row_buttons.size() == menu.ROWS,
		"every visible menu row must have a mouse hit target")
	menu._row_buttons[menu.ROW_HOW_TO].pressed.emit()
	_check(menu._showing_how, "clicking HOW TO PLAY must open the brief instructions")
	_check(not menu._row_buttons[0].visible,
		"the main menu hit targets must not intercept the How to Play screen")

	var back: Button = menu._how_items[menu._how_items.size() - 1]
	back.pressed.emit()
	_check(not menu._showing_how and menu._row_buttons[0].visible,
		"the clickable BACK button must restore the main menu")

	var main_names: Array[String] = menu._page_names()
	_check(main_names == [
		"VS AI (1v1) - VERSION A", "VS AI (1v1) - VERSION B", "4 PLAYERS",
		"VS HUMAN (LOCAL)", "FREE PLAY", "HOW TO PLAY", "QUIT",
	], "the main menu must expose the requested seven choices in order")

	var level_before_main_input: int = menu.level
	menu.handle_key(KEY_D)
	_check(menu.level == level_before_main_input,
		"left/right must not change levels from the main menu")

	var started := [false, -1, 0]
	menu.start_requested.connect(func(_ai: bool, selected_level: int, _players: int):
		started[0] = true
		started[1] = selected_level
		started[2] += 1)
	menu._row_buttons[menu.ROW_MODE_AI_A].pressed.emit()
	_check(menu._page == menu.MenuPage.VERSION_A_LEVELS,
		"Version A must open its level submenu instead of starting immediately")
	_check(not started[0], "opening the Version A submenu must not start a match")
	_check(menu._page_names().size() == Levels.count() + 1,
		"the Version A submenu must list every level plus Back")
	menu.handle_key(KEY_ESCAPE)
	_check(menu._page == menu.MenuPage.MAIN,
		"Escape must return from the level submenu to the main menu")
	menu._row_buttons[menu.ROW_MODE_AI_A].pressed.emit()
	menu._row_buttons[2].pressed.emit()
	_check(started[0] and started[1] == 2 and started[2] == 1,
		"choosing a Version A level must start that level")
	_check(menu.ruleset == menu.Ruleset.ORIGINAL,
		"Version A must use the normal ruleset")

	menu.open()
	menu._row_buttons[menu.ROW_MODE_AI_B].mouse_entered.emit()
	_check(menu._level_preview._level_data["name"] == Levels.build_prototype()["name"],
		"hovering Version B must preview its fixed close-camera arena")
	menu._row_buttons[menu.ROW_MODE_AI_B].pressed.emit()
	_check(menu.ruleset == menu.Ruleset.CAMERA_PROTOTYPE,
		"Version B must select the close-camera ruleset")
	_check(started[2] == 2,
		"Version B must start directly without opening a level selector")

	var four_player_request := [false, 0]
	menu.start_requested.connect(func(_ai: bool, _level: int, players: int):
		four_player_request[0] = _ai
		four_player_request[1] = players)
	menu._row_buttons[menu.ROW_MODE_4P_AI].pressed.emit()
	_check(four_player_request[0] and four_player_request[1] == 4,
		"clicking 4 PLAYERS must request one human and three AI players")
	_check(menu.ruleset == menu.Ruleset.ORIGINAL,
		"other local modes must return to the normal ruleset")

	if _failures == 0:
		print("Menu interactions: all tests passed")
	else:
		push_error("Menu interactions: %d test(s) failed" % _failures)
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
