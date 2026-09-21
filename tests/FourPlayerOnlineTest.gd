extends SceneTree

const MAIN := preload("res://scenes/Main.tscn")
var failures := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var games: Array = []
	for slot in 4:
		var game = MAIN.instantiate()
		root.add_child(game)
		game.process_mode = Node.PROCESS_MODE_DISABLED
		game._sfx.muted = true
		game.online_player = slot
		game.state = Phase.ONLINE_LOBBY
		games.append(game)
	var host = games[0]
	host._online_lobby.open(2)
	host._online_lobby.show_room("ABC234", 0)
	host._on_online_message({"type": "connected", "capacity": 4})
	host._on_online_message({"type": "room_state", "capacity": 4, "level": 2,
		"phase": "waiting", "connected": [true, false, false, false]})
	host._on_online_message({"type": "peer_status", "player": 2, "connected": true})
	check("2/4 CONNECTED" in host._online_lobby._occupancy.text,
		"Host occupancy must refresh when another player's socket connects")
	check(host._online_lobby.level == 2, "Presence changes must preserve the host arena")
	for level in Levels.count():
		for game in games:
			game.online_mode = false
			game.team_mode = true
			game.class_lab = true
			game.real_time_mode = true
			game.execution_duration = 1.5
			game._start_online_match(level, 12345, 1, [0, 0, 0, 0])
			check(game.players.size() == 4 and not game.team_mode and not game.class_lab \
				and not game.real_time_mode, "Online start must clear local modes and spawn four humans")
			check(game.execution_duration == 0.75, "Online start must reset local tuning")
			check(game._keyboard_player() == game.online_player, "Every slot must own its local keyboard")
			for i in 4:
				check(not game.is_ai(i), "Online slots must never run AI")
		var first_digest: String = games[0]._online_state_digest()
		for game in games:
			check(game._online_state_digest() == first_digest, "Initial states must match across all clients")
		for slot in [2, 3]:
			games[0].score[slot] += 1
			check(games[0]._online_state_digest() != first_digest, "P3/P4 score drift must change checksum")
			games[0].score[slot] -= 1
			games[0].player_weapons[slot] = 2
			check(games[0]._online_state_digest() != first_digest, "P3/P4 kit drift must change checksum")
			games[0].player_weapons[slot] = 0
		for round_index in 3:
			var plans: Array = []
			for slot in 4:
				var plan := PlayerPlan.new()
				for tick in 12:
					plan.record(1 if slot % 2 == 0 else -1, tick == 0, tick < 6)
				plan.shot_tick = 10
				plan.aim_angle = 20.0 if slot % 2 == 0 else 160.0
				plan.power = 0.6
				plans.append(plan.to_network_dict())
			for game in games:
				game._apply_online_turn_plans({"turn": game.turn, "plans": plans.slice(0, 3)})
				check(game.state == Phase.PLANNING, "Three plans cannot execute a four-player turn")
				game._apply_online_turn_plans({"turn": game.turn, "plans": plans})
				check(game.state == Phase.COMMITTING, "All four plans must commit")
				for i in 4:
					check(game.players[i].plan.confirmed, "Every received plan must be applied")
				game._begin_execution()
				for tick in game.exec_ticks_total:
					game.exec_tick = tick
					game._sim_tick(1.0 / 60.0)
				game._end_execution()
				check(game.state == Phase.ONLINE_WAIT, "Client must wait for the server turn barrier")
			var digest: String = games[0]._online_state_digest()
			for game in games:
				check(game._online_state_digest() == digest, "Four simulations must agree after level %d turn %d" % [level, round_index])
				game._on_online_message({"type": "turn_start", "turn": game.turn + 1})
				check(game.state == Phase.PLANNING, "Server advance must resume all clients")
	var game = games[0]
	game._on_online_message({"type": "peer_status", "player": 2, "connected": false})
	game._on_online_message({"type": "peer_status", "player": 3, "connected": false})
	game._on_online_message({"type": "peer_status", "player": 2, "connected": true})
	check(game.online_peer_lost, "One reconnect cannot hide another disconnected player")
	game._on_online_message({"type": "peer_status", "player": 3, "connected": true})
	check(not game.online_peer_lost, "All reconnects must restore room health")
	game.state = Phase.ONLINE_WAIT
	var next_turn: int = game.turn + 1
	game._on_online_message({"type": "room_state", "connected": [true, true, true, true],
		"capacity": 4, "phase": "planning", "turn": next_turn, "seed": 12345})
	check(game.state == Phase.PLANNING and game.turn == next_turn,
		"Reconnect must recover a missed turn_start from the room state")
	game.turn = 1
	game.score[3] = 2
	game._start_online_match(0, 999, 1, [0, 0, 0, 0])
	check(game.score[3] == 2, "Reconnect during first turn must not reset the match")
	game.state = Phase.GAME_OVER
	game._start_online_match(1, 999, 1, [0, 0, 0, 0])
	check(game.score[3] == 0 and game.players.size() == 4 and game.level_index == 1,
		"Rematch must reset all four slots on the host-selected level")
	game.state = Phase.REPLAY
	game._online_waiting_rematch = true
	game._start_online_match(2, 1000, 1, [0, 0, 0, 0])
	check(game.state == Phase.PLANNING and game.level_index == 2,
		"An agreed rematch must exit replay instead of stranding that participant")
	for entry in games:
		entry.queue_free()
	await process_frame
	print("Four-player online simulations: %d failures" % failures)
	quit(failures)
