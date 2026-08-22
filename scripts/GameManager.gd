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
const TUTORIAL_SCRIPT := preload("res://scripts/TutorialLayer.gd")
const TELEMETRY_SCRIPT := preload("res://scripts/Telemetry.gd")
const TRANSITION_SCRIPT := preload("res://scripts/TransitionLayer.gd")
const FIGHTER_VISUAL_SCRIPT := preload("res://scripts/FighterVisual.gd")
const FIGHTER_SKIN_SCRIPT := preload("res://scripts/FighterSkin.gd")
const DASHBLADE_SCRIPT := preload("res://scripts/Dashblade.gd")
const CHAKRAM_SCRIPT := preload("res://scripts/Chakram.gd")
const SHOCK_PLASMA_SCRIPT := preload("res://scripts/ShockPlasma.gd")
const SHOCK_ORB_SCRIPT := preload("res://scripts/ShockOrb.gd")
const CHARACTER_SELECT_SCRIPT := preload("res://scripts/CharacterSelectLayer.gd")
const TEAM_SELECT_SCRIPT := preload("res://scripts/TeamSelectLayer.gd")

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
const DEFAULT_HITS_TO_WIN := 5
const MAX_HITS_TO_WIN := 7
const PLAYER_COLORS := [
	Color(0.96, 0.69, 0.18),
	Color(0.76, 0.30, 1.00),
	Color(0.18, 0.82, 0.92),
	Color(1.00, 0.32, 0.42),
]
const TEAM_COLORS := [Color(0.93, 0.19, 0.28), Color(0.16, 0.66, 0.98)]
const TEAM_NAMES := ["CRIMSON", "AZURE"]

enum AimSrc { MOUSE, PAD, KEYS, TOUCH }
## Ids are append-only and id 1 stays vacant where the retired Grenadier sat,
## so old captures and telemetry cannot silently reinterpret a kit.
enum Weapon { KNIVES = 0, DASHBLADE = 2, CHAKRAM = 3, SHOCK = 4 }

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
@export_range(3, MAX_HITS_TO_WIN, 2) var hits_to_win: int = DEFAULT_HITS_TO_WIN
@export var respawn_invuln_turns: int = 1
@export var banner_duration: float = 2.4

@export_group("Visuals")
## Technical Gate 1 harness. Keep disabled until an art-approved skin exists;
## false preserves the original stick renderer exactly.
@export var fighter_visuals_enabled: bool = false
## Launch-only art review mode. P1 receives the simplified Executor while
## opponents retain the legacy renderer until their own silhouettes exist.
var simplified_fighter_proto_enabled: bool = false

@export_group("Replay")
## The match replay concatenates execution ticks only: planning, commit delays
## and SUPER introductions are deliberately absent. Retaining only the latest
## stretch keeps a very long, hitless match from growing memory without limit.
@export_range(0.25, 4.0, 0.05) var replay_speed: float = 1.5
@export_range(10.0, 120.0, 5.0) var replay_history_seconds: float = 30.0

@export_group("Loop Timing")
@export var planning_duration: float = 5.0
## Turns 1-3 use the authored window. Each later turn loses half a second until
## this floor. Multi-bot searches intentionally return the best candidate they
## have evaluated when the clock expires, so this is a gameplay-quality floor,
## not a promise that every exhaustive search finishes on every arena.
@export var planning_shrink_after_rounds: int = 3
@export var planning_shrink_per_round: float = 0.5
@export var minimum_planning_duration: float = 3.5
@export var execution_duration: float = 0.75
@export var commit_delay: float = 0.25

@export_group("Movement")
## Seconds of piloted control per turn. The rest of the window coasts.
@export var movement_budget: float = 0.50
## Ghost piloting runs at this fraction of real time — below 1.0 for precision.
@export var pilot_time_scale: float = 0.5
@export var player_move_speed: float = 260.0
## Locomotion is part of each prototype's identity. These scales multiply the
## shared authored values above/below so the free-play tuning sandbox still
## moves the whole roster together while preserving the differences between
## fighters.
##
## Approximate full-jump rises at the default 780 impulse / 1400 gravity:
## Dagger 217px, Velocity 0px, Static Witch 176px, Broodtail 263px.
@export_group("Class Movement")
@export_subgroup("Dagger Duelist")
@export_range(0.1, 2.0, 0.05) var dagger_move_speed_scale: float = 1.0
@export_range(0.0, 2.0, 0.05) var dagger_jump_impulse_scale: float = 1.0
@export_range(0.0, 2.0, 0.05) var dagger_air_jump_impulse_scale: float = 0.82
@export_range(0, 2, 1) var dagger_air_jumps: int = 1
@export_range(0.1, 2.0, 0.05) var dagger_fall_speed_scale: float = 1.0

@export_subgroup("The Velocity")
@export_range(0.1, 2.0, 0.05) var velocity_move_speed_scale: float = 0.90
## Velocity has no ordinary jump. Her freely aimed CUT TO END is her vertical
## traversal verb, and the faster fall keeps a missed aerial cut committal.
@export_range(0.0, 2.0, 0.05) var velocity_jump_impulse_scale: float = 0.0
@export_range(0.0, 2.0, 0.05) var velocity_air_jump_impulse_scale: float = 0.0
@export_range(0, 2, 1) var velocity_air_jumps: int = 0
@export_range(0.1, 2.0, 0.05) var velocity_fall_speed_scale: float = 1.10

@export_subgroup("The Static Witch")
@export_range(0.1, 2.0, 0.05) var shock_move_speed_scale: float = 0.90
@export_range(0.0, 2.0, 0.05) var shock_jump_impulse_scale: float = 0.90
@export_range(0.0, 2.0, 0.05) var shock_air_jump_impulse_scale: float = 0.0
@export_range(0, 2, 1) var shock_air_jumps: int = 0
@export_range(0.1, 2.0, 0.05) var shock_fall_speed_scale: float = 0.85

@export_subgroup("Broodtail")
@export_range(0.1, 2.0, 0.05) var chakram_move_speed_scale: float = 1.05
@export_range(0.0, 2.0, 0.05) var chakram_jump_impulse_scale: float = 1.10
@export_range(0.0, 2.0, 0.05) var chakram_air_jump_impulse_scale: float = 0.72
@export_range(0, 2, 1) var chakram_air_jumps: int = 1
@export_range(0.1, 2.0, 0.05) var chakram_fall_speed_scale: float = 0.90

@export_group("Movement")
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

@export_group("Character Prototypes")
@export var dash_speed_min: float = 660.0
@export var dash_speed_max: float = 980.0
@export var dash_duration_ticks_min: int = 8
@export var dash_duration_ticks_max: int = 15
@export var dash_guard_durability: int = 2
@export_range(0.0, 1.0, 0.01) var dash_exit_momentum_retention: float = 0.28
## Velocity moves at nine tenths of the shared pace. The horizontal distance
## denied by that ratio becomes Frame Debt: every completed cell adds one dash
## tick, and a full three-cell cut adds one front-parry point.
@export_range(1, 6, 1) var frame_debt_max_cells: int = 3
@export_range(1.0, 32.0, 0.25) var frame_debt_distance_per_cell: float = 2.75
@export_range(0, 4, 1) var frame_debt_dash_ticks_per_cell: int = 1
@export_range(0, 3, 1) var frame_debt_full_guard_bonus: int = 1
@export var chakram_speed_min: float = 200.0
@export var chakram_speed_max: float = 360.0
## The normal throw follows the committed aim exactly.
@export var shock_plasma_speed_min: float = 860.0
@export var shock_plasma_speed: float = 1160.0
@export var shock_plasma_range_min: float = 320.0
@export var shock_plasma_range_partial_max: float = 1040.0
@export var shock_plasma_range_full: float = 1440.0
@export var shock_orb_speed_min: float = 280.0
@export var shock_orb_speed_max: float = 520.0
@export var shock_orb_arm_ticks: int = 30
@export var shock_small_radius: float = 84.0
@export var shock_combo_radius_min: float = 190.0
@export var shock_combo_radius: float = 280.0
@export var shock_small_impulse: float = 460.0
@export var shock_combo_impulse: float = 980.0
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

@export_group("Knife Terrain Ricochet")
@export var knife_ricochet_min_speed: float = 560.0
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
var respawn_points: Array[Vector2] = []
var _last_respawn_choice: Array[int] = [-1, -1, -1, -1]
var score: Array[int] = [0, 0, 0, 0]
var team_mode: bool = false
var player_teams: Array[int] = [-1, -1, -1, -1]
var team_score: Array[int] = [0, 0]
var winning_team: int = -1
var player_roles: Array[String] = ["HUMAN", "AI", "AI", "AI"]
var player_devices: Array[int] = [-2, -1, -1, -1]

var banner_text: String = ""
var banner_color: Color = Color.WHITE
var banner_time: float = 0.0

var rng := RandomNumberGenerator.new()
var _ai_think: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _ai_searches: Array = [null, null, null, null]
var _ai_step_cursor: int = 0
var _menu
var _character_select: CharacterSelectLayer
var _team_select: TeamSelectLayer
var _tuning
var planning_time_left: float = 0.0
var planning_window_duration: float = 5.0
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
const REPLAY_COMPACTION_SLACK_SECONDS := 2.0

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
var dashblades: Array = []
var chakrams: Array = []
var shock_plasmas: Array = []
var shock_orbs: Array = []
var player_weapons: Array[int] = [Weapon.KNIVES, Weapon.KNIVES, Weapon.KNIVES, Weapon.KNIVES]
var local_weapon_choices: Array[int] = [Weapon.KNIVES, Weapon.KNIVES, Weapon.KNIVES, Weapon.KNIVES]
var _character_select_player_count: int = 2
var _character_select_vs_ai: bool = false
var _character_select_freeplay: bool = false
var _next_volley: int = 1
var _next_arrow_id: int = 1
var _next_character_projectile_id: int = 100000

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
## Attack captured when a charge begins. Shock uses 0 for LMB plasma and 1 for
## RMB orb; other kits leave this at zero.
var charge_attack_mode: Array[int] = [0, 0, 0, 0]
var stamina: Array[float] = [0.0, 0.0, 0.0, 0.0]
## Persistent for the whole match. It only resets when the super is actually
## released (or the match restarts), not between turns or after taking a hit.
var super_meter: Array[float] = [0.0, 0.0, 0.0, 0.0]
## A full meter is only spent when the player explicitly toggles SUPER on
## before placing the shot. The choice persists between turns until changed or
## the burst is actually released.
var super_armed: Array[bool] = [false, false, false, false]
## Completed Lost Frame cells plus the sub-cell distance progress, retained
## between turns. Progress is stored as thousandths of a pixel so lockstep state
## never depends on repeatedly adding an imprecise display float.
var frame_debt_cells: Array[int] = [0, 0, 0, 0]
var frame_debt_units: Array[int] = [0, 0, 0, 0]
## CUT TO END locks earning for the rest of that execution, preventing an early
## dash from immediately reloading itself through its remaining movement plan.
## Free Play has no turn boundary and deliberately ignores this lock.
var frame_debt_locked: Array[bool] = [false, false, false, false]

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
## Combat-free copies of dashes that crossed a time-stop boundary. They advance
## with the piloted ghost so ignored inputs and exit momentum match execution.
var ghost_dash: Array = [null, null, null, null]
## Recorded path plus the coasted tail — always exactly one full window long.
var ghost_path: Array[PackedVector2Array] = [
	PackedVector2Array(), PackedVector2Array(), PackedVector2Array(), PackedVector2Array(),
]
## A player's prediction depends only on frozen world state and that player's
## recorded movement. Most planning frames change neither, so rebuild lazily.
var _ghost_path_dirty: Array[bool] = [true, true, true, true]

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


func _exit_tree() -> void:
	for pending_dash in ghost_dash:
		if pending_dash != null and is_instance_valid(pending_dash):
			pending_dash.free()


func _ready() -> void:
	if "--simplified-fighter-proto" in OS.get_cmdline_user_args():
		simplified_fighter_proto_enabled = true
		fighter_visuals_enabled = true
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
	_menu.character_select_requested.connect(_on_menu_character_select)
	_menu.team_battle_requested.connect(_on_menu_team_battle)
	_menu.roster_select_requested.connect(_on_menu_roster_select)
	_menu.configured_match_requested.connect(_on_menu_configured_match)
	_menu.freeplay_requested.connect(_on_menu_freeplay)
	_menu.online_requested.connect(_on_menu_online)
	_menu.tutorial_requested.connect(_on_menu_tutorial)
	_menu.option_changed.connect(_on_option_changed)
	_menu.ui_navigated.connect(func(): _sfx.play("ui_move"))
	_menu.ui_accepted.connect(func(): _sfx.play("ui_accept"))

	_character_select = CHARACTER_SELECT_SCRIPT.new()
	add_child(_character_select)
	_character_select.selection_confirmed.connect(_on_local_character_selection)
	_character_select.canceled.connect(_on_character_select_canceled)
	_character_select.ui_navigated.connect(func(): _sfx.play("ui_move"))
	_character_select.ui_accepted.connect(func(): _sfx.play("ui_accept"))

	_team_select = TEAM_SELECT_SCRIPT.new()
	add_child(_team_select)
	_team_select.formation_confirmed.connect(_on_team_formation_confirmed)
	_team_select.canceled.connect(_on_team_select_canceled)
	_team_select.ui_navigated.connect(func(): _sfx.play("ui_move"))
	_team_select.ui_accepted.connect(func(): _sfx.play("ui_accept"))

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

	_load_level(0)
	_spawn_players()
	_tuning.build(self)
	_tuning.visible = false
	_load_settings()
	_menu.configure_options(_settings)
	_assign_pads()
	Input.joy_connection_changed.connect(func(_d, _c):
		_assign_pads()
		if _menu != null:
			_menu.refresh_controller_assignments()
		if _team_select != null:
			_team_select.refresh_connections())
	_prev_mouse = get_viewport().get_mouse_position()
	_begin_planning(true)
	_open_menu()


func is_ai(i: int) -> bool:
	return not online_mode and i >= 0 and i < players.size() \
		and i < player_roles.size() and player_roles[i] == "AI"


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
	if _character_select != null:
		_character_select.close()
	if _team_select != null:
		_team_select.close()
	_menu.open()
	if _transition != null:
		_transition.play("ZAWARUDO", "TIME AWAITS", PLAYER_COLORS[0], reduced_flashes)


func _on_menu_character_select() -> void:
	team_mode = false
	_open_character_select(2, false, false, ["HUMAN", "HUMAN"])


func _on_menu_team_battle() -> void:
	tutorial_mode = false
	online_mode = false
	online_player = -1
	team_mode = true
	state = Phase.TEAM_SELECT
	_ui.visible = false
	_tuning.visible = false
	_menu.close()
	_character_select.close()
	if _transition != null:
		_transition.visible = false
	_team_select.open(_menu.level)


func _on_team_formation_confirmed(slots: Array, selected_level: int) -> void:
	if slots.size() != MAX_PLAYERS:
		return
	for i in MAX_PLAYERS:
		var slot: Dictionary = slots[i]
		player_roles[i] = str(slot["role"])
		player_devices[i] = int(slot["device"])
		player_teams[i] = int(slot["team"])
	_menu.level = posmod(selected_level, Levels.count())
	var roles: Array[String] = []
	for i in MAX_PLAYERS:
		roles.append(("CRIMSON" if player_teams[i] == 0 else "AZURE") + " · " + player_roles[i])
	_team_select.close()
	_character_select_player_count = MAX_PLAYERS
	_character_select_vs_ai = true
	_character_select_freeplay = false
	state = Phase.CHARACTER_SELECT
	_character_select.open(local_weapon_choices, MAX_PLAYERS, roles, true, player_roles)


func _on_team_select_canceled() -> void:
	team_mode = false
	state = Phase.MENU
	_team_select.close()
	_menu.open()
	_menu._show_local_menu()


func _on_menu_roster_select(requested_players: int, freeplay: bool) -> void:
	team_mode = false
	var count := 2 if freeplay else clampi(requested_players, 2, MAX_PLAYERS)
	var slot_roles: Array[String] = ["HUMAN"]
	for i in range(1, count):
		slot_roles.append("DUMMY" if freeplay else "AI")
	_open_character_select(count, not freeplay, freeplay, slot_roles)


func _on_menu_configured_match(config: Dictionary) -> void:
	var mode := int(config.get("mode", MENU_SCRIPT.BattleMode.VS))
	var count := clampi(int(config.get("player_count", 2)), 2, MAX_PLAYERS)
	var weapons: Array = config.get("weapons", [])
	var roles: Array = config.get("roles", [])
	if mode == MENU_SCRIPT.BattleMode.FREE_PLAY:
		_start_freeplay(int(config.get("level", 0)), weapons, count,
			config.get("roles", []), config.get("devices", []))
		return
	team_mode = mode == MENU_SCRIPT.BattleMode.TEAM_BATTLE
	_start_local_match(roles.has("AI"),
		int(config.get("level", 0)), count, weapons, config)


func _open_character_select(count: int, ai: bool, freeplay: bool, slot_roles: Array) -> void:
	tutorial_mode = false
	online_mode = false
	online_player = -1
	_character_select_player_count = clampi(count, 2, MAX_PLAYERS)
	_character_select_vs_ai = ai
	_character_select_freeplay = freeplay
	state = Phase.CHARACTER_SELECT
	_ui.visible = false
	_tuning.visible = false
	_menu.close()
	if _transition != null:
		_transition.visible = false
	_character_select.open(local_weapon_choices, _character_select_player_count, slot_roles)


func _on_local_character_selection(weapons: Array) -> void:
	for i in _character_select_player_count:
		local_weapon_choices[i] = _roster_weapon_or_default(int(weapons[i]))
	_character_select.close()
	if _character_select_freeplay:
		_start_freeplay(_menu.level, weapons)
	else:
		_start_local_match(_character_select_vs_ai, _menu.level,
			_character_select_player_count, weapons)


func _on_character_select_canceled() -> void:
	if team_mode:
		state = Phase.TEAM_SELECT
		_character_select.close()
		_team_select.open(_menu.level)
		return
	state = Phase.MENU
	_menu.open()
	_menu._show_local_menu()


func _on_menu_start(ai: bool, lvl: int, requested_players: int = 2) -> void:
	team_mode = false
	_start_local_match(ai, lvl, requested_players, [])


func _start_local_match(ai: bool, lvl: int, requested_players: int, weapons: Array,
		setup: Dictionary = {}) -> void:
	tutorial_mode = false
	online_mode = false
	online_player = -1
	hits_to_win = clampi(_menu.match_lives, 3, MAX_HITS_TO_WIN)
	if not setup.is_empty():
		var configured_roles: Array = setup.get("roles", [])
		var configured_devices: Array = setup.get("devices", [])
		var configured_teams: Array = setup.get("teams", [])
		for i in MAX_PLAYERS:
			player_roles[i] = str(configured_roles[i]) if i < configured_roles.size() else "AI"
			player_devices[i] = int(configured_devices[i]) if i < configured_devices.size() else -1
			player_teams[i] = int(configured_teams[i]) if i < configured_teams.size() else -1
	elif not team_mode:
		winning_team = -1
		team_score = [0, 0]
		for i in MAX_PLAYERS:
			player_teams[i] = -1
			player_roles[i] = "HUMAN" if not ai or i == 0 else "AI"
			player_devices[i] = -2 if i == 0 else -1
	vs_ai = player_roles.has("AI") if not setup.is_empty() or team_mode else ai
	player_weapons.fill(Weapon.KNIVES)
	if not weapons.is_empty():
		for i in mini(requested_players, weapons.size()):
			player_weapons[i] = _roster_weapon_or_default(int(weapons[i]))
	elif not ai and requested_players == 2:
		player_weapons[0] = local_weapon_choices[0]
		player_weapons[1] = local_weapon_choices[1]
	_set_player_count(requested_players)
	_ui.visible = true
	_tuning.visible = false
	_menu.close()
	_character_select.close()
	_load_level(lvl)
	restart()
	_sfx.play("title")
	var team_shape := "%dv%d" % [
		int(ceil(float(requested_players) / 2.0)), int(requested_players / 2),
	]
	var telemetry_mode := "local_team_%s" % team_shape if team_mode else \
		"ai_wide" if ai else \
		("local_2p_%s_%s" % [weapon_short_name(0).to_lower(), weapon_short_name(1).to_lower()] \
		if requested_players == 2 else "local_%dp" % requested_players)
	_begin_match_telemetry(telemetry_mode)
	var matchup := "CRIMSON VS AZURE // %s" % team_shape.to_upper() if team_mode else \
		("%dP ROSTER" % requested_players if requested_players > 2 else \
		("VS AI" if ai else "%s VS %s" % [weapon_short_name(0), weapon_short_name(1)]))
	_transition.play("%s // %s" % [matchup, level_name],
		"WRITE THE MOVE", PLAYER_COLORS[0], reduced_flashes)


func _on_menu_tutorial() -> void:
	team_mode = false
	tutorial_mode = true
	online_mode = false
	online_player = -1
	state = Phase.TUTORIAL
	_ui.visible = false
	_tuning.visible = false
	_menu.close()
	_tutorial.start(self)
	_transition.visible = false


func _on_menu_online(lvl: int) -> void:
	team_mode = false
	tutorial_mode = false
	_menu.close()
	_ui.visible = false
	_tuning.visible = false
	state = Phase.ONLINE_LOBBY
	_online_lobby.open(lvl, local_weapon_choices[0])
	_transition.play("ONLINE DUEL", "PRIVATE PLANS", PLAYER_COLORS[1], reduced_flashes)


func _on_online_create(lvl: int, weapon: int) -> void:
	_online_lobby.set_status("CREATING PRIVATE ROOM…", false)
	_online_client.create_room(lvl, weapon)


func _on_online_join(code: String, weapon: int) -> void:
	_online_client.join_room(code, weapon)


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
				int(message.get("seed", 0)), int(message.get("turn", 1)),
				message.get("weapons", [Weapon.KNIVES, Weapon.KNIVES]))
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


func _start_online_match(lvl: int, seed_value: int, server_turn: int,
		weapons: Array = [Weapon.KNIVES, Weapon.KNIVES]) -> void:
	if server_turn != 1:
		# Live reconnects retain their local simulation. A full page reload cannot
		# safely reconstruct an in-progress match from only the current turn.
		if online_mode:
			return
		_online_lobby.set_status("ROOM ALREADY HAS A MATCH IN PROGRESS", true)
		return
	online_mode = true
	vs_ai = false
	hits_to_win = DEFAULT_HITS_TO_WIN
	player_weapons.fill(Weapon.KNIVES)
	for i in mini(2, weapons.size()):
		player_weapons[i] = _roster_weapon_or_default(int(weapons[i]))
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
	# The same cap the room service enforces. Both ends derive it from the
	# movement budget, so neither can accept a recording the other rejects.
	var max_recorded := mini(exec_ticks(), movement_tick_budget())
	if dirs.size() > max_recorded:
		return "movement has %d ticks; maximum is %d" % [dirs.size(), max_recorded]
	var shot_tick := int(data.get("shot_tick", -1))
	if shot_tick < -1 or shot_tick > dirs.size():
		return "shot tick %d is outside the recording" % shot_tick
	var attack_mode := int(data.get("attack_mode", 0))
	if attack_mode < 0 or attack_mode > 1:
		return "attack mode %d is outside 0..1" % attack_mode
	if bool(data.get("super_shot", false)) and (shot_tick < 0 or super_meter[i] < 1.0):
		return "SUPER was requested without a legal charged shot"
	return ""


## Free play: no turns, no freeze. One player under continuous control so the
## movement and shooting can be judged by feel, with the tuning values editable
## live. Whatever you set here is what the real match uses afterwards.
func _on_menu_freeplay(lvl: int) -> void:
	team_mode = false
	_start_freeplay(lvl, [])


func _start_freeplay(lvl: int, weapons: Array, requested_players: int = 2,
		configured_roles: Array = [], configured_devices: Array = []) -> void:
	team_mode = false
	winning_team = -1
	team_score = [0, 0]
	for i in MAX_PLAYERS:
		player_teams[i] = -1
		player_roles[i] = str(configured_roles[i]) if i < configured_roles.size() else \
			("HUMAN" if i == 0 else "DUMMY")
		player_devices[i] = int(configured_devices[i]) if i < configured_devices.size() else \
			(-2 if i == 0 else -1)
	tutorial_mode = false
	online_mode = false
	online_player = -1
	vs_ai = false
	player_weapons.fill(Weapon.KNIVES)
	for i in mini(requested_players, weapons.size()):
		player_weapons[i] = _roster_weapon_or_default(int(weapons[i]))
	_menu.close()
	_ui.visible = false
	_tuning.visible = true
	_set_player_count(requested_players)
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
	_clear_character_projectiles()
	_effects.clear_all()
	_load_level(level_index)
	for i in players.size():
		var p: Player = players[i]
		p.fighter_style = player_weapons[i]
		p.clear_afterimages()
		p.position = spawns[i]
		p.vel = Vector2.ZERO
		p.on_ground = true
		p.air_jumps_left = air_jumps_for(i)
		p.drop_ticks = 0
		p.drop_from_y = 0.0
		p.alive = true
		p.invuln_turns = 0
		p.plan = PlayerPlan.new()
		p.plan.power = 0.5
		super_meter[i] = 0.0
		super_armed[i] = false
		frame_debt_cells[i] = 0
		frame_debt_units[i] = 0
		frame_debt_locked[i] = false
		p.queue_redraw()
	charging[0] = false
	_charge_t[0] = 0.0
	_jump_prev[0] = _jump_input_held(0)
	_reset_temporal_core()
	banner_time = 0.0


func _clear_character_projectiles() -> void:
	for group in [dashblades, chakrams, shock_plasmas, shock_orbs]:
		for entity in group:
			if is_instance_valid(entity):
				entity.queue_free()
	dashblades.clear()
	chakrams.clear()
	shock_plasmas.clear()
	shock_orbs.clear()


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


## Collision geometry paired with its material. Projectile previews need this
## richer view because HARD surfaces ricochet while breakable ones terminate and
## take damage; a flat rect list cannot express that difference.
func platform_colliders_at(abs_tick: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pf: Dictionary in platforms:
		var posed: Rect2 = pf["rect"] if abs_tick < 0 else platform_rect_at(pf, abs_tick)
		for rect: Rect2 in _seam_copies(posed):
			out.append({"rect": rect, "hp": int(pf.get("hp", -1))})
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
	var lv := Levels.build_tutorial() if tutorial_mode \
		else Levels.build(level_index, player_count)
	level_name = lv["name"]
	_backdrop.show_level(level_index)
	level_wrap = Levels.wrap_label(lv)
	rematch_level_index = level_index
	rematch_level_name = level_name
	wrap_x = lv["wrap_x"]
	wrap_y = lv["wrap_y"]
	platforms = lv["platforms"]
	_arena.configure_level(level_index, wrap_x, wrap_y)
	var sp: Array = lv["spawns"]
	for i in MAX_PLAYERS:
		spawns[i] = sp[i]
	respawn_points.clear()
	for point in lv.get("respawn_points", sp):
		respawn_points.append(point)
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
		h.dagger_launch_speed = float(spec.get("dagger_launch_speed", arrow_speed_max))
		h.recharge_windows = int(spec.get("recharge_windows", h.recharge_windows))
		h.sync_to_tick(world_tick)
		_hazard_layer.add_child(h)
		hazards.append(h)


func next_level() -> void:
	_load_level(level_index + 1)
	restart()   # also zeroes the score


func _spawn_players() -> void:
	for i in player_count:
		_add_player(i)
	_update_facing()


func _add_player(i: int) -> void:
	var p := Player.new()
	p.cfg = self
	p.index = i
	p.fighter_style = player_weapons[i]
	p.color = PLAYER_COLORS[i]
	p.position = spawns[i]
	p.on_ground = true
	p.air_jumps_left = air_jumps_for(i)
	p.plan.set_aim_from_vector(_default_aim_vector(i), aim_min_angle, aim_max_angle)
	p.plan.power = 0.55
	_player_layer.add_child(p)
	if fighter_visuals_enabled and (not simplified_fighter_proto_enabled or i == 0):
		var fighter_visual := FIGHTER_VISUAL_SCRIPT.new()
		fighter_visual.name = "FighterVisual"
		var fighter_skin = FIGHTER_SKIN_SCRIPT.simplified_executor_proof() \
			if simplified_fighter_proto_enabled else FIGHTER_SKIN_SCRIPT.executor_prototype(i)
		fighter_visual.configure(p, fighter_skin)
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
	if team_mode:
		for i in mini(players.size(), player_devices.size()):
			var device := player_devices[i]
			if device >= 0 and device in list and not is_ai(i):
				_pads[i] = device
		return
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


func uses_dashblade(i: int) -> bool:
	return i >= 0 and i < players.size() and player_weapons[i] == Weapon.DASHBLADE


func uses_chakram(i: int) -> bool:
	return i >= 0 and i < players.size() and player_weapons[i] == Weapon.CHAKRAM


func uses_shock(i: int) -> bool:
	return i >= 0 and i < players.size() and player_weapons[i] == Weapon.SHOCK


func can_pilot_move(i: int) -> bool:
	return i >= 0 and i < players.size()


func movement_speed_scale(i: int) -> float:
	if i < 0 or i >= player_weapons.size():
		return dagger_move_speed_scale
	match player_weapons[i]:
		Weapon.DASHBLADE:
			return velocity_move_speed_scale
		Weapon.CHAKRAM:
			return chakram_move_speed_scale
		Weapon.SHOCK:
			return shock_move_speed_scale
		_:
			return dagger_move_speed_scale


func jump_impulse_for(i: int) -> float:
	return jump_impulse * _class_movement_scale(i, "jump")


func air_jump_impulse_for(i: int) -> float:
	return jump_impulse * _class_movement_scale(i, "air_jump")


func air_jumps_for(i: int) -> int:
	if i < 0 or i >= player_weapons.size():
		return dagger_air_jumps
	match player_weapons[i]:
		Weapon.DASHBLADE: return velocity_air_jumps
		Weapon.CHAKRAM: return chakram_air_jumps
		Weapon.SHOCK: return shock_air_jumps
		_: return dagger_air_jumps


func max_fall_speed_for(i: int) -> float:
	return max_fall_speed * _class_movement_scale(i, "fall")


func _class_movement_scale(i: int, stat: String) -> float:
	var weapon := player_weapons[i] if i >= 0 and i < player_weapons.size() else Weapon.KNIVES
	match weapon:
		Weapon.DASHBLADE:
			match stat:
				"jump": return velocity_jump_impulse_scale
				"air_jump": return velocity_air_jump_impulse_scale
				_: return velocity_fall_speed_scale
		Weapon.CHAKRAM:
			match stat:
				"jump": return chakram_jump_impulse_scale
				"air_jump": return chakram_air_jump_impulse_scale
				_: return chakram_fall_speed_scale
		Weapon.SHOCK:
			match stat:
				"jump": return shock_jump_impulse_scale
				"air_jump": return shock_air_jump_impulse_scale
				_: return shock_fall_speed_scale
		_:
			match stat:
				"jump": return dagger_jump_impulse_scale
				"air_jump": return dagger_air_jump_impulse_scale
				_: return dagger_fall_speed_scale


func _frame_debt_threshold_units() -> int:
	return maxi(1, roundi(maxf(0.001, frame_debt_distance_per_cell) * 1000.0))


## Convert real horizontal displacement into the distance Velocity was denied
## by her class multiplier. At 90%, every nine travelled pixels represent one
## deleted pixel. Pressing into a wall earns nothing because no movement exists
## to edit out of the sequence.
func _frame_debt_units_between(i: int, from: Vector2, to: Vector2) -> int:
	var scale := movement_speed_scale(i)
	if scale <= 0.0 or scale >= 1.0:
		return 0
	var travelled := absf(wrap_delta(from, to).x)
	var missing_ratio := 1.0 / scale - 1.0
	return maxi(0, roundi(travelled * missing_ratio * 1000.0))


func _accrue_frame_debt(i: int, from: Vector2, to: Vector2, input_dir: int) -> void:
	if not uses_dashblade(i) or input_dir == 0 or frame_debt_cells[i] >= frame_debt_max_cells \
			or (frame_debt_locked[i] and state != Phase.FREEPLAY):
		return
	var total := frame_debt_units[i] + _frame_debt_units_between(i, from, to)
	var threshold := _frame_debt_threshold_units()
	var gained := total / threshold
	if gained <= 0:
		frame_debt_units[i] = total
		return
	frame_debt_cells[i] = mini(frame_debt_max_cells, frame_debt_cells[i] + gained)
	frame_debt_units[i] = 0 if frame_debt_cells[i] >= frame_debt_max_cells else total % threshold
	players[i].queue_redraw()


func _projected_frame_debt_from_path(i: int, path: PackedVector2Array,
		through_tick: int, input_at: Callable) -> int:
	if not uses_dashblade(i):
		return 0
	var threshold := _frame_debt_threshold_units()
	var total := frame_debt_cells[i] * threshold + frame_debt_units[i]
	var steps := mini(maxi(0, through_tick), maxi(0, path.size() - 1))
	for t in steps:
		if int(input_at.call(t)) != 0:
			total += _frame_debt_units_between(i, path[t], path[t + 1])
	return mini(frame_debt_max_cells, total / threshold)


## Planning preview counterpart to live accumulation. `ghost_path` is built by
## the same movement primitive as execution, so the promised dash endpoint also
## includes every cell that will exist before its chosen release tick.
func projected_frame_debt(i: int, through_tick: int = -1) -> int:
	if i < 0 or i >= players.size() or not uses_dashblade(i):
		return 0
	var pl: PlayerPlan = players[i].plan
	var limit := pl.recorded_ticks() if through_tick < 0 else through_tick
	return _projected_frame_debt_from_path(i, ghost_path[i], limit,
		func(t: int) -> int: return pl.dir_at(t))


func projected_frame_debt_for_constant_path(i: int, path: PackedVector2Array,
		through_tick: int, input_dir: int) -> int:
	return _projected_frame_debt_from_path(i, path, through_tick,
		func(_t: int) -> int: return input_dir)


func dash_frame_debt_spent(i: int) -> int:
	for dash in dashblades:
		if dash.active and dash.owner_index == i:
			return dash.frame_debt_spent
	return 0


func shock_orb_count(i: int) -> int:
	var count := 0
	for orb in shock_orbs:
		if orb.shooter == i:
			count += 1
	return count


func _roster_weapon_or_default(value: int) -> int:
	return value if value in [Weapon.KNIVES, Weapon.DASHBLADE, Weapon.SHOCK,
		Weapon.CHAKRAM] \
		else Weapon.KNIVES


func weapon_short_name(i: int) -> String:
	match player_weapons[i] if i >= 0 and i < player_weapons.size() else Weapon.KNIVES:
		Weapon.DASHBLADE: return "VELOCITY"
		Weapon.CHAKRAM: return "BROODTAIL"
		Weapon.SHOCK: return "STATIC WITCH"
		_: return "DUELIST"


func character_display_name(i: int) -> String:
	match player_weapons[i] if i >= 0 and i < player_weapons.size() else Weapon.KNIVES:
		Weapon.DASHBLADE: return "THE VELOCITY"
		Weapon.CHAKRAM: return "BROODTAIL"
		Weapon.SHOCK: return "THE STATIC WITCH"
		_: return "DAGGER DUELIST"


func chakram_launch_velocities(aim: Vector2, power: float,
		empowered: bool = false) -> Array[Vector2]:
	var direct := aim.normalized()
	if direct.is_zero_approx():
		direct = Vector2.RIGHT
	var speed := lerpf(chakram_speed_min, chakram_speed_max,
		clampf(power, 0.0, 1.0))
	var offsets := PackedFloat32Array([-14.0, 0.0, 14.0]) if empowered else \
		PackedFloat32Array([0.0])
	var launches: Array[Vector2] = []
	for offset in offsets:
		launches.append(direct.rotated(deg_to_rad(offset)) * speed)
	return launches


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
		var half_spread := knife_spread_for(power) * 0.5
		offsets.append(-half_spread)
		offsets.append(0.0)
		offsets.append(half_spread)
	var out: Array[Vector2] = []
	for off in offsets:
		out.append(base.rotated(deg_to_rad(off)))
	return out


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
			_tick_ai(delta)
			_update_facing()
			_refresh_dirty_ghost_paths()
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
				# The fixed tick, never the frame delta. The planning ghost is built
				# from tick_dt(), so execution has to integrate with the same number
				# or the plan the player committed to stops being the one that runs.
				_sim_tick(tick_dt())
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
				_super_freeze.play(p.index, p.color, player_weapons[p.index])
			_sfx.play("muda")
			return

	# Shots scheduled for this tick leave before anything moves.
	for p in players:
		if not p.alive or not p.plan.has_shot():
			continue
		if p.plan.super_shot:
			var since_launch: int = exec_tick - p.plan.shot_tick
			if player_weapons[p.index] == Weapon.KNIVES \
					and since_launch >= 0 and since_launch % maxi(1, super_wave_interval_ticks) == 0:
				var wave: int = since_launch / maxi(1, super_wave_interval_ticks)
				if wave < maxi(1, super_waves):
					_spawn_super_wave(p, wave)
			elif since_launch == 0:
				_spawn_character_super(p)
		elif p.plan.shot_tick == exec_tick:
			_spawn_player_attack(p)

	# The world advances first, so bodies resolve against the geometry as it
	# stands at the END of this tick and inherit the movement of whatever they
	# were standing on. `from_tick` is the tick they are leaving.
	var from_tick: int = world_tick
	world_tick += 1
	_apply_movers(world_tick)

	for p in players:
		if not _player_is_dashing(p.index):
			var move_from: Vector2 = p.position
			p.sim_step(dt, exec_tick, from_tick)
			_accrue_frame_debt(p.index, move_from, p.position, p.plan.dir_at(exec_tick))
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

	var was_dashing := _player_is_dashing(0)
	var move_from: Vector2 = p.position
	p.sim_free(delta, dir, jump_edge and not drop_now, jump_now and not drop_now, drop_now)
	if not was_dashing:
		_accrue_frame_debt(0, move_from, p.position, dir)
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
	var primary_held: bool = _held(K_P1["charge"]) or _touch_controls.charge_held
	var secondary_held: bool = uses_shock(0) and not _touch_controls.has_active_touches() \
		and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if not _touch_controls.has_active_touches() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		primary_held = true
	if _pads[0] >= 0 and Input.get_joy_axis(_pads[0], JOY_AXIS_TRIGGER_RIGHT) > trigger_threshold:
		primary_held = true
	var held: bool = secondary_held or primary_held
	if held:
		if not charging[0]:
			charging[0] = true
			_charge_t[0] = 0.0
			charge_attack_mode[0] = 1 if secondary_held and not primary_held else 0
			p.plan.attack_mode = charge_attack_mode[0]
		else:
			_charge_t[0] = minf(_charge_t[0] + delta, charge_time)
		p.plan.power = _charge_t[0] / charge_time
	elif charging[0]:
		charging[0] = false
		_spawn_player_attack(p)

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
	var hittable_players: Array = players.filter(func(p): return not _player_is_dashing(p.index))
	for a in arrows:
		var res: Dictionary = a.sim_step(dt, hittable_players)
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
	_step_dashblades(dt, survivors)
	_resolve_clashes(survivors)
	arrows = survivors
	_step_chakrams(dt)
	_step_shock_weapons(dt)
	if not damaged.is_empty():
		_apply_platform_damage(damaged)


func _player_is_dashing(player_index: int) -> bool:
	for dash in dashblades:
		if dash.active and dash.owner_index == player_index:
			return true
	return false


func _step_dashblades(dt: float, live_arrows: Array) -> void:
	var live: Array = []
	for dash in dashblades:
		var owner: Player = players[dash.owner_index]
		var from: Vector2 = dash.position
		var result: Dictionary = dash.sim_step(dt, live_arrows, players, platforms)
		owner.position = wrap_point(result["position"])
		owner.vel = result["velocity"]
		owner.queue_redraw()
		for victim: int in result["hit_fighters"]:
			_on_player_hit(victim, players[victim].position, dash.owner_index)
		for projectile in result["owner_hit_projectiles"]:
			if live_arrows.has(projectile):
				live_arrows.erase(projectile)
				projectile.queue_free()
				_on_player_hit(dash.owner_index, owner.position, projectile.shooter)
		for orb in shock_orbs.duplicate():
			var closest := Arrow.moving_points_closest(from, dash.position,
				orb.prev_pos, orb.position)
			if closest[0] > Dashblade.DEFAULT_GUARD_HALF_LENGTH + ShockOrb.COLLISION_RADIUS:
				continue
			if orb.is_armed():
				_detonate_shock_orb(orb, false, dash.owner_index)
			else:
				orb.vel = dash.velocity * 0.72
				orb.resting = false
				orb.support_platform = -1
		if result["stopped_by_hard"]:
			_effects.add(Effects.Kind.CLASH, owner.position, owner.color.lightened(0.45))
			_sfx.play("clash")
		if result["active"] and owner.alive:
			live.append(dash)
		else:
			dash.queue_free()
	dashblades = live


func _step_chakrams(dt: float) -> void:
	var live: Array = []
	for chakram in chakrams:
		var simulation_turn := -1 if state == Phase.FREEPLAY else turn
		var result: Dictionary = chakram.sim_step(dt, players, simulation_turn)
		if result["hit_player"] >= 0:
			_on_player_hit(result["hit_player"], chakram.position, chakram.shooter)
		if result.get("stuck", false):
			_effects.add(Effects.Kind.CLASH, chakram.position, chakram.color.lightened(0.35))
			_remember_aftermath("CHAKRAM STUCK", chakram.position, chakram.color)
			_sfx.play("thud")
		if result["alive"]:
			live.append(chakram)
		else:
			chakram.queue_free()
	chakrams = live

	# Any opposing dagger impact destroys the chakram; the dagger keeps its
	# trajectory. Stationary holding discs still participate through swept-point
	# contact, making them destructible during their extra arena turn.
	for chakram in chakrams.duplicate():
		for arrow: Arrow in arrows:
			if chakram.shooter == arrow.shooter \
					or not chakram.can_clash_with_projectile(arrow.stable_id()):
				continue
			var contact := Arrow.moving_points_closest(chakram.prev_pos, chakram.position,
				arrow.prev_pos, arrow.position)
			if contact[0] > Chakram.COLLISION_RADIUS + knife_clash_radius * 0.5:
				continue
			var clash: Dictionary = chakram.resolve_projectile_clash(arrow.vel, arrow.stable_id())
			if not clash["accepted"]:
				continue
			_effects.add(Effects.Kind.CLASH, chakram.position, chakram.color.lightened(0.4))
			_sfx.play("clash")
			if not clash["alive"]:
				chakrams.erase(chakram)
				chakram.queue_free()
			break

	# Opposing chakrams are projectiles too: direct disc-on-disc contact breaks
	# both instead of creating another reflection rule.
	var broken_chakrams: Array = []
	for i in chakrams.size():
		for j in range(i + 1, chakrams.size()):
			var a = chakrams[i]
			var b = chakrams[j]
			if a.shooter == b.shooter:
				continue
			var contact := Arrow.moving_points_closest(a.prev_pos, a.position,
				b.prev_pos, b.position)
			if contact[0] <= Chakram.COLLISION_RADIUS * 2.0:
				if not broken_chakrams.has(a): broken_chakrams.append(a)
				if not broken_chakrams.has(b): broken_chakrams.append(b)
	for chakram in broken_chakrams:
		if chakrams.has(chakram):
			chakrams.erase(chakram)
			chakram.queue_free()
			_effects.add(Effects.Kind.CLASH, chakram.position, chakram.color.lightened(0.4))
	if not broken_chakrams.is_empty():
		_sfx.play("clash")



func _step_shock_weapons(dt: float) -> void:
	# Expiration is a real small pop now, not a silent deletion. Iterate a copy
	# because detonation removes the orb and may redirect every other live shot.
	for orb in shock_orbs.duplicate():
		if not shock_orbs.has(orb):
			continue
		var result: Dictionary = orb.sim_step(dt)
		if not result["alive"] and result["expired"]:
			_detonate_shock_orb(orb, false, orb.shooter)
		elif not result["alive"]:
			shock_orbs.erase(orb)
			orb.queue_free()

	var live_plasma: Array = []
	for plasma in shock_plasmas:
		# Dash bodies are resolved together with their moving front guards below;
		# letting plasma hit the body first would make an interceptible bolt ignore
		# the blade merely because the integration order reached it later.
		var plasma_targets: Array = players.filter(
			func(player): return not _player_is_dashing(player.index))
		var result: Dictionary = plasma.sim_step(dt, plasma_targets)
		var dash_contact: Dictionary = {}
		for dash in dashblades:
			if not dash.active:
				continue
			var contact: Dictionary = dash.swept_projectile_contact(
				plasma.prev_pos, plasma.position, ShockPlasma.COLLISION_RADIUS)
			var first_time: float = minf(contact["guard_time"], contact["body_time"])
			if first_time < INF and (dash_contact.is_empty() \
					or first_time < float(dash_contact["time"])):
				dash_contact = {"dash": dash, "contact": contact, "time": first_time}
		if not dash_contact.is_empty():
			var struck_dash = dash_contact["dash"]
			var contact: Dictionary = dash_contact["contact"]
			var guard_first: bool = float(contact["guard_time"]) <= float(contact["body_time"])
			if guard_first and struck_dash.spend_guard():
				var parry_at: Vector2 = players[struck_dash.owner_index].position \
					+ struck_dash.direction * struck_dash.guard_offset
				_effects.add(Effects.Kind.CLASH, parry_at, plasma.color.lightened(0.25))
				_remember_aftermath("PLASMA PARRY", parry_at, plasma.color)
				_sfx.play("clash")
				plasma.queue_free()
				continue
			elif float(contact["body_time"]) < INF:
				_on_player_hit(struck_dash.owner_index,
					players[struck_dash.owner_index].position, plasma.shooter)
				plasma.queue_free()
				continue
		# Plasma continues through a chakram, but the disc itself is destroyed on
		# contact like it is by every other opposing projectile family.
		for chakram in chakrams.duplicate():
			if chakram.shooter == plasma.shooter:
				continue
			var contact := Arrow.moving_points_closest(plasma.prev_pos, plasma.position,
				chakram.prev_pos, chakram.position)
			if contact[0] <= ShockPlasma.COLLISION_RADIUS + Chakram.COLLISION_RADIUS:
				chakrams.erase(chakram)
				chakram.queue_free()
				_effects.add(Effects.Kind.CLASH, chakram.position, plasma.color)
				_sfx.play("clash")
		var combo_orb = null
		var combo_time := INF
		for orb in shock_orbs:
			var contact := Arrow.moving_points_closest(plasma.prev_pos, plasma.position,
				orb.prev_pos, orb.position)
			if contact[0] <= ShockPlasma.COLLISION_RADIUS + ShockOrb.COLLISION_RADIUS \
					and contact[3] < combo_time:
				var request: Dictionary = orb.request_plasma_hit(plasma.shooter)
				if request["detonate"]:
					combo_orb = orb
					combo_time = contact[3]
		var blocking_arrow = null
		var block_time := INF
		for arrow: Arrow in arrows:
			if arrow.shooter == plasma.shooter:
				continue
			var contact := Arrow.moving_points_closest(plasma.prev_pos, plasma.position,
				arrow.prev_pos, arrow.position)
			if contact[0] <= ShockPlasma.COLLISION_RADIUS + knife_clash_radius * 0.5 \
					and contact[3] < block_time:
				blocking_arrow = arrow
				block_time = contact[3]
		if blocking_arrow != null and block_time <= combo_time:
			_effects.add(Effects.Kind.CLASH, blocking_arrow.position, plasma.color)
			_sfx.play("clash")
			arrows.erase(blocking_arrow)
			blocking_arrow.queue_free()
			# One dagger attenuates the lance instead of buying an entire Witch turn.
			# The spent bolt can be intercepted again on a later tick, while a clean
			# single blade still strips most of its threat and range.
			plasma.vel *= 0.45
			live_plasma.append(plasma)
			continue
		if combo_orb != null:
			_detonate_shock_orb(combo_orb, true, plasma.shooter,
				plasma.charge_power, plasma)
			plasma.queue_free()
			continue
		if result["hit_player"] >= 0:
			_on_player_hit(result["hit_player"], result["contact_position"], plasma.shooter)
		if result["hit_platform"] >= 0:
			_effects.add(Effects.Kind.SPARK, result["contact_position"], plasma.color)
			_sfx.play("thud")
		if result["alive"]:
			live_plasma.append(plasma)
		else:
			plasma.queue_free()
	shock_plasmas = live_plasma

	# Ordinary projectiles can deny an armed orb for its small blast. Before
	# arming, contact merely bats both objects apart so setup cannot be erased by
	# an invisible exception.
	for orb in shock_orbs.duplicate():
		var trigger = null
		for arrow: Arrow in arrows:
			var contact := Arrow.moving_points_closest(arrow.prev_pos, arrow.position,
				orb.prev_pos, orb.position)
			if contact[0] <= ShockOrb.COLLISION_RADIUS + knife_clash_radius * 0.5:
				trigger = arrow
				break
		if trigger == null:
			for chakram in chakrams:
				var contact := Arrow.moving_points_closest(chakram.prev_pos, chakram.position,
					orb.prev_pos, orb.position)
				if contact[0] <= ShockOrb.COLLISION_RADIUS + Chakram.COLLISION_RADIUS:
					trigger = chakram
					break
		if trigger == null:
			continue
		if trigger is Chakram:
			chakrams.erase(trigger)
			trigger.queue_free()
		if orb.is_armed():
			_detonate_shock_orb(orb, false, trigger.shooter)
		else:
			orb.vel += trigger.vel * 0.28
			orb.resting = false
			orb.support_platform = -1
			if trigger is Arrow:
				trigger.deflect(trigger.vel * 0.55, knife_clash_spin,
					knife_clash_cooldown, orb.network_id)


func shock_plasma_speed_for_power(power: float) -> float:
	return lerpf(shock_plasma_speed_min, shock_plasma_speed, clampf(power, 0.0, 1.0))


func shock_plasma_range_for_power(power: float) -> float:
	var amount := clampf(power, 0.0, 1.0)
	# Full charge is a deliberate breakpoint: partial shots trade screen coverage
	# for speed of release, while only a completed draw crosses the whole arena.
	if amount >= 1.0:
		return shock_plasma_range_full
	return lerpf(shock_plasma_range_min, shock_plasma_range_partial_max,
		pow(amount, 1.35))


func shock_combo_radius_for_power(power: float) -> float:
	return lerpf(shock_combo_radius_min, shock_combo_radius, clampf(power, 0.0, 1.0))


func _detonate_shock_orb(orb, combo: bool, trigger_shooter: int,
		combo_power: float = 1.0, source_projectile = null) -> void:
	if not shock_orbs.has(orb):
		return
	var radius: float = shock_combo_radius_for_power(combo_power) \
		if combo else shock_small_radius
	var impulse: float = shock_combo_impulse if combo else shock_small_impulse
	# Opponents may deny the large combo with a regular hit, but they do not
	# steal ownership of the Witch's smaller trap. A plasma combo remains owned
	# by the fighter who supplied the plasma, enabling deliberate cross-Witch play.
	var scorer: int = trigger_shooter if combo and trigger_shooter >= 0 else orb.shooter
	var blast_color: Color = Color(0.35, 0.95, 1.0) if combo else orb.color
	_blasts_this_execution += 1
	_effects.add(Effects.Kind.EXPLOSION, orb.position, blast_color,
		clampf(radius / 108.0, 0.75, 2.75))
	_remember_aftermath("SHOCK COMBO" if combo else "SHOCK POP", orb.position, blast_color)
	_sfx.play("explosion")
	for player: Player in players:
		if not combo and player.index == orb.shooter:
			continue
		var blast_contact := _shock_blast_player_contact(orb.position, radius, player)
		if player.alive and not player.is_invulnerable() \
				and blast_contact.is_finite() \
				and _blast_reaches(orb.position, blast_contact):
			_on_player_hit(player.index, player.position, scorer)
	for arrow: Arrow in arrows:
		var local_position: Vector2 = orb.position + wrap_delta(orb.position, arrow.position)
		var redirected: Vector2 = ShockOrb.revector_velocity(orb.position, local_position,
			arrow.vel, impulse, radius)
		if not redirected.is_equal_approx(arrow.vel):
			arrow.relaunch(redirected)
	for chakram in chakrams:
		var local_position: Vector2 = orb.position + wrap_delta(orb.position, chakram.position)
		var redirected: Vector2 = ShockOrb.revector_velocity(orb.position, local_position,
			chakram.vel, impulse, radius)
		if not redirected.is_equal_approx(chakram.vel):
			chakram.vel = redirected
			chakram.force_recall()
	for other_plasma in shock_plasmas:
		if other_plasma == source_projectile:
			continue
		var local_position: Vector2 = orb.position \
			+ wrap_delta(orb.position, other_plasma.position)
		var redirected: Vector2 = ShockOrb.revector_velocity(orb.position, local_position,
			other_plasma.vel, impulse, radius)
		if not redirected.is_equal_approx(other_plasma.vel):
			other_plasma.vel = redirected
			other_plasma.prev_pos = other_plasma.position
			other_plasma.rotation = redirected.angle()
	for other_orb in shock_orbs:
		if other_orb == orb:
			continue
		var local_position: Vector2 = orb.position + wrap_delta(orb.position, other_orb.position)
		var redirected: Vector2 = ShockOrb.revector_velocity(orb.position, local_position,
			other_orb.vel, impulse, radius)
		if not redirected.is_equal_approx(other_orb.vel):
			other_orb.vel = redirected
			other_orb.prev_pos = other_orb.position
			other_orb.resting = false
			other_orb.support_platform = -1
	shock_orbs.erase(orb)
	orb.queue_free()


## Returns the nearest point where the radial blast touches the fighter's real
## body rectangle (including seam copies), or INF when there is no contact.
func _shock_blast_player_contact(origin: Vector2, radius: float,
		player: Player) -> Vector2:
	var nearest := Vector2(INF, INF)
	var nearest_distance_sq := INF
	for body: Rect2 in body_rects(player):
		var contact := Vector2(
			clampf(origin.x, body.position.x, body.end.x),
			clampf(origin.y, body.position.y, body.end.y))
		var distance_sq := origin.distance_squared_to(contact)
		if distance_sq <= radius * radius and distance_sq < nearest_distance_sq:
			nearest = contact
			nearest_distance_sq = distance_sq
	return nearest


func _blast_reaches(origin: Vector2, target: Vector2) -> bool:
	var endpoint := origin + wrap_delta(origin, target)
	for r: Rect2 in solid_rects:
		var impact := Arrow.segment_rect_impact(origin, endpoint, r)
		if not impact.is_empty() and impact[0] > 0.025 and impact[0] < 0.975:
			return false
	return true


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
		# The triggering knife survives. Snap it to the contact point so radial
		# launch points back out of the face it entered instead of beyond the orb.
		var contact := Arrow.moving_points_closest(
			a.prev_pos, a.position, struck.position, struck.position)
		a.position = contact[1]
		a.prev_pos = a.position
		kept.append(a)
	# Detonate only once the survivor list is final, so every triggering knife
	# participates in the same deterministic relaunch as the bystanders.
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
		var offset: Vector2 = wrap_delta(h.position, a.position)
		if offset.length() >= h.blast_radius:
			continue
		# At the exact centre, send the knife back against its incoming direction.
		# Everywhere else, the public blast ring gives the radial launch direction.
		var dir: Vector2 = offset.normalized() if not offset.is_zero_approx() \
			else (-a.vel.normalized() if not a.vel.is_zero_approx() else Vector2.UP)
		a.relaunch(dir * h.dagger_launch_speed)


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
	if team_mode and player_teams[scorer] == player_teams[victim_idx]:
		banner_text = "%s FRIENDLY HIT — NO POINT" % TEAM_NAMES[player_teams[scorer]]
		banner_color = TEAM_COLORS[player_teams[scorer]]
		banner_time = banner_duration
		return
	score[scorer] += 1

	if team_mode:
		var scoring_team := player_teams[scorer]
		team_score[scoring_team] += 1
		if team_score[scoring_team] >= hits_to_win:
			state = Phase.GAME_OVER
			winner = scorer
			winning_team = scoring_team
			_prime_game_over_pad_state()
			banner_text = "TEAM %s WINS" % TEAM_NAMES[scoring_team]
			banner_color = TEAM_COLORS[scoring_team]
			_finish_match_telemetry()
		else:
			banner_text = "%s SCORES — %d : %d" % [TEAM_NAMES[scoring_team], team_score[0], team_score[1]]
			banner_color = TEAM_COLORS[scoring_team]
		banner_time = banner_duration
		return
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
	if team_mode:
		return "CRIMSON  %d   ·   %d  AZURE" % [team_score[0], team_score[1]]
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
	_online_plan_sent = false
	_online_match_reported = false
	if not first:
		turn += 1
	_advance_chakrams_for_turn()
	planning_window_duration = _planning_duration_for_turn(turn)
	planning_time_left = planning_window_duration
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


func _advance_chakrams_for_turn() -> void:
	var live: Array = []
	for chakram in chakrams:
		if chakram.advance_to_turn(turn):
			live.append(chakram)
		else:
			chakram.queue_free()
	chakrams = live


func _planning_duration_for_turn(turn_number: int) -> float:
	if tutorial_mode:
		return planning_duration
	var reductions := maxi(0, turn_number - maxi(1, planning_shrink_after_rounds))
	return maxf(minimum_planning_duration,
		planning_duration - float(reductions) * maxf(0.0, planning_shrink_per_round))


func start_tutorial_timed_turns() -> void:
	if not tutorial_mode or state != Phase.PLANNING:
		return
	planning_duration = 5.0
	planning_window_duration = planning_duration
	planning_time_left = planning_window_duration
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
	var best_cost := INF
	var best_tie_rank := MAX_PLAYERS + 1
	var preferred := posmod(ai_idx + turn, players.size())
	if preferred == ai_idx:
		preferred = posmod(preferred + 1, players.size())
	for i in players.size():
		if i == ai_idx or not players[i].alive:
			continue
		if team_mode and player_teams[i] == player_teams[ai_idx]:
			continue
		var distance: float = wrap_delta(players[ai_idx].position, players[i].position).length_squared()
		# In a crowd, a nearby score leader is the meaningful threat. This mirrors
		# natural table politics and prevents a fast opener from farming its nearest
		# respawn while every other bot looks away. The bonus is deliberately below
		# the cost of crossing an entire arena, so proximity still matters.
		var leader_pressure: float = float(score[i]) * 120_000.0 if players.size() > 2 else 0.0
		var cost := distance - leader_pressure
		var tie_rank := posmod(i - preferred, players.size())
		if cost < best_cost - 0.01 \
				or (is_equal_approx(cost, best_cost) and tie_rank < best_tie_rank):
			best_cost = cost
			best = i
			best_tie_rank = tie_rank
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
	frame_debt_locked.fill(false)
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
		"frame_debt_cells": frame_debt_cells.duplicate(),
		"frame_debt_units": frame_debt_units.duplicate(),
		"core_position": core_position,
		"core_announced": core_announced,
		"core_active": core_active,
		"core_turns_left": core_turns_left,
		"core_time": _temporal_core._time if _temporal_core != null else 0.0,
		"effects": _effects._fx.duplicate(true) if _effects != null else [],
	})
	_trim_replay_history()


func replay_frame_capacity() -> int:
	return maxi(1, int(ceil(replay_history_seconds * float(Engine.physics_ticks_per_second))))


## Compact in batches rather than shifting a large Array every simulation tick.
## The small slack is still a hard, predictable upper bound during a match; a
## replay request forces the exact configured limit before playback begins.
func _trim_replay_history(force: bool = false) -> void:
	var capacity := replay_frame_capacity()
	var slack := maxi(1, int(ceil(REPLAY_COMPACTION_SLACK_SECONDS \
		* float(Engine.physics_ticks_per_second))))
	if _replay_frames.size() <= capacity \
			or (not force and _replay_frames.size() <= capacity + slack):
		return
	var compacted: Array[Dictionary] = []
	compacted.assign(_replay_frames.slice(_replay_frames.size() - capacity))
	_replay_frames = compacted


func _start_match_replay() -> void:
	if state != Phase.GAME_OVER or _replay_frames.is_empty():
		return
	_trim_replay_history(true)
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
	var frame_cells: Array = frame.get("frame_debt_cells", frame_debt_cells)
	var frame_units: Array = frame.get("frame_debt_units", frame_debt_units)
	for i in players.size():
		score[i] = int(frame_score[i])
		super_meter[i] = float(frame_meter[i])
		super_armed[i] = bool(frame_armed[i])
		frame_debt_cells[i] = int(frame_cells[i])
		frame_debt_units[i] = int(frame_units[i])
		var p: Player = players[i]
		var data: Dictionary = frame["players"][i]
		p.position = data["position"]
		p.vel = data["vel"]
		p.on_ground = bool(data["on_ground"])
		p.air_jumps_left = int(data.get("air_jumps_left", air_jumps_for(i)))
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
	banner_text = "TEAM %s WINS THE MATCH" % TEAM_NAMES[winning_team] \
		if team_mode and winning_team >= 0 else \
		("PLAYER %d WINS THE MATCH" % (winner + 1) if winner >= 0 else "MATCH OVER")
	banner_color = TEAM_COLORS[winning_team] if team_mode and winning_team >= 0 else \
		(PLAYER_COLORS[winner] if winner >= 0 else Color.WHITE)
	banner_time = banner_duration
	_replay_frame_index = 0
	_replay_accum = 0.0


func _end_execution() -> void:
	# A shot placed at the very end of the window leaves as it closes.
	for p in players:
		if p.alive and p.plan.has_shot() and not p.plan.super_shot \
				and p.plan.shot_tick >= exec_ticks_total:
			_spawn_player_attack(p)
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
	p.position = _choose_respawn_point(i)
	p.vel = Vector2.ZERO
	p.on_ground = true
	p.air_jumps_left = air_jumps_for(i)
	p.drop_ticks = 0
	p.drop_from_y = 0.0
	p.alive = true
	p.invuln_turns = respawn_invuln_turns
	p.queue_redraw()


## Maximin placement: score every authored socket by its nearest living rival,
## then take the socket whose nearest threat is farthest away. Because every
## fighter respawned earlier in this same sweep is already alive, simultaneous
## deaths also spread out correctly in three- and four-player matches.
func _choose_respawn_point(player_index: int) -> Vector2:
	var candidates: Array[Vector2] = respawn_points if not respawn_points.is_empty() else spawns
	if candidates.is_empty():
		return spawns[player_index]
	var best_index := 0
	var best_distance := -INF
	var death_position: Vector2 = players[player_index].position
	var has_other_player := false
	for other_index in players.size():
		if other_index != player_index and players[other_index].alive:
			has_other_player = true
			break
	for candidate_index in candidates.size():
		var candidate: Vector2 = candidates[candidate_index]
		var nearest := INF
		if has_other_player:
			for other_index in players.size():
				if other_index == player_index or not players[other_index].alive:
					continue
				nearest = minf(nearest,
					wrap_delta(candidate, players[other_index].position).length_squared())
		else:
			# A total wipe has no living rival yet. Move the first respawn away from
			# where they died; subsequent respawns spread from that player.
			nearest = wrap_delta(candidate, death_position).length_squared()
		var avoids_repeat := candidate_index != _last_respawn_choice[player_index]
		var best_avoids_repeat := best_index != _last_respawn_choice[player_index]
		if nearest > best_distance + 0.001 or (is_equal_approx(nearest, best_distance) \
				and avoids_repeat and not best_avoids_repeat):
			best_distance = nearest
			best_index = candidate_index
	_last_respawn_choice[player_index] = best_index
	return candidates[best_index]


## One throw looses the whole fan from the same point at the same tick — the
## spread is the shot, not a sequence of shots.
func _spawn_player_attack(p: Player) -> void:
	match player_weapons[p.index]:
		Weapon.DASHBLADE:
			_spawn_dashblade(p, false)
		Weapon.CHAKRAM:
			_spawn_chakram(p)
		Weapon.SHOCK:
			_spawn_shock_attack(p)
		_:
			_spawn_arrow(p)


func _spawn_dashblade(p: Player, empowered: bool) -> void:
	# One committed body trajectory at a time. Re-firing while an old dash is
	# somehow still live ends the old action at its current physical position.
	for old in dashblades.duplicate():
		if old.owner_index == p.index:
			dashblades.erase(old)
			old.queue_free()
	var lost_frames := frame_debt_max_cells if empowered else frame_debt_cells[p.index]
	var dash_params := dash_parameters(p.plan.power, empowered, lost_frames)
	var dash = DASHBLADE_SCRIPT.new()
	dash.begin(p.position, p.aim_dir(), dash_params["speed"], dash_params["ticks"],
		p.index, dash_params["durability"], lost_frames, dash_exit_momentum_retention)
	_arrow_layer.add_child(dash)
	dashblades.append(dash)
	frame_debt_locked[p.index] = true
	frame_debt_cells[p.index] = 0
	if empowered:
		frame_debt_units[p.index] = 0
	if lost_frames > 0:
		_effects.add(Effects.Kind.CLASH, p.position, Color(0.36, 0.96, 1.0))
		_remember_aftermath("%d LOST FRAME%s" % [lost_frames,
			"" if lost_frames == 1 else "S"], p.position, Color(0.36, 0.96, 1.0))
	p.queue_redraw()
	_sfx.play("shoot")


func dash_parameters(power: float, empowered: bool = false,
		lost_frames: int = 0) -> Dictionary:
	var amount := clampf(power, 0.0, 1.0)
	var speed := lerpf(dash_speed_min, dash_speed_max, amount)
	var duration := roundi(lerpf(float(dash_duration_ticks_min),
		float(dash_duration_ticks_max), amount))
	var durability := dash_guard_durability
	var committed := clampi(lost_frames, 0, frame_debt_max_cells)
	duration += committed * frame_debt_dash_ticks_per_cell
	if committed >= frame_debt_max_cells:
		durability += frame_debt_full_guard_bonus
	if empowered:
		speed *= 1.28
		duration += 6
		durability += 3
	return {"speed": speed, "ticks": duration, "durability": durability,
		"lost_frames": committed}


## Uses the exact dash primitive against the current frozen terrain. The preview
## can therefore promise a body endpoint—including a wall shimmy—rather than
## showing a dagger-shaped guess.
func dash_preview_path(origin: Vector2, direction: Vector2, power: float,
		empowered: bool = false, lost_frames: int = 0) -> PackedVector2Array:
	var params := dash_parameters(power, empowered, lost_frames)
	var preview_dash = DASHBLADE_SCRIPT.new()
	preview_dash.begin(origin, direction, params["speed"], params["ticks"], -1,
		params["durability"], lost_frames, dash_exit_momentum_retention)
	var path := PackedVector2Array([origin])
	var safety := 0
	while preview_dash.active and safety < 64:
		var result: Dictionary = preview_dash.sim_step(tick_dt(), [], [], platforms)
		path.append(result["position"])
		safety += 1
	preview_dash.free()
	return path


func _spawn_chakram(p: Player, angle_offset: float = 0.0,
		recall_scale: float = 1.0) -> void:
	var direct: Vector2 = p.aim_dir().rotated(deg_to_rad(angle_offset))
	var chakram = CHAKRAM_SCRIPT.new()
	chakram.cfg = self
	chakram.shooter = p.index
	chakram.volley = _next_volley
	_next_volley += 1
	chakram.network_id = _next_character_projectile_id
	_next_character_projectile_id += 1
	chakram.color = p.color
	chakram.begin_lifecycle(turn)
	chakram.position = p.shoulder() + direct * 24.0
	chakram.prev_pos = chakram.position
	chakram.vel = direct * lerpf(chakram_speed_min, chakram_speed_max, p.plan.power)
	chakram.freeplay_window_ticks = maxi(12, roundi(float(exec_ticks()) * recall_scale))
	_arrow_layer.add_child(chakram)
	chakrams.append(chakram)
	_sfx.play("shoot")


func _spawn_shock_attack(p: Player) -> void:
	var direct := p.aim_dir()
	if p.plan.attack_mode == 1:
		_spawn_shock_orb(p, direct, false)
	else:
		_spawn_shock_plasma(p, direct)


func _spawn_shock_plasma(p: Player, direct: Vector2) -> void:
	var plasma = SHOCK_PLASMA_SCRIPT.new()
	plasma.cfg = self
	plasma.shooter = p.index
	plasma.network_id = _next_character_projectile_id
	_next_character_projectile_id += 1
	plasma.color = p.color.lightened(0.35)
	plasma.position = p.shoulder() + direct.normalized() * 24.0
	plasma.configure_launch(direct, shock_plasma_speed_for_power(p.plan.power),
		p.plan.power, shock_plasma_range_for_power(p.plan.power))
	_arrow_layer.add_child(plasma)
	shock_plasmas.append(plasma)
	_sfx.play("shoot")


func _spawn_shock_orb(p: Player, direct: Vector2, prearmed: bool) -> void:
	# Every cast adds another persistent setup. Lifetime and counterplay bound the
	# field naturally; casting a new orb never silently dismisses an older one.
	var orb = SHOCK_ORB_SCRIPT.new()
	orb.cfg = self
	orb.shooter = p.index
	orb.arm_ticks = maxi(1, shock_orb_arm_ticks)
	orb.network_id = _next_character_projectile_id
	_next_character_projectile_id += 1
	orb.color = p.color
	orb.position = p.shoulder() + direct.normalized() * (180.0 if prearmed else 24.0)
	orb.configure_lob(direct, 120.0 if prearmed else lerpf(
		shock_orb_speed_min, shock_orb_speed_max, p.plan.power))
	if prearmed:
		orb.age_ticks = orb.arm_ticks
	_arrow_layer.add_child(orb)
	shock_orbs.append(orb)
	_sfx.play("shoot")


func _spawn_character_super(p: Player) -> void:
	super_meter[p.index] = 0.0
	super_armed[p.index] = false
	p.queue_redraw()
	_effects.add(Effects.Kind.CLASH, p.shoulder(), Color(1.0, 0.92, 0.42))
	banner_text = "PLAYER %d — %s" % [p.index + 1, weapon_short_name(p.index)]
	banner_color = PLAYER_COLORS[p.index].lightened(0.35)
	banner_time = 0.9
	match player_weapons[p.index]:
		Weapon.DASHBLADE:
			_spawn_dashblade(p, true)
		Weapon.CHAKRAM:
			for launch in chakram_launch_velocities(p.aim_dir(), p.plan.power, true):
				var offset := rad_to_deg(p.aim_dir().angle_to(launch))
				_spawn_chakram(p, offset, 1.4)
		Weapon.SHOCK:
			_spawn_shock_orb(p, p.aim_dir(), true)
			_spawn_shock_plasma(p, p.aim_dir())


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
	_clear_character_projectiles()
	_next_volley = 1
	_next_arrow_id = 1
	_next_character_projectile_id = 100000
	_effects.clear_all()
	_load_level(level_index)
	for i in players.size():
		var p: Player = players[i]
		p.fighter_style = player_weapons[i]
		p.clear_afterimages()
		p.position = spawns[i]
		p.vel = Vector2.ZERO
		p.on_ground = true
		p.air_jumps_left = air_jumps_for(i)
		p.drop_ticks = 0
		p.drop_from_y = 0.0
		p.alive = true
		p.invuln_turns = 0
		p.plan = PlayerPlan.new()
		p.plan.set_aim_from_vector(_default_aim_vector(i), aim_min_angle, aim_max_angle)
		p.plan.power = 0.55
		p.queue_redraw()
	turn = 1
	winner = -1
	winning_team = -1
	team_score = [0, 0]
	for i in MAX_PLAYERS:
		score[i] = 0
		_last_respawn_choice[i] = -1
		super_meter[i] = 0.0
		super_armed[i] = false
		frame_debt_cells[i] = 0
		frame_debt_units[i] = 0
		frame_debt_locked[i] = false
	_reset_temporal_core()
	banner_time = 0.0
	_begin_planning(true)


# ------------------------------------------------------------ ghost piloting --

func _reset_pilot(i: int) -> void:
	var p: Player = players[i]
	if ghost_dash[i] != null and is_instance_valid(ghost_dash[i]):
		ghost_dash[i].free()
	ghost_dash[i] = _dash_prediction_copy(i)
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
	# Planning may resume long after the previous input poll. Sampling the actual
	# button prevents a stale edge from swallowing an airborne jump.
	_jump_prev[i] = _jump_input_held(i)
	_mark_ghost_path_dirty(i)


## Records exactly one tick of piloted input onto the ghost.
func _pilot_step(i: int, dir: int, jump: bool, hold: bool, drop: bool = false) -> bool:
	var pl: PlayerPlan = players[i].plan
	if pl.recorded_ticks() >= movement_tick_budget() or stamina[i] <= 0.0:
		return false
	# The tick this step LEAVES, in absolute time — the moving world is projected
	# forward from here, so the ghost meets the geometry the plan will meet.
	var from_tick: int = world_tick + pl.recorded_ticks()
	var pending_dash = ghost_dash[i]
	if pending_dash != null and pending_dash.active:
		# Execution ignores locomotion while a body dash owns this tick. Record the
		# elapsed tick, but do not promise a jump or directional acceleration.
		pl.record(dir, false, false, false)
		var dash_result: Dictionary = pending_dash.sim_step(tick_dt(), [], [], platforms)
		ghost_pos[i] = wrap_point(dash_result["position"])
		ghost_vel[i] = dash_result["velocity"]
		stamina[i] = maxf(0.0, stamina[i] - tick_dt())
		if not pending_dash.active:
			pending_dash.free()
			ghost_dash[i] = null
		_mark_ghost_path_dirty(i)
		return true
	var drop_result := Player.apply_drop(ghost_pos[i].y, ghost_vel[i], ghost_ground[i],
		ghost_drop[i], ghost_drop_from[i], drop)
	ghost_vel[i] = drop_result[0]
	ghost_ground[i] = drop_result[1]
	ghost_drop[i] = drop_result[2]
	ghost_drop_from[i] = drop_result[3]
	var jump_result := Player.apply_jump(ghost_vel[i], ghost_ground[i], ghost_air_jumps[i],
		jump, jump_impulse_for(i), air_jump_impulse_for(i), air_jumps_for(i))
	ghost_vel[i] = jump_result[0]
	ghost_ground[i] = jump_result[1]
	ghost_air_jumps[i] = jump_result[2]
	var jumped: bool = jump_result[3]
	pl.record(dir, jumped, hold or jumped, drop)
	var st := Player.step_state(ghost_pos[i], ghost_vel[i], ghost_ground[i], dir,
		hold or jumped, tick_dt(), self, from_tick, ghost_drop[i], ghost_drop_from[i],
		movement_speed_scale(i), jump_impulse_for(i), max_fall_speed_for(i))
	ghost_pos[i] = st[0]
	ghost_vel[i] = st[1]
	ghost_ground[i] = st[2]
	if ghost_ground[i]:
		ghost_air_jumps[i] = air_jumps_for(i)
	stamina[i] = maxf(0.0, stamina[i] - tick_dt())
	_mark_ghost_path_dirty(i)
	return true


## Recorded path + the coasted remainder, so the ghost always shows the true
## end of the window rather than just where the stamina ran out.
func _rebuild_ghost_paths() -> void:
	for i in players.size():
		_rebuild_ghost_path(i)


func _mark_ghost_path_dirty(i: int) -> void:
	if i >= 0 and i < _ghost_path_dirty.size():
		_ghost_path_dirty[i] = true


func _refresh_dirty_ghost_paths() -> void:
	for i in players.size():
		if _ghost_path_dirty[i]:
			_rebuild_ghost_path(i)


func _rebuild_ghost_path(i: int) -> void:
	if i < 0 or i >= players.size():
		return
	var p: Player = players[i]
	var pl: PlayerPlan = p.plan
	var path := PackedVector2Array()
	# Replay the recording from the live body state.
	var pos: Vector2 = p.position
	var vel: Vector2 = p.vel
	var og: bool = p.on_ground
	var air_jumps: int = p.air_jumps_left
	var drop: int = p.drop_ticks
	var drop_from: float = p.drop_from_y
	var pending_dash = _dash_prediction_copy(i)
	path.append(pos)
	for t in exec_ticks():
		if pending_dash != null and pending_dash.active:
			var dash_result: Dictionary = pending_dash.sim_step(tick_dt(), [], [], platforms)
			pos = wrap_point(dash_result["position"])
			vel = dash_result["velocity"]
			path.append(pos)
			continue
		var drop_result := Player.apply_drop(pos.y, vel, og, drop, drop_from, pl.drop_at(t))
		vel = drop_result[0]
		og = drop_result[1]
		drop = drop_result[2]
		drop_from = drop_result[3]
		var jump_result := Player.apply_jump(vel, og, air_jumps, pl.jump_at(t),
			jump_impulse_for(i), air_jump_impulse_for(i), air_jumps_for(i))
		vel = jump_result[0]
		og = jump_result[1]
		air_jumps = jump_result[2]
		var st := Player.step_state(pos, vel, og, pl.dir_at(t), pl.hold_at(t), tick_dt(),
			self, world_tick + t, drop, drop_from, movement_speed_scale(i),
			jump_impulse_for(i), max_fall_speed_for(i))
		pos = st[0]
		vel = st[1]
		og = st[2]
		if og:
			air_jumps = air_jumps_for(i)
		path.append(pos)
	if pending_dash != null:
		pending_dash.free()
	ghost_path[i] = path
	_ghost_path_dirty[i] = false


func _dash_prediction_copy(i: int):
	for dash in dashblades:
		if dash.active and dash.owner_index == i:
			return dash.prediction_copy()
	return null


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
	"left": [KEY_A], "right": [KEY_D], "jump": [KEY_SPACE, KEY_W, KEY_UP], "wait": [KEY_S],
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
	return K_P1 if online_mode else (K_P1 if i == _keyboard_player() else K_GAMEPAD_ONLY)


func _keyboard_player() -> int:
	if online_mode:
		return online_player
	if team_mode:
		for i in player_devices.size():
			if player_devices[i] == TeamSelectLayer.KEYBOARD_DEVICE and player_roles[i] == "HUMAN":
				return i
	return 0


func _slot_for_device(device_id: int) -> int:
	for i in player_devices.size():
		if player_devices[i] == device_id and player_roles[i] == "HUMAN":
			return i
	return -1


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
			("ai_wide" if vs_ai else "local_2p"))


func _cycle_rematch_level(direction: int) -> void:
	if state != Phase.GAME_OVER or direction == 0 \
			or (online_mode and (online_player != 0 or _online_waiting_rematch)):
		return
	rematch_level_index = posmod(rematch_level_index + direction, Levels.count())
	var selected := Levels.build(rematch_level_index)
	rematch_level_name = str(selected["name"])


func _unhandled_input(event: InputEvent) -> void:
	if state == Phase.TEAM_SELECT:
		var team_joy := event as InputEventJoypadButton
		if team_joy != null and team_joy.pressed:
			_team_select.handle_input(team_joy)
		return
	if state == Phase.CHARACTER_SELECT:
		var joy := event as InputEventJoypadButton
		if joy != null and joy.pressed:
			if team_mode:
				_character_select.handle_joy_button_for_slot(_slot_for_device(joy.device), joy.button_index)
			else:
				_character_select.handle_joy_button(joy.button_index)
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		var mouse_player := _keyboard_player()
		if state in [Phase.PLANNING, Phase.FREEPLAY] and uses_shock(mouse_player):
			# Shock owns RMB as its orb trigger; it must never undo the plan.
			return
		_rollback(mouse_player)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if state == Phase.TEAM_SELECT:
		_team_select.handle_input(k)
		return
	if state == Phase.CHARACTER_SELECT:
		if team_mode:
			_character_select.handle_key_for_slot(_keyboard_player(), k.keycode)
		else:
			_character_select.handle_key(k.keycode)
		return
	if state == Phase.TUTORIAL:
		_tutorial.handle_key(k.keycode)
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
			KEY_1, KEY_2, KEY_3:
				if uses_shock(0) and k.keycode in [KEY_1, KEY_2]:
					_set_shock_attack_mode(0, 0 if k.keycode == KEY_1 else 1)
				else:
					_tuning.handle_key(k.keycode, k.shift_pressed)
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
		if uses_shock(online_player):
			match k.keycode:
				KEY_1:
					_set_shock_attack_mode(online_player, 0)
					return
				KEY_2:
					_set_shock_attack_mode(online_player, 1)
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
	var keyboard_player := _keyboard_player()
	if k.keycode == KEY_SHIFT:
		if k.location != KEY_LOCATION_RIGHT and not is_ai(keyboard_player):
			_confirm(keyboard_player)
		return

	if state != Phase.PLANNING:
		return

	if uses_shock(keyboard_player):
		match k.keycode:
			KEY_1:
				_set_shock_attack_mode(keyboard_player, 0)
				return
			KEY_2:
				_set_shock_attack_mode(keyboard_player, 1)
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


func _set_shock_attack_mode(i: int, mode: int) -> void:
	if state not in [Phase.PLANNING, Phase.FREEPLAY] or not uses_shock(i) or is_ai(i):
		return
	var p: Player = players[i]
	if not p.alive or p.plan.confirmed:
		return
	p.plan.attack_mode = clampi(mode, 0, 1)
	banner_text = "P%d SHOCK — %s" % [i + 1,
		"PLASMA LANCE" if p.plan.attack_mode == 0 else "SHOCK ORB"]
	banner_color = p.color
	banner_time = 1.1
	p.queue_redraw()


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
	var fuse_previous := _pad_edge(i, pad, JOY_BUTTON_LEFT_SHOULDER)
	var fuse_next := _pad_edge(i, pad, JOY_BUTTON_RIGHT_SHOULDER)
	if start:
		_confirm(i)
	if back or b:
		_rollback(i)
	if x:
		_reset_path(i)
	if y:
		_toggle_super(i)
	if fuse_previous:
		_cycle_attack_mode(i, -1)
	if fuse_next:
		_cycle_attack_mode(i, 1)


func _pad_edge(i: int, pad: int, btn: int) -> bool:
	var now: bool = Input.is_joy_button_pressed(pad, btn)
	var was: bool = _pad_btn_prev[i].get(btn, false)
	_pad_btn_prev[i][btn] = now
	return now and not was


## The shoulder buttons cycle whichever secondary choice the kit owns. Only
## the Static Witch has one, so for every other fighter this is inert.
func _cycle_attack_mode(i: int, direction: int) -> void:
	if direction == 0 or not uses_shock(i):
		return
	_set_shock_attack_mode(i, posmod(players[i].plan.attack_mode + direction, 2))


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
	elif i == _keyboard_player() \
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

	var primary_held: bool = _held(map["charge"]) \
		or (i == _touch_player() and _touch_controls.charge_held)
	var secondary_held := false
	if i == _keyboard_player() \
			and not _touch_controls.has_active_touches() \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		primary_held = true
	if uses_shock(i) and i == _keyboard_player() \
			and not _touch_controls.has_active_touches() \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		secondary_held = true
	if pad >= 0 and Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_RIGHT) > trigger_threshold:
		primary_held = true
	var held: bool = primary_held or secondary_held

	if held:
		if not charging[i]:
			charging[i] = true
			_charge_t[i] = 0.0
			charge_attack_mode[i] = 1 if secondary_held and not primary_held else 0
			if uses_shock(i):
				p.plan.attack_mode = charge_attack_mode[i]
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
	_telemetry.begin_match(mode, level_name, input_name)
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
	parts.append("ids:%d,%d,%d" % [
		_next_volley, _next_arrow_id, _next_character_projectile_id,
	])
	parts.append("kits:%d,%d" % [player_weapons[0], player_weapons[1]])
	parts.append("rng:%d" % rng.state)
	for i in players.size():
		var p: Player = players[i]
		parts.append("p%d:%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d" % [
			i,
			int(round(p.position.x * 10000.0)), int(round(p.position.y * 10000.0)),
			int(round(p.vel.x * 10000.0)), int(round(p.vel.y * 10000.0)),
			1 if p.on_ground else 0, p.air_jumps_left,
			p.drop_ticks, int(round(p.drop_from_y * 10000.0)),
			1 if p.alive else 0, p.invuln_turns,
			int(round(super_meter[i] * 1000000.0)), 1 if super_armed[i] else 0,
			p.plan.attack_mode,
		])
		parts.append("fd%d:%d,%d" % [i, frame_debt_cells[i], frame_debt_units[i]])
		parts.append("fdl%d:%d" % [i, 1 if frame_debt_locked[i] else 0])
	var ordered_arrows: Array = arrows.duplicate()
	ordered_arrows.sort_custom(func(a: Arrow, b: Arrow): return a.network_id < b.network_id)
	for a: Arrow in ordered_arrows:
		parts.append("a:" + a.lockstep_digest_fragment())
	var ordered_dashes: Array = dashblades.duplicate()
	ordered_dashes.sort_custom(func(a, b): return a.owner_index < b.owner_index)
	for dash in ordered_dashes:
		parts.append("d:" + dash.lockstep_digest_fragment())
	var ordered_chakrams: Array = chakrams.duplicate()
	ordered_chakrams.sort_custom(func(a, b): return a.network_id < b.network_id)
	for chakram in ordered_chakrams:
		parts.append("c:" + chakram.lockstep_digest_fragment())
	var ordered_plasmas: Array = shock_plasmas.duplicate()
	ordered_plasmas.sort_custom(func(a, b): return a.network_id < b.network_id)
	for plasma in ordered_plasmas:
		parts.append("sp:" + plasma.lockstep_digest_fragment())
	var ordered_orbs: Array = shock_orbs.duplicate()
	ordered_orbs.sort_custom(func(a, b): return a.network_id < b.network_id)
	for orb in ordered_orbs:
		parts.append("so:" + orb.lockstep_digest_fragment())
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
	planning_window_duration = _planning_duration_for_turn(turn)
	planning_time_left = minf(planning_time_left, planning_window_duration)
