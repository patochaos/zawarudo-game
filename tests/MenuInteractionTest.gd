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
		"every menu row slot must have a mouse hit target")
	_check(menu._page_names() == ["PLAY", "TUTORIAL", "ONLINE", "OPTIONS", "QUIT"],
		"the main menu must expose only the five primary choices")
	_check(not menu._footer.text.is_empty(),
		"the highlighted main choice must have a footer description")
	var play_footer: String = menu._footer.text
	menu._row_buttons[menu.ROW_TUTORIAL].mouse_entered.emit()
	_check(menu._footer.text != play_footer and "stamina" in menu._footer.text,
		"hovering a row must replace the contextual footer copy")

	var tutorial_started := [false]
	menu.tutorial_requested.connect(func(): tutorial_started[0] = true)
	menu._row_buttons[menu.ROW_TUTORIAL].pressed.emit()
	_check(tutorial_started[0], "Tutorial must remain directly launchable")

	var online_opened := [false]
	menu.online_requested.connect(func(_level): online_opened[0] = true)
	menu.open()
	menu._row_buttons[menu.ROW_ONLINE].pressed.emit()
	_check(online_opened[0], "Online must remain directly accessible from the main menu")

	var level_before_main_input: int = menu.level
	menu.open()
	menu.handle_key(KEY_D)
	_check(menu.level == level_before_main_input,
		"left/right must not change levels from the main menu")

	menu._row_buttons[menu.ROW_PLAY].pressed.emit()
	_check(menu._page == menu.MenuPage.LOCAL_PLAY,
		"Play must open the local mode submenu")
	_check(menu._page_names() == [
		"VS AI — WIDE", "VS AI — CLOSE", "VS HUMAN", "4 PLAYERS", "FREE PLAY", "‹  BACK",
	], "the local submenu must group every local mode plus Back")
	for row in menu._page_row_count():
		menu._select(row)
		_check(not menu._footer.text.is_empty(),
			"every local mode must have a footer description")

	var started := [false, -1, 0]
	menu.start_requested.connect(func(_ai: bool, selected_level: int, _players: int):
		started[0] = true
		started[1] = selected_level
		started[2] += 1)
	menu._row_buttons[menu.LOCAL_AI_WIDE].pressed.emit()
	_check(menu._page == menu.MenuPage.WIDE_LEVELS,
		"Wide must open its level submenu instead of starting immediately")
	_check(not started[0], "opening the Wide submenu must not start a match")
	_check(menu._page_names().size() == Levels.count() + 1,
		"the Wide submenu must list every level plus Back")
	for row in menu._page_row_count():
		menu._select(row)
		_check(not menu._footer.text.is_empty(),
			"every arena and Back must have a footer description")
	menu.handle_key(KEY_ESCAPE)
	_check(menu._page == menu.MenuPage.LOCAL_PLAY,
		"Escape from arenas must return to local modes")
	menu.handle_key(KEY_ESCAPE)
	_check(menu._page == menu.MenuPage.MAIN,
		"Escape from local modes must return to the main menu")

	menu._row_buttons[menu.ROW_PLAY].pressed.emit()
	menu._row_buttons[menu.LOCAL_AI_WIDE].pressed.emit()
	menu._row_buttons[2].pressed.emit()
	_check(started[0] and started[1] == 2 and started[2] == 1,
		"choosing a Wide arena must start that level")
	_check(menu.ruleset == menu.Ruleset.ORIGINAL,
		"Wide must use the normal ruleset")

	menu.open()
	menu._row_buttons[menu.ROW_PLAY].pressed.emit()
	menu._row_buttons[menu.LOCAL_AI_CLOSE].mouse_entered.emit()
	_check(menu._level_preview._level_data["name"] == Levels.build_prototype()["name"],
		"hovering Close must preview its fixed close-camera arena")
	menu._row_buttons[menu.LOCAL_AI_CLOSE].pressed.emit()
	_check(menu.ruleset == menu.Ruleset.CAMERA_PROTOTYPE,
		"Close must select the close-camera ruleset")
	_check(started[2] == 2,
		"Close must start directly without opening a level selector")

	menu.open()
	var changed := [[]]
	menu.option_changed.connect(func(key, value): changed[0] = [key, value])
	menu._row_buttons[menu.ROW_OPTIONS].pressed.emit()
	_check(menu._page == menu.MenuPage.OPTIONS,
		"Options must open its own compact page")
	for row in menu._page_row_count():
		menu._select(row)
		_check(not menu._footer.text.is_empty(),
			"every option must explain its effect in the footer")
	menu._row_buttons[menu.OPTION_HIT_FREEZE].pressed.emit()
	_check(changed[0].size() == 2 and changed[0][0] == "hit_freeze",
		"changing an option must emit its setting")
	menu.handle_key(KEY_ESCAPE)
	_check(menu._page == menu.MenuPage.MAIN,
		"Escape must return from Options to the main menu")

	var four_player_request := [false, 0]
	menu.start_requested.connect(func(_ai: bool, _level: int, players: int):
		four_player_request[0] = _ai
		four_player_request[1] = players)
	menu._row_buttons[menu.ROW_PLAY].pressed.emit()
	menu._row_buttons[menu.LOCAL_4P_AI].pressed.emit()
	_check(four_player_request[0] and four_player_request[1] == 4,
		"4 Players must request one human and three AI players")
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
