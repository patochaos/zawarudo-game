extends RefCounted
class_name OnlineSession

## The online lockstep session, split out of GameManager: room create and join,
## the networked selection screens, room messages, match start, the plan relay
## and its validation, and the per-turn lockstep digest. GameManager owns one
## instance as `_online` and keeps `online_mode` and `online_player`, which the
## whole game reads. `gm` is that GameManager.

const ONLINE_CLIENT_SCRIPT := preload("res://scripts/OnlineClient.gd")
const ONLINE_LOBBY_SCRIPT := preload("res://scripts/OnlineLobby.gd")
## Legacy lockstep padding. Protocol 4 hashes a third id counter that only the
## retired kits ever advanced, so a Duelist match always reports its reset
## value. Drop it at the next protocol bump.
const LEGACY_CHARACTER_PROJECTILE_ID := 100000

var gm
var online_room: String = ""
var online_peer_connected: bool = false
var _online_connected: Array = [true, true]
## One nickname per online seat, as the room reports them. An empty entry means
## that seat shows its P1..P4 tag.
var online_names: Array = []
## True from the moment an opponent drops out of a live match until they come
## back or the match is claimed. banner_time expires; being stranded does not,
## so the way out has to stay on screen rather than flash past.
var online_peer_lost: bool = false
## Set when the room reports a desync or rejects a plan. Neither side can be
## trusted as the winner, so the only honest exit is back to the menu.
var online_match_broken: bool = false
var _online_seed: int = 0
var _online_plan_sent: bool = false
var _online_match_reported: bool = false
var _online_waiting_rematch: bool = false
var _online_client: OnlineClient
var _online_lobby: OnlineLobby
## The custom-match lineup and rules screens, run over the network once every
## seat is connected (room protocol 4).
var _online_roster: OnlineRosterLayer
var _online_setup: OnlineSetupLayer
## This machine's pending pick. The room echoes it back, but the local copy wins
## so a fast double press never snaps back to a stale echo.
var _online_pick := {"weapon": Roster.DUELIST, "level": 0, "lives": 5, "ready": false}


func _init(owner) -> void:
	gm = owner


func build() -> void:
	_online_client = ONLINE_CLIENT_SCRIPT.new()
	gm.add_child(_online_client)
	_online_client.room_ready.connect(_on_online_room_ready)
	_online_client.message_received.connect(_on_online_message)
	_online_client.status_changed.connect(_on_online_status)

	_online_lobby = ONLINE_LOBBY_SCRIPT.new()
	gm.add_child(_online_lobby)
	_online_lobby.create_requested.connect(_on_online_create)
	_online_lobby.join_requested.connect(_on_online_join)
	_online_lobby.cancel_requested.connect(_leave_online)
	_online_lobby.ui_navigated.connect(func(): gm._sfx.play("ui_move"))
	_online_lobby.ui_accepted.connect(func(): gm._sfx.play("ui_accept"))
	_online_client.room_lost.connect(_on_online_room_lost)

	_online_roster = OnlineRosterLayer.new()
	gm.add_child(_online_roster)
	_online_roster.pick_changed.connect(func(weapon: int):
		_online_pick["weapon"] = weapon
		_send_online_pick())
	_online_roster.lineup_confirmed.connect(func(_lineup: Dictionary): _open_online_setup())
	_online_roster.canceled.connect(_leave_online)
	_online_setup = OnlineSetupLayer.new()
	gm.add_child(_online_setup)
	_online_setup.vote_changed.connect(func(vote_level: int, vote_lives: int):
		_online_pick["level"] = vote_level
		_online_pick["lives"] = vote_lives
		_send_online_pick())
	_online_setup.ready_changed.connect(func(is_ready: bool):
		_online_pick["ready"] = is_ready
		_send_online_pick())
	_online_setup.canceled.connect(func(): _online_roster.open())
	for layer_node in [_online_roster, _online_setup]:
		layer_node.ui_navigated.connect(func(): gm._sfx.play("ui_move"))
		layer_node.ui_accepted.connect(func(): gm._sfx.play("ui_accept"))


## The nickname an online seat registered, or "" when it has none or the match
## is local. Local and CPU matches never carry names, so their labels stay P1..P4.
func online_nickname(player_index: int) -> String:
	if not gm.online_mode or player_index < 0 or player_index >= online_names.size():
		return ""
	return str(online_names[player_index]).strip_edges()


func _set_online_names(names: Array, seats: int) -> void:
	online_names.resize(seats)
	for i in seats:
		online_names[i] = str(names[i]).strip_edges() if i < names.size() else ""


func _on_menu_online() -> void:
	gm._reset_experiment_modes()
	gm.team_mode = false
	gm.fate_trial_mode = false
	gm.tutorial_mode = false
	if gm.offline_tuning != null:
		gm.offline_tuning.apply_standard()
	gm._menu.close()
	gm._ui.visible = false
	gm._tuning.visible = false
	gm.state = Phase.ONLINE_LOBBY
	# The lobby starts from the arena and fighter the roster screen last held,
	# then lets each side choose its own before the room opens.
	_online_lobby.open(gm._setup.level, gm.local_weapon_choices[0], str(gm._settings_store._settings.get("nickname", "")))
	gm._transition.play("ONLINE MATCH", "PRIVATE PLANS", gm.PLAYER_COLORS[1], gm.reduced_flashes)


func _on_online_create(lvl: int, weapon: int, capacity: int = 4) -> void:
	_online_lobby.set_status("CREATING PRIVATE ROOM…", false)
	_online_client.create_room(lvl, weapon, capacity, _remember_nickname())


func _on_online_join(code: String, weapon: int) -> void:
	_online_client.join_room(code, weapon, _remember_nickname())


## The lobby's nickname is saved with the other options the moment it is used
## for a room, so the next session starts with it filled in.
func _remember_nickname() -> String:
	var nick: String = _online_lobby.nickname
	if nick != str(gm._settings_store._settings.get("nickname", "")):
		gm._settings_store._on_option_changed("nickname", nick)
	return nick


func _on_online_room_ready(code: String, player_slot: int) -> void:
	online_room = code
	gm.online_player = player_slot
	_online_lobby.show_room(code, player_slot)


func _on_online_status(text: String, is_error: bool) -> void:
	if gm.state == Phase.ONLINE_LOBBY:
		_online_lobby.set_status(text, is_error)
	elif gm.online_mode:
		online_peer_connected = _online_client.is_socket_open()
		gm.banner_text = text
		gm.banner_color = Color(1.0, 0.40, 0.35) if is_error else Color(0.62, 0.85, 0.72)
		gm.banner_time = 1.8


func _leave_online() -> void:
	_online_client.disconnect_from_room()
	_reset_online_session()
	_online_lobby.close()
	gm._open_menu()


func _reset_online_session() -> void:
	if gm.state == Phase.REPLAY:
		gm._replay._finish_match_replay()
	gm.online_mode = false
	gm.online_player = -1
	online_room = ""
	online_peer_connected = false
	online_peer_lost = false
	online_match_broken = false
	_online_waiting_rematch = false
	_online_connected = [true, true]
	online_names = []
	_close_online_selection()


## The room or this seat is gone for good (host closed it, or the seat went to
## someone else). Land back on the lobby with the reason instead of retrying.
func _on_online_room_lost(reason: String) -> void:
	if online_room.is_empty() and not gm.online_mode:
		return
	_reset_online_session()
	gm._ui.visible = false
	gm.state = Phase.ONLINE_LOBBY
	_online_lobby.open(gm._setup.level, int(_online_pick["weapon"]), str(gm._settings_store._settings.get("nickname", "")))
	_online_lobby.set_status(reason, true)


func _close_online_selection() -> void:
	if _online_roster != null:
		_online_roster.close()
	if _online_setup != null:
		_online_setup.close()


func _send_online_pick() -> void:
	_online_client.send_select(int(_online_pick["weapon"]), int(_online_pick["level"]),
		int(_online_pick["lives"]), bool(_online_pick["ready"]))


## Feeds the room's view of every seat to both selection screens and opens the
## lineup screen the first time the room reaches the selection phase.
func _on_online_selection(message: Dictionary) -> void:
	var seats := int(message.get("capacity", 2))
	var room_weapons: Array = message.get("weapons", [])
	var votes: Array = message.get("level_votes", [])
	var lives: Array = message.get("lives_votes", [])
	var ready: Array = message.get("ready", [])
	var connected: Array = message.get("connected", [])
	if message.has("names"):
		_set_online_names(message["names"], seats)
	if not connected.is_empty():
		_online_connected = connected.duplicate()
	var entering: bool = gm.state != Phase.ONLINE_SELECT
	if entering:
		if gm.state == Phase.REPLAY:
			gm._replay._finish_match_replay()
		var me: int = gm.online_player
		_online_pick = {
			"weapon": int(room_weapons[me]) if me < room_weapons.size() else Roster.DUELIST,
			"level": posmod(int(votes[me]), Levels.count()) if me < votes.size() and int(votes[me]) >= 0 \
				else _online_lobby.level,
			"lives": int(lives[me]) if me < lives.size() else gm.DEFAULT_HITS_TO_WIN,
			"ready": false,
		}
		gm.online_mode = false
		_online_waiting_rematch = false
		_online_lobby.close()
		gm._ui.visible = false
		gm.state = Phase.ONLINE_SELECT
	_online_roster.configure_room(gm.online_player, seats, online_names, _online_connected,
		room_weapons, ready, entering)
	var lineup := room_weapons.duplicate()
	if gm.online_player < lineup.size():
		lineup[gm.online_player] = _online_pick["weapon"]
	_online_setup.configure_room(gm.online_player, online_names, lineup, votes, lives, ready)
	if entering:
		_online_roster.open()


func _open_online_setup() -> void:
	_online_roster.close()
	_online_setup.open_vote(int(_online_pick["level"]), int(_online_pick["lives"]),
		bool(_online_pick["ready"]))


## Someone left before or between matches; the room is waiting for a full table
## again, so show the code and seats instead of the selection screens.
func _return_to_online_room(note: String) -> void:
	_close_online_selection()
	if gm.state == Phase.REPLAY:
		gm._replay._finish_match_replay()
	gm.online_mode = false
	_online_waiting_rematch = false
	gm._ui.visible = false
	gm.state = Phase.ONLINE_LOBBY
	_online_lobby.visible = true
	_online_lobby.show_room(online_room, gm.online_player)
	_online_lobby.update_room(_online_connected, _online_connected.size(), _online_lobby.level,
		online_names)
	_online_lobby.set_status(note, true)


func _refresh_online_connections() -> void:
	online_peer_lost = false
	for i in _online_connected.size():
		if i != gm.online_player and not bool(_online_connected[i]):
			online_peer_lost = true
	online_peer_connected = not online_peer_lost


func _on_online_message(message: Dictionary) -> void:
	var kind := str(message.get("type", ""))
	match kind:
		"connected":
			online_peer_connected = true
			if not gm.online_mode:
				_online_connected.resize(int(message.get("capacity", 2)))
				_online_connected.fill(false)
			if message.has("names"):
				_set_online_names(message["names"], int(message.get("capacity", _online_connected.size())))
		"room_state":
			var connected: Array = message.get("connected", [])
			_online_connected = connected.duplicate()
			_refresh_online_connections()
			if message.has("names"):
				_set_online_names(message["names"], int(message.get("capacity", connected.size())))
			if gm.state == Phase.ONLINE_LOBBY:
				_online_lobby.update_room(connected, int(message.get("capacity", connected.size())),
					int(message.get("level", 0)), online_names)
			# Recover server transitions missed while our socket was disconnected.
			var server_phase := str(message.get("phase", "waiting"))
			var server_turn := int(message.get("turn", 1))
			if server_phase == "desync":
				_on_online_message({"type": "desync"})
			elif server_phase == "selecting":
				var selection := message.duplicate()
				selection["type"] = "selection_state"
				_on_online_selection(selection)
			elif server_phase == "planning":
				if gm.online_mode and gm.state == Phase.ONLINE_WAIT and server_turn == gm.turn + 1:
					gm._begin_planning(false)
				elif server_turn == 1 and (not gm.online_mode or \
						(_online_waiting_rematch and int(message.get("seed", 0)) != _online_seed)):
					_start_online_match(int(message.get("level", 0)),
						int(message.get("seed", 0)), server_turn, message.get("weapons", []),
						message.get("names", []), int(message.get("lives", gm.DEFAULT_HITS_TO_WIN)))
		"selection_state":
			if str(message.get("phase", "")) == "selecting":
				_on_online_selection(message)
		"peer_left":
			var left_slot := int(message.get("player", -1))
			if gm.state in [Phase.ONLINE_SELECT, Phase.GAME_OVER, Phase.REPLAY, Phase.ONLINE_LOBBY]:
				_return_to_online_room("%s LEFT · WAITING FOR A NEW PLAYER" \
					% OnlineLobby.seat_tag(left_slot, online_names))
		"room_closed":
			_online_client.disconnect_from_room()
			_on_online_room_lost("THE HOST CLOSED THE ROOM")
		"peer_status":
			var peer_slot := int(message.get("player", -1))
			var connected := bool(message.get("connected", false))
			if peer_slot >= 0 and peer_slot < _online_connected.size():
				_online_connected[peer_slot] = connected
				_refresh_online_connections()
				# A newcomer's name arrives only here: room_state went to their socket.
				if message.has("name"):
					if online_names.size() < _online_connected.size():
						_set_online_names(online_names, _online_connected.size())
					online_names[peer_slot] = str(message["name"]).strip_edges()
				if gm.state == Phase.ONLINE_LOBBY:
					_online_lobby.update_room(_online_connected, _online_connected.size(),
						_online_lobby.level, online_names)
				if gm.state == Phase.ONLINE_SELECT:
					_online_roster.seat_connected = _online_connected.duplicate()
					_online_roster.refresh_connections()
				if gm.online_mode and peer_slot != gm.online_player:
					gm.banner_text = "%s RECONNECTED" % gm.player_title(peer_slot) if connected \
						else ("%s DISCONNECTED · WAIT FOR RECONNECT OR ESC TO LEAVE" % gm.player_title(peer_slot) \
						if gm.player_count > 2 else "OPPONENT DISCONNECTED · ENTER CLAIMS THE MATCH")
					gm.banner_color = Color(0.52, 0.95, 0.70) if connected else Color(1.0, 0.45, 0.35)
					gm.banner_time = 2.0
		"match_start":
			_start_online_match(int(message.get("level", 0)),
				int(message.get("seed", 0)), int(message.get("turn", 1)),
				message.get("weapons", [gm.Weapon.KNIVES, gm.Weapon.KNIVES]),
				message.get("names", []), int(message.get("lives", gm.DEFAULT_HITS_TO_WIN)))
		"plan_ack":
			gm.banner_text = "PLAN LOCKED · WAITING FOR PLAYERS"
			gm.banner_color = gm.PLAYER_COLORS[gm.online_player].lightened(0.3)
			gm.banner_time = 1.0
		"turn_plans":
			_apply_online_turn_plans(message)
		"turn_complete_ack":
			gm.banner_text = "TURN COMPLETE · WAITING FOR PLAYERS"
			gm.banner_color = Color(0.62, 0.78, 0.70)
			gm.banner_time = 1.0
		"turn_start":
			var next_turn := int(message.get("turn", -1))
			if gm.online_mode and gm.state == Phase.ONLINE_WAIT and next_turn == gm.turn + 1:
				gm._begin_planning(false)
		"match_over":
			gm.banner_text = "MATCH VERIFIED · RESULTS READY"
			gm.banner_color = gm.PLAYER_COLORS[gm.winner].lightened(0.3) if gm.winner >= 0 else Color.WHITE
			gm.banner_time = 2.2
		"rematch_status":
			var ready: Array = message.get("ready", [])
			# Guests follow the host's arena. The host keeps its own pick: a guest
			# readying up first echoes the old arena, which must not undo a choice
			# the host has not sent yet.
			if message.has("level") and gm.online_player != 0:
				gm.rematch_level_index = posmod(int(message["level"]), Levels.count())
				gm.rematch_level_name = str(Levels.build(gm.rematch_level_index)["name"])
			gm.banner_text = "REMATCH %d / %d READY" % [ready.size(), gm.player_count]
			gm.banner_color = Color(0.86, 0.68, 1.0)
			gm.banner_time = 1.4
		"opponent_left":
			gm._finish_abandoned_match(int(message.get("winner", gm.online_player)))
		"desync":
			gm.state = Phase.ONLINE_WAIT
			online_match_broken = true
			gm.banner_text = "MATCH DESYNC DETECTED · ESC RETURNS TO THE MENU"
			gm.banner_color = Color(1.0, 0.24, 0.20)
			gm.banner_time = 999.0
		"error":
			gm.banner_text = str(message.get("message", "ONLINE ERROR"))
			gm.banner_color = Color(1.0, 0.35, 0.30)
			gm.banner_time = 2.4


## `names` carries one nickname per seat; when the message has none, the names
## learned in the lobby stay in force.
func _start_online_match(lvl: int, seed_value: int, server_turn: int,
		weapons: Array = [gm.Weapon.KNIVES, gm.Weapon.KNIVES], names: Array = [],
		lives: int = gm.DEFAULT_HITS_TO_WIN) -> void:
	if weapons.size() not in [2, 4] or gm.online_player < 0 or gm.online_player >= weapons.size():
		_online_lobby.set_status("ROOM RETURNED AN INVALID PLAYER LINEUP", true)
		return
	# A socket reconnect must never restart an already-running first turn.
	if gm.online_mode and gm.state == Phase.REPLAY and _online_waiting_rematch and seed_value != _online_seed:
		gm._replay._finish_match_replay()
	if gm.online_mode and gm.state != Phase.GAME_OVER:
		return
	# Older clients may still send retired kits. Do not silently simulate a
	# different lineup from the peer.
	for weapon in weapons:
		if int(weapon) not in Roster.ORDER:
			_online_lobby.set_status("ROOM USES UNAVAILABLE FIGHTERS; CREATE A DUELIST ROOM", true)
			return
	if server_turn != 1:
		# Live reconnects retain their local simulation. A full page reload cannot
		# safely reconstruct an in-progress match from only the current turn.
		if gm.online_mode:
			return
		_online_lobby.set_status("ROOM ALREADY HAS A MATCH IN PROGRESS", true)
		return
	gm.online_mode = true
	if gm._practice != null: gm._practice.stop()
	gm._reset_experiment_modes()
	gm.demo_match = false
	gm.fate_trial_mode = false
	gm.tutorial_mode = false
	gm.team_mode = false
	gm.player_teams.fill(-1)
	gm.player_roles.fill("HUMAN")
	# Restore every exposed property, including values changed in the sandbox.
	# The saved offline profile is kept intact for the next local match.
	if gm.offline_tuning != null:
		gm.offline_tuning.apply_standard()
	gm.planning_duration = 4.0
	gm.planning_shrink_per_round = 0.0
	gm.execution_duration = 0.75
	gm.movement_budget = 0.50
	gm.vs_ai = false
	# The room's vote; every client receives the same number, so lockstep holds.
	gm.hits_to_win = clampi(lives, 3, gm.MAX_HITS_TO_WIN)
	gm.player_weapons.fill(gm.Weapon.KNIVES)
	for i in weapons.size():
		gm.player_weapons[i] = gm._roster_weapon_or_default(int(weapons[i]))
	gm._set_player_count(weapons.size())
	_online_connected.resize(gm.player_count)
	_online_connected.fill(true)
	_set_online_names(names if not names.is_empty() else online_names, gm.player_count)
	gm._player_input._assign_pads()
	_online_seed = seed_value
	gm.rng.seed = _online_seed
	_online_plan_sent = false
	_online_match_reported = false
	_online_waiting_rematch = false
	online_peer_lost = false
	online_match_broken = false
	_online_lobby.close()
	_close_online_selection()
	gm._ui.visible = true
	gm._tuning.visible = false
	gm._load_level(lvl)
	gm.restart()
	gm._sfx.play("match_start")
	gm._begin_match_telemetry("online")
	gm._transition.play("ONLINE // ROOM %s" % online_room, "%d PLAYERS CONNECTED" % gm.player_count,
		gm.PLAYER_COLORS[gm.online_player], gm.reduced_flashes)


func _apply_online_turn_plans(message: Dictionary) -> void:
	if not gm.online_mode or gm.state != Phase.PLANNING or int(message.get("turn", -1)) != gm.turn:
		return
	var plans: Array = message.get("plans", [])
	if plans.size() != gm.player_count:
		return
	for i in gm.player_count:
		if not plans[i] is Dictionary:
			return
	for i in gm.player_count:
		var invalid_reason := _online_plan_invalid_reason(i, plans[i])
		if not invalid_reason.is_empty():
			gm.state = Phase.ONLINE_WAIT
			online_match_broken = true
			var owner := "YOUR" if i == gm.online_player else "OPPONENT"
			gm.banner_text = "%s PLAN FAILED VALIDATION · ESC RETURNS TO THE MENU" % owner
			gm.banner_color = Color(1.0, 0.24, 0.20)
			gm.banner_time = 999.0
			push_error("Online plan rejected for player %d: %s" % [i + 1, invalid_reason])
			return
	for i in gm.player_count:
		gm.players[i].plan.apply_network_dict(plans[i])
	gm._rebuild_ghost_paths()
	gm._update_facing()
	gm._begin_commit()


func _online_plan_is_legal(i: int, data: Dictionary) -> bool:
	return _online_plan_invalid_reason(i, data).is_empty()


func _online_plan_invalid_reason(i: int, data: Dictionary) -> String:
	var dirs: Array = data.get("dirs", [])
	var jumps: Array = data.get("jumps", [])
	var holds: Array = data.get("holds", [])
	var drops: Array = data.get("drops", [])
	if dirs.size() != jumps.size() or dirs.size() != holds.size() or dirs.size() != drops.size():
		return "recording arrays have different lengths"
	# The same cap the room service enforces. Both ends derive it from the
	# movement budget, so neither can accept a recording the other rejects.
	var max_recorded := mini(gm.exec_ticks(), gm.movement_tick_budget())
	if dirs.size() > max_recorded:
		return "movement has %d ticks; maximum is %d" % [dirs.size(), max_recorded]
	var shot_tick := int(data.get("shot_tick", -1))
	if shot_tick < -1 or shot_tick > dirs.size():
		return "shot tick %d is outside the recording" % shot_tick
	var attack_mode := int(data.get("attack_mode", 0))
	if attack_mode < 0 or attack_mode > 1:
		return "attack mode %d is outside 0..1" % attack_mode
	if bool(data.get("super_shot", false)) and (shot_tick < 0 or gm.super_meter[i] < 1.0):
		return "SUPER was requested without a legal charged shot"
	var lock_permille := int(data.get("lock_permille", 0))
	if lock_permille < 0 or lock_permille > 1000:
		return "lock share %d is outside 0..1000" % lock_permille
	return ""


func _report_online_match_over() -> void:
	if not gm.online_mode or _online_match_reported or gm.winner < 0:
		return
	_online_match_reported = true
	_online_client.send_match_over(gm.turn, gm.winner, _online_state_digest())


## Both browsers hash the gameplay state after each execution. The room advances
## only when the hashes match, catching platform/physics drift before it can
## silently corrupt a later turn.
func _online_state_digest() -> String:
	var parts := PackedStringArray()
	parts.append("turn:%d" % gm.turn)
	parts.append("players:%d" % gm.player_count)
	parts.append("ids:%d,%d,%d" % [
		gm._next_volley, gm._next_arrow_id, LEGACY_CHARACTER_PROJECTILE_ID,
	])
	parts.append("rng:%d" % gm.rng.state)
	for i in gm.players.size():
		var p: Player = gm.players[i]
		parts.append("scorekit%d:%d,%d" % [i, gm.score[i], gm.player_weapons[i]])
		parts.append("p%d:%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d" % [
			i,
			int(round(p.position.x * 10000.0)), int(round(p.position.y * 10000.0)),
			int(round(p.vel.x * 10000.0)), int(round(p.vel.y * 10000.0)),
			1 if p.on_ground else 0, p.air_jumps_left,
			p.drop_ticks, int(round(p.drop_from_y * 10000.0)),
			1 if p.alive else 0, p.invuln_turns,
			int(round(gm.super_meter[i] * 1000000.0)), 1 if gm.super_armed[i] else 0,
			p.plan.attack_mode,
		])
		# Legacy lockstep padding: the retired Rook's frame debt cells, units and
		# lock flag, always zero for a Duelist. Protocol 4 peers still hash these
		# fragments; drop them at the next protocol bump.
		parts.append("fd%d:0,0" % i)
		parts.append("fdl%d:0" % i)
	var ordered_arrows: Array = gm.arrows.duplicate()
	ordered_arrows.sort_custom(func(a: Knife, b: Knife): return a.network_id < b.network_id)
	for a: Knife in ordered_arrows:
		parts.append("a:" + a.lockstep_digest_fragment())
	for i in gm.platforms.size():
		var pf: Dictionary = gm.platforms[i]
		var rect: Rect2 = pf["rect"]
		parts.append("f%d:%d,%d,%d,%d,%d" % [
			i, int(pf["hp"]),
			int(round(rect.position.x * 10000.0)), int(round(rect.position.y * 10000.0)),
			int(round(rect.size.x * 10000.0)), int(round(rect.size.y * 10000.0)),
		])
	parts.append("world:%d" % gm.world_tick)
	for i in gm.hazards.size():
		parts.append("h%d:%s" % [i, gm.hazards[i].lockstep_digest_fragment()])
	parts.append("core:%d,%d,%d,%d,%d,%d,%d" % [
		1 if gm.core_announced else 0, 1 if gm.core_active else 0, gm.core_turns_left,
		gm.hitless_execution_streak,
		int(round(gm.core_position.x * 10000.0)), int(round(gm.core_position.y * 10000.0)),
		1 if gm._core_collected_this_execution else 0,
	])
	return "|".join(parts).sha256_text()
