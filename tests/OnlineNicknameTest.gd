extends SceneTree

## Online nicknames: typed once in the lobby, remembered with the options,
## shown in the room occupancy, and used for seat tags and banners in the
## match. Seats without a name keep P1..P4, and local play never changes.

const MAIN := preload("res://scenes/Main.tscn")
const SETTINGS_PATH := "user://online-nickname-test-settings.cfg"
var failures := 0


func _init() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func run() -> void:
	check(OnlineLobby.sanitize_name("  pato  chaos!! ") == "PATO CHAOS",
		"Names must be upper-cased, filtered and single-spaced")
	check(OnlineLobby.sanitize_name("zé-dos_anos 2026 extra") == "Z-DOS_ANOS 2",
		"Names must stop at twelve characters, matching the room service")
	check(OnlineLobby.sanitize_name("!!!") == "", "A name with no allowed characters is empty")

	var game = MAIN.instantiate()
	game.settings_path = SETTINGS_PATH
	root.add_child(game)
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game._sfx.muted = true
	await process_frame
	game._on_menu_online()
	var lobby = game._online_lobby
	check(lobby._name_input.visible and lobby._name_input.text == "",
		"A fresh install opens the lobby with an empty name field")
	lobby._name_input.text = "pato chaos"
	lobby._name_input.text_changed.emit("pato chaos")
	check(lobby.nickname == "PATO CHAOS" and lobby._name_input.text == "PATO CHAOS",
		"Typing must sanitize live and keep the field in sync")

	check(game._remember_nickname() == "PATO CHAOS" and game._settings["nickname"] == "PATO CHAOS",
		"Using a name for a room must store it with the options")
	var saved := ConfigFile.new()
	check(saved.load(SETTINGS_PATH) == OK and saved.get_value("options", "nickname", "") == "PATO CHAOS",
		"The nickname must persist to the settings file")
	lobby.open(0, 0, str(game._settings["nickname"]))
	check(lobby._name_input.text == "PATO CHAOS", "Reopening the lobby must prefill the saved name")

	lobby.show_room("ABC234", 0)
	check(not lobby._name_input.visible, "The name field closes once the room exists")
	check("YOU ARE PATO CHAOS (P1)" in lobby._status.text, "The room status names this player")
	game.online_player = 0
	game.state = Phase.ONLINE_LOBBY
	game._on_online_message({"type": "connected", "capacity": 4, "names": ["PATO CHAOS", "", "", ""]})
	game._on_online_message({"type": "room_state", "capacity": 4, "level": 1, "phase": "waiting",
		"connected": [true, false, false, false], "names": ["PATO CHAOS", "", "", ""]})
	game._on_online_message({"type": "peer_status", "player": 2, "connected": true, "name": "RIVAL"})
	var occupancy: String = lobby._occupancy.text
	check("PATO CHAOS READY" in occupancy and "P2 WAITING" in occupancy and "RIVAL READY" in occupancy,
		"Occupancy must show nicknames where known and seat numbers elsewhere: %s" % occupancy)

	game._start_online_match(1, 777, 1, [0, 0, 0, 0], ["PATO CHAOS", "", "RIVAL", ""])
	check(game.player_tag(0) == "PATO CHAOS" and game.player_tag(1) == "P2"
		and game.player_title(2) == "RIVAL" and game.player_title(3) == "PLAYER 4",
		"Match labels must use nicknames and fall back per seat")
	check(game.players[2].seat_tag() == "RIVAL" and game.players[1].seat_tag() == "P2",
		"Fighter tags must follow the same rule")
	var score_text: String = game._score_text()
	check("PATO CHAOS 0" in score_text and "P2 0" in score_text,
		"The score line must name the seats: %s" % score_text)
	game._on_online_message({"type": "peer_status", "player": 2, "connected": false})
	check(game.banner_text.begins_with("RIVAL DISCONNECTED"),
		"Presence banners must use the nickname: %s" % game.banner_text)

	game._leave_online()
	check(game.online_names.is_empty() and game.player_tag(0) == "P1",
		"Leaving the room must drop the names so local matches show P1 again")

	game.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	if failures == 0:
		print("Online nickname checks passed.")
	quit(1 if failures else 0)
