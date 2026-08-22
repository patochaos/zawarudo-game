extends Node
class_name OnlineClient

## Thin Godot client for the Cloudflare room service. HTTP allocates a private
## room/token; WebSocket carries only lockstep plans and turn acknowledgements.

signal room_ready(code: String, player: int)
signal message_received(message: Dictionary)
signal status_changed(text: String, is_error: bool)

const API_URL := "https://zawarudo-rooms.patochaos.workers.dev"
const PROTOCOL_VERSION := 2
const HEARTBEAT_SECONDS := 20.0
const RECONNECT_SECONDS := 1.5

enum RequestKind { NONE, CREATE, JOIN }

var room_code: String = ""
var player_slot: int = -1
var _token: String = ""
var _http: HTTPRequest
var _request_kind: int = RequestKind.NONE
var _peer: WebSocketPeer
var _socket_was_open: bool = false
var _manual_close: bool = false
var _reconnect_at: float = 0.0
var _heartbeat_left: float = HEARTBEAT_SECONDS
var _pending_messages: Array[Dictionary] = []


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.request_completed.connect(_on_http_completed)
	add_child(_http)


func create_room(level: int, weapon: int = 0) -> void:
	if _request_kind != RequestKind.NONE:
		return
	_request_kind = RequestKind.CREATE
	status_changed.emit("CREATING PRIVATE ROOM…", false)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := _http.request(API_URL + "/rooms", headers, HTTPClient.METHOD_POST,
		JSON.stringify({"level": level, "weapon": weapon, "protocol": PROTOCOL_VERSION}))
	if err != OK:
		_request_kind = RequestKind.NONE
		status_changed.emit("COULD NOT START ROOM REQUEST", true)


func join_room(code: String, weapon: int = 0) -> void:
	if _request_kind != RequestKind.NONE:
		return
	var clean := code.strip_edges().to_upper()
	if clean.length() != 6:
		status_changed.emit("ROOM CODE MUST HAVE 6 CHARACTERS", true)
		return
	_request_kind = RequestKind.JOIN
	status_changed.emit("JOINING ROOM %s…" % clean, false)
	var err := _http.request(API_URL + "/rooms/%s/join" % clean,
		PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST,
		JSON.stringify({"weapon": weapon, "protocol": PROTOCOL_VERSION}))
	if err != OK:
		_request_kind = RequestKind.NONE
		status_changed.emit("COULD NOT START JOIN REQUEST", true)


func disconnect_from_room() -> void:
	_manual_close = true
	if _request_kind != RequestKind.NONE:
		_http.cancel_request()
	if _peer != null and _peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_peer.close(1000, "Leaving room")
	_peer = null
	room_code = ""
	_token = ""
	player_slot = -1
	_socket_was_open = false
	_request_kind = RequestKind.NONE
	_pending_messages.clear()


func send_plan(turn: int, plan: Dictionary) -> bool:
	return _send({"type": "plan", "turn": turn, "plan": plan})


func send_turn_complete(turn: int, digest: String) -> bool:
	return _send({"type": "turn_complete", "turn": turn, "digest": digest})


func send_match_over(turn: int, winner: int, digest: String) -> bool:
	return _send({"type": "match_over", "turn": turn, "winner": winner, "digest": digest})


func send_rematch(level: int) -> bool:
	return _send({"type": "rematch", "level": level})


func is_socket_open() -> bool:
	return _peer != null and _peer.get_ready_state() == WebSocketPeer.STATE_OPEN


func _process(delta: float) -> void:
	if _peer == null:
		if not _manual_close and not room_code.is_empty() and Time.get_ticks_msec() * 0.001 >= _reconnect_at:
			_connect_socket()
		return

	_peer.poll()
	var ready := _peer.get_ready_state()
	if ready == WebSocketPeer.STATE_OPEN:
		if not _socket_was_open:
			_socket_was_open = true
			_heartbeat_left = HEARTBEAT_SECONDS
			status_changed.emit("CONNECTED — WAITING FOR OPPONENT", false)
			_flush_pending_messages()
		while _peer.get_available_packet_count() > 0:
			var text := _peer.get_packet().get_string_from_utf8()
			if text == "pong":
				continue
			var decoded = JSON.parse_string(text)
			if decoded is Dictionary:
				message_received.emit(decoded)
		_heartbeat_left -= delta
		if _heartbeat_left <= 0.0:
			_peer.send_text("ping")
			_heartbeat_left = HEARTBEAT_SECONDS
	elif ready == WebSocketPeer.STATE_CLOSED:
		var was_open := _socket_was_open
		_peer = null
		_socket_was_open = false
		if not _manual_close:
			_reconnect_at = Time.get_ticks_msec() * 0.001 + RECONNECT_SECONDS
			status_changed.emit("CONNECTION LOST — RECONNECTING…" if was_open \
				else "COULD NOT CONNECT — RETRYING…", true)


func _on_http_completed(_result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:
	var kind := _request_kind
	_request_kind = RequestKind.NONE
	var decoded = JSON.parse_string(body.get_string_from_utf8())
	if response_code < 200 or response_code >= 300 or not decoded is Dictionary:
		var reason := "ROOM REQUEST FAILED (%d)" % response_code
		if decoded is Dictionary and decoded.has("error"):
			reason = str(decoded["error"]).to_upper()
		status_changed.emit(reason, true)
		return

	room_code = str(decoded.get("room", ""))
	_token = str(decoded.get("token", ""))
	player_slot = int(decoded.get("player", -1))
	if room_code.is_empty() or _token.is_empty() or player_slot < 0:
		status_changed.emit("ROOM SERVICE RETURNED INVALID DATA", true)
		return
	_manual_close = false
	room_ready.emit(room_code, player_slot)
	status_changed.emit("ROOM CREATED" if kind == RequestKind.CREATE else "ROOM JOINED", false)
	_connect_socket()


func _connect_socket() -> void:
	if room_code.is_empty() or _token.is_empty():
		return
	_peer = WebSocketPeer.new()
	_socket_was_open = false
	var socket_url := API_URL.replace("https://", "wss://").replace("http://", "ws://")
	var err := _peer.connect_to_url("%s/rooms/%s/socket?token=%s" % [
		socket_url, room_code, _token,
	])
	if err != OK:
		_peer = null
		_reconnect_at = Time.get_ticks_msec() * 0.001 + RECONNECT_SECONDS
		status_changed.emit("WEBSOCKET CONNECTION FAILED — RETRYING…", true)


func _send(payload: Dictionary) -> bool:
	if not is_socket_open():
		# Plan/result messages are idempotent on the server. Keep the latest copy
		# so a brief Wi-Fi drop cannot strand the match between turns.
		for i in range(_pending_messages.size() - 1, -1, -1):
			if _pending_messages[i].get("type") == payload.get("type") \
					and _pending_messages[i].get("turn", -1) == payload.get("turn", -1):
				_pending_messages.remove_at(i)
		_pending_messages.append(payload.duplicate(true))
		status_changed.emit("MESSAGE QUEUED — RECONNECTING…", true)
		return true
	return _peer.send_text(JSON.stringify(payload)) == OK


func _flush_pending_messages() -> void:
	if not is_socket_open() or _pending_messages.is_empty():
		return
	var queued := _pending_messages.duplicate(true)
	_pending_messages.clear()
	for payload: Dictionary in queued:
		if _peer.send_text(JSON.stringify(payload)) != OK:
			_pending_messages.append(payload)
