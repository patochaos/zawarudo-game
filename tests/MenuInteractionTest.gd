extends SceneTree

## The title screen only chooses a destination. Everything about a local match
## is decided on the roster screen, so this suite pins that the title stays a
## short list of destinations and never grows a configuration page again.

const MENU_SCRIPT := preload("res://scripts/MenuLayer.gd")
const GAME_MANAGER := preload("res://scripts/GameManager.gd")
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var menu = MENU_SCRIPT.new()
	root.add_child(menu)
	await process_frame

	menu.configure_bindings(GAME_MANAGER.DEFAULT_BINDINGS.duplicate(true))
	var controls_node_count: int = menu._controls_sheet.get_child_count()
	menu.configure_bindings(GAME_MANAGER.DEFAULT_BINDINGS.duplicate(true))
	_check(menu._controls_sheet.get_child_count() == controls_node_count,
		"refreshing live bindings must not rebuild the controls sheet")
	_check(menu._row_buttons.size() == menu.ROWS,
		"every menu row slot must have a mouse hit target")
	_check(menu._page_names() == [
		"PLAY", "SANDBOX", "HOW TO PLAY", "ONLINE", "CONTROLS", "OPTIONS", "QUIT",
	], "the main menu must retain its primary destinations")
	_check(menu._rows[menu.ROWS - 1].visible == false,
		"rows the current page does not fill must stay hidden")
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
	_check(_tree_has_text(menu._controls_sheet, "presses A to take an open slot"),
		"Controls must explain how a pad claims a roster slot")
	menu.handle_key(KEY_ESCAPE)
	_check(menu._page == menu.MenuPage.MAIN and menu._cursor == menu.ROW_CONTROLS,
		"leaving the reference sheet must return to the row that opened it")

	# Play is a destination, not a page: it hands the whole local match over to
	# the roster screen rather than unfolding a configuration list in place.
	var opened := [0]
	menu.roster_requested.connect(func(): opened[0] += 1)
	menu._row_buttons[menu.ROW_PLAY].pressed.emit()
	_check(opened[0] == 1 and menu._page == menu.MenuPage.MAIN,
		"Play must request the roster screen instead of opening a setup page")
	var sandbox_opened := [0]
	menu.sandbox_requested.connect(func(): sandbox_opened[0] += 1)
	menu._row_buttons[menu.ROW_SANDBOX].pressed.emit()
	_check(sandbox_opened[0] == 1 and menu._page == menu.MenuPage.MAIN,
		"Sandbox must request its direct launch without opening setup")
	_check(menu.MenuPage.keys() == ["MAIN", "CONTROLS", "OPTIONS", "BINDINGS"],
		"the title screen must no longer carry a setup page")

	var changed := [[]]
	menu.option_changed.connect(func(key, value): changed[0] = [key, value])
	menu._activate(menu.ROW_OPTIONS)
	_check(menu._page == menu.MenuPage.OPTIONS and menu._page_names().size() == 8,
		"Options must open its own seven-setting page plus Back")
	menu._activate(menu.OPTION_HIT_FREEZE)
	_check(changed[0].size() == 2 and changed[0][0] == "hit_freeze",
		"Options must remain functional outside battle setup")

	# Effects and voice are separate channels: this game has no music bed, and the
	# loud cues people actually want to turn down are the shout and the chant.
	menu._select(menu.OPTION_SFX)
	menu.handle_key(KEY_LEFT)
	_check(changed[0][0] == "sfx" and menu._sfx_percent == 75 and menu._voice_percent == 100,
		"A / D must adjust one sound channel without activating it or moving the other")
	menu._select(menu.OPTION_VOICE)
	menu.handle_key(KEY_LEFT)
	_check(changed[0][0] == "voice" and menu._voice_percent == 75 and menu._sfx_percent == 75,
		"the voice channel must carry its own level")
	menu._select(menu.OPTION_DISPLAY)
	menu.handle_key(KEY_RIGHT)
	_check(changed[0][0] == "display" and changed[0][1] == 4 \
		and "FULLSCREEN" in menu._page_names()[menu.OPTION_DISPLAY],
		"one display row must own window size and fullscreen together")
	menu.handle_key(KEY_ESCAPE)
	_check(menu._page == menu.MenuPage.MAIN,
		"Escape must return from Options to the main menu")

	# The dossier panel is a caption card now, not a field holding one sentence.
	_check(menu._footer_plate.polygon[2].y <= 200.0,
		"the context panel must be sized for its copy instead of half the screen")

	_test_bindings(menu)

	# The mist behind the title is decoration only; the match's arena belongs to
	# the roster screen and must never be read back out of here.
	menu.backdrop_level = 3
	menu._refresh()
	_check(menu._level_preview != null and not ("level" in menu),
		"the title screen must hold no match configuration of its own")

	if _failures == 0:
		print("Menu interactions: all tests passed")
	else:
		push_error("Menu interactions: %d test(s) failed" % _failures)
	quit(_failures)


## Rebinding: pressing Enter on an action arms it, the next key takes it, and a
## key can only ever drive one action at a time.
func _test_bindings(menu) -> void:
	menu._activate(menu.ROW_CONTROLS)
	menu._open_bindings()
	_check(menu._page == menu.MenuPage.BINDINGS and menu._page_names().size() == 11,
		"the binding list must reach every rebindable Player 1 action")
	_check("A" in menu._page_names()[0] and "MOVE LEFT" in menu._page_names()[0],
		"each row must name its action and the key that currently drives it")

	var bound := [[]]
	menu.binding_changed.connect(func(action, codes): bound[0] = [action, codes])
	menu._activate(0)
	_check(menu._binding_row == 0 and "PRESS A KEY" in menu._page_names()[0],
		"an armed row must say it is listening")
	menu.handle_key(KEY_J)
	_check(bound[0][0] == "left" and bound[0][1] == [KEY_J] and menu._binding_row == -1,
		"the next key pressed must become the binding and end capture")

	menu._activate(2)
	menu.handle_key(KEY_ESCAPE)
	_check(menu._binding_row == -1 and bound[0][0] == "left",
		"Escape must cancel capture without binding anything")
	_check(not "PRESS A KEY" in menu._rows[2].text,
		"canceling capture must immediately clear the listening prompt")

	var reset := [0]
	menu.bindings_reset.connect(func(): reset[0] += 1)
	menu._activate(menu.BINDING_RESET_ROW)
	_check(reset[0] == 1, "the list must offer a way back to the shipped layout")
	menu._activate(menu.BINDING_BACK_ROW)
	_check(menu._page == menu.MenuPage.CONTROLS,
		"leaving the binding list must return to the controls reference")
	menu.handle_key(KEY_ESCAPE)


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
