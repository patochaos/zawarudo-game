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
const TOUCH_CONTROLS_SCRIPT := preload("res://scripts/TouchControls.gd")
const HAZARD_SCRIPT := preload("res://scripts/Hazard.gd")
const CAMERA_SCRIPT := preload("res://scripts/DuelCamera.gd")
const TUTORIAL_SCRIPT := preload("res://scripts/TutorialLayer.gd")
const TELEMETRY_SCRIPT := preload("res://scripts/Telemetry.gd")
const TRANSITION_SCRIPT := preload("res://scripts/TransitionLayer.gd")
const FIGHTER_VISUAL_SCRIPT := preload("res://scripts/FighterVisual.gd")
const FIGHTER_SKIN_SCRIPT := preload("res://scripts/FighterSkin.gd")

## How close a body's feet must be to a moving lip to be carried by it.
const RIDE_TOLERANCE := 3.0
## Upper bound on projected collision sets held at once, so a long AI search
## cannot grow the cache without limit.
const SOLIDS_CACHE_LIMIT := 900
## Brief presentation-only hit-stop. At 60 Hz this holds roughly three frames.
const HIT_PAUSE_DURATION := 0.045

# Rival aristocratic palettes: antique gold versus imperial violet. Both remain
# bright enough to read over the near-black arenas and planning overlays.
const MAX_PLAYERS := 4
const PLAYER_COLORS := [
	Color(0.96, 0.69, 0.18),
	Color(0.76, 0.30, 1.00),
	Color(0.18, 0.82, 0.92),
	Color(1.00, 0.32, 0.42),
]

enum AimSrc { MOUSE, PAD, KEYS, TOUCH }

# ------------------------------------------------------------------ tuning ---

@export_group("Opponent")
## When true, every active player after Player 1 is driven by Ai.gd and its
## preview stays hidden — it cannot see your plan, so showing it would be a
## one-way giveaway.
@export var vs_ai: bool = true
@export var ai_aim_jitter: float = 2.0        # degrees of slop on the AI's aim
@export var ai_think_min: float = 0.8         # it takes a beat before confirming
@export var ai_think_max: float = 2.2
## Soft budget for the one AI search advanced each frame. A single candidate
## cannot be pre-empted, so keeping this low avoids visible planning hitches.
@export var ai_slice_usec: int = 1200

@export_group("Match")
## Hits needed to take the match. A hit does not end the round — the victim
## respawns and the world carries on exactly where it was.
@export var hits_to_win: int = 3
@export var respawn_invuln_turns: int = 1
@export var banner_duration: float = 2.4

@export_group("Visuals")
## Technical Gate 1 harness. Keep disabled until an art-approved skin exists;
## false preserves the original stick renderer exactly.
@export var fighter_visuals_enabled: bool = false

@export_group("Replay")
## The match replay concatenates execution ticks only: planning, commit delays
## and SUPER introductions are deliberately absent.
@export_range(0.25, 4.0, 0.05) var replay_speed: float = 1.5

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
## Fraction of FORWARD speed a knife sheds per second. Vertical speed is never
## damped, so the throw running out of steam collapses the arc into a drop
## instead of flattening into a glide. At 0.45 a knife keeps ~71% of its forward
## speed through one execution window, and a flat full-draw shot reaches roughly
## two thirds of the arena before it hits the floor instead of almost all of it.
@export_range(0.0, 3.0, 0.05) var arrow_drag: float = 0.45
## Gravity multiplier once a knife has been struck. A deflected knife is debris,
## not a shot, and should leave the board rather than float for its full age cap.
@export_range(1.0, 6.0, 0.1) var arrow_clashed_gravity_scale: float = 2.2
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

@export_group("Prototype")
## PROTOTYPE — selectable as a ruleset from the main menu, disposable as a whole.
##
## Three changes tested together, because the question is about the FEEL of a
## duel and they only answer it as a set:
##   * a camera that pushes in while time is stopped and pulls out when it runs
##   * Knife Court V3: raised side shelves, a timed high shuttle, low wrap gates
##     and a jumpable centre plinth that breaks the flat opening shot
##   * a fixed pair: one knife follows the aim, one leaves slightly upward
##
## Delete `prototype_mode`, DuelCamera.gd and Levels._proving_ground() together
## once it has answered its question, whichever way it answers.
@export var prototype_mode: bool = false
@export var prototype_knives_per_shot: int = 2
@export_range(2.0, 20.0, 1.0) var prototype_secondary_lob_angle: float = 10.0
## Lower than the authored 780 impulse: ~129px of rise under normal gravity.
## Every step in the prototype arena stays at or below 110px.
@export var prototype_jump_impulse: float = 600.0
## Short turns. The full 5s window is built for reading a sixteen-platform board;
## this fixed arena can be read in a fraction of that, and the loop gains far more
## from cycling quickly than from time nobody is using.
@export var prototype_planning_duration: float = 3.5
## The commit beat is now the only pause between deciding and watching, so it
## stays long enough to register as a transition rather than a hitch.
@export var prototype_commit_delay: float = 0.20
## Finishing your action IS the commitment — no separate confirm press. Rollback
## still un-readies, because rolling back un-fires the shot that made you ready.
@export var prototype_auto_ready: bool = true
## How long a player must have stopped acting before finishing counts as being
## done. Throwing is not the end of a turn — piloting after the shot is a real
## and useful move — so readiness waits for the hands to come off, not for the
## knife to leave.
@export var prototype_ready_grace: float = 0.6

## Close Camera's persistent knives have a small deterministic physics
## vocabulary: trailing boosts and energy-gated ricochets.
@export var knife_boost_alignment: float = 0.82
@export var knife_boost_min_closing_speed: float = 80.0
@export var knife_boost_transfer: float = 0.72
@export var knife_boost_speed_cap: float = 1.35
@export var knife_ricochet_min_speed: float = 560.0
@export_range(0.1, 0.9, 0.05) var knife_ricochet_max_normal_ratio: float = 0.55
@export_range(0.1, 1.0, 0.05) var knife_ricochet_retention: float = 0.72
@export var knife_ricochet_limit: int = 2

@export_group("Input")
## Useful for editor/browser QA on a machine without a touchscreen. Production
## enables the overlay automatically when the display reports touch support.
@export var force_touch_controls: bool = false

# ------------------------------------------------------------------- state ---

var state: int = Phase.PLANNING
var turn: int = 1
var level_index: int = 0
var level_name: String = ""
var level_wrap: String = ""
var player_count: int = 2
var spawns: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var score: Array[int] = [0, 0, 0, 0]

var banner_text: String = ""
var banner_color: Color = Color.WHITE
var banner_time: float = 0.0

var rng := RandomNumberGenerator.new()
var _ai_think: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _ai_searches: Array = [null, null, null, null]
var _ai_step_cursor: int = 0
var _menu
var _tuning
var planning_time_left: float = 0.0
var commit_time_left: float = 0.0
var exec_tick: int = 0
var exec_ticks_total: int = 0
var winner: int = -1
## Result-screen selection. It stays separate from `level_index` so browsing
## levels never mutates the frozen winning frame; it is applied on rematch.
var rematch_level_index: int = 0
var rematch_level_name: String = ""

## Visual snapshots of execution ticks. Replaying snapshots instead of running
## the simulation again keeps the online result immutable and includes every
## persistent knife and damaged platform without re-triggering game rules.
var _replay_frames: Array[Dictionary] = []
var _replay_terminal_frame: Dictionary = {}
var _replay_frame_index: int = 0
var _replay_accum: float = 0.0

var platforms: Array = []
var solid_rects: Array[Rect2] = []
var world_bounds := Rect2(-160.0, -1600.0, 1600.0, 2600.0)

## Absolute simulated ticks since the match began. Moving geometry and hazards
## are pure functions of it, which is what lets planning project them forward
## instead of ambushing the player with them.
var world_tick: int = 0
var _has_movers: bool = false
## Projected collision sets, keyed by absolute tick. Dropped whenever the
## platform set itself changes (damage, level load, a mover being applied).
var _solids_cache: Dictionary = {}
## Pulse orbs. Empty on the static arenas.
var hazards: Array = []
## Blast impulses raised this window, so the aftermath is legible in the replay.
var _blasts_this_execution: int = 0

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

var aim_source: Array[int] = [AimSrc.MOUSE, AimSrc.KEYS, AimSrc.KEYS, AimSrc.KEYS]
var charging: Array[bool] = [false, false, false, false]
var stamina: Array[float] = [0.0, 0.0, 0.0, 0.0]
## Persistent for the whole match. It only resets when the super is actually
## released (or the match restarts), not between turns or after taking a hit.
var super_meter: Array[float] = [0.0, 0.0, 0.0, 0.0]
## A full meter is only spent when the player explicitly toggles SUPER on
## before placing the shot. The choice persists between turns until changed or
## the burst is actually released.
var super_armed: Array[bool] = [false, false, false, false]

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
var ghost_pos: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var ghost_vel: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var ghost_ground: Array[bool] = [false, false, false, false]
var ghost_air_jumps: Array[int] = [
	Player.MAX_AIR_JUMPS, Player.MAX_AIR_JUMPS,
	Player.MAX_AIR_JUMPS, Player.MAX_AIR_JUMPS,
]
var ghost_drop: Array[int] = [0, 0, 0, 0]
var ghost_drop_from: Array[float] = [0.0, 0.0, 0.0, 0.0]
## Recorded path plus the coasted tail — always exactly one full window long.
var ghost_path: Array[PackedVector2Array] = [
	PackedVector2Array(), PackedVector2Array(), PackedVector2Array(), PackedVector2Array(),
]

var _pads: Array[int] = [-1, -1, -1, -1]
var _pad_btn_prev: Array[Dictionary] = [{}, {}, {}, {}]
var _jump_prev: Array[bool] = [false, false, false, false]
var _charge_t: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _pilot_accum: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _prev_mouse := Vector2.ZERO

var _backdrop: Node2D
var _arena: Arena
var _arrow_layer: Node2D
var _player_layer: Node2D
var _preview: Node2D
var _temporal_core: TemporalCore
var _hazard_layer: Node2D
var _camera: DuelCamera
## Loop timings as authored, so prototype mode can be turned off cleanly.
var _authored_timings: Dictionary = {}
var _authored_jump_impulse: float = -1.0
## Seconds each player has gone without driving their ghost, and the recording
## length that judgement was made against. Prototype auto-ready only.
var _plan_idle: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _plan_ticks_seen: Array[int] = [0, 0, 0, 0]
var _effects
var _sfx
var _time_stop
var _super_freeze
var _transition: TransitionLayer
var _super_cutins_shown: Array[bool] = [false, false, false, false]
var _ui
var _online_client: OnlineClient
var _online_lobby: OnlineLobby
var _touch_controls: TouchControls
var _tutorial
var tutorial_mode: bool = false
var _telemetry
var _telemetry_finished: bool = true
var hit_freeze_enabled: bool = true
var reduced_flashes: bool = false
var _hit_pause_left: float = 0.0
var _hit_pause_used_this_execution: bool = false
var _secret_triple_match: bool = false
var _settings: Dictionary = {
	"sound": 1.0,
	"hit_freeze": true,
	"reduced_flashes": false,
	"high_contrast_previews": false,
	"maximized": true,
	"telemetry": true,
}


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

	# Orbs sit behind the knives: their blast footprint is a large translucent
	# ring and must never obscure a frozen threat.
	_hazard_layer = Node2D.new()
	add_child(_hazard_layer)

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

	_touch_controls = TOUCH_CONTROLS_SCRIPT.new()
	add_child(_touch_controls)
	var touch_enabled := force_touch_controls or DisplayServer.is_touchscreen_available()
	_touch_controls.configure(self, touch_enabled)
	_touch_controls.confirm_requested.connect(_on_touch_confirm)
	_touch_controls.rollback_requested.connect(_on_touch_rollback)
	_touch_controls.reset_requested.connect(_on_touch_reset)
	_touch_controls.super_requested.connect(_on_touch_super)
	_touch_controls.menu_requested.connect(_on_touch_menu)
	_touch_controls.rematch_requested.connect(_on_touch_rematch)
	_touch_controls.replay_requested.connect(_on_touch_replay)
	_touch_controls.report_requested.connect(copy_match_report)
	_touch_controls.level_previous_requested.connect(func(): _cycle_rematch_level(-1))
	_touch_controls.level_next_requested.connect(func(): _cycle_rematch_level(1))
	_ui.set_touch_mode(touch_enabled)

	# This CanvasLayer sits above the HUD and keeps animating while the explicit
	# simulation clock is paused for a SUPER introduction.
	_super_freeze = SUPER_FREEZE_SCRIPT.new()
	add_child(_super_freeze)
	_transition = TRANSITION_SCRIPT.new()
	add_child(_transition)

	_tutorial = TUTORIAL_SCRIPT.new()
	add_child(_tutorial)

	_telemetry = TELEMETRY_SCRIPT.new()
	add_child(_telemetry)

	_menu = MENU_SCRIPT.new()
	add_child(_menu)
	_menu.start_requested.connect(_on_menu_start)
	_menu.freeplay_requested.connect(_on_menu_freeplay)
	_menu.online_requested.connect(_on_menu_online)
	_menu.tutorial_requested.connect(_on_menu_tutorial)
	_menu.option_changed.connect(_on_option_changed)
	_menu.ui_navigated.connect(func(): _sfx.play("ui_move"))
	_menu.ui_accepted.connect(func(): _sfx.play("ui_accept"))

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
	_online_lobby.ui_navigated.connect(func(): _sfx.play("ui_move"))
	_online_lobby.ui_accepted.connect(func(): _sfx.play("ui_accept"))

	_tuning = TUNING_SCRIPT.new()
	add_child(_tuning)

	# PROTOTYPE. The camera is inert until prototype mode turns it on, so the
	# shipping build renders through the plain viewport exactly as before.
	_camera = CAMERA_SCRIPT.new()
	_camera.gm = self
	add_child(_camera)
	_sync_prototype_camera()
	_sync_prototype_timings()

	_load_level(0)
	_spawn_players()
	_tuning.build(self)
	_tuning.visible = false
	_load_settings()
	_menu.configure_options(_settings)
	_assign_pads()
	Input.joy_connection_changed.connect(func(_d, _c): _assign_pads())
	_prev_mouse = get_viewport().get_mouse_position()
	_begin_planning(true)
	_open_menu()


func is_ai(i: int) -> bool:
	return not online_mode and vs_ai and i > 0 and i < players.size()


## The AI's plan is hidden for the same reason a human opponent's would be if we
## could hide it: it plans blind, so it must be planned against blind.
func hides_plan(i: int) -> bool:
	if online_mode:
		return i != online_player and state != Phase.GAME_OVER
	return is_ai(i) and state != Phase.GAME_OVER


func _open_menu() -> void:
	if state == Phase.REPLAY:
		_finish_match_replay()
	if _super_freeze != null:
		_super_freeze.cancel()
	if _tutorial != null:
		_tutorial.stop()
	tutorial_mode = false
	state = Phase.MENU
	banner_time = 0.0
	_ui.visible = false     # the arena stays as a backdrop; the HUD would be noise
	_tuning.visible = false
	if _online_lobby != null:
		_online_lobby.close()
	_menu.open()
	if _transition != null:
		_transition.play("ZAWARUDO", "TIME AWAITS", PLAYER_COLORS[0], reduced_flashes)


func _on_menu_start(ai: bool, lvl: int, requested_players: int = 2) -> void:
	tutorial_mode = false
	online_mode = false
	online_player = -1
	_apply_ruleset(_menu.ruleset)
	vs_ai = ai
	_set_player_count(requested_players)
	_ui.visible = true
	_tuning.visible = false
	_menu.close()
	_load_level(lvl)
	restart()
	_sfx.play("title")
	_begin_match_telemetry("ai_%s" % ("close" if prototype_mode else "wide") \
		if ai else "local_%dp" % requested_players)
	_transition.play("%s // %s" % ["VS AI" if ai else "LOCAL DUEL", level_name],
		"WRITE THE MOVE", PLAYER_COLORS[0], reduced_flashes)


func _on_menu_tutorial() -> void:
	tutorial_mode = true
	online_mode = false
	online_player = -1
	_apply_ruleset(0)
	vs_ai = false
	_set_player_count(1)
	_ui.visible = true
	_ui.show_controls(true)
	_tuning.visible = false
	_menu.close()
	_load_level(0)
	restart()
	_tutorial.start(self)
	_sfx.play("title")
	_begin_match_telemetry("tutorial")
	_transition.play("TRAINING // NO TIMER", "LEARN TO STOP TIME", PLAYER_COLORS[0], reduced_flashes)


func _on_menu_online(lvl: int) -> void:
	tutorial_mode = false
	_apply_ruleset(0)
	_menu.close()
	_ui.visible = false
	_tuning.visible = false
	state = Phase.ONLINE_LOBBY
	_online_lobby.open(lvl)
	_transition.play("ONLINE DUEL", "PRIVATE PLANS", PLAYER_COLORS[1], reduced_flashes)


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
			banner_text = "MATCH VERIFIED — RESULTS READY"
			banner_color = PLAYER_COLORS[winner].lightened(0.3) if winner >= 0 else Color.WHITE
			banner_time = 2.2
		"rematch_status":
			var ready: Array = message.get("ready", [])
			if message.has("level"):
				rematch_level_index = posmod(int(message["level"]), Levels.count())
				rematch_level_name = str(Levels.build(rematch_level_index)["name"])
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
	_set_player_count(2)
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
	_begin_match_telemetry("online")
	_transition.play("ONLINE // ROOM %s" % online_room, "OPPONENT FOUND",
		PLAYER_COLORS[online_player], reduced_flashes)


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
	var drops: Array = data.get("drops", [])
	if dirs.size() != jumps.size() or dirs.size() != holds.size() or dirs.size() != drops.size():
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
	tutorial_mode = false
	_apply_ruleset(0)
	_menu.close()
	_ui.visible = false
	_tuning.visible = true
	_set_player_count(2)
	_load_level(lvl)
	_reset_freeplay()
	state = Phase.FREEPLAY
	_transition.play("FREE PLAY // %s" % level_name, "TIME FLOWS", PLAYER_COLORS[0], reduced_flashes)


func _load_settings() -> void:
	_settings["maximized"] = DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		for key in _settings.keys():
			_settings[key] = cfg.get_value("options", key, _settings[key])
	_apply_settings()


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in _settings.keys():
		cfg.set_value("options", key, _settings[key])
	var error := cfg.save("user://settings.cfg")
	if error != OK:
		push_warning("Could not save options (error %d)" % error)


func _on_option_changed(key: String, value: Variant) -> void:
	if not _settings.has(key):
		return
	_settings[key] = value
	_apply_settings()
	_save_settings()


func _apply_settings() -> void:
	hit_freeze_enabled = bool(_settings["hit_freeze"])
	reduced_flashes = bool(_settings["reduced_flashes"])
	if _sfx != null:
		_sfx.set_volume(float(_settings["sound"]))
	if _time_stop != null:
		_time_stop.reduced_flashes = reduced_flashes
	if _preview != null:
		_preview.high_contrast = bool(_settings["high_contrast_previews"])
		_preview.queue_redraw()
	if _telemetry != null:
		_telemetry.enabled = bool(_settings["telemetry"])
	if DisplayServer.get_name() != "headless":
		var desired := DisplayServer.WINDOW_MODE_MAXIMIZED if bool(_settings["maximized"]) \
			else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != desired:
			DisplayServer.window_set_mode(desired)


func _reset_freeplay() -> void:
	for a in arrows:
		a.queue_free()
	arrows.clear()
	_effects.clear_all()
	_load_level(level_index)
	for i in players.size():
		var p: Player = players[i]
		p.clear_afterimages()
		p.position = spawns[i]
		p.vel = Vector2.ZERO
		p.on_ground = true
		p.air_jumps_left = Player.MAX_AIR_JUMPS
		p.drop_ticks = 0
		p.drop_from_y = 0.0
		p.alive = true
		p.invuln_turns = 0
		p.plan = PlayerPlan.new()
		p.plan.power = 0.5
		super_meter[i] = 0.0
		super_armed[i] = false
		p.queue_redraw()
	charging[0] = false
	_charge_t[0] = 0.0
	_jump_prev[0] = _jump_input_held(0)
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
	_has_movers = false
	for pf in platforms:
		if pf.has("motion"):
			_has_movers = true
		var copies := _seam_copies(pf["rect"])
		pf["rects"] = copies
		r.append_array(copies)
	solid_rects = r
	_solids_cache.clear()


# ------------------------------------------------------- moving geometry -----
#
# Everything below answers one question — "where is the world at tick N?" — and
# every consumer (execution, ghost piloting, the coasted tail, the AI search)
# asks it the same way. That single source is what keeps a plan honest: if a
# lift will have risen by the time your ghost lands there, the ghost lands on
# the risen lift while you are still editing.

## Where a platform stands at an absolute tick. Static pieces ignore the tick.
func platform_rect_at(pf: Dictionary, abs_tick: int) -> Rect2:
	var rect: Rect2 = pf["rect"]
	if not pf.has("motion"):
		return rect
	return Rect2(pf["home"] + Mover.offset(pf["motion"], abs_tick), rect.size)


## The whole collision set as it will stand at `abs_tick`. The live set is
## handed back untouched for the current tick and on static arenas, so the
## execution path pays nothing for a feature it is not using.
func solids_at(abs_tick: int) -> Array[Rect2]:
	if not _has_movers or abs_tick < 0 or abs_tick == world_tick:
		return solid_rects
	if _solids_cache.has(abs_tick):
		return _solids_cache[abs_tick]
	var out: Array[Rect2] = []
	for pf in platforms:
		out.append_array(_seam_copies(platform_rect_at(pf, abs_tick)))
	# The AI walks candidate plans in a scattered tick order, so a one-slot cache
	# would thrash. Bound it instead of growing it forever.
	if _solids_cache.size() > SOLIDS_CACHE_LIMIT:
		_solids_cache.clear()
	_solids_cache[abs_tick] = out
	return out


## Displacement a body inherits from the moving piece it is standing on when the
## world advances from `abs_tick` to the next tick. Without it a rising lift
## would pass straight through its rider and a sliding one would leave it behind.
func mover_carry(pos: Vector2, abs_tick: int) -> Vector2:
	if not _has_movers or abs_tick < 0:
		return Vector2.ZERO
	var carry := Vector2.ZERO
	for pf in platforms:
		if not pf.has("motion"):
			continue
		var here: Rect2 = platform_rect_at(pf, abs_tick)
		var delta: Vector2 = platform_rect_at(pf, abs_tick + 1).position - here.position
		if delta.is_zero_approx():
			continue
		for r in _seam_copies(here):
			if _rides(pos, r):
				carry += delta
				break
	return carry


## Standing on the lip counts, and so does already being inside the piece: a
## platform closing on a body has to push it, not swallow it.
func _rides(centre: Vector2, r: Rect2) -> bool:
	if absf(centre.x - r.get_center().x) >= Player.HALF.x + r.size.x * 0.5:
		return false
	var feet: float = centre.y + Player.HALF.y
	if absf(feet - r.position.y) <= RIDE_TOLERANCE:
		return true
	return absf(centre.y - r.get_center().y) < Player.HALF.y + r.size.y * 0.5


## Snaps every moving platform and orb onto `abs_tick` and refreshes collision.
func _apply_movers(abs_tick: int) -> void:
	for h: Hazard in hazards:
		h.sync_to_tick(abs_tick)
	if not _has_movers:
		return
	for pf in platforms:
		if pf.has("motion"):
			pf["rect"] = platform_rect_at(pf, abs_tick)
	_rebuild_solids()
	_arena.setup(platforms)


func _load_level(index: int) -> void:
	level_index = posmod(index, Levels.count())
	var lv := Levels.build_tutorial() if tutorial_mode else \
		(Levels.build_prototype() if prototype_mode else Levels.build(level_index))
	level_name = lv["name"]
	_backdrop.show_level(level_index)
	level_wrap = Levels.wrap_label(lv)
	rematch_level_index = level_index
	rematch_level_name = level_name
	wrap_x = lv["wrap_x"]
	wrap_y = lv["wrap_y"]
	platforms = lv["platforms"]
	var sp: Array = lv["spawns"]
	for i in MAX_PLAYERS:
		spawns[i] = sp[i]
	core_spawn_points.clear()
	for point in lv.get("core_spawns", []):
		core_spawn_points.append(point)
	world_tick = 0
	_rebuild_solids()
	_arena.setup(platforms)
	_load_hazards(lv.get("hazards", []))


func _load_hazards(specs: Array) -> void:
	for h: Hazard in hazards:
		_hazard_layer.remove_child(h)
		h.queue_free()
	hazards.clear()
	for spec: Dictionary in specs:
		var h := HAZARD_SCRIPT.new()
		h.cfg = self
		h.home = spec["home"]
		h.motion = spec.get("motion", {})
		h.blast_radius = float(spec.get("blast_radius", h.blast_radius))
		h.blast_impulse = float(spec.get("blast_impulse", h.blast_impulse))
		h.recharge_windows = int(spec.get("recharge_windows", h.recharge_windows))
		h.sync_to_tick(world_tick)
		_hazard_layer.add_child(h)
		hazards.append(h)


func next_level() -> void:
	_load_level(level_index + 1)
	restart()   # also zeroes the score


# ------------------------------------------------------------- prototype -----

## Menu-owned ruleset selection. 0 = authored game, 1 = close-camera test.
## Applying it before level load keeps every match isolated
## from whichever experiment was played previously.
func _apply_ruleset(selected: int) -> void:
	prototype_mode = selected == 1
	_sync_prototype_tuning()
	_sync_prototype_camera()
	_sync_prototype_timings()

## Captured once so switching rulesets cannot drift tuning.
func _sync_prototype_tuning() -> void:
	if _authored_jump_impulse < 0.0:
		_authored_jump_impulse = jump_impulse
	jump_impulse = prototype_jump_impulse if prototype_mode else _authored_jump_impulse


## The authored timings are captured once, on the first call, so toggling back
## and forth cannot drift them.
func _sync_prototype_timings() -> void:
	if _authored_timings.is_empty():
		_authored_timings = {
			"planning_duration": planning_duration,
			"commit_delay": commit_delay,
			"ai_think_min": ai_think_min,
			"ai_think_max": ai_think_max,
		}
	if prototype_mode:
		planning_duration = prototype_planning_duration
		commit_delay = prototype_commit_delay
		# An opponent that deliberates for two seconds would eat the whole short
		# window and make auto-ready pointless, so the AI's beat scales with it.
		ai_think_min = minf(_authored_timings["ai_think_min"], prototype_planning_duration * 0.25)
		ai_think_max = minf(_authored_timings["ai_think_max"], prototype_planning_duration * 0.60)
	else:
		for key in _authored_timings:
			set(key, _authored_timings[key])
	_clamp_planning_timer()


## PROTOTYPE. Finishing your action readies you. There is no separate confirm
## press to remember, which is what makes a two-and-a-half second turn workable.
##
## "Finished" is deliberately NOT "has thrown". Piloting after the shot — firing
## early, then running for cover behind your own knife — is one of the better
## moves in the game, and readying on the throw would silently delete it, since
## a confirmed plan stops accepting pilot input. So the rule is: the shot is
## placed, and the player has stopped driving for a moment.
##
## Rollback is untouched — it un-fires the shot, so the plan stops being finished
## and the ready state falls away with it.
func _auto_ready_finished_plans(delta: float) -> void:
	if not prototype_mode or not prototype_auto_ready:
		return
	for i in players.size():
		if not _is_locally_controlled(i) or is_ai(i):
			continue
		var p: Player = players[i]
		if not p.alive or p.plan.confirmed:
			continue
		# A ghost that advanced this frame, or a draw still being held, is a
		# player still acting. Comparing the recording length is enough to see
		# it, and keeps this rule out of the piloting code entirely.
		var recorded: int = p.plan.recorded_ticks()
		if charging[i] or recorded != _plan_ticks_seen[i] or not p.plan.has_shot():
			_plan_ticks_seen[i] = recorded
			_plan_idle[i] = 0.0
			continue
		_plan_idle[i] += delta
		if _plan_idle[i] >= prototype_ready_grace:
			_confirm(i)


func _sync_prototype_camera() -> void:
	if _camera == null:
		return
	_camera.enabled = prototype_mode
	if not prototype_mode:
		_camera.position = Vector2(ARENA_W, ARENA_H) * 0.5
		_camera.zoom = Vector2.ONE


func _spawn_players() -> void:
	for i in player_count:
		_add_player(i)
	_update_facing()


func _add_player(i: int) -> void:
	var p := Player.new()
	p.cfg = self
	p.index = i
	p.color = PLAYER_COLORS[i]
	p.position = spawns[i]
	p.on_ground = true
	p.air_jumps_left = Player.MAX_AIR_JUMPS
	p.plan.set_aim_from_vector(_default_aim_vector(i), aim_min_angle, aim_max_angle)
	p.plan.power = 0.55
	_player_layer.add_child(p)
	if fighter_visuals_enabled:
		var fighter_visual := FIGHTER_VISUAL_SCRIPT.new()
		fighter_visual.name = "FighterVisual"
		fighter_visual.configure(p, FIGHTER_SKIN_SCRIPT.greybox(i))
		p.add_child(fighter_visual)
		p.draw_legacy_visual = false
	players.append(p)


## Local matches can switch between the one-player tutorial, the duel roster,
## and one human plus three AI opponents without rebuilding the scene.
func _set_player_count(requested: int) -> void:
	_ai_searches.fill(null)
	player_count = clampi(requested, 1, MAX_PLAYERS)
	while players.size() > player_count:
		var p: Player = players.pop_back()
		_player_layer.remove_child(p)
		p.queue_free()
	while players.size() < player_count:
		_add_player(players.size())
	_assign_pads()


func _default_aim_vector(i: int) -> Vector2:
	return Vector2(1.0 if spawns[i].x < ARENA_W * 0.5 else -1.0, -0.45)


func _assign_pads() -> void:
	var list := Input.get_connected_joypads()
	_pads.fill(-1)
	if list.is_empty():
		return
	# A local duel has one intentional device split: P1 owns keyboard + mouse;
	# the first connected pad owns P2. Online still maps the first pad to the
	# server-assigned local fighter because there is only one person per machine.
	if online_mode and online_player >= 0:
		_pads[online_player] = list[0]
	elif players.size() > 1:
		_pads[1] = list[0]


func arrow_speed_for(power: float) -> float:
	return lerpf(arrow_speed_min, arrow_speed_max, clampf(power, 0.0, 1.0))


## Authored launch: power changes speed, while the player's aim owns direction.
func knife_launch_velocity(aim: Vector2, power: float) -> Vector2:
	var direct: Vector2 = aim.normalized()
	if direct.is_zero_approx():
		direct = Vector2.RIGHT
	return direct * arrow_speed_for(power)


## One direct knife plus one small upward branch in Close Camera. The upward
## sign mirrors with facing, so the second knife rises on both sides.
func knife_launch_velocities(aim: Vector2, power: float, secret_triple: bool = false) -> Array[Vector2]:
	secret_triple = secret_triple or _secret_triple_match
	var base: Vector2 = knife_launch_velocity(aim, power)
	var side: float = -1.0 if base.x < 0.0 else 1.0
	var offsets: PackedFloat32Array = knife_offsets(power)
	if secret_triple:
		offsets.clear()
		if prototype_mode:
			offsets.append(-prototype_secondary_lob_angle)
			offsets.append(0.0)
			offsets.append(prototype_secondary_lob_angle)
		else:
			var half_spread := knife_spread_for(power) * 0.5
			offsets.append(-half_spread)
			offsets.append(0.0)
			offsets.append(half_spread)
	var out: Array[Vector2] = []
	for off in offsets:
		var signed_offset: float = -side * off if prototype_mode else off
		out.append(base.rotated(deg_to_rad(signed_offset)))
	return out


## Total fan angle in degrees for a throw at this draw. Wide and forgiving when
## barely drawn, near-parallel at full.
func knife_spread_for(power: float) -> float:
	return lerpf(knife_spread_max, knife_spread_min, clampf(power, 0.0, 1.0))


## Angular offsets from the aim line, one per knife, symmetric about it. The
## preview, the throw and the AI all read the fan from here so they cannot drift
## apart.
func knife_offsets(power: float) -> PackedFloat32Array:
	var n: int = maxi(1, prototype_knives_per_shot if prototype_mode else knives_per_shot)
	var out := PackedFloat32Array()
	if prototype_mode:
		out.append(0.0)
		if n > 1:
			out.append(prototype_secondary_lob_angle)
		return out
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


func replay_time_left() -> float:
	if state != Phase.REPLAY:
		return 0.0
	return float(maxi(0, _replay_frames.size() - 1 - _replay_frame_index)) \
		/ float(Engine.physics_ticks_per_second) / maxf(replay_speed, 0.01)


# -------------------------------------------------------------- main loop ----

func _physics_process(delta: float) -> void:
	# Hit-stop pauses wall-clock presentation only. No deterministic tick is
	# consumed, so offline, replay and lockstep simulation remain identical.
	if _hit_pause_left > 0.0 and state == Phase.EXECUTING:
		_hit_pause_left = maxf(0.0, _hit_pause_left - delta)
		_preview.queue_redraw()
		_ui.refresh()
		return
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
			var tutorial_waiting: bool = tutorial_mode and _tutorial != null \
				and not _tutorial.timed_turns_started
			if tutorial_waiting and _tutorial.observe_planning():
				_ui.refresh()
				return
			_auto_ready_finished_plans(delta)
			_tick_ai(delta)
			_update_facing()
			_rebuild_ghost_paths()
			if not tutorial_waiting:
				planning_time_left -= delta
			if not tutorial_waiting and planning_time_left <= 0.0:
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
					_capture_replay_frame()
					if online_mode and state == Phase.GAME_OVER:
						exec_tick += 1
						_report_online_match_over()
					elif state == Phase.EXECUTING:
						exec_tick += 1
						# A kill on the final tick must not be undone by ending the window.
						if exec_tick >= exec_ticks_total:
							_end_execution()
		Phase.GAME_OVER:
			_poll_game_over_pad()
		Phase.REPLAY:
			_poll_replay_pad()
			if state == Phase.REPLAY:
				_tick_match_replay(delta)

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

	# The world advances first, so bodies resolve against the geometry as it
	# stands at the END of this tick and inherit the movement of whatever they
	# were standing on. `from_tick` is the tick they are leaving.
	var from_tick: int = world_tick
	world_tick += 1
	_apply_movers(world_tick)

	for p in players:
		p.sim_step(dt, exec_tick, from_tick)
	_check_core_collection()
	_step_arrows(dt)


## Continuous real-time control of Player 1. Player 2 is an inert dummy that
## just falls and stands — something to shoot at while judging arrow feel.
func _freeplay_tick(delta: float) -> void:
	var p: Player = players[0]

	var dir := 0
	if _held(K_P1["left"]) or _pad_left(_pads[0]) or _touch_controls.left_held:
		dir -= 1
	if _held(K_P1["right"]) or _pad_right(_pads[0]) or _touch_controls.right_held:
		dir += 1
	var jump_now: bool = _held(K_P1["jump"]) \
		or (_pads[0] >= 0 and Input.is_joy_button_pressed(_pads[0], JOY_BUTTON_A)) \
		or _touch_controls.jump_held
	var jump_edge: bool = jump_now and not _jump_prev[0]
	_jump_prev[0] = jump_now
	var wait_now: bool = _held(K_P1["wait"]) or _pad_down(_pads[0]) \
		or _touch_controls.wait_held
	var drop_now: bool = jump_edge and wait_now

	p.sim_free(delta, dir, jump_edge and not drop_now, jump_now and not drop_now, drop_now)
	players[1].sim_free(delta, 0, false, false)

	if _touch_controls.enabled:
		if _touch_controls.aim_active:
			p.plan.set_aim_from_vector(_touch_controls.aim_position - p.shoulder(),
				aim_min_angle, aim_max_angle)
		elif dir != 0 and not _touch_controls.aim_latched:
			p.plan.set_aim_side(dir)
	else:
		p.plan.set_aim_from_vector(get_global_mouse_position() - p.shoulder(),
			aim_min_angle, aim_max_angle)
	_update_facing()

	# hold to draw, release to loose — immediately, no turn to wait for
	var held: bool = _held(K_P1["charge"]) or _touch_controls.charge_held
	if not _touch_controls.has_active_touches() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		held = true
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
			_on_player_hit(res["hit_player"], a.position, a.shooter)
		if res["hit_platform"] >= 0:
			damaged.append(res["hit_platform"])
			_effects.add(Effects.Kind.SPARK, a.position, Color(0.95, 0.85, 0.6))
			_sfx.play("thud")
		if res.get("ricochet", false):
			var ricochet_at: Vector2 = res.get("ricochet_position", a.position)
			_effects.add(Effects.Kind.CLASH, ricochet_at, Color(0.62, 0.95, 1.0))
			_remember_aftermath("RICOCHET", ricochet_at, Color(0.62, 0.95, 1.0))
			_sfx.play("clash")
		if res["alive"]:
			survivors.append(a)
		else:
			a.queue_free()
	survivors = _resolve_hazard_strikes(survivors)
	_resolve_clashes(survivors)
	arrows = survivors
	if not damaged.is_empty():
		_apply_platform_damage(damaged)


## A knife that reaches a charged orb is spent on it and the orb detonates.
## Tested against the swept segment for the same reason knife-vs-knife is: at
## full draw a knife covers more than the orb's diameter in a single tick.
func _resolve_hazard_strikes(live: Array) -> Array:
	if hazards.is_empty():
		return live
	var triggered: Array = []
	var kept: Array = []
	for a: Arrow in live:
		var struck: Hazard = null
		for h: Hazard in hazards:
			if not h.charged or triggered.has(h):
				continue
			if Arrow.moving_points_closest(a.prev_pos, a.position, h.position, h.position)[0] \
					<= Hazard.RADIUS + knife_clash_radius * 0.5:
				struck = h
				break
		if struck == null:
			kept.append(a)
			continue
		triggered.append(struck)
		a.queue_free()
	# Detonate only once the survivor list is final, so a blast never pushes a
	# knife that was already spent this tick.
	for h: Hazard in triggered:
		_detonate(h, kept)
	return kept


## The forcefield. It damages nobody — knives remain the only source of damage —
## but it rewrites position, momentum and every firing line inside its radius,
## and the knives it throws outward stay in the world afterwards.
func _detonate(h: Hazard, affected_arrows: Array) -> void:
	h.discharge()
	_blasts_this_execution += 1
	_effects.add(Effects.Kind.SHATTER, h.position, Color(0.62, 0.95, 1.0))
	_remember_aftermath("PULSE", h.position, Color(0.62, 0.95, 1.0))
	_sfx.play("break")

	for p in players:
		if not p.alive:
			continue
		p.vel += _blast_impulse_at(h, p.position)
		# Being blown off a ledge has to actually free the body, or the next tick
		# simply resolves it back down onto the surface it was resting on.
		if p.vel.y < 0.0:
			p.on_ground = false
	for a: Arrow in affected_arrows:
		var push: Vector2 = _blast_impulse_at(h, a.position)
		if push.is_zero_approx():
			continue
		# Reuse the deflected read: a knife shoved by a pulse is no longer on
		# anyone's aimed line, and its tumble says so.
		a.deflect(a.vel + push, knife_clash_spin, knife_clash_cooldown)


## Full strength at the centre, nothing at the rim, straight line between. The
## falloff is linear so a player can judge the edge of the ring by eye.
func _blast_impulse_at(h: Hazard, at: Vector2) -> Vector2:
	var offset: Vector2 = wrap_delta(h.position, at)
	var distance: float = offset.length()
	if distance >= h.blast_radius:
		return Vector2.ZERO
	# A body sitting exactly on the orb is thrown straight up rather than in an
	# arbitrary direction picked by floating-point noise.
	var dir: Vector2 = offset / distance if distance > 0.001 else Vector2.UP
	return dir * (h.blast_impulse * (1.0 - distance / h.blast_radius))


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

			var at: Vector2 = (hit[1] + hit[2]) * 0.5
			if prototype_mode and _try_trailing_boost(a, b, at):
				break

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


## Same-direction contact is not a clash in Close Camera: if the
## faster knife genuinely approached from behind, it spends itself to relay
## momentum into the leading knife. Ownership of the leader never changes.
func _try_trailing_boost(a: Arrow, b: Arrow, at: Vector2) -> bool:
	var sa: float = a.vel.length()
	var sb: float = b.vel.length()
	if sa <= 0.001 or sb <= 0.001:
		return false
	if a.vel.normalized().dot(b.vel.normalized()) < knife_boost_alignment:
		return false
	var chaser: Arrow = a if sa > sb else b
	var leader: Arrow = b if chaser == a else a
	if chaser.vel.length() - leader.vel.length() < knife_boost_min_closing_speed:
		return false
	var travel: Vector2 = chaser.vel.normalized()
	if (leader.prev_pos - chaser.prev_pos).dot(travel) < -knife_clash_radius * 0.25:
		return false

	var relayed: Vector2 = leader.vel + chaser.vel * knife_boost_transfer
	var cap: float = arrow_speed_max * knife_boost_speed_cap
	if relayed.length() > cap:
		relayed = relayed.normalized() * cap
	leader.boost(relayed, knife_clash_cooldown, chaser.stable_id())
	# A clean relay re-energises one spent bank, keeping a successful chain live.
	leader.ricochet_count = maxi(0, leader.ricochet_count - 1)
	chaser.deflect(chaser.vel * 0.18, knife_clash_spin, knife_clash_cooldown,
		leader.stable_id())
	_effects.add(Effects.Kind.CLASH, at, Color(1.0, 0.72, 0.18))
	_remember_aftermath("BOOST", at, Color(1.0, 0.72, 0.18))
	_sfx.play("clash")
	return true


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
	if tutorial_mode:
		return
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
		var nearest := INF
		var farthest := 0.0
		for p: Player in players:
			var distance: float = wrap_delta(p.position, point).length()
			nearest = minf(nearest, distance)
			farthest = maxf(farthest, distance)
		var too_close: float = maxf(0.0, 120.0 - nearest) * 2.0
		var cost: float = farthest - nearest + too_close + rng.randf() * 18.0
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
	if _telemetry != null:
		_telemetry.record("core_claimed", turn, {"players": collectors.duplicate()})
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
		banner_text = "MULTIPLE PLAYERS — SUPER READY"
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
func _on_player_hit(victim_idx: int, at: Vector2, shooter_idx: int = -1) -> void:
	var victim: Player = players[victim_idx]
	if not victim.alive:
		return
	var scorer: int = shooter_idx
	victim.alive = false
	victim.queue_redraw()
	_effects.add(Effects.Kind.KILL, at, victim.color)
	_remember_aftermath("HIT", at, victim.color.lightened(0.35))
	_sfx.play("hit")
	# One short accent per execution keeps a crowded four-player volley from
	# turning several legitimate impacts into a chain of apparent frame stalls.
	if hit_freeze_enabled and state == Phase.EXECUTING and not _hit_pause_used_this_execution:
		_hit_pause_left = HIT_PAUSE_DURATION
		_hit_pause_used_this_execution = true
	if _time_stop != null:
		_time_stop.impact_flash(at, victim.color)
	if state == Phase.FREEPLAY:
		return          # the sandbox keeps no score and never ends
	_hit_this_execution = true
	if _telemetry != null:
		_telemetry.record("hit", turn, {
			"victim": victim_idx + 1,
			"shooter": shooter_idx + 1 if shooter_idx >= 0 else 0,
			"x": int(round(at.x)),
			"y": int(round(at.y)),
		})
	# A returning knife may hit its owner. The hit still removes them for this
	# window, but it must not award a point to an arbitrary rival.
	if scorer < 0 or scorer >= players.size() or scorer == victim_idx:
		banner_text = "P%d  SELF-HIT" % (victim_idx + 1)
		banner_color = victim.color
		banner_time = banner_duration
		return
	score[scorer] += 1

	if score[scorer] >= hits_to_win:
		state = Phase.GAME_OVER
		winner = scorer
		_prime_game_over_pad_state()
		banner_text = "P%d  WINS" % (scorer + 1)
		banner_color = PLAYER_COLORS[scorer]
		_finish_match_telemetry()
	else:
		banner_text = "P%d  →  HIT  →  P%d" % [scorer + 1, victim_idx + 1]
		banner_color = PLAYER_COLORS[scorer]
	banner_time = banner_duration


func _score_text() -> String:
	var parts := PackedStringArray()
	for i in players.size():
		parts.append("P%d %d" % [i + 1, score[i]])
	return "  ·  ".join(parts)


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
	for i in players.size():
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

	# Every AI gets an independent blind search and a small confirmation delay,
	# so a four-player planning phase remains readable rather than snapping READY.
	_ai_searches.fill(null)
	_ai_step_cursor = 0
	for i in players.size():
		if not is_ai(i) or not players[i].alive:
			continue
		var target := _ai_target_for(i)
		if target < 0:
			continue
		var search := Ai.new()
		search.begin(self, i, target)
		_ai_searches[i] = search
		_ai_think[i] = rng.randf_range(ai_think_min, ai_think_max)


func start_tutorial_timed_turns() -> void:
	if not tutorial_mode or state != Phase.PLANNING:
		return
	planning_duration = 5.0
	planning_time_left = planning_duration
	banner_text = "TIMED TURNS"
	banner_color = Color(1.0, 0.78, 0.30)
	banner_time = 1.5


## Advance one opponent per frame in round-robin order. Giving every AI its own
## slice in the same frame multiplied the soft budget by three in four-player
## matches, and one expensive candidate could overrun each slice.
func _tick_ai(delta: float) -> void:
	var rebuilt := false
	for offset in players.size():
		var i: int = (_ai_step_cursor + offset) % players.size()
		if not is_ai(i) or players[i].plan.confirmed or not players[i].alive:
			continue
		var search = _ai_searches[i]
		if search == null or search.done:
			continue
		search.step(ai_slice_usec)
		_ai_step_cursor = (i + 1) % players.size()
		if search.done:
			search.apply()
			rebuilt = true
		break

	for i in players.size():
		if not is_ai(i) or players[i].plan.confirmed or not players[i].alive:
			continue
		var search = _ai_searches[i]
		if search != null and not search.done:
			continue
		_ai_think[i] -= delta
		if _ai_think[i] <= 0.0:
			_confirm(i)
	if rebuilt:
		_rebuild_ghost_paths()


func _ai_target_for(ai_idx: int) -> int:
	var best := -1
	var best_distance := INF
	for i in players.size():
		if i == ai_idx or not players[i].alive:
			continue
		var distance: float = wrap_delta(players[ai_idx].position, players[i].position).length_squared()
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


func _begin_commit() -> void:
	state = Phase.COMMITTING
	commit_time_left = commit_delay


func _begin_execution() -> void:
	# Use the best candidate found so far if the planning clock beats the sliced
	# search. Finishing several searches synchronously caused a large hitch at the
	# exact moment a four-player execution began.
	var rebuilt := false
	for i in players.size():
		var search = _ai_searches[i]
		if search != null and not search.done:
			search.complete_early()
			search.apply()
			rebuilt = true
	# apply() adds recorded ticks, so the cached ghost is now stale — and the
	# shot origin is read from it.
	if rebuilt:
		_rebuild_ghost_paths()

	# A charge still being held when the window opens counts as released.
	for i in players.size():
		if charging[i]:
			_release_charge(i)

	state = Phase.EXECUTING
	_super_cutins_shown.fill(false)
	exec_tick = 0
	exec_ticks_total = exec_ticks()
	_hit_pause_left = 0.0
	_hit_pause_used_this_execution = false
	_hit_this_execution = false
	_core_collected_this_execution = false
	_blasts_this_execution = 0
	if _time_stop != null:
		_time_stop.phase_changed(Phase.EXECUTING)
	if _sfx != null:
		_sfx.play("resume")
	_capture_replay_frame()


func _remember_aftermath(label: String, at: Vector2, col: Color) -> void:
	if state == Phase.EXECUTING and _effects != null and _effects.has_method("remember"):
		_effects.remember(label, at, col)


# -------------------------------------------------------------- replay -------

## Store the drawn state after each simulation tick. No planning frame reaches
## this method, which is what makes the finished replay one continuous burst.
func _capture_replay_frame() -> void:
	if state != Phase.EXECUTING and state != Phase.GAME_OVER:
		return
	var player_frames: Array[Dictionary] = []
	for p: Player in players:
		player_frames.append({
			"position": p.position,
			"vel": p.vel,
			"on_ground": p.on_ground,
			"air_jumps_left": p.air_jumps_left,
			"drop_ticks": p.drop_ticks,
			"drop_from_y": p.drop_from_y,
			"alive": p.alive,
			"facing": p.facing,
			"invuln_turns": p.invuln_turns,
			"aim_angle": p.plan.aim_angle,
			"power": p.plan.power,
			"anim_time": p._anim_time,
		})

	var arrow_frames: Array[Dictionary] = []
	for a: Arrow in arrows:
		arrow_frames.append({
			"network_id": a.network_id,
			"shooter": a.shooter,
			"volley": a.volley,
			"position": a.position,
			"prev_pos": a.prev_pos,
			"vel": a.vel,
			"rotation": a.rotation,
			"color": a.color,
			"age_ticks": a.age_ticks,
			"clashed": a.clashed,
			"spin": a.spin,
			"clash_count": a.clash_count,
			"boost_count": a.boost_count,
			"ricochet_count": a.ricochet_count,
			"trail": a.trail.duplicate(),
		})

	var hazard_frames: Array[Dictionary] = []
	for h: Hazard in hazards:
		hazard_frames.append({
			"position": h.position,
			"charged": h.charged,
			"windows_left": h.windows_left,
			"flash": h.flash,
		})

	_replay_frames.append({
		"turn": turn,
		"score": score.duplicate(),
		"players": player_frames,
		"arrows": arrow_frames,
		"hazards": hazard_frames,
		"world_tick": world_tick,
		"platforms": platforms.duplicate(true),
		"super_meter": super_meter.duplicate(),
		"super_armed": super_armed.duplicate(),
		"core_position": core_position,
		"core_announced": core_announced,
		"core_active": core_active,
		"core_turns_left": core_turns_left,
		"core_time": _temporal_core._time if _temporal_core != null else 0.0,
		"effects": _effects._fx.duplicate(true) if _effects != null else [],
	})


func _start_match_replay() -> void:
	if state != Phase.GAME_OVER or _replay_frames.is_empty():
		return
	_replay_terminal_frame = _replay_frames.back().duplicate(true)
	_replay_frame_index = 0
	_replay_accum = 0.0
	state = Phase.REPLAY
	if _super_freeze != null:
		_super_freeze.cancel()
	_apply_replay_frame(_replay_frames[0])
	banner_time = 0.0
	_preview.queue_redraw()
	_ui.refresh()


func _tick_match_replay(delta: float) -> void:
	_replay_accum += delta * maxf(replay_speed, 0.01)
	var frame_time := tick_dt()
	while _replay_accum >= frame_time:
		_replay_accum -= frame_time
		_replay_frame_index += 1
		if _replay_frame_index >= _replay_frames.size():
			_finish_match_replay()
			return
		_apply_replay_frame(_replay_frames[_replay_frame_index])


func _apply_replay_frame(frame: Dictionary) -> void:
	turn = int(frame["turn"])
	var frame_score: Array = frame["score"]
	var frame_meter: Array = frame["super_meter"]
	var frame_armed: Array = frame["super_armed"]
	for i in players.size():
		score[i] = int(frame_score[i])
		super_meter[i] = float(frame_meter[i])
		super_armed[i] = bool(frame_armed[i])
		var p: Player = players[i]
		var data: Dictionary = frame["players"][i]
		p.position = data["position"]
		p.vel = data["vel"]
		p.on_ground = bool(data["on_ground"])
		p.air_jumps_left = int(data.get("air_jumps_left", Player.MAX_AIR_JUMPS))
		p.drop_ticks = int(data.get("drop_ticks", 0))
		p.drop_from_y = float(data.get("drop_from_y", 0.0))
		p.alive = bool(data["alive"])
		p.facing = int(data["facing"])
		p.invuln_turns = int(data["invuln_turns"])
		p.plan.aim_angle = float(data["aim_angle"])
		p.plan.power = float(data["power"])
		p._anim_time = float(data["anim_time"])
		p.queue_redraw()

	var arrow_by_id: Dictionary = {}
	for child in _arrow_layer.get_children():
		if child is Arrow:
			arrow_by_id[child.network_id] = child
			child.visible = false
	var frame_arrows: Array = []
	for data: Dictionary in frame["arrows"]:
		var id := int(data["network_id"])
		var a: Arrow = arrow_by_id.get(id)
		if a == null:
			a = Arrow.new()
			a.cfg = self
			a.network_id = id
			_arrow_layer.add_child(a)
			arrow_by_id[id] = a
		a.visible = true
		a.shooter = int(data["shooter"])
		a.volley = int(data["volley"])
		a.position = data["position"]
		a.prev_pos = data["prev_pos"]
		a.vel = data["vel"]
		a.rotation = float(data["rotation"])
		a.color = data["color"]
		a.age_ticks = int(data["age_ticks"])
		a.clashed = bool(data["clashed"])
		a.spin = float(data["spin"])
		a.clash_count = int(data["clash_count"])
		a.boost_count = int(data.get("boost_count", 0))
		a.ricochet_count = int(data.get("ricochet_count", 0))
		a.trail = PackedVector2Array(data["trail"])
		a.queue_redraw()
		frame_arrows.append(a)
	arrows = frame_arrows

	world_tick = int(frame["world_tick"])
	platforms = frame["platforms"].duplicate(true)
	_rebuild_solids()
	_arena.setup(platforms)
	var hazard_frames: Array = frame["hazards"]
	for i in mini(hazards.size(), hazard_frames.size()):
		var h: Hazard = hazards[i]
		var data: Dictionary = hazard_frames[i]
		h.position = data["position"]
		h.charged = bool(data["charged"])
		h.windows_left = int(data["windows_left"])
		h.flash = float(data["flash"])
		h.queue_redraw()
	core_position = frame["core_position"]
	core_announced = bool(frame["core_announced"])
	core_active = bool(frame["core_active"])
	core_turns_left = int(frame["core_turns_left"])
	_sync_temporal_core_visual()
	if _temporal_core != null:
		_temporal_core._time = float(frame["core_time"])
	if _effects != null:
		_effects._fx = frame["effects"].duplicate(true)
		_effects._remembered.clear()
		_effects.queue_redraw()


func _finish_match_replay() -> void:
	if not _replay_terminal_frame.is_empty():
		_apply_replay_frame(_replay_terminal_frame)
	for child in _arrow_layer.get_children():
		if child is Arrow and not arrows.has(child):
			child.queue_free()
	state = Phase.GAME_OVER
	banner_text = "PLAYER %d WINS THE MATCH" % (winner + 1) if winner >= 0 else "MATCH OVER"
	banner_color = PLAYER_COLORS[winner] if winner >= 0 else Color.WHITE
	banner_time = banner_duration
	_replay_frame_index = 0
	_replay_accum = 0.0


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
	for h: Hazard in hazards:
		h.end_of_window()
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
	p.clear_afterimages()
	p.position = spawns[i]
	p.vel = Vector2.ZERO
	p.on_ground = true
	p.air_jumps_left = Player.MAX_AIR_JUMPS
	p.drop_ticks = 0
	p.drop_from_y = 0.0
	p.alive = true
	p.invuln_turns = respawn_invuln_turns
	p.queue_redraw()


## One throw looses the whole fan from the same point at the same tick — the
## spread is the shot, not a sequence of shots.
func _spawn_arrow(p: Player) -> void:
	var launches: Array[Vector2] = knife_launch_velocities(p.aim_dir(), p.plan.power)
	var origin: Vector2 = p.shoulder() + launches[0].normalized() * 22.0
	var volley: int = _next_volley
	_next_volley += 1
	for launch in launches:
		var a := Arrow.new()
		a.cfg = self
		a.shooter = p.index
		a.volley = volley
		a.network_id = _next_arrow_id
		_next_arrow_id += 1
		a.color = p.color
		a.position = origin
		a.vel = launch
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
	_secret_triple_match = false
	if _super_freeze != null:
		_super_freeze.cancel()
	_replay_frames.clear()
	_replay_terminal_frame.clear()
	_replay_frame_index = 0
	_replay_accum = 0.0
	if online_mode:
		rng.seed = _online_seed
	for a in arrows:
		a.queue_free()
	arrows.clear()
	_next_volley = 1
	_next_arrow_id = 1
	_effects.clear_all()
	_load_level(level_index)
	for i in players.size():
		var p: Player = players[i]
		p.clear_afterimages()
		p.position = spawns[i]
		p.vel = Vector2.ZERO
		p.on_ground = true
		p.air_jumps_left = Player.MAX_AIR_JUMPS
		p.alive = true
		p.invuln_turns = 0
		p.plan = PlayerPlan.new()
		p.plan.set_aim_from_vector(_default_aim_vector(i), aim_min_angle, aim_max_angle)
		p.plan.power = 0.55
		p.queue_redraw()
	turn = 1
	winner = -1
	for i in MAX_PLAYERS:
		score[i] = 0
		super_meter[i] = 0.0
		super_armed[i] = false
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
	ghost_air_jumps[i] = p.air_jumps_left
	ghost_drop[i] = p.drop_ticks
	ghost_drop_from[i] = p.drop_from_y
	stamina[i] = movement_budget
	_pilot_accum[i] = 0.0
	charging[i] = false
	_charge_t[i] = 0.0
	_plan_idle[i] = 0.0
	_plan_ticks_seen[i] = 0
	# Planning may resume long after the previous input poll. Sampling the actual
	# button prevents a stale edge from swallowing an airborne jump.
	_jump_prev[i] = _jump_input_held(i)


## Records exactly one tick of piloted input onto the ghost.
func _pilot_step(i: int, dir: int, jump: bool, hold: bool, drop: bool = false) -> bool:
	var pl: PlayerPlan = players[i].plan
	if pl.recorded_ticks() >= movement_tick_budget() or stamina[i] <= 0.0:
		return false
	# The tick this step LEAVES, in absolute time — the moving world is projected
	# forward from here, so the ghost meets the geometry the plan will meet.
	var from_tick: int = world_tick + pl.recorded_ticks()
	var drop_result := Player.apply_drop(ghost_pos[i].y, ghost_vel[i], ghost_ground[i],
		ghost_drop[i], ghost_drop_from[i], drop)
	ghost_vel[i] = drop_result[0]
	ghost_ground[i] = drop_result[1]
	ghost_drop[i] = drop_result[2]
	ghost_drop_from[i] = drop_result[3]
	var jump_result := Player.apply_jump(ghost_vel[i], ghost_ground[i], ghost_air_jumps[i],
		jump, jump_impulse)
	ghost_vel[i] = jump_result[0]
	ghost_ground[i] = jump_result[1]
	ghost_air_jumps[i] = jump_result[2]
	var jumped: bool = jump_result[3]
	pl.record(dir, jumped, hold or jumped, drop)
	var st := Player.step_state(ghost_pos[i], ghost_vel[i], ghost_ground[i], dir,
		hold or jumped, tick_dt(), self, from_tick, ghost_drop[i], ghost_drop_from[i])
	ghost_pos[i] = st[0]
	ghost_vel[i] = st[1]
	ghost_ground[i] = st[2]
	if ghost_ground[i]:
		ghost_air_jumps[i] = Player.MAX_AIR_JUMPS
	stamina[i] = maxf(0.0, stamina[i] - tick_dt())
	return true


## Recorded path + the coasted remainder, so the ghost always shows the true
## end of the window rather than just where the stamina ran out.
func _rebuild_ghost_paths() -> void:
	for i in players.size():
		var p: Player = players[i]
		var pl: PlayerPlan = p.plan
		var path := PackedVector2Array()
		# replay the recording from the live body state
		var pos: Vector2 = p.position
		var vel: Vector2 = p.vel
		var og: bool = p.on_ground
		var air_jumps: int = p.air_jumps_left
		var drop: int = p.drop_ticks
		var drop_from: float = p.drop_from_y
		path.append(pos)
		for t in pl.recorded_ticks():
			var drop_result := Player.apply_drop(pos.y, vel, og, drop, drop_from, pl.drop_at(t))
			vel = drop_result[0]
			og = drop_result[1]
			drop = drop_result[2]
			drop_from = drop_result[3]
			var jump_result := Player.apply_jump(vel, og, air_jumps, pl.jump_at(t), jump_impulse)
			vel = jump_result[0]
			og = jump_result[1]
			air_jumps = jump_result[2]
			var st := Player.step_state(pos, vel, og, pl.dir_at(t), pl.hold_at(t), tick_dt(),
				self, world_tick + t, drop, drop_from)
			pos = st[0]
			vel = st[1]
			og = st[2]
			if og:
				air_jumps = Player.MAX_AIR_JUMPS
			path.append(pos)
		# coast whatever is left of the window
		var tail := PredictionSystem.coast(pos, vel, og, exec_ticks() - pl.recorded_ticks(), self,
			world_tick + pl.recorded_ticks(), drop, drop_from)
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
#   Aim   : mouse (P1) / right stick (P2)
#   Power : hold to charge — the ghost FREEZES while charging — release to fire
#           from wherever the ghost is standing
#   Super : toggles whether a full meter upgrades the next placed shot
#   Rollback   : un-fires the shot and drops the confirmation, keeps the path
#   Reset path : throws the recorded movement away and refills stamina

const K_P1 := {
	"left": [KEY_A], "right": [KEY_D], "jump": [KEY_SPACE], "wait": [KEY_S],
	"charge": [], "rollback": [KEY_R], "reset": [KEY_F],
	"super": [KEY_T],
	"aim_up": [KEY_Q], "aim_down": [KEY_E],
}
const K_GAMEPAD_ONLY := {
	"left": [], "right": [], "jump": [], "wait": [],
	"charge": [], "rollback": [], "reset": [], "super": [],
	"aim_up": [], "aim_down": [],
}


func _is_locally_controlled(i: int) -> bool:
	return i == online_player if online_mode else not is_ai(i)


func _input_map_for(i: int) -> Dictionary:
	# In an online room both people get the natural P1 bindings on their own
	# machine, regardless of whether the server assigned them slot 0 or slot 1.
	# In a local duel P2 is gamepad-only so the two players never fight over one
	# keyboard or accidentally drive each other's plan.
	return K_P1 if online_mode else (K_P1 if i == 0 else K_GAMEPAD_ONLY)


func _touch_player() -> int:
	# A phone controls its own lockstep slot online and Player 1 everywhere else.
	return online_player if online_mode else 0


func _on_touch_confirm() -> void:
	_confirm(_touch_player())


func _on_touch_rollback() -> void:
	_rollback(_touch_player())


func _on_touch_reset() -> void:
	_reset_path(_touch_player())


func _on_touch_super() -> void:
	_toggle_super(_touch_player())


func _on_touch_menu() -> void:
	if online_mode:
		_leave_online()
	else:
		_open_menu()


func _on_touch_rematch() -> void:
	_request_rematch()


func _on_touch_replay() -> void:
	if state == Phase.REPLAY:
		_finish_match_replay()
	else:
		_start_match_replay()


func _request_rematch() -> void:
	if state != Phase.GAME_OVER:
		return
	if online_mode:
		if _online_waiting_rematch:
			return
		_online_waiting_rematch = _online_client.send_rematch(rematch_level_index)
		banner_text = "REMATCH REQUESTED — WAITING FOR OPPONENT"
		banner_color = Color(0.86, 0.68, 1.0)
		banner_time = 2.0
	else:
		_load_level(rematch_level_index)
		restart()
		_begin_match_telemetry("tutorial" if tutorial_mode else \
			("ai_%s" % ("close" if prototype_mode else "wide") if vs_ai else "local_2p"))


func _cycle_rematch_level(direction: int) -> void:
	if state != Phase.GAME_OVER or direction == 0 \
			or (online_mode and (online_player != 0 or _online_waiting_rematch)):
		return
	rematch_level_index = posmod(rematch_level_index + direction, Levels.count())
	var selected := Levels.build(rematch_level_index)
	rematch_level_name = str(selected["name"])


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
			KEY_F7:
				_activate_secret_triple_match()
			KEY_F8:
				_fill_test_super(k.shift_pressed)
			_:
				_tuning.handle_key(k.keycode, k.shift_pressed)
		return

	if state == Phase.REPLAY:
		match k.keycode:
			KEY_ESCAPE:
				_finish_match_replay()
				if online_mode:
					_leave_online()
				else:
					_open_menu()
			KEY_ENTER, KEY_KP_ENTER, KEY_R:
				_finish_match_replay()
			KEY_M:
				_sfx.toggle_mute()
			KEY_H:
				_ui.toggle_help()
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
			if k.keycode in [KEY_ENTER, KEY_KP_ENTER]:
				_request_rematch()
			elif k.keycode == KEY_R:
				_start_match_replay()
			elif k.keycode == KEY_LEFT:
				_cycle_rematch_level(-1)
			elif k.keycode == KEY_RIGHT:
				_cycle_rematch_level(1)
			elif k.keycode == KEY_C:
				copy_match_report()
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

	if state == Phase.GAME_OVER:
		match k.keycode:
			KEY_ESCAPE:
				_open_menu()
			KEY_ENTER, KEY_KP_ENTER:
				_request_rematch()
			KEY_R:
				_start_match_replay()
			KEY_LEFT:
				_cycle_rematch_level(-1)
			KEY_RIGHT:
				_cycle_rematch_level(1)
			KEY_M:
				_sfx.toggle_mute()
			KEY_C:
				copy_match_report()
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
			_activate_secret_triple_match()
			return
		KEY_F8:
			_fill_test_super(k.shift_pressed)
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

	# Local P1 owns keyboard + mouse. Right Shift used to confirm P2, but local P2
	# is now deliberately gamepad-only and confirms with Start.
	if k.keycode == KEY_SHIFT:
		if k.location != KEY_LOCATION_RIGHT and not is_ai(0):
			_confirm(0)
		return

	if state != Phase.PLANNING:
		return

	for i in players.size():
		if is_ai(i):
			continue
		var map: Dictionary = _input_map_for(i)
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
	if _telemetry != null:
		_telemetry.record("super_toggled", turn, {"player": i + 1, "armed": super_armed[i]})


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
	if _telemetry != null:
		_telemetry.record("undo", turn, {"player": i + 1})


## Throws the movement recording away and refills stamina. The shot goes with
## it, because its tick indexes into the path that just disappeared.
func _reset_path(i: int) -> void:
	if state != Phase.PLANNING or not players[i].alive:
		return
	players[i].plan.confirmed = false
	_reset_pilot(i)
	if _telemetry != null:
		_telemetry.record("path_reset", turn, {"player": i + 1})


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
	if _telemetry != null:
		_telemetry.record("plan_locked", turn, {
			"player": i + 1,
			"movement_ticks": p.plan.recorded_ticks(),
			"shot_tick": p.plan.shot_tick,
			"power": snappedf(p.plan.power, 0.01),
			"super": p.plan.super_shot,
			"live_knives": arrows.size(),
		})
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

func _poll_game_over_pad() -> void:
	for i in players.size():
		var pad: int = _pads[i]
		if pad < 0:
			continue
		var rematch_pressed := _pad_edge(i, pad, JOY_BUTTON_A)
		var replay_pressed := _pad_edge(i, pad, JOY_BUTTON_Y)
		var report_pressed := _pad_edge(i, pad, JOY_BUTTON_X)
		var previous_pressed := _pad_edge(i, pad, JOY_BUTTON_DPAD_LEFT)
		var next_pressed := _pad_edge(i, pad, JOY_BUTTON_DPAD_RIGHT)
		if replay_pressed:
			_start_match_replay()
			return
		if report_pressed:
			copy_match_report()
			return
		if rematch_pressed:
			_request_rematch()
			return
		if previous_pressed:
			_cycle_rematch_level(-1)
		elif next_pressed:
			_cycle_rematch_level(1)


func _poll_replay_pad() -> void:
	for i in players.size():
		var pad: int = _pads[i]
		if pad < 0:
			continue
		var a := _pad_edge(i, pad, JOY_BUTTON_A)
		var b := _pad_edge(i, pad, JOY_BUTTON_B)
		var y := _pad_edge(i, pad, JOY_BUTTON_Y)
		if a or b or y:
			_finish_match_replay()
			return


func _prime_game_over_pad_state() -> void:
	# A may still be held from the final jump. Seed result-screen edges so that
	# carrying a gameplay button through the kill never starts an instant rematch.
	for i in players.size():
		var pad: int = _pads[i]
		if pad < 0:
			continue
		for button in [JOY_BUTTON_A, JOY_BUTTON_X, JOY_BUTTON_Y,
				JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
			_pad_btn_prev[i][button] = Input.is_joy_button_pressed(pad, button)


func _poll_planning_input(delta: float) -> void:
	var mouse := get_viewport().get_mouse_position()
	var mouse_moved: bool = mouse.distance_to(_prev_mouse) > 0.5
	_prev_mouse = mouse

	for i in players.size():
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
	var touch_player := _touch_player()
	if _held(map["left"]) or _pad_left(pad) or (i == touch_player and _touch_controls.left_held):
		dir -= 1
	if _held(map["right"]) or _pad_right(pad) or (i == touch_player and _touch_controls.right_held):
		dir += 1
	# On touch, walking establishes the natural default facing. A deliberate
	# right-side aim gesture latches the bow, so walking the other way afterwards
	# cannot flip the shot.
	if i == touch_player and _touch_controls.enabled and dir != 0 \
			and not _touch_controls.aim_latched:
		players[i].plan.set_aim_side(dir)

	var jump_now: bool = _jump_input_held(i)
	var jump_edge: bool = jump_now and not _jump_prev[i]
	_jump_prev[i] = jump_now

	var wait_held: bool = _held(map["wait"]) or _pad_down(pad) \
		or (i == touch_player and _touch_controls.wait_held)

	if charging[i] or stamina[i] <= 0.0:
		_pilot_accum[i] = 0.0
		return

	# Down + jump goes DOWN. Checked before the jump so the two verbs sharing one
	# button never both fire, and only from the ground, because dropping through
	# a ledge you are not standing on is not a move anyone means to make.
	if jump_edge and wait_held and ghost_ground[i]:
		_pilot_step(i, dir, false, false, true)
		_pilot_accum[i] = 0.0
		return

	# A jump press must land on a tick even if nothing else is being held.
	if jump_edge and (ghost_ground[i] or ghost_air_jumps[i] > 0):
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


func _jump_input_held(i: int) -> bool:
	var map: Dictionary = _input_map_for(i)
	var pad: int = _pads[i]
	var touch_jump := _touch_controls != null and i == _touch_player() \
		and _touch_controls.jump_held
	return _held(map["jump"]) \
		or (pad >= 0 and Input.is_joy_button_pressed(pad, JOY_BUTTON_A)) \
		or touch_jump


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
	var touch_driven := i == _touch_player() and _touch_controls.enabled
	# Browsers emulate a mouse cursor from the most recent finger. Without this
	# arbitration, dragging the left joystick can replace a rightward touch aim
	# with the joystick's screen position and silently flip the shot left.
	if touch_driven and aim_source[i] == AimSrc.MOUSE:
		aim_source[i] = AimSrc.TOUCH

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
	elif i == _touch_player() and _touch_controls.aim_active:
		aim_source[i] = AimSrc.TOUCH
	elif i == (online_player if online_mode else 0) \
			and should_accept_mouse_aim(_touch_controls.enabled, mouse_moved):
		aim_source[i] = AimSrc.MOUSE

	# --- apply it ---
	match aim_source[i]:
		AimSrc.PAD:
			if stick.length() > stick_deadzone:
				p.plan.set_aim_from_vector(stick, aim_min_angle, aim_max_angle)
		AimSrc.MOUSE:
			if not _touch_controls.enabled:
				# Measured from the ghost, because that is where the shot leaves from.
				p.plan.set_aim_from_vector(get_global_mouse_position() \
					- Player.shoulder_at(shot_origin(i)),
					aim_min_angle, aim_max_angle)
		AimSrc.TOUCH:
			if _touch_controls.aim_active:
				p.plan.set_aim_from_vector(_touch_controls.aim_position \
					- Player.shoulder_at(shot_origin(i)),
					aim_min_angle, aim_max_angle)
		AimSrc.KEYS:
			if key_dir != 0.0:
				p.plan.set_elevation(p.plan.elevation() + key_dir * aim_rate * delta,
					aim_min_angle, aim_max_angle)


static func should_accept_mouse_aim(touch_enabled: bool, mouse_moved: bool) -> bool:
	return mouse_moved and not touch_enabled


func _poll_charge(i: int, delta: float) -> void:
	var p: Player = players[i]
	var map: Dictionary = _input_map_for(i)
	var pad: int = _pads[i]

	var held: bool = _held(map["charge"]) or (i == _touch_player() and _touch_controls.charge_held)
	if i == (online_player if online_mode else 0) \
			and not _touch_controls.has_active_touches() \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
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


## Undocumented F7 easter egg. Once activated, every ordinary throw in the
## current local match uses the three-knife pattern for every player.
func _activate_secret_triple_match() -> void:
	if online_mode:
		return
	_secret_triple_match = true
	for p: Player in players:
		p.queue_redraw()
	_rebuild_ghost_paths()


## Restored playtest shortcut: F8 fills P1; Shift+F8 fills P2.
func _fill_test_super(second_player: bool) -> void:
	var who := 1 if second_player else 0
	if who < 0 or who >= players.size():
		return
	super_meter[who] = 1.0
	super_armed[who] = false
	players[who].queue_redraw()
	banner_text = "PLAYER %d — SUPER READY (TEST)" % (who + 1)
	banner_color = PLAYER_COLORS[who].lightened(0.35)
	banner_time = 1.4


func _report_online_match_over() -> void:
	if not online_mode or _online_match_reported or winner < 0:
		return
	_online_match_reported = true
	_online_client.send_match_over(turn, winner, _online_state_digest())


func _begin_match_telemetry(mode: String) -> void:
	if _telemetry == null:
		return
	var input_name := "touch" if _touch_controls.enabled else \
		("gamepad" if not _pads.is_empty() and _pads[0] >= 0 else "keyboard_mouse")
	_telemetry.begin_match(mode, level_name,
		"close" if prototype_mode else "wide", input_name)
	_telemetry_finished = false


func _finish_match_telemetry() -> void:
	if _telemetry == null or _telemetry_finished:
		return
	_telemetry_finished = true
	_telemetry.finish_match(winner, score, turn, _online_state_digest())


func copy_match_report() -> bool:
	if _telemetry == null or not _telemetry.copy_latest_to_clipboard():
		banner_text = "NO REPORT YET"
		banner_color = Color(0.72, 0.66, 0.82)
		banner_time = 1.2
		return false
	banner_text = "MATCH REPORT COPIED"
	banner_color = Color(0.62, 0.95, 0.72)
	banner_time = 1.4
	return true


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
		parts.append("p%d:%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d" % [
			i,
			int(round(p.position.x * 10000.0)), int(round(p.position.y * 10000.0)),
			int(round(p.vel.x * 10000.0)), int(round(p.vel.y * 10000.0)),
			1 if p.on_ground else 0, p.air_jumps_left,
			p.drop_ticks, int(round(p.drop_from_y * 10000.0)),
			1 if p.alive else 0, p.invuln_turns,
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
	parts.append("world:%d" % world_tick)
	for i in hazards.size():
		parts.append("h%d:%s" % [i, hazards[i].lockstep_digest_fragment()])
	parts.append("core:%d,%d,%d,%d,%d,%d,%d" % [
		1 if core_announced else 0, 1 if core_active else 0, core_turns_left,
		hitless_execution_streak,
		int(round(core_position.x * 10000.0)), int(round(core_position.y * 10000.0)),
		1 if _core_collected_this_execution else 0,
	])
	return "|".join(parts).sha256_text()


func _clamp_planning_timer() -> void:
	planning_time_left = minf(planning_time_left, planning_duration)
