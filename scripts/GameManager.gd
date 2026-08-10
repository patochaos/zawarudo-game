extends Node2D

## Drives the loop:  PLANNING -> COMMITTING -> EXECUTING -> PLANNING -> ...
##
## Movement is planned by PILOTING a ghost. During planning each player drives
## their ghost with ordinary platformer controls; every tick of input is
## recorded and stamina drains as the ghost advances. Execution replays the
## recording verbatim, then coasts for whatever is left of the window.
##
## Nothing in the world has its own _physics_process. GameManager steps every
## entity explicitly, so "frozen" is the default and execution is an exact,
## deterministic number of physics ticks.

const PREVIEW_SCRIPT := preload("res://scripts/PreviewLayer.gd")
const UI_SCRIPT := preload("res://scripts/UI.gd")
const BACKDROP_SCRIPT := preload("res://scripts/Backdrop.gd")
const EFFECTS_SCRIPT := preload("res://scripts/Effects.gd")
const SFX_SCRIPT := preload("res://scripts/Sfx.gd")
const TIME_STOP_SCRIPT := preload("res://scripts/TimeStopLayer.gd")
const SUPER_FREEZE_SCRIPT := preload("res://scripts/SuperFreezeFrame.gd")
const MENU_SCRIPT := preload("res://scripts/MenuLayer.gd")
const TUNING_SCRIPT := preload("res://scripts/TuningLayer.gd")
const TEMPORAL_CORE_SCRIPT := preload("res://scripts/TemporalCore.gd")
const ONLINE_CLIENT_SCRIPT := preload("res://scripts/OnlineClient.gd")
const ONLINE_LOBBY_SCRIPT := preload("res://scripts/OnlineLobby.gd")

# Rival aristocratic palettes: antique gold versus imperial violet. Both remain
# bright enough to read over the near-black arenas and planning overlays.
const PLAYER_COLORS := [Color(0.96, 0.69, 0.18), Color(0.76, 0.30, 1.00)]

enum AimSrc { MOUSE, PAD, KEYS }

# ------------------------------------------------------------------ tuning ---

@export_group("Opponent")
## When true, Player 2 is driven by Ai.gd and its preview stays hidden — it
## cannot see your plan, so showing you its plan would be a one-way giveaway.
@export var vs_ai: bool = true
@export var ai_aim_jitter: float = 2.0        # degrees of slop on the AI's aim
@export var ai_think_min: float = 0.8         # it takes a beat before confirming
@export var ai_think_max: float = 2.2
## Microseconds of search the AI may burn per frame. Its full sweep costs tens
## of milliseconds, so it is sliced rather than done in one hitch.
@export var ai_slice_usec: int = 3000

@export_group("Match")
## Hits needed to take the match. A hit does not end the round — the victim
## respawns and the world carries on exactly where it was.
@export var hits_to_win: int = 3
@export var respawn_invuln_turns: int = 1
@export var banner_duration: float = 2.4

@export_group("Loop Timing")
@export var planning_duration: float = 5.0
@export var execution_duration: float = 0.75
@export var commit_delay: float = 0.25

@export_group("Movement")
## Seconds of piloted control per turn. The rest of the window coasts.
@export var movement_budget: float = 0.50
## Ghost piloting runs at this fraction of real time — below 1.0 for precision.
@export var pilot_time_scale: float = 0.5
@export var player_move_speed: float = 260.0
@export var player_acceleration: float = 1800.0
@export var player_air_acceleration: float = 900.0
@export var jump_impulse: float = 780.0
## Releasing the jump key mid-climb caps the rise at this fraction of the
## impulse. 1.0 disables variable jump height entirely.
@export_range(0.1, 1.0, 0.05) var jump_cut: float = 0.40
@export var gravity: float = 1400.0
@export var max_fall_speed: float = 1200.0

@export_group("Knives")
@export var arrow_speed_min: float = 300.0
@export var arrow_speed_max: float = 720.0
@export var arrow_gravity: float = 220.0
@export var charge_time: float = 1.1          # seconds to go from 0% to 100%
## On a fully wrapping arena a knife has no edge to leave through, so it is
## aged out instead. 900 ticks is 15s — twenty execution phases.
@export var arrow_max_ticks: int = 900
## One throw looses this many knives at once, fanned around the aim line.
@export var knives_per_shot: int = 2
## Total fan angle. A light throw scatters wide and slow — area denial you do
## not have to predict exactly; a full wind-up is a tight, fast pair.
@export var knife_spread_max: float = 26.0    # degrees, at 0% draw
@export var knife_spread_min: float = 4.0     # degrees, at 100% draw

@export_group("Knife Clash")
## Knives collide with each other in mid-air. Both survive, both get knocked off
## line and slowed, so a deflected pair falls in floaty arcs that nobody planned
## and everybody still has to dodge.
@export var knife_clash_enabled: bool = true
@export var knife_clash_radius: float = 13.0
## Bounce along the contact normal. 0 = they just stop separating, 1 = fully
## elastic. Low values keep the pair near the impact point.
@export_range(0.0, 1.0, 0.05) var knife_clash_restitution: float = 0.35
## Speed both knives keep after a clash. This is what makes a stray floaty:
## the same gravity now bends a much slower knife into a visible arc.
@export_range(0.1, 1.0, 0.05) var knife_clash_damping: float = 0.55
@export var knife_clash_spin: float = 9.0     # rad/sec of tumble after a clash
## Ticks before a knife may clash again, so a pair does not grind together.
@export var knife_clash_cooldown: int = 8
## A previously deflected knife should be re-energised, not damped into a dead
## object. Each prior impact restores this much damping, up to the cap.
@export_range(0.0, 0.3, 0.01) var knife_reclash_damping_bonus: float = 0.12
@export_range(0.3, 1.0, 0.05) var knife_reclash_damping_cap: float = 0.82
## Later impacts gain a small deterministic glancing angle. It looks chaotic,
## but replays identically and therefore remains honest in a planning game.
@export var knife_reclash_scatter: float = 11.0   # degrees

@export_group("Super")
## A clean opposing-knife clash grants this much meter if the owner is moving.
## At 0.075 it takes fourteen qualifying clashes to earn a super, making it a
## late-match pressure valve rather than part of every opening exchange.
@export_range(0.01, 1.0, 0.005) var super_charge_per_clash: float = 0.075
@export var super_move_speed_min: float = 80.0
@export var super_waves: int = 5
@export var super_knives_per_wave: int = 3
## Eight ticks is 0.133s at 60Hz: separate enough to read as repeated waves,
## while five waves still fit comfortably inside one 0.75s execution window.
@export var super_wave_interval_ticks: int = 8
@export var super_spread: float = 10.0
@export var super_speed_multiplier: float = 1.08

@export_group("Temporal Core")
## After this many consecutive hitless executions the location is announced.
## One further hitless execution makes the core tangible.
@export var core_hitless_turns_to_announce: int = 2
@export var core_active_turns: int = 2
@export var core_collect_radius: float = 22.0
## Movement value used by the AI. It is deliberately lower than the danger
## penalty, so the opponent contests the core but will not run through a knife.
@export var ai_core_collect_value: float = 280.0
@export var ai_core_approach_value: float = 150.0

@export_group("Aim")
## Full 360°: elevation runs from straight down to straight up, and either
## facing covers the rest. Narrow these only to deliberately restrict a build.
@export var aim_min_angle: float = -90.0
@export var aim_max_angle: float = 90.0
@export var aim_rate: float = 70.0            # degrees/sec for keyboard aiming
@export var stick_deadzone: float = 0.30
@export var trigger_threshold: float = 0.45

@export_group("Preview")
@export var trajectory_preview_time: float = 4.5

@export_group("Input")
## Which player the first connected gamepad drives. The second pad, if any,
## goes to the other player.
@export_enum("Player 1:0", "Player 2:1") var first_gamepad_to: int = 1

# ------------------------------------------------------------------- state ---

var state: int = Phase.PLANNING
var turn: int = 1
var level_index: int = 0
var level_name: String = ""
var level_wrap: String = ""
var spawns: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var score: Array[int] = [0, 0]

var banner_text: String = ""
var banner_color: Color = Color.WHITE
var banner_time: float = 0.0

var rng := RandomNumberGenerator.new()
var _ai_think: float = 0.0
var _ai_search
var _menu
var _tuning
var planning_time_left: float = 0.0
var commit_time_left: float = 0.0
var exec_tick: int = 0
var exec_ticks_total: int = 0
var winner: int = -1

var platforms: Array = []
var solid_rects: Array[Rect2] = []
var world_bounds := Rect2(-160.0, -1600.0, 1600.0, 2600.0)

## TowerFall-style screen wrap. Anything leaving a wrapping edge re-enters the
## opposite one — arrows and players alike.
var wrap_x: bool = false
var wrap_y: bool = false
const ARENA_W := Levels.ARENA_W
const ARENA_H := Levels.ARENA_H
const WRAP_TOP := Levels.WRAP_TOP
const SEAM_MARGIN := 340.0   # how far from an edge a platform gets a seam copy

var players: Array = []
var arrows: Array = []
var _next_volley: int = 1
var _next_arrow_id: int = 1

## Online mode is lockstep: this browser records only its assigned player and
## receives the rival plan after both sides confirm.
var online_mode: bool = false
var online_player: int = -1
var online_room: String = ""
var online_peer_connected: bool = false
var _online_seed: int = 0
var _online_plan_sent: bool = false
var _online_match_reported: bool = false
var _online_waiting_rematch: bool = false

var aim_source: Array[int] = [AimSrc.MOUSE, AimSrc.KEYS]
var charging: Array[bool] = [false, false]
var stamina: Array[float] = [0.0, 0.0]
## Persistent for the whole match. It only resets when the super is actually
## released (or the match restarts), not between turns or after taking a hit.
var super_meter: Array[float] = [0.0, 0.0]
## A full meter is only spent when the player explicitly toggles SUPER on
## before placing the shot. The choice persists between turns until changed or
## the burst is actually released.
var super_armed: Array[bool] = [false, false]

## A location is telegraphed for one full turn before it becomes collectible.
## Once active it lasts for `core_active_turns` executions. A same-tick touch
## grants both players the reward, avoiding an arbitrary player-order tie.
var core_spawn_points: Array[Vector2] = []
var core_position: Vector2 = Vector2.ZERO
var core_announced: bool = false
var core_active: bool = false
var core_turns_left: int = 0
var hitless_execution_streak: int = 0
var _hit_this_execution: bool = false
var _core_collected_this_execution: bool = false

# Ghost piloting state, one entry per player.
var ghost_pos: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var ghost_vel: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var ghost_ground: Array[bool] = [false, false]
## Recorded path plus the coasted tail — always exactly one full window long.
var ghost_path: Array[PackedVector2Array] = [PackedVector2Array(), PackedVector2Array()]

var _pads: Array[int] = [-1, -1]
var _pad_btn_prev: Array[Dictionary] = [{}, {}]
var _jump_prev: Array[bool] = [false, false]
var _charge_t: Array[float] = [0.0, 0.0]
var _pilot_accum: Array[float] = [0.0, 0.0]
var _prev_mouse := Vector2.ZERO

var _backdrop: Node2D
var _arena: Arena
var _arrow_layer: Node2D
var _player_layer: Node2D
var _preview: Node2D
var _temporal_core: TemporalCore
var _effects
var _sfx
var _time_stop
var _super_freeze
var _super_cutins_shown: Array[bool] = [false, false]
var _ui
var _online_client: OnlineClient
var _online_lobby: OnlineLobby


func _ready() -> void:
	_backdrop = BACKDROP_SCRIPT.new()
	add_child(_backdrop)

	_arena = Arena.new()
	add_child(_arena)

	# Previews sit behind the live entities so frozen arrows stay readable.
	_preview = PREVIEW_SCRIPT.new()
	_preview.gm = self
	add_child(_preview)

	_temporal_core = TEMPORAL_CORE_SCRIPT.new()
	_temporal_core.hide_core()
	add_child(_temporal_core)

	_arrow_layer = Node2D.new()
	add_child(_arrow_layer)

	_player_layer = Node2D.new()
	add_child(_player_layer)

	_effects = EFFECTS_SCRIPT.new()
	add_child(_effects)

	_sfx = SFX_SCRIPT.new()
	add_child(_sfx)

	_time_stop = TIME_STOP_SCRIPT.new()
	_time_stop.gm = self
	add_child(_time_stop)

	_ui = UI_SCRIPT.new()
	add_child(_ui)
	_ui.build(self)

	# This CanvasLayer sits above the HUD and keeps animating while the explicit
	# simulation clock is paused for a SUPER introduction.
	_super_freeze = SUPER_FREEZE_SCRIPT.new()
	add_child(_super_freeze)

	_menu = MENU_SCRIPT.new()
	add_child(_menu)
	_menu.start_requested.connect(_on_menu_start)
	_menu.freeplay_requested.connect(_on_menu_freeplay)
	_menu.online_requested.connect(_on_menu_online)

	_online_client = ONLINE_CLIENT_SCRIPT.new()
	add_child(_online_client)
	_online_client.room_ready.connect(_on_online_room_ready)
	_online_client.message_received.connect(_on_online_message)
	_online_client.status_changed.connect(_on_online_status)

	_online_lobby = ONLINE_LOBBY_SCRIPT.new()
	add_child(_online_lobby)
	_online_lobby.create_requested.connect(_on_online_create)
	_online_lobby.join_requested.connect(_on_online_join)
	_online_lobby.cancel_requested.connect(_leave_online)

	_tuning = TUNING_SCRIPT.new()
	add_child(_tuning)

	_load_level(0)
	_spawn_players()
	_tuning.build(self)
	_tuning.visible = false
	_assign_pads()
	Input.joy_connection_changed.connect(func(_d, _c): _assign_pads())
	_prev_mouse = get_viewport().get_mouse_position()
	_begin_planning(true)
	_open_menu()


func is_ai(i: int) -> bool:
	return not online_mode and vs_ai and i == 1


## The AI's plan is hidden for the same reason a human opponent's would be if we
## could hide it: it plans blind, so it must be planned against blind.
func hides_plan(i: int) -> bool:
	if online_mode:
		return i != online_player and state != Phase.GAME_OVER
	return is_ai(i) and state != Phase.GAME_OVER


func _open_menu() -> void:
	if _super_freeze != null:
		_super_freeze.cancel()
	state = Phase.MENU
	banner_time = 0.0
	_ui.visible = false     # the arena stays as a backdrop; the HUD would be noise
	_tuning.visible = false
	if _online_lobby != null:
		_online_lobby.close()
	_menu.open()


func _on_menu_start(ai: bool, lvl: int) -> void:
	online_mode = false
	online_player = -1
	vs_ai = ai
	_ui.visible = true
	_tuning.visible = false
	_menu.close()
	_load_level(lvl)
	restart()
	_sfx.play("title")


func _on_menu_online(lvl: int) -> void:
	_menu.close()
	_ui.visible = false
	_tuning.visible = false
	state = Phase.ONLINE_LOBBY
	_online_lobby.open(lvl)


func _on_online_create(lvl: int) -> void:
	_online_lobby.set_status("CREATING PRIVATE ROOM…", false)
	_online_client.create_room(lvl)


func _on_online_join(code: String) -> void:
	_online_client.join_room(code)


func _on_online_room_ready(code: String, player_slot: int) -> void:
	online_room = code
	online_player = player_slot
	_online_lobby.show_room(code, player_slot)


func _on_online_status(text: String, is_error: bool) -> void:
	if state == Phase.ONLINE_LOBBY:
		_online_lobby.set_status(text, is_error)
	elif online_mode:
		online_peer_connected = _online_client.is_socket_open()
		banner_text = text
		banner_color = Color(1.0, 0.40, 0.35) if is_error else Color(0.62, 0.85, 0.72)
		banner_time = 1.8


func _leave_online() -> void:
	_online_client.disconnect_from_room()
	online_mode = false
	online_player = -1
	online_room = ""
	online_peer_connected = false
	_online_lobby.close()
	_open_menu()


func _on_online_message(message: Dictionary) -> void:
	var kind := str(message.get("type", ""))
	match kind:
		"connected":
			online_peer_connected = true
		"room_state":
			var connected: Array = message.get("connected", [])
			if state == Phase.ONLINE_LOBBY and connected.size() >= 2:
				_online_lobby.set_status("BOTH PLAYERS CONNECTED — STARTING…" \
					if bool(connected[0]) and bool(connected[1]) \
					else "WAITING FOR THE OTHER PLAYER…", false)
		"peer_status":
			var peer_slot := int(message.get("player", -1))
			var connected := bool(message.get("connected", false))
			if peer_slot != online_player:
				online_peer_connected = connected
				if state == Phase.ONLINE_LOBBY:
					_online_lobby.set_status("OPPONENT CONNECTED — STARTING…" if connected \
						else "WAITING FOR PLAYER 2…", false)
				elif online_mode:
					banner_text = "OPPONENT RECONNECTED" if connected else "OPPONENT DISCONNECTED — WAITING"
					banner_color = Color(0.52, 0.95, 0.70) if connected else Color(1.0, 0.45, 0.35)
					banner_time = 2.0
		"match_start":
			_start_online_match(int(message.get("level", 0)),
				int(message.get("seed", 0)), int(message.get("turn", 1)))
		"plan_ack":
			banner_text = "PLAN LOCKED — WAITING FOR OPPONENT"
			banner_color = PLAYER_COLORS[online_player].lightened(0.3)
			banner_time = 1.0
		"turn_plans":
			_apply_online_turn_plans(message)
		"turn_complete_ack":
			banner_text = "TURN COMPLETE — WAITING FOR OPPONENT"
			banner_color = Color(0.62, 0.78, 0.70)
			banner_time = 1.0
		"turn_start":
			var next_turn := int(message.get("turn", -1))
			if online_mode and state == Phase.ONLINE_WAIT and next_turn == turn + 1:
				_begin_planning(false)
		"match_over":
			banner_text = "MATCH VERIFIED — ENTER FOR REMATCH"
			banner_color = PLAYER_COLORS[winner].lightened(0.3) if winner >= 0 else Color.WHITE
			banner_time = 2.2
		"rematch_status":
			var ready: Array = message.get("ready", [])
			banner_text = "REMATCH %d / 2 READY" % ready.size()
			banner_color = Color(0.86, 0.68, 1.0)
			banner_time = 1.4
		"desync":
			state = Phase.ONLINE_WAIT
			banner_text = "MATCH DESYNC DETECTED — RETURN TO MENU"
			banner_color = Color(1.0, 0.24, 0.20)
			banner_time = 999.0
		"error":
			banner_text = str(message.get("message", "ONLINE ERROR"))
			banner_color = Color(1.0, 0.35, 0.30)
			banner_time = 2.4


func _start_online_match(lvl: int, seed_value: int, server_turn: int) -> void:
	if server_turn != 1:
		# Live reconnects retain their local simulation. A full page reload cannot
		# safely reconstruct an in-progress match from only the current turn.
		if online_mode:
			return
		_online_lobby.set_status("ROOM ALREADY HAS A MATCH IN PROGRESS", true)
		return
	online_mode = true
	vs_ai = false
	_online_seed = seed_value
	rng.seed = _online_seed
	_online_plan_sent = false
	_online_match_reported = false
	_online_waiting_rematch = false
	_online_lobby.close()
	_ui.visible = true
	_tuning.visible = false
	_load_level(lvl)
	restart()
	_sfx.play("title")


func _apply_online_turn_plans(message: Dictionary) -> void:
	if not online_mode or state != Phase.PLANNING or int(message.get("turn", -1)) != turn:
		return
	var plans: Array = message.get("plans", [])
	if plans.size() != 2 or not plans[0] is Dictionary or not plans[1] is Dictionary:
		return
	for i in 2:
		var invalid_reason := _online_plan_invalid_reason(i, plans[i])
		if not invalid_reason.is_empty():
			state = Phase.ONLINE_WAIT
			var owner := "YOUR" if i == online_player else "OPPONENT"
			banner_text = "%s PLAN FAILED VALIDATION — MATCH STOPPED" % owner
			banner_color = Color(1.0, 0.24, 0.20)
			banner_time = 999.0
			push_error("Online plan rejected for player %d: %s" % [i + 1, invalid_reason])
			return
		players[i].plan.apply_network_dict(plans[i])
		online_peer_connected = true
	_rebuild_ghost_paths()
	_update_facing()
	_begin_commit()


func _online_plan_is_legal(i: int, data: Dictionary) -> bool:
	return _online_plan_invalid_reason(i, data).is_empty()


func _online_plan_invalid_reason(i: int, data: Dictionary) -> String:
	var dirs: Array = data.get("dirs", [])
	var jumps: Array = data.get("jumps", [])
	var holds: Array = data.get("holds", [])
	if dirs.size() != jumps.size() or dirs.size() != holds.size():
		return "recording arrays have different lengths"
	# Builds published before the integer cap could emit one extra tick when
	# stamina reached a tiny positive float residue. Accept that single legacy
	# tick so a stale browser can finish a match with a freshly loaded one.
	var max_recorded := mini(exec_ticks(), movement_tick_budget() + 1)
	if dirs.size() > max_recorded:
		return "movement has %d ticks; maximum is %d" % [dirs.size(), max_recorded]
	var shot_tick := int(data.get("shot_tick", -1))
	if shot_tick < -1 or shot_tick > dirs.size():
		return "shot tick %d is outside the recording" % shot_tick
	if bool(data.get("super_shot", false)) and (shot_tick < 0 or super_meter[i] < 1.0):
		return "SUPER was requested without a legal charged shot"
	return ""


## Free play: no turns, no freeze. One player under continuous control so the
## movement and shooting can be judged by feel, with the tuning values editable
## live. Whatever you set here is what the real match uses afterwards.
func _on_menu_freeplay(lvl: int) -> void:
	_menu.close()
	_ui.visible = false
	_tuning.visible = true
	_load_level(lvl)
	_reset_freeplay()
	state = Phase.FREEPLAY


func _reset_freeplay() -> void:
	for a in arrows:
		a.queue_free()
	arrows.clear()
	_effects.clear_all()
	_load_level(level_index)
	for i in 2:
		var p: Player = players[i]
		p.position = spawns[i]
		p.vel = Vector2.ZERO
		p.on_ground = true
		p.alive = true
		p.invuln_turns = 0
		p.plan = PlayerPlan.new()
		p.plan.power = 0.5
		super_meter[i] = 0.0
		super_armed[i] = false
		p.queue_redraw()
	charging[0] = false
	_charge_t[0] = 0.0
	_reset_temporal_core()
	banner_time = 0.0


## Wraps a point back into the arena. Vertical wrapping uses a band that starts
## below the HUD, so nothing re-enters behind a panel.
func wrap_point(p: Vector2) -> Vector2:
	if wrap_x:
		p.x = fposmod(p.x, ARENA_W)
	if wrap_y:
		p.y = WRAP_TOP + fposmod(p.y - WRAP_TOP, ARENA_H - WRAP_TOP)
	return p


## Shortest separation between two points, going around the seam if that is
## nearer. Used for aiming and scoring, not for collision.
func wrap_delta(from: Vector2, to: Vector2) -> Vector2:
	var d: Vector2 = to - from
	if wrap_x and absf(d.x) > ARENA_W * 0.5:
		d.x -= signf(d.x) * ARENA_W
	if wrap_y:
		var h: float = ARENA_H - WRAP_TOP
		if absf(d.y) > h * 0.5:
			d.y -= signf(d.y) * h
	return d


## Collision copies for a platform near a wrapping seam, so a body standing on
## the edge is standing on the same piece from either side.
## A player's hit box plus its seam copies, so an arrow overhanging an edge can
## still strike someone standing on the other side.
func body_rects(p: Player) -> Array[Rect2]:
	return _seam_copies(p.rect())


func body_rects_at(centre: Vector2) -> Array[Rect2]:
	return _seam_copies(Rect2(centre - Player.HALF, Player.SIZE))


func _seam_copies(r: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = [r]
	if wrap_x:
		if r.position.x < SEAM_MARGIN:
			out.append(Rect2(r.position + Vector2(ARENA_W, 0.0), r.size))
		if r.end.x > ARENA_W - SEAM_MARGIN:
			out.append(Rect2(r.position - Vector2(ARENA_W, 0.0), r.size))
	return out


func _rebuild_solids() -> void:
	var r: Array[Rect2] = []
	for pf in platforms:
		var copies := _seam_copies(pf["rect"])
		pf["rects"] = copies
		r.append_array(copies)
	solid_rects = r


func _load_level(index: int) -> void:
	level_index = posmod(index, Levels.count())
	var lv := Levels.build(level_index)
	level_name = lv["name"]
	level_wrap = Levels.wrap_label(lv)
	wrap_x = lv["wrap_x"]
	wrap_y = lv["wrap_y"]
	platforms = lv["platforms"]
	var sp: Array = lv["spawns"]
	spawns = [sp[0], sp[1]]
	core_spawn_points.clear()
	for point in lv.get("core_spawns", []):
		core_spawn_points.append(point)
	_rebuild_solids()
	_arena.setup(platforms)


func next_level() -> void:
	_load_level(level_index + 1)
	restart()   # also zeroes the score


func _spawn_players() -> void:
	for i in 2:
		var p := Player.new()
		p.cfg = self
		p.index = i
		p.color = PLAYER_COLORS[i]
		p.position = spawns[i]
		p.on_ground = true
		p.plan.set_aim_from_vector(Vector2(1.0 if i == 0 else -1.0, -0.45), aim_min_angle, aim_max_angle)
		p.plan.power = 0.55
		_player_layer.add_child(p)
		players.append(p)
	_update_facing()


func _assign_pads() -> void:
	var list := Input.get_connected_joypads()
	var a: int = first_gamepad_to
	var b: int = 1 - a
	_pads[a] = list[0] if list.size() > 0 else -1
	_pads[b] = list[1] if list.size() > 1 else -1


func arrow_speed_for(power: float) -> float:
	return lerpf(arrow_speed_min, arrow_speed_max, clampf(power, 0.0, 1.0))


## Total fan angle in degrees for a throw at this draw. Wide and forgiving when
## barely drawn, near-parallel at full.
func knife_spread_for(power: float) -> float:
	return lerpf(knife_spread_max, knife_spread_min, clampf(power, 0.0, 1.0))


## Angular offsets from the aim line, one per knife, symmetric about it. The
## preview, the throw and the AI all read the fan from here so they cannot drift
## apart.
func knife_offsets(power: float) -> PackedFloat32Array:
	var n: int = maxi(1, knives_per_shot)
	var out := PackedFloat32Array()
	if n == 1:
		out.append(0.0)
		return out
	var spread: float = knife_spread_for(power)
	for i in n:
		out.append((float(i) / float(n - 1) - 0.5) * spread)
	return out


func super_offsets() -> PackedFloat32Array:
	var n: int = maxi(1, super_knives_per_wave)
	var out := PackedFloat32Array()
	if n == 1:
		out.append(0.0)
		return out
	for i in n:
		out.append((float(i) / float(n - 1) - 0.5) * super_spread)
	return out


func exec_ticks() -> int:
	return maxi(1, int(round(execution_duration * float(Engine.physics_ticks_per_second))))


## Convert the movement budget to ticks once, instead of repeatedly subtracting
## tick_dt() and trusting a floating-point zero. At 0.5s / 60Hz the subtraction
## can leave a tiny positive remainder and previously recorded a 31st tick.
func movement_tick_budget() -> int:
	var hz := float(Engine.physics_ticks_per_second)
	return mini(exec_ticks(), maxi(0, int(ceil(movement_budget * hz))))


func exec_time_left() -> float:
	return float(exec_ticks_total - exec_tick) / float(Engine.physics_ticks_per_second)


func tick_dt() -> float:
	return 1.0 / float(Engine.physics_ticks_per_second)


# -------------------------------------------------------------- main loop ----

func _physics_process(delta: float) -> void:
	match state:
		Phase.MENU:
			return
		Phase.ONLINE_LOBBY:
			return
		Phase.ONLINE_WAIT:
			if banner_time > 0.0:
				banner_time = maxf(0.0, banner_time - delta)
			_ui.refresh()
			return
		Phase.FREEPLAY:
			_freeplay_tick(delta)
			_preview.queue_redraw()
			_tuning.refresh()
			if banner_time > 0.0:
				banner_time = maxf(0.0, banner_time - delta)
			return
		Phase.PLANNING:
			_poll_planning_input(delta)
			_tick_ai(delta)
			_update_facing()
			_rebuild_ghost_paths()
			planning_time_left -= delta
			if planning_time_left <= 0.0:
				planning_time_left = 0.0
				if online_mode:
					# Each client submits independently; execution only begins after
					# Cloudflare has both private plans.
					if not _online_plan_sent:
						_confirm(online_player)
				else:
					# Local modes lock whatever is on the table and fire at once.
					_begin_execution()
		Phase.COMMITTING:
			commit_time_left -= delta
			if commit_time_left <= 0.0:
				_begin_execution()
		Phase.EXECUTING:
			# Cut-ins run on ordinary frame time, but no deterministic simulation tick
			# is consumed until the portrait and chant have completely cleared.
			if _super_freeze == null or not _super_freeze.is_active():
				_sim_tick(delta)
				if _super_freeze == null or not _super_freeze.is_active():
					if online_mode and state == Phase.GAME_OVER:
						exec_tick += 1
						_report_online_match_over()
					elif state == Phase.EXECUTING:
						exec_tick += 1
						# A kill on the final tick must not be undone by ending the window.
						if exec_tick >= exec_ticks_total:
							_end_execution()
		Phase.GAME_OVER:
			pass

	if banner_time > 0.0:
		banner_time = maxf(0.0, banner_time - delta)
	_preview.queue_redraw()
	_ui.refresh()


func _sim_tick(dt: float) -> void:
	# Announce every SUPER scheduled for this tick before spawning anything. If
	# both players fire together, their cut-ins play in player order and the
	# shared simulation tick remains untouched until both are finished.
	for p in players:
		if not p.alive or not p.plan.has_shot() or not p.plan.super_shot:
			continue
		var since_launch: int = exec_tick - p.plan.shot_tick
		if since_launch == 0 and not _super_cutins_shown[p.index]:
			_super_cutins_shown[p.index] = true
			if _super_freeze != null:
				_super_freeze.play(p.index, p.color)
			_sfx.play("muda")
			return

	# Shots scheduled for this tick leave before anything moves.
	for p in players:
		if not p.alive or not p.plan.has_shot():
			continue
		if p.plan.super_shot:
			var since_launch: int = exec_tick - p.plan.shot_tick
			if since_launch >= 0 and since_launch % maxi(1, super_wave_interval_ticks) == 0:
				var wave: int = since_launch / maxi(1, super_wave_interval_ticks)
				if wave < maxi(1, super_waves):
					_spawn_super_wave(p, wave)
		elif p.plan.shot_tick == exec_tick:
			_spawn_arrow(p)

	for p in players:
		p.sim_step(dt, exec_tick)
	_check_core_collection()
	_step_arrows(dt)


## Continuous real-time control of Player 1. Player 2 is an inert dummy that
## just falls and stands — something to shoot at while judging arrow feel.
func _freeplay_tick(delta: float) -> void:
	var p: Player = players[0]

	var dir := 0
	if _held(K_P1["left"]) or _pad_left(_pads[0]):
		dir -= 1
	if _held(K_P1["right"]) or _pad_right(_pads[0]):
		dir += 1
	var jump_now: bool = _held(K_P1["jump"]) \
		or (_pads[0] >= 0 and Input.is_joy_button_pressed(_pads[0], JOY_BUTTON_A))
	var jump_edge: bool = jump_now and not _jump_prev[0]
	_jump_prev[0] = jump_now

	p.sim_free(delta, dir, jump_edge, jump_now)
	players[1].sim_free(delta, 0, false, false)

	p.plan.set_aim_from_vector(get_global_mouse_position() - p.shoulder(),
		aim_min_angle, aim_max_angle)
	_update_facing()

	# hold to draw, release to loose — immediately, no turn to wait for
	var held: bool = _held(K_P1["charge"]) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if _pads[0] >= 0 and Input.get_joy_axis(_pads[0], JOY_AXIS_TRIGGER_RIGHT) > trigger_threshold:
		held = true
	if held:
		if not charging[0]:
			charging[0] = true
			_charge_t[0] = 0.0
		else:
			_charge_t[0] = minf(_charge_t[0] + delta, charge_time)
		p.plan.power = _charge_t[0] / charge_time
	elif charging[0]:
		charging[0] = false
		_spawn_arrow(p)

	_step_arrows(delta)

	# the dummy just gets back up; nothing here is scored
	if not players[1].alive:
		players[1].position = spawns[1]
		players[1].vel = Vector2.ZERO
		players[1].alive = true
		players[1].queue_redraw()
		banner_text = "TARGET HIT"
		banner_color = PLAYER_COLORS[0]
		banner_time = 0.9


## Advances every arrow one tick and resolves what it struck. Shared by the
## turn-based loop and free play, so both behave identically.
func _step_arrows(dt: float) -> void:
	var survivors: Array = []
	var damaged: Array[int] = []
	for a in arrows:
		var res: Dictionary = a.sim_step(dt, players)
		if res["hit_player"] >= 0:
			_on_player_hit(res["hit_player"], a.position)
		if res["hit_platform"] >= 0:
			damaged.append(res["hit_platform"])
			_effects.add(Effects.Kind.SPARK, a.position, Color(0.95, 0.85, 0.6))
			_sfx.play("thud")
		if res["alive"]:
			survivors.append(a)
		else:
			a.queue_free()
	_resolve_clashes(survivors)
	arrows = survivors
	if not damaged.is_empty():
		_apply_platform_damage(damaged)


## Resolves at most one mid-air contact per knife per tick. Collision uses the
## synchronised closest approach of both swept paths, so fast head-on knives do
## not tunnel and paths that merely cross at different times do not false-hit.
func _resolve_clashes(live: Array) -> void:
	if not knife_clash_enabled or live.size() < 2:
		return
	for i in live.size() - 1:
		var a: Arrow = live[i]
		for j in range(i + 1, live.size()):
			var b: Arrow = live[j]
			if a.volley == b.volley or not a.can_clash_with(b) or not b.can_clash_with(a):
				continue
			var hit := Arrow.moving_points_closest(a.prev_pos, a.position, b.prev_pos, b.position)
			if hit[0] > knife_clash_radius:
				continue

			var normal: Vector2 = hit[1] - hit[2]
			if normal.is_zero_approx():
				normal = a.prev_pos - b.prev_pos
			if normal.is_zero_approx():
				normal = -(a.vel - b.vel).normalized()
			# A closest point at the start, with the pair separating, is residual
			# overlap from a previous tick rather than a new impact.
			if hit[3] <= 0.0001 and (a.vel - b.vel).dot(normal) >= 0.0:
				continue

			var prior_hits: int = maxi(a.clash_count, b.clash_count)
			var damping: float = minf(knife_reclash_damping_cap,
				knife_clash_damping + float(prior_hits) * knife_reclash_damping_bonus)
			var bounced := Arrow.clash_velocities(a.vel, b.vel, normal,
				knife_clash_restitution, damping)
			if prior_hits > 0:
				var chaos_seed: int = posmod(a.volley * 31 + b.volley * 17
					+ a.clash_count * 13 + b.clash_count * 7, 101)
				var chaos: float = lerpf(-knife_reclash_scatter, knife_reclash_scatter,
					float(chaos_seed) / 100.0)
				bounced[0] = bounced[0].rotated(deg_to_rad(chaos))
				bounced[1] = bounced[1].rotated(deg_to_rad(-chaos * 0.82))
			var spin_sign := -1.0 if ((a.stable_id() + b.stable_id()) & 1) == 0 else 1.0
			a.deflect(bounced[0], knife_clash_spin * spin_sign, knife_clash_cooldown,
				b.stable_id())
			b.deflect(bounced[1], -knife_clash_spin * spin_sign, knife_clash_cooldown,
				a.stable_id())
			var at: Vector2 = (hit[1] + hit[2]) * 0.5
			var clash_color := Color(1.0, 0.42, 0.16) if prior_hits > 0 else Color(1.0, 0.82, 0.30)
			_effects.add(Effects.Kind.CLASH, at, clash_color)
			_remember_aftermath("CLASH", at, clash_color)
			_sfx.play("clash")
			# Re-clashes are spectacular but easy to farm. Only the first clean
			# impact between opposing throws can advance the late-match meter.
			if prior_hits == 0 and a.shooter != b.shooter:
				_award_super_charge(a.shooter)
				_award_super_charge(b.shooter)
			break


func _award_super_charge(shooter: int) -> void:
	if shooter < 0 or shooter >= players.size() or shooter >= super_meter.size():
		return
	var p: Player = players[shooter]
	if not p.alive or p.vel.length() < super_move_speed_min or super_meter[shooter] >= 1.0:
		return
	super_meter[shooter] = minf(1.0, super_meter[shooter] + super_charge_per_clash)
	p.queue_redraw()
	if super_meter[shooter] >= 1.0:
		banner_text = "PLAYER %d — SUPER READY" % (shooter + 1)
		banner_color = PLAYER_COLORS[shooter].lightened(0.35)
		banner_time = 1.4


# ---------------------------------------------------------- temporal core ---

## Advances only at execution boundaries, so the telegraph and active lifetime
## are expressed in whole player decisions rather than wall-clock seconds.
func _advance_temporal_core() -> void:
	if _core_collected_this_execution:
		hitless_execution_streak = 0
		return

	if core_active:
		core_turns_left -= 1
		if core_turns_left <= 0:
			_clear_temporal_core()
			hitless_execution_streak = 0
		return

	if core_announced:
		if _hit_this_execution:
			_clear_temporal_core()
			hitless_execution_streak = 0
		else:
			core_announced = false
			core_active = true
			core_turns_left = maxi(1, core_active_turns)
			_sync_temporal_core_visual()
			banner_text = "TEMPORAL CORE MATERIALIZED — FULL SUPER"
			banner_color = Color(1.0, 0.84, 0.34)
			banner_time = 1.8
		return

	if _hit_this_execution:
		hitless_execution_streak = 0
		return

	hitless_execution_streak += 1
	if hitless_execution_streak >= maxi(1, core_hitless_turns_to_announce):
		core_position = _choose_core_spawn()
		core_announced = true
		_sync_temporal_core_visual()
		banner_text = "TEMPORAL CORE INCOMING — NEXT TURN"
		banner_color = Color(0.86, 0.68, 1.0)
		banner_time = 1.8


## Picks the authored socket with the fairest current travel distance. A small
## random term stops a perfectly symmetrical opening from repeating forever.
func _choose_core_spawn() -> Vector2:
	if core_spawn_points.is_empty():
		return Vector2(ARENA_W * 0.5, 420.0)
	if players.size() < 2:
		return core_spawn_points[0]
	var best: Vector2 = core_spawn_points[0]
	var best_cost := INF
	for point in core_spawn_points:
		var d0: float = wrap_delta(players[0].position, point).length()
		var d1: float = wrap_delta(players[1].position, point).length()
		var too_close: float = maxf(0.0, 120.0 - minf(d0, d1)) * 2.0
		var cost: float = absf(d0 - d1) + too_close + rng.randf() * 18.0
		if cost < best_cost:
			best_cost = cost
			best = point
	return best


func _check_core_collection() -> void:
	if not core_active:
		return
	var collectors: Array[int] = []
	for i in players.size():
		var p: Player = players[i]
		if not p.alive or super_meter[i] >= 1.0:
			continue
		if _body_touches_core(p.position):
			collectors.append(i)
	if collectors.is_empty():
		return

	for i in collectors:
		super_meter[i] = 1.0
		super_armed[i] = false
		players[i].queue_redraw()
	_core_collected_this_execution = true
	core_active = false
	core_announced = false
	core_turns_left = 0
	hitless_execution_streak = 0
	_sync_temporal_core_visual()
	if _effects != null:
		_effects.add(Effects.Kind.CLASH, core_position, Color(1.0, 0.88, 0.36))
	if _sfx != null:
		_sfx.play("clash")
	if collectors.size() > 1:
		banner_text = "BOTH PLAYERS — SUPER READY"
		banner_color = Color(1.0, 0.90, 0.48)
	else:
		banner_text = "PLAYER %d CLAIMED THE CORE — SUPER READY" % (collectors[0] + 1)
		banner_color = PLAYER_COLORS[collectors[0]].lightened(0.35)
	banner_time = 1.8


func _body_touches_core(at: Vector2) -> bool:
	var d: Vector2 = wrap_delta(at, core_position)
	return absf(d.x) <= Player.HALF.x + core_collect_radius \
		and absf(d.y) <= Player.HALF.y + core_collect_radius


func path_touches_core(path: PackedVector2Array) -> bool:
	for point in path:
		if _body_touches_core(point):
			return true
	return false


func _clear_temporal_core() -> void:
	core_announced = false
	core_active = false
	core_turns_left = 0
	_sync_temporal_core_visual()


func _reset_temporal_core() -> void:
	_clear_temporal_core()
	core_position = Vector2.ZERO
	hitless_execution_streak = 0
	_hit_this_execution = false
	_core_collected_this_execution = false


func _sync_temporal_core_visual() -> void:
	if _temporal_core == null:
		return
	if core_active:
		_temporal_core.activate(core_position)
	elif core_announced:
		_temporal_core.show_announcement(core_position)
	else:
		_temporal_core.hide_core()


## A hit costs a point and takes the victim off the board for the rest of the
## window. It does NOT reset anything else: arrows keep flying, platform damage
## stands, the other player keeps their position and velocity.
func _on_player_hit(victim_idx: int, at: Vector2) -> void:
	var victim: Player = players[victim_idx]
	if not victim.alive:
		return
	var scorer: int = 1 - victim_idx
	victim.alive = false
	victim.queue_redraw()
	_effects.add(Effects.Kind.KILL, at, victim.color)
	_remember_aftermath("HIT", at, victim.color.lightened(0.35))
	_sfx.play("hit")
	if state == Phase.FREEPLAY:
		return          # the sandbox keeps no score and never ends
	_hit_this_execution = true
	score[scorer] += 1

	if score[scorer] >= hits_to_win:
		state = Phase.GAME_OVER
		winner = scorer
		banner_text = "PLAYER %d WINS THE MATCH" % (scorer + 1)
		banner_color = PLAYER_COLORS[scorer]
	else:
		banner_text = "PLAYER %d HIT     %d — %d" % [victim_idx + 1, score[0], score[1]]
		banner_color = PLAYER_COLORS[scorer]
	banner_time = banner_duration


## Indices are collected first and applied in one sweep, so removals cannot
## invalidate an index still waiting to be used.
func _apply_platform_damage(idxs: Array[int]) -> void:
	for idx in idxs:
		var pf: Dictionary = platforms[idx]
		if pf["hp"] > 0:
			pf["hp"] -= 1
	var kept: Array = []
	for pf in platforms:
		if pf["hp"] != 0:
			kept.append(pf)
		else:
			var r: Rect2 = pf["rect"]
			_effects.add(Effects.Kind.SHATTER, r.position + r.size * 0.5, Color(0.85, 0.55, 0.42))
			_remember_aftermath("BROKEN", r.position + r.size * 0.5, Color(0.95, 0.65, 0.42))
			_sfx.play("break")
	platforms = kept
	_rebuild_solids()
	_arena.setup(platforms)


# ------------------------------------------------------------ phase changes --

func _begin_planning(first: bool) -> void:
	if _super_freeze != null:
		_super_freeze.cancel()
	state = Phase.PLANNING
	planning_time_left = planning_duration
	_online_plan_sent = false
	_online_match_reported = false
	if not first:
		turn += 1
	for i in 2:
		charging[i] = false
		_charge_t[i] = 0.0
		if not players[i].alive:
			_respawn(i)
		players[i].plan.start_new_turn()
		_reset_pilot(i)
	_update_facing()
	_rebuild_ghost_paths()
	if _time_stop != null:
		_time_stop.phase_changed(Phase.PLANNING)
	if not first and _sfx != null:
		_sfx.play("freeze")
	if not first and _effects != null and _effects.has_method("reveal_aftermath"):
		_effects.reveal_aftermath()

	# The AI starts thinking now and confirms after a beat, so the human is not
	# stared at by an instantly-READY opponent.
	_ai_search = null
	if is_ai(1) and players[1].alive:
		_ai_search = Ai.new()
		_ai_search.begin(self, 1, 0)
		_ai_think = rng.randf_range(ai_think_min, ai_think_max)


## The search runs in slices so it never costs a visible frame.
func _tick_ai(delta: float) -> void:
	if not is_ai(1) or players[1].plan.confirmed or not players[1].alive:
		return
	if _ai_search != null and not _ai_search.done:
		_ai_search.step(ai_slice_usec)
		if _ai_search.done:
			_ai_search.apply()
			_rebuild_ghost_paths()
		return
	_ai_think -= delta
	if _ai_think <= 0.0:
		_confirm(1)


func _begin_commit() -> void:
	state = Phase.COMMITTING
	commit_time_left = commit_delay


func _begin_execution() -> void:
	# Safety net: if the window opens before the sliced search finished (very
	# short planning phases), finish it in one go rather than shipping no plan.
	if _ai_search != null and not _ai_search.done:
		_ai_search.finish()
		_ai_search.apply()
		# apply() adds recorded ticks, so the cached ghost is now stale — and
		# the shot origin is read from it.
		_rebuild_ghost_paths()

	# A charge still being held when the window opens counts as released.
	for i in 2:
		if charging[i]:
			_release_charge(i)

	state = Phase.EXECUTING
	_super_cutins_shown.fill(false)
	exec_tick = 0
	exec_ticks_total = exec_ticks()
	_hit_this_execution = false
	_core_collected_this_execution = false
	if _time_stop != null:
		_time_stop.phase_changed(Phase.EXECUTING)
	if _sfx != null:
		_sfx.play("resume")


func _remember_aftermath(label: String, at: Vector2, col: Color) -> void:
	if state == Phase.EXECUTING and _effects != null and _effects.has_method("remember"):
		_effects.remember(label, at, col)


func _end_execution() -> void:
	# A shot placed at the very end of the window leaves as it closes.
	for p in players:
		if p.alive and p.plan.has_shot() and not p.plan.super_shot \
				and p.plan.shot_tick >= exec_ticks_total:
			_spawn_arrow(p)
	for p in players:
		if p.invuln_turns > 0:
			p.invuln_turns -= 1
			p.queue_redraw()
	_advance_temporal_core()
	# Everything keeps its position / velocity — nothing is cleared.
	if online_mode:
		state = Phase.ONLINE_WAIT
		if not _online_client.send_turn_complete(turn, _online_state_digest()):
			banner_text = "TURN SAVED LOCALLY — RECONNECTING TO OPPONENT"
			banner_color = Color(1.0, 0.45, 0.35)
			banner_time = 2.0
	else:
		_begin_planning(false)


func _respawn(i: int) -> void:
	var p: Player = players[i]
	p.position = spawns[i]
	p.vel = Vector2.ZERO
	p.on_ground = true
	p.alive = true
	p.invuln_turns = respawn_invuln_turns
	p.queue_redraw()


## One throw looses the whole fan from the same point at the same tick — the
## spread is the shot, not a sequence of shots.
func _spawn_arrow(p: Player) -> void:
	var origin: Vector2 = p.muzzle()
	var speed: float = arrow_speed_for(p.plan.power)
	var aim: Vector2 = p.aim_dir()
	var volley: int = _next_volley
	_next_volley += 1
	for off in knife_offsets(p.plan.power):
		var a := Arrow.new()
		a.cfg = self
		a.shooter = p.index
		a.volley = volley
		a.network_id = _next_arrow_id
		_next_arrow_id += 1
		a.color = p.color
		a.position = origin
		a.vel = aim.rotated(deg_to_rad(off)) * speed
		a.rotation = a.vel.angle()
		_arrow_layer.add_child(a)
		arrows.append(a)
	_sfx.play("shoot")


## Five consecutive waves form one logical volley. Sharing its id keeps the
## sequence from self-clashing; opposing knives can still break it apart.
func _spawn_super_wave(p: Player, wave: int) -> void:
	if p.plan.super_volley < 0:
		p.plan.super_volley = _next_volley
		_next_volley += 1
	if wave == 0:
		super_meter[p.index] = 0.0
		super_armed[p.index] = false
		p.queue_redraw()
		_effects.add(Effects.Kind.CLASH, p.shoulder(), Color(1.0, 0.92, 0.42))
		banner_text = "PLAYER %d — SUPER" % (p.index + 1)
		banner_color = PLAYER_COLORS[p.index].lightened(0.35)
		banner_time = 0.9

	var aim: Vector2 = p.aim_dir()
	var speed: float = arrow_speed_max * super_speed_multiplier
	# Every wave follows the same narrow lane. Timing, rather than changing
	# spread or centre angle, is the identity of this SUPER.
	var origin: Vector2 = p.shoulder() + aim * 22.0
	for off in super_offsets():
		var dir: Vector2 = aim.rotated(deg_to_rad(off))
		var a := Arrow.new()
		a.cfg = self
		a.shooter = p.index
		a.volley = p.plan.super_volley
		a.network_id = _next_arrow_id
		_next_arrow_id += 1
		a.color = p.color.lightened(0.22)
		a.position = origin
		a.vel = dir * speed
		a.rotation = a.vel.angle()
		_arrow_layer.add_child(a)
		arrows.append(a)
	_sfx.play("shoot")


## Facing follows the bow, not the opponent — with free aim that is what reads.
func _update_facing() -> void:
	for p in players:
		var f: int = p.plan.aim_side()
		if p.facing != f:
			p.facing = f
			p.queue_redraw()


func restart() -> void:
	if _super_freeze != null:
		_super_freeze.cancel()
	if online_mode:
		rng.seed = _online_seed
	for a in arrows:
		a.queue_free()
	arrows.clear()
	_next_volley = 1
	_next_arrow_id = 1
	_effects.clear_all()
	_load_level(level_index)
	for i in 2:
		var p: Player = players[i]
		p.position = spawns[i]
		p.vel = Vector2.ZERO
		p.on_ground = true
		p.alive = true
		p.invuln_turns = 0
		p.plan = PlayerPlan.new()
		p.plan.set_aim_from_vector(Vector2(1.0 if i == 0 else -1.0, -0.45), aim_min_angle, aim_max_angle)
		p.plan.power = 0.55
		p.queue_redraw()
	turn = 1
	winner = -1
	score[0] = 0
	score[1] = 0
	super_meter[0] = 0.0
	super_meter[1] = 0.0
	super_armed[0] = false
	super_armed[1] = false
	_reset_temporal_core()
	banner_time = 0.0
	_begin_planning(true)


# ------------------------------------------------------------ ghost piloting --

func _reset_pilot(i: int) -> void:
	var p: Player = players[i]
	p.plan.clear_path()
	p.plan.shot_tick = -1
	p.plan.super_shot = false
	p.plan.super_volley = -1
	ghost_pos[i] = p.position
	ghost_vel[i] = p.vel
	ghost_ground[i] = p.on_ground
	stamina[i] = movement_budget
	_pilot_accum[i] = 0.0
	charging[i] = false
	_charge_t[i] = 0.0


## Records exactly one tick of piloted input onto the ghost.
func _pilot_step(i: int, dir: int, jump: bool, hold: bool) -> bool:
	var pl: PlayerPlan = players[i].plan
	if pl.recorded_ticks() >= movement_tick_budget() or stamina[i] <= 0.0:
		return false
	var jumped: bool = jump and ghost_ground[i]
	if jumped:
		ghost_vel[i].y = -jump_impulse
		ghost_ground[i] = false
	pl.record(dir, jumped, hold or jumped)
	var st := Player.step_state(ghost_pos[i], ghost_vel[i], ghost_ground[i], dir,
		hold or jumped, tick_dt(), self)
	ghost_pos[i] = st[0]
	ghost_vel[i] = st[1]
	ghost_ground[i] = st[2]
	stamina[i] = maxf(0.0, stamina[i] - tick_dt())
	return true


## Recorded path + the coasted remainder, so the ghost always shows the true
## end of the window rather than just where the stamina ran out.
func _rebuild_ghost_paths() -> void:
	for i in 2:
		var p: Player = players[i]
		var pl: PlayerPlan = p.plan
		var path := PackedVector2Array()
		# replay the recording from the live body state
		var pos: Vector2 = p.position
		var vel: Vector2 = p.vel
		var og: bool = p.on_ground
		path.append(pos)
		for t in pl.recorded_ticks():
			if pl.jump_at(t) and og:
				vel.y = -jump_impulse
				og = false
			var st := Player.step_state(pos, vel, og, pl.dir_at(t), pl.hold_at(t), tick_dt(), self)
			pos = st[0]
			vel = st[1]
			og = st[2]
			path.append(pos)
		# coast whatever is left of the window
		var tail := PredictionSystem.coast(pos, vel, og, exec_ticks() - pl.recorded_ticks(), self)
		path.append_array(tail["path"])
		ghost_path[i] = path


## Where the ghost currently stands — the point a shot would be loosed from.
func pilot_tick(i: int) -> int:
	var pl: PlayerPlan = players[i].plan
	return pl.shot_tick if pl.has_shot() else pl.recorded_ticks()


func shot_origin(i: int) -> Vector2:
	var path: PackedVector2Array = ghost_path[i]
	if path.is_empty():
		return players[i].position
	return path[clampi(pilot_tick(i), 0, path.size() - 1)]


func ghost_end(i: int) -> Vector2:
	var path: PackedVector2Array = ghost_path[i]
	return path[path.size() - 1] if not path.is_empty() else players[i].position


# ------------------------------------------------------------------- input ---
#
# Raw key handling keeps the project free of an input-map file. Rebind by
# editing the keycodes below.
#
#   Move  : held, drives the ghost in real time (stamina drains)
#   Jump  : press, inserts a jump impulse at the ghost's current tick
#   Aim   : mouse (P1) / , . keys (P2) / right stick
#   Power : hold to charge — the ghost FREEZES while charging — release to fire
#           from wherever the ghost is standing
#   Super : toggles whether a full meter upgrades the next placed shot
#   Rollback   : un-fires the shot and drops the confirmation, keeps the path
#   Reset path : throws the recorded movement away and refills stamina

const K_P1 := {
	"left": [KEY_A], "right": [KEY_D], "jump": [KEY_W], "wait": [KEY_S],
	"charge": [KEY_SPACE], "rollback": [KEY_R], "reset": [KEY_F],
	"super": [KEY_T],
	"aim_up": [KEY_Q], "aim_down": [KEY_E],
}
const K_P2 := {
	"left": [KEY_LEFT], "right": [KEY_RIGHT], "jump": [KEY_UP], "wait": [KEY_DOWN],
	"charge": [KEY_ENTER, KEY_KP_ENTER], "rollback": [KEY_BACKSPACE], "reset": [KEY_SLASH],
	"super": [KEY_P],
	"aim_up": [KEY_PERIOD, KEY_KP_6], "aim_down": [KEY_COMMA, KEY_KP_4],
}


func _is_locally_controlled(i: int) -> bool:
	return i == online_player if online_mode else not is_ai(i)


func _input_map_for(i: int) -> Dictionary:
	# In an online room both people get the natural P1 bindings on their own
	# machine, regardless of whether the server assigned them slot 0 or slot 1.
	return K_P1 if online_mode else (K_P1 if i == 0 else K_P2)


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		_rollback(online_player if online_mode else 0)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return

	if state == Phase.MENU:
		_menu.handle_key(k.keycode)
		return
	if state == Phase.ONLINE_LOBBY:
		_online_lobby.handle_key(k.keycode)
		return

	if state == Phase.FREEPLAY:
		match k.keycode:
			KEY_ESCAPE:
				_open_menu()
			KEY_R:
				_reset_freeplay()
			KEY_M:
				_sfx.toggle_mute()
			KEY_F10:
				_load_level(level_index + 1)
				_reset_freeplay()
			_:
				_tuning.handle_key(k.keycode, k.shift_pressed)
		return

	if online_mode:
		match k.keycode:
			KEY_ESCAPE:
				_leave_online()
				return
			KEY_M:
				var online_muted: bool = _sfx.toggle_mute()
				banner_text = "SOUND OFF" if online_muted else "SOUND ON"
				banner_color = Color(0.62, 0.68, 0.78)
				banner_time = 1.1
				return
			KEY_H:
				_ui.toggle_help()
				return

		if state == Phase.GAME_OVER:
			if k.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_R] and not _online_waiting_rematch:
				_online_waiting_rematch = _online_client.send_rematch()
				banner_text = "REMATCH REQUESTED — WAITING FOR OPPONENT"
				banner_color = Color(0.86, 0.68, 1.0)
				banner_time = 2.0
			return

		if k.keycode == KEY_SHIFT:
			_confirm(online_player)
			return
		if state != Phase.PLANNING:
			return
		var online_map := K_P1
		if k.keycode in online_map["super"]:
			_toggle_super(online_player)
		elif k.keycode in online_map["rollback"]:
			_rollback(online_player)
		elif k.keycode in online_map["reset"]:
			_reset_path(online_player)
		return

	match k.keycode:
		KEY_ESCAPE:
			_open_menu()
			return
		KEY_F1:
			planning_duration = 5.0
			_clamp_planning_timer()
			return
		KEY_F2:
			planning_duration = 8.0
			_clamp_planning_timer()
			return
		KEY_F3:
			planning_duration = 10.0
			_clamp_planning_timer()
			return
		KEY_F5:
			execution_duration = 0.40
			return
		KEY_F6:
			execution_duration = 0.75
			return
		KEY_F7:
			execution_duration = 1.20
			return
		KEY_F8:
			# Playtest shortcut: waiting for clashes or a Core every time would make
			# iteration unnecessarily slow. It fills the meter but does not arm it.
			var who: int = 1 if k.shift_pressed else 0
			super_meter[who] = 1.0
			super_armed[who] = false
			players[who].queue_redraw()
			banner_text = "PLAYER %d — SUPER READY (TEST)" % (who + 1)
			banner_color = PLAYER_COLORS[who].lightened(0.35)
			banner_time = 1.4
			return
		KEY_F9:
			restart()
			return
		KEY_F10:
			next_level()
			return
		KEY_M:
			var m: bool = _sfx.toggle_mute()
			banner_text = "SOUND OFF" if m else "SOUND ON"
			banner_color = Color(0.62, 0.68, 0.78)
			banner_time = 1.1
			return
		KEY_H:
			_ui.toggle_help()
			return

	if state == Phase.GAME_OVER:
		if k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER or k.keycode == KEY_R:
			restart()
		return

	# Confirm uses left/right SHIFT, distinguished by key location.
	if k.keycode == KEY_SHIFT:
		var who: int = 0 if k.location == KEY_LOCATION_LEFT else 1
		if not is_ai(who):
			_confirm(who)
		return

	if state != Phase.PLANNING:
		return

	for i in 2:
		if is_ai(i):
			continue
		var map: Dictionary = K_P1 if i == 0 else K_P2
		if k.keycode in map["super"]:
			_toggle_super(i)
		elif k.keycode in map["rollback"]:
			_rollback(i)
		elif k.keycode in map["reset"]:
			_reset_path(i)


func _toggle_super(i: int) -> void:
	if state != Phase.PLANNING or i < 0 or i >= players.size() or is_ai(i):
		return
	var p: Player = players[i]
	if not p.alive or p.plan.confirmed or p.plan.has_shot() or super_meter[i] < 1.0:
		return
	super_armed[i] = not super_armed[i]
	p.queue_redraw()
	banner_text = "PLAYER %d — SUPER %s" % [i + 1, "ARMED" if super_armed[i] else "STANDBY"]
	banner_color = Color(1.0, 0.94, 0.58) if super_armed[i] \
		else PLAYER_COLORS[i].lightened(0.25)
	banner_time = 1.1


## Un-fires the shot and drops the confirmation. The piloted path survives, so
## a player can re-aim without throwing away a movement they liked.
func _rollback(i: int) -> void:
	if state != Phase.PLANNING:
		return
	var p: Player = players[i]
	if not p.alive:
		return
	p.plan.confirmed = false
	p.plan.shot_tick = -1
	p.plan.super_shot = false
	p.plan.super_volley = -1
	charging[i] = false
	_charge_t[i] = 0.0


## Throws the movement recording away and refills stamina. The shot goes with
## it, because its tick indexes into the path that just disappeared.
func _reset_path(i: int) -> void:
	if state != Phase.PLANNING or not players[i].alive:
		return
	players[i].plan.confirmed = false
	_reset_pilot(i)


func _confirm(i: int) -> void:
	if state != Phase.PLANNING:
		return
	if online_mode and (i != online_player or _online_plan_sent):
		return
	var p: Player = players[i]
	if not p.alive:
		return
	if charging[i]:
		_release_charge(i)
	p.plan.confirmed = true
	if online_mode:
		_online_plan_sent = _online_client.send_plan(turn, p.plan.to_network_dict())
		if _online_plan_sent:
			banner_text = "PLAN LOCKED — WAITING FOR OPPONENT"
			banner_color = PLAYER_COLORS[i].lightened(0.3)
			banner_time = 1.2
		return
	_check_both_confirmed()


func _check_both_confirmed() -> void:
	for p in players:
		if p.alive and not p.plan.confirmed:
			return
	_begin_commit()


# ---------------------------------------------------------- polled planning --

func _poll_planning_input(delta: float) -> void:
	var mouse := get_viewport().get_mouse_position()
	var mouse_moved: bool = mouse.distance_to(_prev_mouse) > 0.5
	_prev_mouse = mouse

	for i in 2:
		var p: Player = players[i]
		if not p.alive or not _is_locally_controlled(i):
			continue
		_poll_pad_meta(i)
		if p.plan.confirmed:
			continue
		# One shot per turn: firing freezes aim and power until a rollback.
		if not p.plan.has_shot():
			_poll_aim(i, delta, mouse_moved)
			_poll_charge(i, delta)
		_poll_pilot(i, delta)


## Confirm / rollback work even while confirmed, so they are polled separately.
func _poll_pad_meta(i: int) -> void:
	var pad: int = _pads[i]
	if pad < 0:
		return
	# Every edge must be sampled each frame, so no short-circuiting here.
	var start := _pad_edge(i, pad, JOY_BUTTON_START)
	var back := _pad_edge(i, pad, JOY_BUTTON_BACK)
	var b := _pad_edge(i, pad, JOY_BUTTON_B)
	var x := _pad_edge(i, pad, JOY_BUTTON_X)
	var y := _pad_edge(i, pad, JOY_BUTTON_Y)
	if start:
		_confirm(i)
	if back or b:
		_rollback(i)
	if x:
		_reset_path(i)
	if y:
		_toggle_super(i)


func _pad_edge(i: int, pad: int, btn: int) -> bool:
	var now: bool = Input.is_joy_button_pressed(pad, btn)
	var was: bool = _pad_btn_prev[i].get(btn, false)
	_pad_btn_prev[i][btn] = now
	return now and not was


## Free platformer control of the ghost, metered by stamina. Time only advances
## while the player is actually driving (or is airborne and committed to the
## arc), and never while a shot is being charged.
func _poll_pilot(i: int, delta: float) -> void:
	var map: Dictionary = _input_map_for(i)
	var pad: int = _pads[i]

	var dir := 0
	if _held(map["left"]) or _pad_left(pad):
		dir -= 1
	if _held(map["right"]) or _pad_right(pad):
		dir += 1

	var jump_now: bool = _held(map["jump"]) or (pad >= 0 and Input.is_joy_button_pressed(pad, JOY_BUTTON_A))
	var jump_edge: bool = jump_now and not _jump_prev[i]
	_jump_prev[i] = jump_now

	var wait_held: bool = _held(map["wait"]) or _pad_down(pad)

	if charging[i] or stamina[i] <= 0.0:
		_pilot_accum[i] = 0.0
		return

	# A jump press must land on a tick even if nothing else is being held.
	if jump_edge and ghost_ground[i]:
		_pilot_step(i, dir, true, true)
		_pilot_accum[i] = 0.0
		return

	# ONE time rule, on the ground and in the air alike: the ghost advances only
	# while you are holding a pilot input. Airborne used to advance on its own,
	# which meant the controls silently changed the moment you left the ground —
	# and since a full jump outlasts the window, that was every jump.
	var advancing: bool = dir != 0 or jump_now or wait_held
	if not advancing:
		_pilot_accum[i] = 0.0
		return

	_pilot_accum[i] += delta * pilot_time_scale
	while _pilot_accum[i] >= tick_dt():
		_pilot_accum[i] -= tick_dt()
		if not _pilot_step(i, dir, false, jump_now):
			_pilot_accum[i] = 0.0
			break


func _held(codes: Array) -> bool:
	for c in codes:
		if Input.is_key_pressed(c):
			return true
	return false


func _pad_left(pad: int) -> bool:
	if pad < 0:
		return false
	return Input.get_joy_axis(pad, JOY_AXIS_LEFT_X) < -0.4 \
		or Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_LEFT)


func _pad_right(pad: int) -> bool:
	if pad < 0:
		return false
	return Input.get_joy_axis(pad, JOY_AXIS_LEFT_X) > 0.4 \
		or Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_RIGHT)


## "Let time run without steering" — hold to walk the ghost forward through a
## fall, or to line a shot up at a precise moment.
func _pad_down(pad: int) -> bool:
	if pad < 0:
		return false
	return Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y) > 0.4 \
		or Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_DOWN)


func _poll_aim(i: int, delta: float, mouse_moved: bool) -> void:
	var p: Player = players[i]
	var map: Dictionary = _input_map_for(i)
	var pad: int = _pads[i]

	# --- pick the active aim source from whatever the player touched last ---
	var stick := Vector2.ZERO
	if pad >= 0:
		stick = Vector2(Input.get_joy_axis(pad, JOY_AXIS_RIGHT_X), Input.get_joy_axis(pad, JOY_AXIS_RIGHT_Y))
		if stick.length() > stick_deadzone:
			aim_source[i] = AimSrc.PAD
	var key_dir := 0.0
	if _held(map["aim_up"]):
		key_dir += 1.0
	if _held(map["aim_down"]):
		key_dir -= 1.0
	if key_dir != 0.0:
		aim_source[i] = AimSrc.KEYS
	elif i == (online_player if online_mode else 0) and mouse_moved:
		aim_source[i] = AimSrc.MOUSE

	# --- apply it ---
	match aim_source[i]:
		AimSrc.PAD:
			if stick.length() > stick_deadzone:
				p.plan.set_aim_from_vector(stick, aim_min_angle, aim_max_angle)
		AimSrc.MOUSE:
			# Measured from the ghost, because that is where the shot leaves from.
			p.plan.set_aim_from_vector(get_global_mouse_position() - Player.shoulder_at(shot_origin(i)),
				aim_min_angle, aim_max_angle)
		AimSrc.KEYS:
			if key_dir != 0.0:
				p.plan.set_elevation(p.plan.elevation() + key_dir * aim_rate * delta,
					aim_min_angle, aim_max_angle)


func _poll_charge(i: int, delta: float) -> void:
	var p: Player = players[i]
	var map: Dictionary = _input_map_for(i)
	var pad: int = _pads[i]

	var held: bool = _held(map["charge"])
	if i == (online_player if online_mode else 0) and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		held = true
	if pad >= 0 and Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_RIGHT) > trigger_threshold:
		held = true

	if held:
		if not charging[i]:
			charging[i] = true
			_charge_t[i] = 0.0
		else:
			_charge_t[i] = minf(_charge_t[i] + delta, charge_time)
		p.plan.power = _charge_t[i] / charge_time
	elif charging[i]:
		_release_charge(i)


## The arrow is pinned to the tick the ghost had reached, so a shot taken
## mid-path leaves from that point and the player can keep piloting afterwards.
func _release_charge(i: int) -> void:
	charging[i] = false
	var pl: PlayerPlan = players[i].plan
	pl.super_shot = super_meter[i] >= 1.0 and super_armed[i]
	pl.super_volley = -1
	pl.shot_tick = pl.recorded_ticks()
	if pl.super_shot:
		# Leave enough execution ticks for all waves. A very late placement moves
		# to the latest viable point on the recorded path, visible in the preview.
		var runway: int = maxi(0, (maxi(1, super_waves) - 1) * maxi(1, super_wave_interval_ticks))
		pl.shot_tick = mini(pl.shot_tick, maxi(0, exec_ticks() - 1 - runway))


func _report_online_match_over() -> void:
	if not online_mode or _online_match_reported or winner < 0:
		return
	_online_match_reported = true
	_online_client.send_match_over(turn, winner, _online_state_digest())


## Both browsers hash the gameplay state after each execution. The room advances
## only when the hashes match, catching platform/physics drift before it can
## silently corrupt a later turn.
func _online_state_digest() -> String:
	var parts := PackedStringArray()
	parts.append("turn:%d" % turn)
	parts.append("score:%d,%d" % [score[0], score[1]])
	parts.append("ids:%d,%d" % [_next_volley, _next_arrow_id])
	parts.append("rng:%d" % rng.state)
	for i in players.size():
		var p: Player = players[i]
		parts.append("p%d:%d,%d,%d,%d,%d,%d,%d,%d,%d" % [
			i,
			int(round(p.position.x * 10000.0)), int(round(p.position.y * 10000.0)),
			int(round(p.vel.x * 10000.0)), int(round(p.vel.y * 10000.0)),
			1 if p.on_ground else 0, 1 if p.alive else 0, p.invuln_turns,
			int(round(super_meter[i] * 1000000.0)), 1 if super_armed[i] else 0,
		])
	var ordered_arrows: Array = arrows.duplicate()
	ordered_arrows.sort_custom(func(a: Arrow, b: Arrow): return a.network_id < b.network_id)
	for a: Arrow in ordered_arrows:
		parts.append("a:" + a.lockstep_digest_fragment())
	for i in platforms.size():
		var pf: Dictionary = platforms[i]
		var rect: Rect2 = pf["rect"]
		parts.append("f%d:%d,%d,%d,%d,%d" % [
			i, int(pf["hp"]),
			int(round(rect.position.x * 10000.0)), int(round(rect.position.y * 10000.0)),
			int(round(rect.size.x * 10000.0)), int(round(rect.size.y * 10000.0)),
		])
	parts.append("core:%d,%d,%d,%d,%d,%d,%d" % [
		1 if core_announced else 0, 1 if core_active else 0, core_turns_left,
		hitless_execution_streak,
		int(round(core_position.x * 10000.0)), int(round(core_position.y * 10000.0)),
		1 if _core_collected_this_execution else 0,
	])
	return "|".join(parts).sha256_text()


func _clamp_planning_timer() -> void:
	planning_time_left = minf(planning_time_left, planning_duration)
