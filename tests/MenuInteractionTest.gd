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

	var previous_level: int = menu.level
	menu._row_buttons[menu.ROW_LEVEL].pressed.emit()
	_check(menu.level == posmod(previous_level + 1, Levels.count()),
		"clicking LEVEL must advance the selected arena")
	_check(menu._level_preview._level_data["name"] == Levels.build(menu.level)["name"],
		"the background preview must follow the selected arena")

	var started := [false]
	menu.start_requested.connect(func(_ai: bool, _level: int): started[0] = true)
	menu._row_buttons[menu.ROW_MODE_AI].pressed.emit()
	_check(started[0], "clicking VS AI must emit the same start request as Enter")

	var online := [false, -1]
	menu.online_requested.connect(func(level: int):
		online[0] = true
		online[1] = level)
	menu._row_buttons[menu.ROW_ONLINE].pressed.emit()
	_check(online[0] and online[1] == menu.level,
		"clicking ONLINE must request a room for the selected level")

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
