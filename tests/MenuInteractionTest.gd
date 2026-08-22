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
		"PLAY", "HOW TO PLAY", "ONLINE", "CONTROLS", "OPTIONS", "QUIT",
	], "the main menu must retain its primary destinations")
	var play_footer: String = menu._footer.text
	menu._row_buttons[menu.ROW_TUTORIAL].mouse_entered.emit()
	_check(menu._footer.text != play_footer and "six-screen" in menu._footer.text,
		"hovering a row must replace the contextual footer copy")

	menu._row_buttons[menu.ROW_CONTROLS].pressed.emit()
	_check(menu._page == menu.MenuPage.CONTROLS and menu._controls_sheet.visible,
		"Controls must open its dedicated reference sheet")
	_check(not menu._rows[0].visible and not menu._footer.visible,
		"the reference sheet must replace menu rows instead of competing with them")
	_check(_tree_has_text(menu._controls_sheet, "KEYBOARD + MOUSE") \
		and _tree_has_text(menu._controls_sheet, "CONNECTED GAMEPAD"),
		"Controls must explain keyboard and controller ownership")
	menu.handle_key(KEY_ESCAPE)

	menu._row_buttons[menu.ROW_PLAY].pressed.emit()
	_check(menu._page == menu.MenuPage.SETUP,
		"Play must open the single local-match setup screen")
	var setup_names := menu._page_names()
	_check(setup_names.size() == 7 and "MODE" in setup_names[0] \
		and "FIGHTERS" in setup_names[1] and "P1" in setup_names[2] \
		and "P2" in setup_names[3] and "ARENA" in setup_names[4] \
		and "MATCH LIVES" in setup_names[5] and setup_names[6] == "START MATCH",
		"mode, count, roster classes, arena, lives and Start must coexist on one screen")
	_check(not "GRENADIER" in " ".join(menu._page_names()) \
		and not "WIDE" in " ".join(menu._page_names()),
		"the retired Grenadier shortcut and Wide suffix must be absent")

	menu._select(menu.SETUP_PLAYERS)
	menu.handle_key(KEY_RIGHT)
	menu.handle_key(KEY_RIGHT)
	_check(menu._page == menu.MenuPage.SETUP and menu.battle_player_count == 4 \
		and menu._page_names().size() == 9,
		"changing fighter count must expand the roster without opening another page")
	_check(menu.battle_roles[0] == "HUMAN" and menu.battle_devices[0] == -2,
		"P1 must always be keyboard-controlled")
	var pads := Input.get_connected_joypads()
	_check((pads.is_empty() and menu.battle_roles[1] == "AI" and menu.battle_devices[1] == -1) \
		or (not pads.is_empty() and menu.battle_roles[1] == "HUMAN" \
			and menu.battle_devices[1] == pads[0]),
		"P2 must be human only when a controller is detected")
	_check(menu.battle_roles[2] == "AI" and menu.battle_roles[3] == "AI",
		"extra prototype slots must remain CPU-controlled")
	menu._select(menu.SETUP_FIRST_FIGHTER)
	menu.handle_key(KEY_RIGHT)
	_check(menu._portrait_preview.visible and menu._portrait_preview.texture == menu.DASHBLADE_PORTRAIT \
		and "LOST FRAMES" in menu._context_meta.text and "LORE" in menu._footer.text,
		"fighter focus must show the selected portrait, abilities and lore")
	menu._select(menu.SETUP_FIRST_FIGHTER + 1)
	menu.handle_key(KEY_RIGHT)
	menu.handle_key(KEY_RIGHT)
	_check(menu.battle_weapons.slice(0, 2) == [2, 4] \
			and "VELOCITY" in menu._page_names()[2] \
			and "STATIC WITCH" in menu._page_names()[3],
		"human and CPU classes must be editable inline")
	menu._select(menu.SETUP_FIRST_FIGHTER + 2)
	menu.handle_key(KEY_LEFT)
	_check(menu.battle_weapons[2] == 3 and "BROODTAIL" in menu._page_names()[4] \
			and menu._portrait_preview.texture == menu.CHAKRAM_PORTRAIT \
			and "RECALL" in menu._context_meta.text,
		"Broodtail must be the fourth roster choice with a complete dossier")
	menu._select(menu._setup_arena_row())
	menu.handle_key(KEY_RIGHT)
	menu.handle_key(KEY_RIGHT)
	_check(menu.level == 2 and menu._page == menu.MenuPage.SETUP,
		"arena selection must stay on the same setup screen")
	_check(menu._arena_dossier.visible and not menu._portrait_preview.visible \
		and "LAYOUT READ" in menu._footer.text,
		"arena focus must replace the portrait with a live layout thumbnail")
	menu._select(menu._setup_lives_row())
	menu.handle_key(KEY_RIGHT)
	_check(menu.match_lives == 7 and "7" in menu._page_names()[menu._setup_lives_row()],
		"match lives must be adjustable beside the rest of the configuration")
	_check("P1" in menu._match_card.text and "FIRST TO 7 HITS" in menu._match_card.text,
		"the live match card must update without a separate review page")

	var final_config := [{}]
	menu.configured_match_requested.connect(func(config: Dictionary): final_config[0] = config)
	menu._activate(menu._setup_start_row())
	_check(final_config[0]["mode"] == menu.BattleMode.VS \
		and final_config[0]["player_count"] == 4 \
		and final_config[0]["weapons"] == [2, 4, 3, 0] \
		and final_config[0]["level"] == 2 \
		and final_config[0]["match_lives"] == 7,
		"Start Match must emit one complete source of truth")

	menu.open()
	menu._activate(menu.ROW_PLAY)
	menu._select(menu.SETUP_MODE)
	menu.handle_key(KEY_RIGHT)
	menu._select(menu.SETUP_PLAYERS)
	menu.handle_key(KEY_LEFT)
	_check(menu.battle_player_count == 3 and menu.battle_teams == [0, 1, 0],
		"Team Battle must update player count and sides inline")
	menu._select(menu.SETUP_MODE)
	menu.handle_key(KEY_RIGHT)
	_check(menu.battle_mode == menu.BattleMode.FREE_PLAY \
		and "OFF" in menu._page_names()[menu._setup_lives_row()] \
		and menu.battle_roles[2] == "DUMMY",
		"Free Play must replace scoring with visible dummy slots on the same screen")

	menu.open()
	var changed := [[]]
	menu.option_changed.connect(func(key, value): changed[0] = [key, value])
	menu._activate(menu.ROW_OPTIONS)
	menu._activate(menu.OPTION_HIT_FREEZE)
	_check(changed[0].size() == 2 and changed[0][0] == "hit_freeze",
		"Options must remain functional outside battle setup")
	menu.handle_key(KEY_ESCAPE)
	_check(menu._page == menu.MenuPage.MAIN,
		"Escape must return from Options to the main menu")

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
