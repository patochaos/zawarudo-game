extends SceneTree

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var lobby := OnlineLobby.new()
	root.add_child(lobby)
	await process_frame
	lobby.open(0)
	var requests: Array = []
	lobby.create_requested.connect(func(level: int, weapon: int, capacity: int):
		requests.append([level, weapon, capacity]))
	lobby._create.pressed.emit()
	_check(requests == [[0, Roster.DUELIST, 4]], "new rooms must request four seats by default")
	lobby._capacity_button.pressed.emit()
	lobby._create.pressed.emit()
	_check(requests.back()[2] == 2, "duel selection must request two seats")
	lobby.show_room("ABC234", 3)
	lobby.update_room([true, true, false, true], 4, 1)
	_check(lobby.capacity == 4 and lobby.level == 1,
		"joining must use the server capacity and arena, not the local host selections")
	_check("3/4 CONNECTED" in lobby._occupancy.text and "P3 WAITING" in lobby._occupancy.text \
		and "P4 JOINED" in lobby._occupancy.text, "all four lobby slots must be represented accurately")
	_check(not lobby._capacity_button.visible and not lobby._create.visible,
		"room settings must be fixed after joining")
	lobby.update_room([true, true, true, true], 4, 1)
	_check("4/4 CONNECTED" in lobby._occupancy.text, "a full room must show all four players")
	lobby.open(0)
	_check(lobby._capacity_button.visible and not lobby._occupancy.visible,
		"reopening must restore settings and hide stale occupancy")
	lobby.queue_free()
	await process_frame
	if _failures == 0:
		print("Online lobby four-player checks passed.")
	quit(1 if _failures else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
