extends SceneTree

## Run against a local Wrangler server with ZAWARUDO_API_URL=http://127.0.0.1:8787.
## Deliberately skips without the override so ordinary tests never create live rooms.
var _clients: Array[OnlineClient] = []
var _messages: Array = []
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if OS.get_environment("ZAWARUDO_API_URL").is_empty():
		print("SKIP OnlineClientIntegrationTest: set ZAWARUDO_API_URL to a local Wrangler server.")
		quit(0)
		return
	create_timer(45.0).timeout.connect(func():
		push_error("Online client integration timed out")
		quit(1))
	for slot in 4:
		var client := OnlineClient.new()
		_clients.append(client)
		_messages.append([])
		client.message_received.connect(func(message: Dictionary): _messages[slot].append(message))
		root.add_child(client)
	_clients[0].create_room(0, Roster.DUELIST, 4)
	await _wait_for(0, "room_state")
	var code := _clients[0].room_code
	for slot in range(1, 3):
		_clients[slot].join_room(code, Roster.DUELIST)
		await _wait_for(slot, "room_state")
	await create_timer(0.15).timeout
	_check(_find(0, "match_start").is_empty(), "three clients must not start a four-seat room")
	_clients[3].join_room(code, Roster.DUELIST)
	for slot in 4:
		var start: Dictionary = await _wait_for(slot, "match_start")
		_check(start.get("weapons", []).size() == 4, "all clients receive four fighters")
		_check(_clients[slot].player_slot == slot, "HTTP assigns each client a distinct slot")
	for slot in 3:
		_clients[slot].send_plan(1, _plan(slot))
		await _wait_for(slot, "plan_ack")
	_check(_find(0, "turn_plans").is_empty(), "plans remain hidden until player four submits")
	_clients[3].send_plan(1, _plan(0))
	var authoritative: Dictionary = await _wait_for(0, "turn_plans")
	_check(authoritative.get("plans", []).size() == 4, "execution includes every plan")
	for slot in range(1, 4):
		var received: Dictionary = await _wait_for(slot, "turn_plans")
		_check(received == authoritative, "every client receives identical execution plans")
	for slot in 3:
		_clients[slot].send_turn_complete(1, "a".repeat(64))
		await _wait_for(slot, "turn_complete_ack")
	_check(_find(0, "turn_start").is_empty(), "next turn waits for all four result digests")
	_clients[3].send_turn_complete(1, "a".repeat(64))
	for slot in 4:
		var next: Dictionary = await _wait_for(slot, "turn_start")
		_check(next.get("turn") == 2, "all four clients advance to turn two")
	for client in _clients:
		client.disconnect_from_room()
		client.queue_free()
	await process_frame
	if _failures == 0:
		print("Four real OnlineClient HTTP/WebSocket connections passed room, reveal and result barriers.")
	quit(1 if _failures else 0)


func _find(slot: int, type: String) -> Dictionary:
	for message: Dictionary in _messages[slot]:
		if message.get("type") == type:
			return message
	return {}


func _plan(direction: int) -> Dictionary:
	return {"dirs": [direction], "jumps": [0], "holds": [0], "drops": [0],
		"shot_tick": -1, "aim_angle": 30, "power": 0.5, "attack_mode": 0, "super_shot": false}


func _wait_for(slot: int, type: String) -> Dictionary:
	while _find(slot, type).is_empty():
		await process_frame
	return _find(slot, type)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
