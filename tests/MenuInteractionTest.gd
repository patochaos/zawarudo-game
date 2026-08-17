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
	_check(menu._page_names() == [
		"PLAY", "TUTORIAL", "ONLINE", "CONTROLS", "OPTIONS", "QUIT",
	], "the main menu must expose Controls alongside the five primary choices")
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

	menu._row_buttons[menu.ROW_CONTROLS].pressed.emit()
	_check(menu._page == menu.MenuPage.CONTROLS and menu._controls_sheet.visible,
		"Controls must open its dedicated reference sheet")
	_check(not menu._rows[0].visible and not menu._footer.visible,
		"the reference sheet must replace menu rows instead of competing with them")
	_check(_tree_has_text(menu._controls_sheet, "KEYBOARD + MOUSE") \
		and _tree_has_text(menu._controls_sheet, "GAMEPAD REQUIRED"),
		"Controls must identify P1 keyboard + mouse and P2 gamepad")
	_check(_tree_has_text(menu._controls_sheet, "Temporal Core") \
		and _tree_has_text(menu._controls_sheet, "first wave"),
		"Controls must explain how SUPER is earned, armed and spent")
	_check("F8 fill P1 SUPER" in menu._controls_sheet.shortcut_body.text \
		and "SHIFT + F8 fill P2 SUPER" in menu._controls_sheet.shortcut_body.text \
		and "F7 activate 3-dagger" in menu._controls_sheet.shortcut_body.text,
		"Controls must expose the SUPER and three-dagger playtest shortcuts")
	menu.handle_key(KEY_ESCAPE)
	_check(menu._page == menu.MenuPage.MAIN and menu._cursor == menu.ROW_CONTROLS,
		"Escape from Controls must return to the same main-menu row")

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
	menu._row_buttons[menu.OPTION_PREVIEW_CONTRAST].pressed.emit()
	_check(changed[0].size() == 2 and changed[0][0] == "high_contrast_previews" \
		and changed[0][1] == true,
		"preview contrast must be directly toggleable from Options")
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


func _tree_has_text(node: Node, fragment: String) -> bool:
	if node is Label and fragment in (node as Label).text:
		return true
	for child in node.get_children():
		if _tree_has_text(child, fragment):
			return true
	return false
