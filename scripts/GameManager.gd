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
##
## Four subsystems live in helper objects this node creates with itself. Each
## holds a `gm` back-reference to this node:
##   OnlineSession.gd (`_online`): rooms, the online selection screens, room
##     messages, online match start, plan relay and validation, and the
##     lockstep state digest. `online_mode` and `online_player` stay here.
##   MatchReplay.gd (`_replay`): end-of-match replay capture and playback.
##   SettingsStore.gd (`_settings_store`): saved options, applying them, and
##     key rebinding.
##   PlayerInput.gd (`_player_input`): key, pointer, pad and touch handling,
##     device to slot mapping and planning-input polling. `_unhandled_input`
##     and `_unhandled_key_input` stay here as forwarders.

const PREVIEW_SCRIPT := preload("res://scripts/PreviewLayer.gd")
const UI_SCRIPT := preload("res://scripts/UI.gd")
const BACKDROP_SCRIPT := preload("res://scripts/Backdrop.gd")
const EFFECTS_SCRIPT := preload("res://scripts/Effects.gd")
const SFX_SCRIPT := preload("res://scripts/Sfx.gd")
const TIME_STOP_SCRIPT := preload("res://scripts/TimeStopLayer.gd")
const SUPER_FREEZE_SCRIPT := preload("res://scripts/SuperFreezeFrame.gd")
const MENU_SCRIPT := preload("res://scripts/MenuLayer.gd")
const TUNING_SCRIPT := preload("res://scripts/TuningLayer.gd")
const OFFLINE_TUNING_SCRIPT := preload("res://scripts/OfflineTuning.gd")
const OFFLINE_TUNING_LAYER_SCRIPT := preload("res://scripts/OfflineTuningLayer.gd")
const TEMPORAL_CORE_SCRIPT := preload("res://scripts/TemporalCore.gd")
const TOUCH_CONTROLS_SCRIPT := preload("res://scripts/TouchControls.gd")
const HAZARD_SCRIPT := preload("res://scripts/Hazard.gd")
const CAMERA_SCRIPT := preload("res://scripts/DuelCamera.gd")
const TUTORIAL_SCRIPT := preload("res://scripts/TutorialLayer.gd")
const TELEMETRY_SCRIPT := preload("res://scripts/Telemetry.gd")
const TRANSITION_SCRIPT := preload("res://scripts/TransitionLayer.gd")
const FIGHTER_VISUAL_SCRIPT := preload("res://scripts/FighterVisual.gd")
const FIGHTER_SKIN_SCRIPT := preload("res://scripts/FighterSkin.gd")
const ROSTER_SCRIPT := preload("res://scripts/RosterLayer.gd")
const MATCH_SETUP_SCRIPT := preload("res://scripts/MatchSetupLayer.gd")

## How close a body's feet must be to a moving lip to be carried by it.
const RIDE_TOLERANCE := 3.0
## Upper bound on projected collision sets held at once, so a long AI search
## cannot grow the cache without limit.
const SOLIDS_CACHE_LIMIT := 900
## Brief presentation-only hit-stop. At 60 Hz this holds roughly three frames.
const HIT_PAUSE_DURATION := 0.045
## Shortest opening distance between rivals when spawns are dealt at random.
const SPAWN_MIN_GAP_DUEL := 480.0
const SPAWN_MIN_GAP_CROWD := 300.0
## Dodging a whole SUPER fan is already its own reward; the meter share stops here.
const SUPER_DODGE_CREDITS_PER_WINDOW := 3

# Rival aristocratic palettes: antique gold versus imperial violet. Both remain
# bright enough to read over the near-black arenas and planning overlays.

const MAX_PLAYERS := 4
## Sentinel device ids: the keyboard-and-mouse seat, and "nobody claimed this".
const KEYBOARD_DEVICE := -2
const NO_DEVICE := -1
const DEFAULT_HITS_TO_WIN := 5
const MAX_HITS_TO_WIN := 7
const FATE_TRIAL_WINDOWS := 3
const FATE_TRIAL_PLANNING_DURATION := 10.0
const PLAYER_COLORS := [
	Color(0.96, 0.69, 0.18),
	Color(0.76, 0.30, 1.00),
	Color(0.18, 0.82, 0.92),
	Color(1.00, 0.32, 0.42),
]
const TEAM_COLORS := [Color(0.93, 0.19, 0.28), Color(0.16, 0.66, 0.98)]
const TEAM_NAMES := ["CRIMSON", "AZURE"]

## Ids are append-only. Ids 1 to 4 are retired (Grenadier, Rook, Eclipse, Pulse)
## and must never be reused: old telemetry, captures and the deployed room
## server still know them.
enum Weapon { KNIVES = 0 }

# ------------------------------------------------------------------ tuning ---

@export_group("Opponent")
## When true, every active player after Player 1 is driven by Ai.gd and its
## preview stays hidden. It cannot see your plan, so showing it would be a
## one-way giveaway.
@export var vs_ai: bool = true
## Opponent skill. Every level plans by the same rules and still cannot see
## your plan. What changes is how much of the search it spends and how
## precisely it aims, so a lower level is a rival you can read rather than a
## different game. Set from the match setup screen; the fields below are what
## it writes, and stay editable for tuning.
enum Difficulty { NOVICE, STANDARD, RUTHLESS }
@export var difficulty: int = Difficulty.STANDARD
@export var ai_aim_jitter: float = 2.0        # degrees of slop on the AI's aim
@export var ai_think_min: float = 0.8         # it takes a beat before confirming
@export var ai_think_max: float = 2.2
## Movement candidates that get a full shot search, out of the eleven the AI
## ranks for safety. The rest are still ranked, just never shot from.
@export_range(1, 11, 1) var ai_moves_searched: int = 2
## Soft budget for the one AI search advanced each frame. A single candidate
## cannot be pre-empted, so keeping this low avoids visible planning hitches.
@export var ai_slice_usec: int = 1200

@export_group("Match")
## Hits needed to take the match. A hit does not end the round: the victim
## respawns and the world carries on exactly where it was.
@export_range(3, MAX_HITS_TO_WIN, 2) var hits_to_win: int = DEFAULT_HITS_TO_WIN
@export var respawn_invuln_turns: int = 1
@export var banner_duration: float = 2.4

@export_group("Visuals")
## Authored fighter skins are the normal presentation. Fighters without an
## approved skin still fall back independently to the legacy renderer.
@export var fighter_visuals_enabled: bool = true

@export_group("Replay")
## The match replay concatenates execution ticks only: planning, commit delays
## and SUPER introductions are deliberately absent. Retaining only the latest
## stretch keeps a very long, hitless match from growing memory without limit.
@export_range(0.25, 4.0, 0.05) var replay_speed: float = 1.5
@export_range(10.0, 120.0, 5.0) var replay_history_seconds: float = 30.0

@export_group("Loop Timing")
@export var planning_duration: float = 4.0
## Turns 1-3 use the authored window. Each later turn loses half a second until
## this floor. Multi-bot searches intentionally return the best candidate they
## have evaluated when the clock expires, so this is a gameplay-quality floor,
## not a promise that every exhaustive search finishes on every arena.
@export var planning_shrink_after_rounds: int = 3
@export var planning_shrink_per_round: float = 0.0
@export var minimum_planning_duration: float = 3.5
@export var execution_duration: float = 0.75
@export var commit_delay: float = 0.25
## Deal versus opening positions from the arena's sockets instead of fixed seats.
@export var randomize_spawns: bool = true
## Wall-clock pacing of the action phase. Engine.time_scale slows the fixed
## physics ticks, effects and animation together, so the simulation still
## advances one deterministic tick at a time and replays and lockstep agree.
@export_range(0.1, 1.0, 0.05) var execution_playback_speed: float = 0.35
## A hit drops to this speed and pushes the camera in on the victim for
## `kill_slowmo_duration` real seconds, so everyone sees who fell and to what.
@export_range(0.05, 1.0, 0.05) var kill_playback_speed: float = 0.15
@export_range(0.0, 3.0, 0.05) var kill_slowmo_duration: float = 1.4
## Afterwards the action eases back up to `execution_playback_speed` over this
## many real seconds, so players can re-read the board before it moves at pace.
@export_range(0.0, 3.0, 0.05) var kill_recover_duration: float = 1.0
@export_range(1.0, 2.0, 0.05) var kill_zoom: float = 1.35

@export_group("Movement")
## Seconds of piloted control per turn. The rest of the window coasts.
@export var movement_budget: float = 0.50
## Ghost piloting runs at this fraction of real time, below 1.0 for precision.
@export var pilot_time_scale: float = 0.5
@export var player_move_speed: float = 260.0
## Locomotion is part of each prototype's identity. These scales multiply the
## shared authored values above/below so the free-play tuning sandbox still
## moves the whole roster together while preserving the differences between
## fighters.
##
## Approximate full-jump rise at the default 780 impulse / 1400 gravity:
## Duelist 217px.
@export_group("Class Movement")
@export_subgroup("The Duelist")
@export_range(0.1, 2.0, 0.05) var dagger_move_speed_scale: float = 1.0
@export_range(0.0, 2.0, 0.05) var dagger_jump_impulse_scale: float = 1.0
@export_range(0.0, 2.0, 0.05) var dagger_air_jump_impulse_scale: float = 0.82
@export_range(0, 2, 1) var dagger_air_jumps: int = 1
@export_range(0.1, 2.0, 0.05) var dagger_fall_speed_scale: float = 1.0

@export_group("Movement")
@export var player_acceleration: float = 1800.0
@export var player_air_acceleration: float = 900.0
@export var jump_impulse: float = 780.0
## Local tuning uses the same scaled jump integration for ghosts and fighters.
@export var double_jump_enabled: bool = true
@export var jump_duration_scale: float = 1.0
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
## aged out instead. 900 ticks is 15s, twenty execution phases.
@export var arrow_max_ticks: int = 900
## One throw looses this many knives at once, fanned around the aim line.
@export var knives_per_shot: int = 2
## Total fan angle. A light throw scatters wide and slow, area denial you do
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
## The meter rewards the play the duel wants: clashing, moving, committing early,
## throwing and landing hits. Every source is deterministic and goes through
## `_gain_super`, which caps the meter and announces SUPER READY once. The shares
## are paced for an ACTIVE human turn (quick lock, full route, full throw, one
## clash, one dodge) to earn about 0.18, so a fighter who plays that way fills
## the meter every five or six rounds while passive play takes far longer.
## tools/sims/SuperMeterPaceSimulation.gd measures both that estimate and the slower
## cadence two AI Duelists produce.
## A clean opposing-knife clash grants this much meter if the owner is moving.
@export_range(0.01, 1.0, 0.005) var super_charge_per_clash: float = 0.06
@export var super_move_speed_min: float = 80.0
## A rival knife that sweeps within this distance of a moving fighter without
## hitting them is a dodge. Each knife credits a fighter once, and a window
## credits at most SUPER_DODGE_CREDITS_PER_WINDOW dodges per fighter.
@export_range(0.0, 1.0, 0.005) var super_charge_per_dodge: float = 0.04
@export var super_dodge_radius: float = 26.0
## Distance covered during an execution window earns meter linearly, reaching
## this much at `super_travel_reference` pixels. A full piloted half-second run
## plus its coast covers about 120px, so a committed route earns most of it and
## a jump earns the rest.
@export_range(0.0, 1.0, 0.005) var super_charge_per_window_travel: float = 0.03
@export var super_travel_reference: float = 140.0
## Locking a plan before the planning clock runs out earns up to this much,
## scaled by the fraction of the window left unused. The AI locks as if it had
## used half the window, so its instant decisions are not a meter engine.
@export_range(0.0, 1.0, 0.005) var super_charge_early_lock: float = 0.04
## Committing a throw earns this much at full charge, scaled by charge, so a
## fighter who keeps attacking out-earns one who waits.
@export_range(0.0, 1.0, 0.005) var super_charge_per_throw: float = 0.02
## Landing a legitimate hit rewards aggression; taking one is a small comeback.
@export_range(0.0, 1.0, 0.005) var super_charge_hit_landed: float = 0.10
@export_range(0.0, 1.0, 0.005) var super_charge_hit_taken: float = 0.05
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
## Visible opening of a newly aimed projectile's path, in moving seconds.
@export var aim_preview_duration: float = 0.45

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
var interception_mode: bool = false
## Trial 01 replaces score with one asymmetric objective: survive a short,
## authored sequence whose hostile plan is public before every execution.
var fate_trial_mode: bool = false
var fate_trial_windows_survived: int = 0
var fate_trial_succeeded: bool = false
var player_teams: Array[int] = [-1, -1, -1, -1]
var team_score: Array[int] = [0, 0]
var winning_team: int = -1
var player_roles: Array[String] = ["HUMAN", "AI", "AI", "AI"]
var player_devices: Array[int] = [-2, -1, -1, -1]
## Each CPU slot owns its preset. The scalar difficulty/exported tuning above
## remains the fallback for legacy match entry points and editor balancing.
var player_difficulties: Array[int] = [
	Difficulty.STANDARD, Difficulty.STANDARD, Difficulty.STANDARD, Difficulty.STANDARD,
]

var banner_text: String = ""
var banner_color: Color = Color.WHITE
var banner_time: float = 0.0

var rng := RandomNumberGenerator.new()
var _ai_think: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _ai_searches: Array = [null, null, null, null]
var _ai_step_cursor: int = 0
var _menu
var _roster: RosterLayer
var _setup: MatchSetupLayer
var _tuning
## Free-play CPU state. The ordinary Ai planner still authors each movement and
## shot; the sandbox simply rolls those plans into back-to-back live windows.
var _sandbox_ai_search = null
var _sandbox_ai_exec_tick: int = -1
var _sandbox_ai_accum: float = 0.0
var planning_time_left: float = 0.0
var planning_window_duration: float = 8.0
var commit_time_left: float = 0.0
var exec_tick: int = 0
var exec_ticks_total: int = 0
var winner: int = -1
## Result-screen selection. It stays separate from `level_index` so browsing
## levels never mutates the frozen winning frame; it is applied on rematch.
var rematch_level_index: int = 0
var rematch_level_name: String = ""

var platforms: Array = []
var solid_rects: Array[Rect2] = []
var world_bounds := Rect2(-160.0, -1600.0, 1600.0, 2600.0)

## Absolute simulated ticks since the match began. Moving geometry and hazards
## are pure functions of it, which is what lets planning project them forward
## instead of ambushing the player with them.
var world_tick: int = 0
var _has_movers: bool = false
## Static arena fields read by position: stasis zones scale integration time
## for bodies and knives. Authored in Levels.gd.
var zones: Array = []
## Tests can load a layout outside the rotation (see Levels.build_kinetic_proof).
var level_override: Dictionary = {}
## Projected collision sets, keyed by absolute tick. Dropped whenever the
## platform set itself changes (damage, level load, a mover being applied).
var _solids_cache: Dictionary = {}
## Pulse orbs. Empty on the static arenas.
var hazards: Array = []
## Blast impulses raised this window, so the aftermath is legible in the replay.
var _blasts_this_execution: int = 0

## TowerFall-style screen wrap. Anything leaving a wrapping edge re-enters the
## opposite one, arrows and players alike.
var wrap_x: bool = false
var wrap_y: bool = false
const ARENA_W := Levels.ARENA_W
const ARENA_H := Levels.ARENA_H
const WRAP_TOP := Levels.WRAP_TOP
const SEAM_MARGIN := 340.0   # how far from an edge a platform gets a seam copy

var players: Array = []
var arrows: Array = []
var player_weapons: Array[int] = [Weapon.KNIVES, Weapon.KNIVES, Weapon.KNIVES, Weapon.KNIVES]
var local_weapon_choices: Array[int] = [Weapon.KNIVES, Weapon.KNIVES, Weapon.KNIVES, Weapon.KNIVES]
var _next_volley: int = 1
var _next_arrow_id: int = 1

## Online mode is lockstep: this browser records only its assigned player and
## receives the rival plan after both sides confirm.
var online_mode: bool = false
var online_player: int = -1

var charging: Array[bool] = [false, false, false, false]
var stamina: Array[float] = [0.0, 0.0, 0.0, 0.0]
## Persistent for the whole match. It only resets when the super is actually
## released (or the match restarts), not between turns or after taking a hit.
var super_meter: Array[float] = [0.0, 0.0, 0.0, 0.0]
## Per execution window: where each body was at the last simulated tick, how far
## it has travelled, and how many dodges have already been credited.
var _exec_last_pos: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var _exec_travel: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _dodge_credits: Array[int] = [0, 0, 0, 0]
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
## Recorded path plus the coasted tail, always exactly one full window long.
var ghost_path: Array[PackedVector2Array] = [
	PackedVector2Array(), PackedVector2Array(), PackedVector2Array(), PackedVector2Array(),
]
## Velocity vectors and grounded samples parallel ghost_path, used only to select the
## correct visual pose for each planning ghost. Simulation still owns the data.
var ghost_velocity_path: Array[PackedVector2Array] = [
	PackedVector2Array(), PackedVector2Array(), PackedVector2Array(), PackedVector2Array(),
]
var ghost_ground_path: Array[PackedByteArray] = [
	PackedByteArray(), PackedByteArray(), PackedByteArray(), PackedByteArray(),
]
## A player's prediction depends only on frozen world state and that player's
## recorded movement. Most planning frames change neither, so rebuild lazily.
var _ghost_path_dirty: Array[bool] = [true, true, true, true]

var _backdrop: Node2D
var _arena: Arena
var _arrow_layer: Node2D
var _player_layer: Node2D
var _preview: Node2D
var _temporal_core: TemporalCore
var _hazard_layer: Node2D
var _camera: DuelCamera
var _effects
var _sfx
var _time_stop
var _super_freeze
var _transition: TransitionLayer
var _super_cutins_shown: Array[bool] = [false, false, false, false]
## GameManager owns the SUPER pause. The cut-in layer only animates for the
## same length; the simulation waits on this timer, not on the art.
@export var super_cutin_duration: float = 1.45
var _super_pause_left: float = 0.0
const EVENT_DIRECTION_SCRIPT := preload("res://scripts/EventDirection.gd")
var _event_direction
var _ui
## Online lockstep session: rooms, selection, plan relay, digest (OnlineSession.gd).
var _online: OnlineSession = OnlineSession.new(self)
## End-of-match replay recording and playback (MatchReplay.gd).
var _replay: MatchReplay = MatchReplay.new(self)
## Saved options and key bindings (SettingsStore.gd).
var _settings_store: SettingsStore = SettingsStore.new(self)
## Keyboard, mouse, pad and touch input (PlayerInput.gd).
var _player_input: PlayerInput = PlayerInput.new(self)
var _touch_controls: TouchControls
var _tutorial
var tutorial_mode: bool = false
var demo_match: bool = false
## Named ladder opponent per slot (-1 = plain difficulty preset), the rung the
## current Start Duel plays, and the rung a rematch will play.
var player_opponents: Array[int] = [-1, -1, -1, -1]
var demo_opponent: int = -1
var rematch_opponent: int = -1
var _practice
var _feedback
var _telemetry
var _telemetry_finished: bool = true
var hit_freeze_enabled: bool = true
var reduced_flashes: bool = false
var _hit_pause_left: float = 0.0
## Real seconds left in the kill slow-motion beat.
var _kill_slowmo_left: float = 0.0
## Real seconds left in the ease back from the kill beat to normal playback.
var _kill_recover_left: float = 0.0
var _hit_pause_used_this_execution: bool = false
var _secret_triple_match: bool = false
var offline_tuning_path: String = "user://offline_tuning.cfg"
var offline_tuning
var _offline_tuning_layer


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _ready() -> void:
	var user_args := OS.get_cmdline_user_args()
	_backdrop = BACKDROP_SCRIPT.new()
	_backdrop.gm = self
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
	_event_direction = EVENT_DIRECTION_SCRIPT.new()
	_event_direction.gm = self
	add_child(_event_direction)

	_ui = UI_SCRIPT.new()
	add_child(_ui)
	_ui.build(self)

	_touch_controls = TOUCH_CONTROLS_SCRIPT.new()
	add_child(_touch_controls)
	var touch_enabled := force_touch_controls or DisplayServer.is_touchscreen_available()
	_touch_controls.configure(self, touch_enabled)
	_touch_controls.confirm_requested.connect(_player_input._on_touch_confirm)
	_touch_controls.rollback_requested.connect(_player_input._on_touch_rollback)
	_touch_controls.reset_requested.connect(_player_input._on_touch_reset)
	_touch_controls.super_requested.connect(_player_input._on_touch_super)
	_touch_controls.menu_requested.connect(_player_input._on_touch_menu)
	_touch_controls.rematch_requested.connect(_player_input._on_touch_rematch)
	_touch_controls.replay_requested.connect(_player_input._on_touch_replay)
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

	_practice = preload("res://scripts/GuidedPractice.gd").new()
	_practice.gm = self
	add_child(_practice)
	_feedback = preload("res://scripts/FeedbackLayer.gd").new()
	_feedback.gm = self
	add_child(_feedback)
	_tutorial = TUTORIAL_SCRIPT.new()
	add_child(_tutorial)

	_telemetry = TELEMETRY_SCRIPT.new()
	add_child(_telemetry)

	_menu = MENU_SCRIPT.new()
	add_child(_menu)
	_menu.duel_requested.connect(start_demo_duel)
	_menu.interception_requested.connect(start_interception)
	_menu.feedback_requested.connect(open_feedback)
	_menu.quit_requested.connect(quit_demo)
	_menu.roster_requested.connect(_open_roster)
	_menu.fate_trial_requested.connect(start_fate_trial)
	_menu.sandbox_requested.connect(start_sandbox)
	_menu.tuning_requested.connect(_open_offline_tuning)
	_menu.online_requested.connect(_online._on_menu_online)
	_menu.tutorial_requested.connect(_on_menu_tutorial)
	_menu.option_changed.connect(_settings_store._on_option_changed)
	_menu.binding_changed.connect(_settings_store._on_binding_changed)
	_menu.bindings_reset.connect(_settings_store._on_bindings_reset)
	_menu.ui_navigated.connect(func(): _sfx.play("ui_move"))
	_menu.ui_accepted.connect(func(): _sfx.play("ui_accept"))

	_roster = ROSTER_SCRIPT.new()
	add_child(_roster)
	_roster.lineup_confirmed.connect(_on_lineup_confirmed)
	_roster.canceled.connect(_on_roster_canceled)
	_roster.ui_navigated.connect(func(): _sfx.play("ui_move"))
	_roster.ui_accepted.connect(func(): _sfx.play("ui_accept"))

	_setup = MATCH_SETUP_SCRIPT.new()
	add_child(_setup)
	_setup.match_confirmed.connect(_on_roster_confirmed)
	_setup.canceled.connect(_on_setup_canceled)
	_setup.ui_navigated.connect(func(): _sfx.play("ui_move"))
	_setup.ui_accepted.connect(func(): _sfx.play("ui_accept"))

	_online.build()

	_tuning = TUNING_SCRIPT.new()
	add_child(_tuning)

	_camera = CAMERA_SCRIPT.new()
	_camera.gm = self
	_camera.enabled = false
	add_child(_camera)

	_load_level(0)
	_spawn_players()
	_tuning.build(self)
	_tuning.visible = false
	_settings_store._load_settings()
	offline_tuning = OFFLINE_TUNING_SCRIPT.new()
	offline_tuning.initialize(self, offline_tuning_path)
	_offline_tuning_layer = OFFLINE_TUNING_LAYER_SCRIPT.new()
	add_child(_offline_tuning_layer)
	_offline_tuning_layer.build(self)
	_offline_tuning_layer.closed.connect(_close_offline_tuning)
	_menu.configure_options(_settings_store._settings)
	_player_input._assign_pads()
	Input.joy_connection_changed.connect(func(_d, _c):
		_player_input._assign_pads()
		if _roster != null:
			_roster.refresh_connections())
	_player_input._prev_mouse = get_viewport().get_mouse_position()
	_begin_planning(true)
	_open_menu()
	if "--vs-3-cpu" in user_args:
		start_vs_three_cpu()


## One knob for three, so a preset cannot be half-applied. NOVICE searches a
## single movement candidate and aims loosely enough to be dodged on read;
## RUTHLESS searches half the candidate set and barely misses. The think
## delay moves with them so a weaker opponent also feels less certain.
func set_difficulty(level: int) -> void:
	difficulty = clampi(level, Difficulty.NOVICE, Difficulty.RUTHLESS)
	var tuning := _difficulty_tuning(difficulty)
	ai_aim_jitter = tuning["aim_jitter"]
	ai_moves_searched = tuning["moves_searched"]
	ai_think_min = tuning["think_min"]
	ai_think_max = tuning["think_max"]
	player_difficulties.fill(difficulty)


func set_player_difficulty(player_index: int, level: int) -> void:
	if player_index < 0 or player_index >= player_difficulties.size():
		return
	player_difficulties[player_index] = clampi(
		level, Difficulty.NOVICE, Difficulty.RUTHLESS)


func player_difficulty(player_index: int) -> int:
	if player_index < 0 or player_index >= player_difficulties.size():
		return difficulty
	return player_difficulties[player_index]


func ai_aim_jitter_for(player_index: int) -> float:
	return float(_ai_tuning_for(player_index)["aim_jitter"])


func ai_moves_searched_for(player_index: int) -> int:
	return int(_ai_tuning_for(player_index)["moves_searched"])


func ai_think_range_for(player_index: int) -> Vector2:
	var tuning := _ai_tuning_for(player_index)
	var out := Vector2(float(tuning["think_min"]), float(tuning["think_max"]))
	return out


## A named opponent carries its own preset; every other CPU slot reads the
## difficulty ladder.
func _ai_tuning_for(player_index: int) -> Dictionary:
	var rung := player_opponent(player_index)
	if rung >= 0:
		return Opponents.tuning(rung)
	return _difficulty_tuning(player_difficulty(player_index))


func ai_style_for(player_index: int) -> Dictionary:
	var rung := player_opponent(player_index)
	return Opponents.style(rung) if rung >= 0 else Opponents.neutral_style()


func player_opponent(player_index: int) -> int:
	if player_index < 0 or player_index >= player_opponents.size():
		return -1
	return player_opponents[player_index]


func set_player_opponent(player_index: int, rung: int) -> void:
	if player_index < 0 or player_index >= player_opponents.size():
		return
	player_opponents[player_index] = rung if Opponents.valid(rung) else -1
	if Opponents.valid(rung):
		set_player_difficulty(player_index, Opponents.skill(rung))
	if player_index == 1:
		demo_opponent = player_opponents[1]
		rematch_opponent = demo_opponent


## Short seat label for tags and score lines: the nickname online, else "P1".
func player_tag(player_index: int) -> String:
	var nick := _online.online_nickname(player_index)
	return nick if not nick.is_empty() else "P%d" % (player_index + 1)


## Long seat label for banners: the nickname online, else "PLAYER 1".
func player_title(player_index: int) -> String:
	var nick := _online.online_nickname(player_index)
	return nick if not nick.is_empty() else "PLAYER %d" % (player_index + 1)


## The opponent's name where the HUD would otherwise show the fighter kit.
func slot_display_name(player_index: int) -> String:
	var rung := player_opponent(player_index)
	if rung >= 0 and is_ai(player_index):
		return Opponents.display_name(rung)
	return weapon_short_name(player_index)


## Experiments keep the numeric aim readouts (fire tick, elevation, draw). Every
## match a player reaches from the public menu gets the plain labels the ladder
## already uses, so Custom Match never looks like a tuning screen.
func player_facing_labels() -> bool:
	if _practice != null and _practice.active:
		return true
	return not (fate_trial_mode or state == Phase.FREEPLAY)


func ladder_progress() -> int:
	return clampi(int(_settings_store._settings.get("ladder_progress", 0)), 0, Opponents.count())


## Start Duel plays the first opponent not yet beaten; after the last one, it
## stays on the last.
func ladder_next_rung() -> int:
	return mini(ladder_progress(), Opponents.count() - 1)


func ladder_menu_line() -> String:
	var next := ladder_next_rung()
	if ladder_progress() >= Opponents.count():
		return "Ladder complete. Start Duel replays %s." % Opponents.display_name(next)
	return "Next: %s, %s." % [Opponents.display_name(next), Opponents.position_label(next).to_lower()]


func next_opponent_available() -> bool:
	return state == Phase.GAME_OVER and demo_match and winner == 0 and demo_opponent >= 0 \
		and demo_opponent + 1 < Opponents.count() and demo_opponent + 1 <= ladder_progress()


func start_next_opponent() -> void:
	if not next_opponent_available():
		return
	if _telemetry != null:
		_telemetry.note_rematch(turn)
	start_demo_duel(demo_opponent + 1)


## Beating the opponent the ladder currently points at unlocks the next one.
## Replaying an earlier rung changes nothing.
func _record_ladder_result(scorer: int) -> void:
	if not demo_match or demo_opponent < 0 or scorer != 0:
		return
	if demo_opponent >= ladder_progress():
		_settings_store._settings["ladder_progress"] = demo_opponent + 1
		_settings_store._save_settings()


func _difficulty_tuning(level: int) -> Dictionary:
	match clampi(level, Difficulty.NOVICE, Difficulty.RUTHLESS):
		Difficulty.NOVICE:
			return {"aim_jitter": 7.0, "moves_searched": 1,
				"think_min": 1.4, "think_max": 3.0}
		Difficulty.RUTHLESS:
			return {"aim_jitter": 0.6, "moves_searched": 5,
				"think_min": 0.5, "think_max": 1.2}
		_:
			return {"aim_jitter": 2.0, "moves_searched": 2,
				"think_min": 0.8, "think_max": 2.2}


func difficulty_name() -> String:
	return _difficulty_label(difficulty)


func player_difficulty_name(player_index: int) -> String:
	return _difficulty_label(player_difficulty(player_index))


func _difficulty_label(level: int) -> String:
	match level:
		Difficulty.NOVICE: return "NOVICE"
		Difficulty.RUTHLESS: return "RUTHLESS"
		_: return "STANDARD"


func is_ai(i: int) -> bool:
	return not online_mode and i >= 0 and i < players.size() \
		and i < player_roles.size() and player_roles[i] == "AI"


## The AI's plan is hidden for the same reason a human opponent's would be if we
## could hide it: it plans blind, so it must be planned against blind.
func hides_plan(i: int) -> bool:
	if online_mode:
		return i != online_player and state != Phase.GAME_OVER
	if fate_trial_mode and i == 1:
		return false
	return is_ai(i) and state != Phase.GAME_OVER


func _open_menu() -> void:
	_abandon_match("menu")
	if _practice != null: _practice.stop()
	if state == Phase.REPLAY:
		_replay._finish_match_replay()
	_reset_experiment_modes()
	_cancel_super_cutin()
	if _event_direction != null:
		_event_direction.clear()
	if _tutorial != null:
		_tutorial.stop()
	tutorial_mode = false
	state = Phase.MENU
	if offline_tuning != null:
		offline_tuning.apply_offline()
	if _offline_tuning_layer != null:
		_offline_tuning_layer.close()
	banner_time = 0.0
	_ui.visible = false     # the arena stays as a backdrop; the HUD would be noise
	_tuning.visible = false
	if _online._online_lobby != null:
		_online._online_lobby.close()
	_online._close_online_selection()
	if _roster != null:
		_roster.close()
	if _setup != null:
		_setup.close()
		_menu.backdrop_level = _setup.level
	_menu.ladder_line = ladder_menu_line()
	_menu.open()
	if _transition != null:
		_transition.play("ZAWARUDO", "TIME AWAITS", PLAYER_COLORS[0], reduced_flashes)


func _open_offline_tuning() -> void:
	if online_mode or state != Phase.MENU:
		return
	_menu.close()
	_transition.visible = false
	_offline_tuning_layer.open()


func _close_offline_tuning() -> void:
	_menu.open()
	_menu._select(_menu.ROW_TUNING)


## One screen owns every local-match decision, so there is exactly one way in
## and exactly one configuration coming back out of it.
func _open_roster() -> void:
	_reset_experiment_modes()
	fate_trial_mode = false
	tutorial_mode = false
	online_mode = false
	online_player = -1
	state = Phase.ROSTER
	_ui.visible = false
	_tuning.visible = false
	_menu.close()
	if _transition != null:
		_transition.visible = false
	_setup.close()
	_roster.open()


func _on_roster_canceled() -> void:
	state = Phase.MENU
	_menu.backdrop_level = _setup.level
	_menu.open()


## Who is fighting is settled; the rules screen takes it from here.
func _on_lineup_confirmed(lineup: Dictionary) -> void:
	state = Phase.MATCH_SETUP
	_roster.close()
	_setup.open(lineup)


## Stepping back is a step, not a reset: the lineup screen reopens holding
## exactly the fighters it handed over.
func _on_setup_canceled() -> void:
	state = Phase.ROSTER
	_setup.close()
	_roster.open()


func _on_roster_confirmed(config: Dictionary) -> void:
	var mode := int(config.get("mode", MatchSetupLayer.BattleMode.VS))
	var count := clampi(int(config.get("player_count", 2)), 2, MAX_PLAYERS)
	var weapons: Array = config.get("weapons", [])
	_menu.backdrop_level = int(config.get("level", 0))
	if mode == MatchSetupLayer.BattleMode.FREE_PLAY:
		_start_freeplay(int(config.get("level", 0)), weapons, count,
			config.get("roles", []), config.get("devices", []))
		return
	team_mode = mode == MatchSetupLayer.BattleMode.TEAM_BATTLE
	_start_local_match(int(config.get("level", 0)), count, weapons, config)


## Test and capture seam: the roster screen's outcome without driving the
## roster screen. It still travels the one configuration path a real match
## uses, so a capture cannot diverge from what a player would get.
func start_quick_match(ai: bool, lvl: int, requested_players: int = 2,
		picks: Array = []) -> void:
	var count := clampi(requested_players, 2, MAX_PLAYERS)
	_roster._debug_pads.clear()
	for i in MAX_PLAYERS:
		_roster.weapons[i] = _roster_weapon_or_default(int(picks[i])) \
			if i < picks.size() else Weapon.KNIVES
		if i >= count:
			_roster.kinds[i] = RosterLayer.SlotKind.OPEN
		elif i == 0 or not ai:
			_roster.kinds[i] = RosterLayer.SlotKind.PLAYER
		else:
			_roster.kinds[i] = RosterLayer.SlotKind.CPU
		_roster.devices[i] = KEYBOARD_DEVICE if i == 0 else NO_DEVICE
		_roster.ready_slots[i] = false
	if not ai:
		# Stand in for the pads a local duel's other seats would have claimed.
		for i in range(1, count):
			_roster._debug_pads.append(i - 1)
			_roster.devices[i] = i - 1
	_roster._normalize()
	_setup.battle_mode = MatchSetupLayer.BattleMode.VS
	_setup.level = posmod(lvl, Levels.count())
	_setup.configure(_roster.build_lineup())
	_on_roster_confirmed(_setup.build_config())


## Playtest shortcut for `Play-1v3-CPU.bat`: keyboard Player 1 against three
## STANDARD CPUs on the first arena, skipping the menu, roster and setup.
func start_vs_three_cpu() -> void:
	for i in MAX_PLAYERS:
		_roster.difficulties[i] = Difficulty.STANDARD
	start_quick_match(true, 0, MAX_PLAYERS)


## Test and capture seam, as above, for the tuning sandbox.
func start_quick_freeplay(lvl: int) -> void:
	team_mode = false
	_start_freeplay(lvl, [])


func start_sandbox() -> void:
	_reset_experiment_modes()
	fate_trial_mode = false
	team_mode = false
	_start_freeplay(0, [Weapon.KNIVES], 1, ["HUMAN"], [KEYBOARD_DEVICE])


## Fixed local experiment. Saved offline tuning is restored when this mode exits.
func start_interception() -> void:
	_reset_experiment_modes()
	if _practice != null:
		_practice.stop()
	interception_mode = true
	team_mode = false
	fate_trial_mode = false
	tutorial_mode = false
	online_mode = false
	online_player = -1
	if offline_tuning != null:
		offline_tuning.apply_standard()
	double_jump_enabled = false
	player_air_acceleration = 450.0
	core_hitless_turns_to_announce = 1
	winning_team = -1
	team_score = [0, 0]
	for i in MAX_PLAYERS:
		player_teams[i] = -1
		player_roles[i] = "HUMAN" if i == 0 else "AI"
		player_devices[i] = KEYBOARD_DEVICE if i == 0 else NO_DEVICE
		set_player_difficulty(i, Difficulty.STANDARD)
	player_weapons.fill(Weapon.KNIVES)
	local_weapon_choices[0] = Weapon.KNIVES
	local_weapon_choices[1] = Weapon.KNIVES
	vs_ai = true
	hits_to_win = 3
	_set_player_count(2)
	_ui.visible = true
	_ui.show_controls(true)
	_tuning.visible = false
	_menu.close()
	_roster.close()
	_setup.close()
	_load_level(0)
	restart()
	_sfx.play("match_start")
	_begin_match_telemetry("ai_interception")
	_transition.play("INTERCEPTION", "ONE JUMP · COMMIT IN AIR · CONTEST THE CORE",
		PLAYER_COLORS[0], reduced_flashes)


## Leaves every experiment mode: restores offline tuning after Interception,
## clears the demo flag and switches the kill camera off.
func _reset_experiment_modes() -> void:
	if interception_mode:
		interception_mode = false
		if offline_tuning != null:
			offline_tuning.apply_offline()
	demo_match = false
	if _camera == null:
		return
	_camera.enabled = false
	_camera.reset_view()


## Direct single-player prototype. The hostile Duelist is not a general-purpose
## bot: its complete plan is authored and visible before the player commits.
func start_fate_trial() -> void:
	_reset_experiment_modes()
	team_mode = false
	fate_trial_mode = true
	fate_trial_windows_survived = 0
	fate_trial_succeeded = false
	tutorial_mode = false
	online_mode = false
	online_player = -1
	winning_team = -1
	team_score = [0, 0]
	for i in MAX_PLAYERS:
		player_teams[i] = -1
		player_roles[i] = "HUMAN" if i == 0 else "AI"
		player_devices[i] = KEYBOARD_DEVICE if i == 0 else NO_DEVICE
	player_weapons.fill(Weapon.KNIVES)
	local_weapon_choices[0] = Weapon.KNIVES
	local_weapon_choices[1] = Weapon.KNIVES
	vs_ai = true
	hits_to_win = FATE_TRIAL_WINDOWS
	_set_player_count(2)
	_ui.visible = true
	_tuning.visible = false
	_menu.close()
	_roster.close()
	_setup.close()
	_load_level(0)
	restart()
	_sfx.play("match_start")
	_begin_match_telemetry("fate_trial_01")
	_transition.play("FATE TRIAL 01 // THE CROSSFIRE",
		"SURVIVE THREE REVEALED VOLLEYS", PLAYER_COLORS[0], reduced_flashes)


func sandbox_cycle_player_character(direction: int = 1) -> void:
	if state != Phase.FREEPLAY or players.is_empty() or direction == 0:
		return
	player_weapons[0] = Roster.step(player_weapons[0], direction)
	local_weapon_choices[0] = player_weapons[0]
	_reset_freeplay()
	_sandbox_banner("P1 // %s" % Roster.short_name(player_weapons[0]), PLAYER_COLORS[0])


func sandbox_cycle_level(direction: int = 1) -> void:
	if state != Phase.FREEPLAY or direction == 0:
		return
	_load_level(level_index + direction)
	_reset_freeplay()
	_sandbox_banner("ARENA %d // %s" % [level_index + 1, level_name],
		Color(0.72, 0.86, 1.0))


func sandbox_toggle_ai() -> void:
	if state != Phase.FREEPLAY:
		return
	var removing := sandbox_has_ai()
	if removing:
		player_roles[1] = "DUMMY"
		_set_player_count(1)
	else:
		player_roles[1] = "AI"
		player_devices[1] = NO_DEVICE
		_set_player_count(2)
	vs_ai = sandbox_has_ai()
	_load_level(level_index)
	_reset_freeplay()
	if removing:
		_sandbox_banner("CPU REMOVED", Color(0.62, 0.68, 0.78))
	else:
		_sandbox_banner("CPU ADDED // %s" % Roster.short_name(player_weapons[1]),
			PLAYER_COLORS[1])


func sandbox_cycle_ai_character(direction: int = 1) -> void:
	if state != Phase.FREEPLAY or not sandbox_has_ai() or direction == 0:
		return
	player_weapons[1] = Roster.step(player_weapons[1], direction)
	local_weapon_choices[1] = player_weapons[1]
	_reset_freeplay()
	_sandbox_banner("CPU // %s" % Roster.short_name(player_weapons[1]), PLAYER_COLORS[1])


func sandbox_cycle_ai_difficulty(direction: int = 1) -> void:
	if state != Phase.FREEPLAY or not sandbox_has_ai() or direction == 0:
		return
	var choices := Difficulty.RUTHLESS - Difficulty.NOVICE + 1
	var next_level := Difficulty.NOVICE + posmod(
		player_difficulty(1) - Difficulty.NOVICE + direction, choices)
	set_player_difficulty(1, next_level)
	_reset_sandbox_ai_cycle()
	_sandbox_banner("CPU SKILL // %s" % player_difficulty_name(1), PLAYER_COLORS[1])


func sandbox_has_ai() -> bool:
	return state == Phase.FREEPLAY and player_count > 1 and is_ai(1)


func _sandbox_banner(text: String, color: Color) -> void:
	banner_text = text
	banner_color = color
	banner_time = 1.2
	if _tuning != null:
		_tuning.refresh()


## The roster screen is the only source of a local match, so the whole
## configuration arrives at once instead of being reassembled from defaults.
func _start_local_match(lvl: int, requested_players: int, weapons: Array,
		setup: Dictionary) -> void:
	demo_match = false
	_reset_experiment_modes()
	fate_trial_mode = false
	tutorial_mode = false
	online_mode = false
	online_player = -1
	if offline_tuning != null:
		if _practice != null and _practice.active:
			offline_tuning.apply_standard()
		else:
			offline_tuning.apply_offline(false)
	hits_to_win = clampi(int(setup.get("match_lives", DEFAULT_HITS_TO_WIN)), 3, MAX_HITS_TO_WIN)
	set_difficulty(int(setup.get("difficulty", difficulty)))
	var configured_roles: Array = setup.get("roles", [])
	var configured_devices: Array = setup.get("devices", [])
	var configured_teams: Array = setup.get("teams", [])
	var configured_difficulties: Array = setup.get("difficulties", [])
	if not team_mode:
		winning_team = -1
		team_score = [0, 0]
	for i in MAX_PLAYERS:
		player_roles[i] = str(configured_roles[i]) if i < configured_roles.size() else "AI"
		player_devices[i] = int(configured_devices[i]) \
			if i < configured_devices.size() else NO_DEVICE
		player_teams[i] = int(configured_teams[i]) if i < configured_teams.size() else -1
		var player_skill := int(configured_difficulties[i]) \
			if i < configured_difficulties.size() else difficulty
		set_player_difficulty(i, player_skill)
	var configured_opponents: Array = setup.get("opponents", [])
	for i in MAX_PLAYERS:
		player_opponents[i] = -1
		if i < configured_opponents.size():
			set_player_opponent(i, int(configured_opponents[i]))
	demo_opponent = player_opponents[1]
	rematch_opponent = demo_opponent
	vs_ai = player_roles.slice(0, requested_players).has("AI")
	player_weapons.fill(Weapon.KNIVES)
	for i in mini(requested_players, weapons.size()):
		player_weapons[i] = _roster_weapon_or_default(int(weapons[i]))
	for i in mini(requested_players, local_weapon_choices.size()):
		local_weapon_choices[i] = player_weapons[i]
	_set_player_count(requested_players)
	_ui.visible = true
	_tuning.visible = false
	_menu.close()
	_roster.close()
	_setup.close()
	_load_level(lvl)
	restart()
	_sfx.play("match_start")
	var team_shape := "%dv%d" % [
		int(ceil(float(requested_players) / 2.0)), int(requested_players / 2),
	]
	var telemetry_mode: String
	if team_mode:
		telemetry_mode = "local_team_%s" % team_shape
	elif vs_ai:
		telemetry_mode = _ai_telemetry_mode()
	elif requested_players == 2:
		telemetry_mode = "local_2p_%s_%s" % [
			weapon_short_name(0).to_lower(), weapon_short_name(1).to_lower(),
		]
	else:
		telemetry_mode = "local_%dp" % requested_players
	if _practice == null or not _practice.active:
		_begin_match_telemetry(telemetry_mode)
	var matchup: String
	if team_mode:
		matchup = "CRIMSON VS AZURE // %s" % team_shape.to_upper()
	elif requested_players > 2:
		matchup = "%dP ROSTER" % requested_players
	elif vs_ai:
		matchup = "VS AI"
	else:
		matchup = "%s VS %s" % [weapon_short_name(0), weapon_short_name(1)]
	_transition.play("%s // %s" % [matchup, level_name],
		"WRITE THE MOVE", PLAYER_COLORS[0], reduced_flashes)


func _on_menu_tutorial() -> void:
	if offline_tuning != null:
		offline_tuning.apply_standard()
	_practice.start()


func _open_reference_briefing() -> void:
	_reset_experiment_modes()
	team_mode = false
	fate_trial_mode = false
	tutorial_mode = true
	online_mode = false
	online_player = -1
	state = Phase.TUTORIAL
	_ui.visible = false
	_tuning.visible = false
	_menu.close()
	_tutorial.start(self)
	_transition.visible = false


## Free play: no turns, no freeze. Players under continuous control so the
## movement and shooting can be judged by feel, with the tuning values editable
## live. Whatever you set here is what the real match uses afterwards.
func _start_freeplay(lvl: int, weapons: Array, requested_players: int = 2,
		configured_roles: Array = [], configured_devices: Array = []) -> void:
	_reset_experiment_modes()
	fate_trial_mode = false
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
	if offline_tuning != null:
		offline_tuning.apply_offline(false)
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


func _reset_freeplay() -> void:
	for a in arrows:
		a.queue_free()
	arrows.clear()
	_effects.clear_all()
	_load_level(level_index)
	for i in players.size():
		var p: Player = players[i]
		p.fighter_style = player_weapons[i]
		_sync_fighter_visual(p, i)
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
		p.queue_redraw()
	charging[0] = false
	_player_input._charge_t[0] = 0.0
	_player_input._jump_prev[0] = _player_input._jump_input_held(0)
	_reset_temporal_core()
	banner_time = 0.0
	_reset_sandbox_ai_cycle()
	if _tuning != null:
		_tuning.refresh()


func _reset_sandbox_ai_cycle() -> void:
	_sandbox_ai_search = null
	_sandbox_ai_exec_tick = -1
	_sandbox_ai_accum = 0.0
	if sandbox_has_ai() and players.size() > 1:
		players[1].plan.start_new_turn()
		_reset_pilot(1)


## Wraps a point back into the arena. Vertical wrapping uses the actual screen
## edges; visible level geometry below the HUD teaches where that route opens.
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


func _seam_copies(r: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = [r]
	if wrap_x:
		if r.position.x < SEAM_MARGIN:
			out.append(Rect2(r.position + Vector2(ARENA_W, 0.0), r.size))
		if r.end.x > ARENA_W - SEAM_MARGIN:
			out.append(Rect2(r.position - Vector2(ARENA_W, 0.0), r.size))
	return out


## `abs_tick` is the tick the gates are evaluated at; it defaults to the live
## world tick, which every caller except `_apply_movers` means.
func _rebuild_solids(abs_tick: int = -1) -> void:
	var at: int = world_tick if abs_tick < 0 else abs_tick
	var r: Array[Rect2] = []
	_has_movers = false
	for pf in platforms:
		if pf.has("motion") or pf.has("cycle"):
			_has_movers = true
		if pf.has("cycle"):
			pf["present"] = platform_present_at(pf, at)
			var left: Array = Mover.cycle_ticks_left(pf["cycle"], at)
			pf["cycle_fraction"] = float(left[0]) / float(maxi(int(left[1]), 1))
			if not pf["present"]:
				var none: Array[Rect2] = []
				pf["rects"] = none
				continue
		var copies := _seam_copies(pf["rect"])
		pf["rects"] = copies
		r.append_array(copies)
	solid_rects = r
	_solids_cache.clear()


## A shutter is part of the world only while its clock says so. Static pieces
## are always present.
func platform_present_at(pf: Dictionary, abs_tick: int) -> bool:
	return not pf.has("cycle") or Mover.cycle_solid(pf["cycle"], abs_tick)


## How fast time runs at a point: 1 outside every stasis field, the field's
## scale inside. Bodies and knives integrate with this factor, so the ghost,
## the knife preview and the AI all slow down exactly where execution does.
func time_scale_at(p: Vector2) -> float:
	if zones.is_empty():
		return 1.0
	var scale := 1.0
	for zone in zones:
		if zone["rect"].has_point(p):
			scale = minf(scale, float(zone["time_scale"]))
	return scale


# ------------------------------------------------------- moving geometry -----
#
# Everything below answers one question, "where is the world at tick N?", and
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
		if not platform_present_at(pf, abs_tick):
			continue
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
		if not platform_present_at(pf, world_tick if abs_tick < 0 else abs_tick):
			continue
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
	_rebuild_solids(abs_tick)
	_arena.setup(platforms)


func _load_level(index: int) -> void:
	level_index = posmod(index, Levels.count())
	var lv := Levels.build_fate_trial_crossfire() if fate_trial_mode else \
		(Levels.build_tutorial() if tutorial_mode else Levels.build(level_index, player_count))
	if interception_mode:
		lv = Levels.build_interception()
	if _practice != null and _practice.active:
		lv = Levels.build_tutorial()
	if not level_override.is_empty():
		lv = level_override.duplicate(true)
	level_name = lv["name"]
	_backdrop.show_level(level_index)
	level_wrap = Levels.wrap_label(lv)
	rematch_level_index = level_index
	rematch_level_name = level_name
	wrap_x = lv["wrap_x"]
	wrap_y = lv["wrap_y"]
	platforms = lv["platforms"]
	zones = lv.get("zones", [])
	_arena.configure_level(level_index, wrap_x, wrap_y)
	if _effects != null and _effects.has_method("set_level_theme"):
		_effects.set_level_theme(_arena.level_theme)
	_arena.setup_fields(zones)
	var sp: Array = lv["spawns"]
	for i in MAX_PLAYERS:
		spawns[i] = sp[i]
	respawn_points.clear()
	for point in lv.get("respawn_points", sp):
		respawn_points.append(point)
	if _is_duel_vs_cpu():
		_seat_human_left()
	elif _uses_random_spawns(lv):
		_shuffle_spawns(lv.get("hazards", []))
	core_spawn_points.clear()
	for point in lv.get("core_spawns", []):
		core_spawn_points.append(point)
	world_tick = 0
	_rebuild_solids()
	_arena.setup(platforms)
	_load_hazards(lv.get("hazards", []))


## A single human against one CPU always opens on the authored left socket, so
## the player learns one fixed reading of each arena.
func _is_duel_vs_cpu() -> bool:
	if online_mode or player_count != 2 or player_roles.size() < 2:
		return false
	var seats: Array = player_roles.slice(0, 2)
	return seats.has("HUMAN") and seats.has("AI")


func _seat_human_left() -> void:
	var left: Vector2 = spawns[0] if spawns[0].x <= spawns[1].x else spawns[1]
	var right: Vector2 = spawns[1] if left == spawns[0] else spawns[0]
	var human := 0 if player_roles[0] == "HUMAN" else 1
	spawns[human] = left
	spawns[1 - human] = right


## Other versus matches deal opening positions at random. Authored situations
## (lessons, trials, Interception) keep theirs.
func _uses_random_spawns(lv: Dictionary) -> bool:
	if not randomize_spawns or not level_override.is_empty():
		return false
	if fate_trial_mode or tutorial_mode or interception_mode:
		return false
	if _practice != null and _practice.active:
		return false
	return not lv.get("respawn_points", []).is_empty()


## Picks each fighter's opening socket from this board's supported spawn and
## respawn sockets, keeping rivals apart and out of hazard blasts. One draw from
## the shared `rng` seeds the deal, so online peers that share the match seed
## deal the same positions.
func _shuffle_spawns(hazard_specs: Array) -> void:
	var deal := RandomNumberGenerator.new()
	deal.seed = rng.randi()
	var pool: Array[Vector2] = []
	var candidates: Array[Vector2] = []
	for i in player_count:
		candidates.append(spawns[i])
	candidates.append_array(respawn_points)
	for point: Vector2 in candidates:
		if not pool.has(point) and not _inside_hazard_blast(point, hazard_specs):
			pool.append(point)
	if pool.size() < player_count:
		return
	var min_gap: float = SPAWN_MIN_GAP_DUEL if player_count <= 2 else SPAWN_MIN_GAP_CROWD
	var chosen: Array[Vector2] = []
	for i in player_count:
		var open: Array[Vector2] = []
		var best := pool[0]
		var best_gap := -INF
		for point: Vector2 in pool:
			if chosen.has(point):
				continue
			var gap := INF
			for other: Vector2 in chosen:
				gap = minf(gap, wrapped_distance(point, other))
			if gap >= min_gap:
				open.append(point)
			if gap > best_gap:
				best_gap = gap
				best = point
		chosen.append(open[deal.randi_range(0, open.size() - 1)] if not open.is_empty() else best)
	for i in player_count:
		spawns[i] = chosen[i]


func wrapped_distance(a: Vector2, b: Vector2) -> float:
	var delta := b - a
	if wrap_x and absf(delta.x) > ARENA_W * 0.5:
		delta.x -= signf(delta.x) * ARENA_W
	if wrap_y and absf(delta.y) > ARENA_H * 0.5:
		delta.y -= signf(delta.y) * ARENA_H
	return delta.length()


## An opening socket inside an orb's reach (anywhere along its rail) would let
## the first knife into that orb decide the round.
func _inside_hazard_blast(point: Vector2, hazard_specs: Array) -> bool:
	for spec: Dictionary in hazard_specs:
		if int(spec.get("min_players", 2)) > player_count:
			continue
		var reach: float = float(spec.get("blast_radius", 180.0)) + Player.HALF.length()
		reach += float(spec.get("motion", {}).get("travel", 0.0))
		if wrapped_distance(point, spec["home"]) <= reach:
			return true
	return false


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
	_sync_fighter_visual(p, i)
	players.append(p)


func _fighter_skin_for(i: int):
	if not fighter_visuals_enabled:
		return null
	# A fighter is drawn the same way in every slot; the player's own accent is
	# what separates two people who picked it, so the roster's duplicate rule
	# stays legible instead of putting two identical figures on the board.
	var identity: Color = PLAYER_COLORS[i % PLAYER_COLORS.size()]
	if player_weapons[i] == Weapon.KNIVES:
		return FIGHTER_SKIN_SCRIPT.animated_executor_proof(identity)
	return null


func _sync_fighter_visual(p: Player, i: int) -> void:
	var fighter_skin = _fighter_skin_for(i)
	var visual := p.get_node_or_null("FighterVisual") as FighterVisual
	if fighter_skin == null:
		p.draw_legacy_visual = true
		if visual != null:
			p.remove_child(visual)
			visual.free()
		return
	if visual == null:
		visual = FIGHTER_VISUAL_SCRIPT.new()
		visual.name = "FighterVisual"
		visual.configure(p, fighter_skin)
		p.add_child(visual)
	else:
		visual.configure(p, fighter_skin)
	p.draw_legacy_visual = false


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
	_player_input._assign_pads()


func _default_aim_vector(i: int) -> Vector2:
	return Vector2(1.0 if spawns[i].x < ARENA_W * 0.5 else -1.0, -0.45)


func arrow_speed_for(power: float) -> float:
	return lerpf(arrow_speed_min, arrow_speed_max, clampf(power, 0.0, 1.0))


func can_pilot_move(i: int) -> bool:
	return i >= 0 and i < players.size()


## Per-fighter movement stats. The slot index is unused while the Duelist is
## the only fighter; it stays in each signature so a new kit can branch here.
func movement_speed_scale(_i: int) -> float:
	return dagger_move_speed_scale


func jump_impulse_for(_i: int) -> float:
	return jump_impulse * dagger_jump_impulse_scale / jump_duration_scale


func air_jump_impulse_for(_i: int) -> float:
	return jump_impulse * dagger_air_jump_impulse_scale / jump_duration_scale if double_jump_enabled else 0.0


func air_jumps_for(_i: int) -> int:
	return dagger_air_jumps if double_jump_enabled else 0


func max_fall_speed_for(_i: int) -> float:
	return max_fall_speed * dagger_fall_speed_scale / jump_duration_scale


func movement_gravity() -> float:
	return gravity / (jump_duration_scale * jump_duration_scale)


func _roster_weapon_or_default(value: int) -> int:
	return value if value in Roster.ORDER else Weapon.KNIVES


func weapon_short_name(i: int) -> String:
	return Roster.short_name(
		player_weapons[i] if i >= 0 and i < player_weapons.size() else Weapon.KNIVES)


## Authored launch: power changes speed, while the player's aim owns direction.
func knife_launch_velocity(aim: Vector2, power: float) -> Vector2:
	var direct: Vector2 = aim.normalized()
	if direct.is_zero_approx():
		direct = Vector2.RIGHT
	return direct * arrow_speed_for(power)


## One launch velocity per knife in the fan, rotated about the aim line.
func knife_launch_velocities(aim: Vector2, power: float, secret_triple: bool = false) -> Array[Vector2]:
	secret_triple = secret_triple or _secret_triple_match
	var base: Vector2 = knife_launch_velocity(aim, power)
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
	return float(maxi(0, _replay._replay_frames.size() - 1 - _replay._replay_frame_index)) \
		/ float(Engine.physics_ticks_per_second) / maxf(replay_speed, 0.01)


# -------------------------------------------------------------- main loop ----

func _process(_delta: float) -> void:
	Engine.time_scale = presentation_time_scale()


## Planning, menus and the SUPER cut-in run at full speed. Only moving time
## and a fresh kill are slowed.
func presentation_time_scale() -> float:
	if state == Phase.EXECUTING and not _super_pause_active():
		if _kill_slowmo_left > 0.0:
			return kill_playback_speed
		if _kill_recover_left > 0.0 and kill_recover_duration > 0.0:
			var t: float = smoothstep(0.0, 1.0, 1.0 - _kill_recover_left / kill_recover_duration)
			return lerpf(kill_playback_speed, execution_playback_speed, t)
		return execution_playback_speed
	if state == Phase.GAME_OVER and _kill_slowmo_left > 0.0:
		return kill_playback_speed
	return 1.0


func _begin_kill_beat(at: Vector2) -> void:
	if kill_slowmo_duration <= 0.0:
		return
	_kill_slowmo_left = kill_slowmo_duration
	_kill_recover_left = 0.0
	if _camera != null:
		# Hold the push-in for the slow death; it eases out as play resumes. If
		# planning starts first, the camera snaps whole so the mouse aims true.
		_camera.focus_kill(at, kill_zoom, kill_slowmo_duration)


func _physics_process(delta: float) -> void:
	# The physics step is fixed; under time_scale each one spans more real time.
	# The kill beat is measured in real seconds.
	var real_delta: float = delta / maxf(Engine.time_scale, 0.001)
	if _kill_slowmo_left > 0.0:
		_kill_slowmo_left = maxf(0.0, _kill_slowmo_left - real_delta)
		if _kill_slowmo_left <= 0.0:
			_kill_recover_left = kill_recover_duration
	elif _kill_recover_left > 0.0:
		_kill_recover_left = maxf(0.0, _kill_recover_left - real_delta)
	if _feedback != null and _feedback.visible: return
	# The opening wipe is presentation, not part of the player's planning seconds.
	if demo_match and state == Phase.PLANNING and _transition.visible: return
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
		Phase.ROSTER:
			return
		Phase.MATCH_SETUP:
			return
		Phase.ONLINE_LOBBY, Phase.ONLINE_SELECT:
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
			if _ui._turn_review.visible:
				return
			_player_input._poll_planning_input(delta)
			var tutorial_waiting: bool = tutorial_mode and _tutorial != null \
				and not _tutorial.timed_turns_started
			if tutorial_waiting and _tutorial.observe_planning():
				_ui.refresh()
				return
			_tick_ai(delta)
			_update_facing()
			_refresh_dirty_ghost_paths()
			if not tutorial_waiting:
				if planning_time_left > 0.0 and planning_time_left <= delta and _telemetry != null:
					_telemetry.record("planning_timeout", turn, {"live_knives": arrows.size(),
						"movement_ticks": players[_player_input._keyboard_player()].plan.recorded_ticks(),
						"has_throw": players[_player_input._keyboard_player()].plan.has_shot()})
				planning_time_left -= delta
			if not tutorial_waiting and planning_time_left <= 0.0:
				planning_time_left = 0.0
				if online_mode:
					# Each client submits independently; execution only begins after
					# Cloudflare has both private plans.
					if not _online._online_plan_sent:
						_confirm(online_player)
				else:
					# Local modes lock whatever is on the table and fire at once.
					_begin_execution()
		Phase.COMMITTING:
			commit_time_left -= delta
			if commit_time_left <= 0.0:
				_begin_execution()
		Phase.EXECUTING:
			# A kill near the end of the window holds the last frame until its
			# slow-motion beat has played, instead of cutting straight to planning.
			if exec_tick >= exec_ticks_total:
				if _kill_slowmo_left <= 0.0:
					_end_execution()
				_preview.queue_redraw()
				_ui.refresh()
				return
			# The SUPER pause is a GameManager timer on frame time. No deterministic
			# simulation tick is consumed until it has run out (or the cut-in was
			# explicitly cancelled).
			if _super_pause_left > 0.0:
				_super_pause_left = maxf(0.0, _super_pause_left - delta)
			if not _super_pause_active():
				# The fixed tick, never the frame delta. The planning ghost is built
				# from tick_dt(), so execution has to integrate with the same number
				# or the plan the player committed to stops being the one that runs.
				_sim_tick(tick_dt())
				if not _super_pause_active():
					_replay._capture_replay_frame()
					if online_mode and state == Phase.GAME_OVER:
						exec_tick += 1
						_online._report_online_match_over()
					elif state == Phase.EXECUTING:
						exec_tick += 1
						# A kill on the final tick must not be undone by ending the window.
						if exec_tick >= exec_ticks_total and _kill_slowmo_left <= 0.0:
							_end_execution()
		Phase.GAME_OVER:
			_player_input._poll_game_over_pad()
		Phase.REPLAY:
			_player_input._poll_replay_pad()
			if state == Phase.REPLAY:
				_replay._tick_match_replay(delta)

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
			_super_pause_left = super_cutin_duration
			if _super_freeze != null:
				_super_freeze.play(p.index, p.color, player_weapons[p.index], reduced_flashes,
					super_cutin_duration)
			if _event_direction != null:
				_event_direction.super_beats(p.index, p.color, super_cutin_duration)
			_sfx.play("super_chant")
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
			_spawn_player_attack(p)

	# The world advances first, so bodies resolve against the geometry as it
	# stands at the END of this tick and inherit the movement of whatever they
	# were standing on. `from_tick` is the tick they are leaving.
	var from_tick: int = world_tick
	world_tick += 1
	_apply_movers(world_tick)

	for p in players:
		p.sim_step(dt, exec_tick, from_tick)
	_accrue_window_travel()
	_check_core_collection()
	_step_arrows(dt)


## Continuous real-time control of Player 1. Optional non-AI seats remain inert
## targets; a sandbox CPU runs plans authored by the same Ai.gd used in matches.
func _freeplay_tick(delta: float) -> void:
	var p: Player = players[0]

	var dir := 0
	if _player_input._held(_player_input.key_bindings["left"]) or _player_input._pad_left(_player_input._pads[0]) or _touch_controls.left_held:
		dir -= 1
	if _player_input._held(_player_input.key_bindings["right"]) or _player_input._pad_right(_player_input._pads[0]) or _touch_controls.right_held:
		dir += 1
	var jump_now: bool = _player_input._held(_player_input.key_bindings["jump"]) \
		or (_player_input._pads[0] >= 0 and Input.is_joy_button_pressed(_player_input._pads[0], JOY_BUTTON_A)) \
		or _touch_controls.jump_held
	var jump_edge: bool = jump_now and not _player_input._jump_prev[0]
	_player_input._jump_prev[0] = jump_now
	var wait_now: bool = _player_input._held(_player_input.key_bindings["wait"]) or _player_input._pad_down(_player_input._pads[0]) \
		or _touch_controls.wait_held
	var drop_now: bool = jump_edge and wait_now

	p.sim_free(delta, dir, jump_edge and not drop_now, jump_now and not drop_now, drop_now)
	for i in range(1, players.size()):
		if is_ai(i):
			_sandbox_ai_tick(delta, i)
		else:
			players[i].sim_free(delta, 0, false, false)

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

	# hold to draw, release to loose immediately, no turn to wait for
	var primary_held: bool = _player_input._held(_player_input.key_bindings["charge"]) or _touch_controls.charge_held
	if not _touch_controls.has_active_touches() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		primary_held = true
	if _player_input._pads[0] >= 0 and Input.get_joy_axis(_player_input._pads[0], JOY_AXIS_TRIGGER_RIGHT) > trigger_threshold:
		primary_held = true
	if primary_held:
		if not charging[0]:
			charging[0] = true
			_player_input._charge_t[0] = 0.0
		else:
			_player_input._charge_t[0] = minf(_player_input._charge_t[0] + delta, charge_time)
		p.plan.power = _player_input._charge_t[0] / charge_time
	elif charging[0]:
		charging[0] = false
		_spawn_player_attack(p)

	_step_arrows(delta)

	# Sandbox hits carry no score; restore either side immediately so iteration
	# never stops at a round or result screen.
	for i in players.size():
		if players[i].alive:
			continue
		players[i].position = spawns[i]
		players[i].vel = Vector2.ZERO
		players[i].on_ground = true
		players[i].air_jumps_left = air_jumps_for(i)
		players[i].alive = true
		players[i].plan = PlayerPlan.new()
		players[i].queue_redraw()
		_sandbox_banner("%s HIT" % ("P1" if i == 0 else "CPU"),
			PLAYER_COLORS[i])
		if i == 1 and is_ai(i):
			_reset_sandbox_ai_cycle()


## Search while the sandbox keeps running, then replay the authored plan as one
## ordinary execution window. This preserves the shipped AI's movement, aim
## and difficulty presets without forcing time-stop between tests.
func _sandbox_ai_tick(delta: float, player_index: int) -> void:
	if player_index != 1 or not sandbox_has_ai() or not players[player_index].alive:
		return
	var cpu: Player = players[player_index]
	if _sandbox_ai_exec_tick < 0:
		if _sandbox_ai_search == null:
			_reset_pilot(player_index)
			_sandbox_ai_search = Ai.new()
			_sandbox_ai_search.begin(self, player_index, 0)
		if not _sandbox_ai_search.step(ai_slice_usec):
			cpu.sim_free(delta, 0, false, false)
			return
		_sandbox_ai_search.apply()
		_sandbox_ai_search = null
		_sandbox_ai_exec_tick = 0
		_sandbox_ai_accum = 0.0

	_sandbox_ai_accum += delta
	var dt := tick_dt()
	while _sandbox_ai_accum >= dt and _sandbox_ai_exec_tick >= 0:
		_sandbox_ai_accum -= dt
		if cpu.plan.has_shot() and cpu.plan.shot_tick == _sandbox_ai_exec_tick:
			_spawn_player_attack(cpu)
		cpu.sim_step(dt, _sandbox_ai_exec_tick)
		_sandbox_ai_exec_tick += 1
		if _sandbox_ai_exec_tick >= exec_ticks():
			_reset_sandbox_ai_cycle()


## Advances every arrow one tick and resolves what it struck. Shared by the
## turn-based loop and free play, so both behave identically.
func _step_arrows(dt: float) -> void:
	var survivors: Array = []
	var damaged: Array[int] = []
	for a in arrows:
		var res: Dictionary = a.sim_step(dt, players)
		if res["hit_player"] < 0 and not res.get("ricochet", false):
			_credit_dodges(a, players)
		if res["hit_player"] >= 0:
			_sfx.play("knife_hit")
			if _telemetry != null:
				_telemetry.record("knife_hit", turn, {"shooter": a.shooter + 1,
					"victim": int(res["hit_player"]) + 1, "age_ticks": a.age_ticks,
					"clashes": a.clash_count, "ricochets": a.ricochet_count})
			_on_player_hit(res["hit_player"], a.position, a.shooter)
		if res["hit_platform"] >= 0:
			damaged.append(res["hit_platform"])
			_effects.add(Effects.Kind.SPARK, a.position, Color(0.95, 0.85, 0.6))
			_sfx.play("knife_impact")
		if res.get("ricochet", false):
			var ricochet_at: Vector2 = res.get("ricochet_position", a.position)
			_effects.add(Effects.Kind.CLASH, ricochet_at, Color(0.62, 0.95, 1.0))
			_remember_aftermath("RICOCHET", ricochet_at, Color(0.62, 0.95, 1.0))
			_sfx.play("knife_ricochet")
		if res["alive"]:
			survivors.append(a)
		else:
			a.queue_free()
	survivors = _resolve_hazard_strikes(survivors)
	_resolve_clashes(survivors)
	arrows = survivors.filter(func(a): return not a.is_queued_for_deletion())
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
	for a: Knife in live:
		var struck: Hazard = null
		for h: Hazard in hazards:
			if not h.charged or triggered.has(h):
				continue
			if Knife.moving_points_closest(a.prev_pos, a.position, h.position, h.position)[0] \
					<= Hazard.RADIUS + knife_clash_radius * 0.5:
				struck = h
				break
		if struck == null:
			kept.append(a)
			continue
		triggered.append(struck)
		# The triggering knife survives. Snap it to the contact point so radial
		# launch points back out of the face it entered instead of beyond the orb.
		var contact := Knife.moving_points_closest(
			a.prev_pos, a.position, struck.position, struck.position)
		a.position = contact[1]
		a.prev_pos = a.position
		kept.append(a)
	# Detonate only once the survivor list is final, so every triggering knife
	# participates in the same deterministic relaunch as the bystanders.
	for h: Hazard in triggered:
		_detonate(h, kept)
	return kept


## The forcefield. It damages nobody (knives remain the only source of damage)
## but it rewrites position, momentum and every firing line inside its radius,
## and the knives it throws outward stay in the world afterwards.
func _detonate(h: Hazard, affected_arrows: Array) -> void:
	h.discharge()
	_blasts_this_execution += 1
	_effects.add(Effects.Kind.SHATTER, h.position, Color(0.62, 0.95, 1.0))
	_remember_aftermath("PULSE", h.position, Color(0.62, 0.95, 1.0))
	_sfx.play("hazard_blast")

	for p in players:
		if not p.alive:
			continue
		p.vel += _blast_impulse_at(h, p.position)
		# Being blown off a ledge has to actually free the body, or the next tick
		# simply resolves it back down onto the surface it was resting on.
		if p.vel.y < 0.0:
			p.on_ground = false
	for a: Knife in affected_arrows:
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
		var a: Knife = live[i]
		for j in range(i + 1, live.size()):
			var b: Knife = live[j]
			if a.is_queued_for_deletion() or b.is_queued_for_deletion():
				continue
			if a.volley == b.volley or not a.can_clash_with(b) or not b.can_clash_with(a):
				continue
			var hit := Knife.moving_points_closest(a.prev_pos, a.position, b.prev_pos, b.position)
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
			var bounced := Knife.clash_velocities(a.vel, b.vel, normal,
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
			_sfx.play("knife_clash")
			# Re-clashes are spectacular but easy to farm. Only the first clean
			# impact between opposing throws can advance the late-match meter.
			if prior_hits == 0 and a.shooter != b.shooter:
				_award_super_charge(a.shooter)
				_award_super_charge(b.shooter)
			break


func _award_super_charge(shooter: int) -> void:
	if shooter < 0 or shooter >= players.size():
		return
	var p: Player = players[shooter]
	if not p.alive or p.vel.length() < super_move_speed_min:
		return
	_gain_super(shooter, super_charge_per_clash, "clash")


## The single entry for every meter source. Capped at full, announced once.
func _gain_super(i: int, amount: float, reason: String) -> void:
	if amount <= 0.0:
		return
	if i < 0 or i >= players.size() or i >= super_meter.size() or super_meter[i] >= 1.0:
		return
	super_meter[i] = minf(1.0, super_meter[i] + amount)
	players[i].queue_redraw()
	if _telemetry != null:
		_telemetry.record("super_gain", turn, {"player": i + 1, "reason": reason,
			"amount": snappedf(amount, 0.001), "meter": snappedf(super_meter[i], 0.001)})
	if super_meter[i] >= 1.0:
		banner_text = "%s · SUPER READY" % player_title(i)
		banner_color = PLAYER_COLORS[i].lightened(0.35)
		banner_time = 1.4
		if _sfx != null:
			_sfx.play("super_ready")


## A rival knife passing close to a moving body without touching it. The swept
## segment is tested against the body grown by the dodge radius; the body itself
## was already cleared by the arrow's own hit test this tick.
func _credit_dodges(a: Knife, candidates: Array) -> void:
	if super_charge_per_dodge <= 0.0 or a.prev_pos.is_equal_approx(a.position):
		return
	for p in candidates:
		var i: int = p.index
		if not p.alive or p.is_invulnerable() or i == a.shooter or i >= _dodge_credits.size():
			continue
		if a.shooter >= 0 and team_mode and player_teams[i] == player_teams[a.shooter]:
			continue
		if a.dodged_by & (1 << i) or _dodge_credits[i] >= SUPER_DODGE_CREDITS_PER_WINDOW:
			continue
		if p.vel.length() < super_move_speed_min:
			continue
		var near := false
		for r in body_rects(p):
			if Knife.seg_hits_rect(a.prev_pos, a.position, r.grow(super_dodge_radius)):
				near = true
				break
		if not near:
			continue
		a.dodged_by |= 1 << i
		_dodge_credits[i] += 1
		_gain_super(i, super_charge_per_dodge, "dodge")
		_remember_aftermath("DODGE", p.position, p.color.lightened(0.3))


## Called once per simulated tick so coasting and carried movement both
## count. Only living bodies accumulate; a respawn starts from zero next window.
func _accrue_window_travel() -> void:
	for p in players:
		var i: int = p.index
		if i >= _exec_travel.size() or not p.alive:
			continue
		_exec_travel[i] += wrap_delta(_exec_last_pos[i], p.position).length()
		_exec_last_pos[i] = p.position


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
			banner_text = "TEMPORAL CORE MATERIALIZED · FULL SUPER"
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
		banner_text = "TEMPORAL CORE INCOMING · NEXT TURN"
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
		_sfx.play("core_collect")
	if collectors.size() > 1:
		banner_text = "MULTIPLE PLAYERS · SUPER READY"
		banner_color = Color(1.0, 0.90, 0.48)
	else:
		banner_text = "%s CLAIMED THE CORE · SUPER READY" % player_title(collectors[0])
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
	if interception_mode and not core_spawn_points.is_empty():
		core_position = core_spawn_points[0]
		core_announced = true
		_sync_temporal_core_visual()


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
	_sfx.play("fighter_hit")
	# One short accent per execution keeps a crowded four-player volley from
	# turning several legitimate impacts into a chain of apparent frame stalls.
	if hit_freeze_enabled and state == Phase.EXECUTING and not _hit_pause_used_this_execution:
		_hit_pause_left = HIT_PAUSE_DURATION
		_hit_pause_used_this_execution = true
	if _event_direction != null:
		_event_direction.impact(at, victim.color)
	if state == Phase.EXECUTING:
		_begin_kill_beat(at)
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
	if fate_trial_mode:
		if victim_idx == 0:
			_finish_fate_trial(false)
		else:
			banner_text = "HOSTILE ECHO DISRUPTED  //  THE TRIAL CONTINUES"
			banner_color = PLAYER_COLORS[0].lightened(0.25)
			banner_time = banner_duration
		return
	# A returning knife may hit its owner. The hit still removes them for this
	# window, but it must not award a point to an arbitrary rival.
	if scorer < 0 or scorer >= players.size() or scorer == victim_idx:
		banner_text = "%s  SELF-HIT" % player_tag(victim_idx)
		banner_color = victim.color
		banner_time = banner_duration
		return
	if team_mode and player_teams[scorer] == player_teams[victim_idx]:
		banner_text = "%s FRIENDLY HIT · NO POINT" % TEAM_NAMES[player_teams[scorer]]
		banner_color = TEAM_COLORS[player_teams[scorer]]
		banner_time = banner_duration
		return
	score[scorer] += 1
	# Meter first, so the hit banner below stays the headline.
	_gain_super(scorer, super_charge_hit_landed, "hit_landed")
	_gain_super(victim_idx, super_charge_hit_taken, "hit_taken")

	if team_mode:
		var scoring_team := player_teams[scorer]
		team_score[scoring_team] += 1
		if team_score[scoring_team] >= hits_to_win:
			state = Phase.GAME_OVER
			winner = scorer
			winning_team = scoring_team
			_player_input._prime_game_over_pad_state()
			banner_text = "TEAM %s WINS" % TEAM_NAMES[scoring_team]
			banner_color = TEAM_COLORS[scoring_team]
			_sfx.play("victory")
			_finish_match_telemetry()
		else:
			banner_text = "%s SCORES   %d : %d" % [TEAM_NAMES[scoring_team], team_score[0], team_score[1]]
			banner_color = TEAM_COLORS[scoring_team]
		banner_time = banner_duration
		return
	if score[scorer] >= hits_to_win:
		state = Phase.GAME_OVER
		winner = scorer
		_player_input._prime_game_over_pad_state()
		banner_text = "%s  WINS" % player_tag(scorer)
		banner_color = PLAYER_COLORS[scorer]
		_sfx.play("victory")
		_finish_match_telemetry()
		_record_ladder_result(scorer)
		if _event_direction != null:
			_event_direction.impact(at, victim.color)
			_event_direction.tableau(scorer)
	else:
		banner_text = "%s  →  HIT  →  %s" % [player_tag(scorer), player_tag(victim_idx)]
		banner_color = PLAYER_COLORS[scorer]
	banner_time = banner_duration


func _score_text() -> String:
	if fate_trial_mode:
		return "WINDOWS SURVIVED  %d / %d" % [
			fate_trial_windows_survived, FATE_TRIAL_WINDOWS]
	if team_mode:
		return "CRIMSON  %d   ·   %d  AZURE" % [team_score[0], team_score[1]]
	var parts := PackedStringArray()
	for i in players.size():
		parts.append("%s %d" % [player_tag(i), score[i]])
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
			_sfx.play("platform_break")
	platforms = kept
	_rebuild_solids()
	_arena.setup(platforms)


# ------------------------------------------------------------ phase changes --

func _begin_planning(first: bool) -> void:
	if _super_freeze != null:
		_cancel_super_cutin()
	state = Phase.PLANNING
	_online._online_plan_sent = false
	_online._online_match_reported = false
	if not first:
		turn += 1
	planning_window_duration = _planning_duration_for_turn(turn)
	planning_time_left = planning_window_duration
	for i in players.size():
		charging[i] = false
		_player_input._charge_t[i] = 0.0
		if not players[i].alive:
			_respawn(i)
		players[i].plan.start_new_turn()
		_reset_pilot(i)
	if fate_trial_mode:
		_author_fate_trial_plan()
	_update_facing()
	_rebuild_ghost_paths()
	if _time_stop != null:
		_time_stop.phase_changed(Phase.PLANNING)
	if not first and _sfx != null:
		_sfx.play("time_freeze")
	if not first and _effects != null and _effects.has_method("reveal_aftermath"):
		_effects.reveal_aftermath()

	# Every AI gets an independent blind search and a small confirmation delay,
	# so a four-player planning phase remains readable rather than snapping READY.
	_ai_searches.fill(null)
	_ai_step_cursor = 0
	for i in players.size():
		if not is_ai(i) or not players[i].alive or players[i].plan.confirmed:
			continue
		var target := _ai_target_for(i)
		if target < 0:
			continue
		var search := Ai.new()
		search.begin(self, i, target)
		_ai_searches[i] = search
		var think_range := ai_think_range_for(i)
		_ai_think[i] = rng.randf_range(think_range.x, think_range.y)


## Three short laws replace opponent search: a direct opening sentence, a wide
## advancing fan, then an airborne closing throw. The exact recording is public,
## turning its predictability into the trial's information rather than a bot flaw.
func _author_fate_trial_plan() -> void:
	if players.size() < 2 or not players[1].alive:
		return
	var hostile: Player = players[1]
	var plan: PlayerPlan = hostile.plan
	var pattern := clampi(turn - 1, 0, FATE_TRIAL_WINDOWS - 1)
	match pattern:
		1:
			for _tick in 18:
				plan.record(-1, false, false)
			plan.shot_tick = 12
			plan.power = 0.28
		2:
			for tick in 24:
				plan.record(-1, tick == 0, tick < 14)
			plan.shot_tick = 18
			plan.power = 0.72
		_:
			plan.shot_tick = 0
			plan.power = 0.92
	var target_delta: Vector2 = wrap_delta(hostile.position, players[0].position)
	var lift := -65.0 if pattern == 2 else (-35.0 if pattern == 1 else -12.0)
	plan.set_aim_from_vector(target_delta + Vector2(0.0, lift), aim_min_angle, aim_max_angle)
	plan.confirmed = true
	banner_text = "HOSTILE PLAN REVEALED  //  SURVIVE %d / %d" % [
		fate_trial_windows_survived, FATE_TRIAL_WINDOWS]
	banner_color = PLAYER_COLORS[1].lightened(0.28)
	banner_time = 1.8


func _planning_duration_for_turn(turn_number: int) -> float:
	if fate_trial_mode:
		return FATE_TRIAL_PLANNING_DURATION
	if tutorial_mode:
		return planning_duration
	var reductions := maxi(0, turn_number - maxi(1, planning_shrink_after_rounds))
	return maxf(minimum_planning_duration,
		planning_duration - float(reductions) * maxf(0.0, planning_shrink_per_round))


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
	# apply() adds recorded ticks, so the cached ghost is now stale, and the
	# shot origin is read from it.
	if rebuilt:
		_rebuild_ghost_paths()

	# A charge still being held when the window opens counts as released.
	for i in players.size():
		if charging[i]:
			_release_charge(i)

	state = Phase.EXECUTING
	_super_cutins_shown.fill(false)
	_super_pause_left = 0.0
	exec_tick = 0
	exec_ticks_total = exec_ticks()
	_hit_pause_left = 0.0
	_hit_pause_used_this_execution = false
	_hit_this_execution = false
	_core_collected_this_execution = false
	_blasts_this_execution = 0
	_dodge_credits.fill(0)
	_exec_travel.fill(0.0)
	for p in players:
		if p.index < _exec_last_pos.size():
			_exec_last_pos[p.index] = p.position
		# The lock share lives on the plan so both lockstep clients read the same
		# number from the relayed payload rather than their own clocks.
		if p.alive and p.plan.confirmed and p.plan.lock_permille > 0:
			_gain_super(p.index,
				super_charge_early_lock * float(p.plan.lock_permille) / 1000.0, "early_lock")
	if _time_stop != null:
		_time_stop.phase_changed(Phase.EXECUTING)
	if _sfx != null:
		_sfx.play("time_resume")
	_replay._capture_replay_frame()


func _remember_aftermath(label: String, at: Vector2, col: Color) -> void:
	if state == Phase.EXECUTING and _effects != null and _effects.has_method("remember"):
		_effects.remember(label, at, col)


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
	if super_travel_reference > 0.0:
		for p in players:
			if p.alive and p.index < _exec_travel.size():
				_gain_super(p.index, super_charge_per_window_travel
					* clampf(_exec_travel[p.index] / super_travel_reference, 0.0, 1.0), "travel")
	for h: Hazard in hazards:
		h.end_of_window()
	if fate_trial_mode:
		fate_trial_windows_survived += 1
		if fate_trial_windows_survived >= FATE_TRIAL_WINDOWS:
			_finish_fate_trial(true)
		else:
			_begin_planning(false)
		return
	if _practice != null and _practice.active:
		_practice.finish_window()
		return
	_advance_temporal_core()
	# Everything keeps its position / velocity. Nothing is cleared.
	if online_mode:
		state = Phase.ONLINE_WAIT
		if not _online._online_client.send_turn_complete(turn, _online._online_state_digest()):
			banner_text = "TURN SAVED LOCALLY · RECONNECTING TO OPPONENT"
			banner_color = Color(1.0, 0.45, 0.35)
			banner_time = 2.0
	else:
		_begin_planning(false)


func _finish_fate_trial(success: bool) -> void:
	if not fate_trial_mode:
		return
	fate_trial_succeeded = success
	state = Phase.GAME_OVER
	winner = 0 if success else 1
	_player_input._prime_game_over_pad_state()
	banner_text = "FATE DEFIED" if success else "FATE CLAIMED YOU"
	banner_color = PLAYER_COLORS[0] if success else PLAYER_COLORS[1]
	banner_time = banner_duration
	if success:
		_sfx.play("victory")
	_finish_match_telemetry()


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


## One throw looses the whole fan from the same point at the same tick. The
## spread is the shot, not a sequence of shots.
func _spawn_player_attack(p: Player) -> void:
	if _telemetry != null:
		_telemetry.record("throw_fired", turn, {"player": p.index + 1, "power": p.plan.power})
	_gain_super(p.index, super_charge_per_throw * clampf(p.plan.power, 0.0, 1.0), "throw")
	_spawn_arrow(p)


func _spawn_arrow(p: Player) -> void:
	var launches: Array[Vector2] = knife_launch_velocities(p.aim_dir(), p.plan.power)
	var origin: Vector2 = p.shoulder() + launches[0].normalized() * 22.0
	var volley: int = _next_volley
	_next_volley += 1
	for launch in launches:
		var a := Knife.new()
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
	_sfx.play("knife_throw")


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
		banner_text = "%s · SUPER" % player_title(p.index)
		banner_color = PLAYER_COLORS[p.index].lightened(0.35)
		banner_time = 0.9

	var aim: Vector2 = p.aim_dir()
	var speed: float = arrow_speed_max * super_speed_multiplier
	# Every wave follows the same narrow lane. Timing, rather than changing
	# spread or centre angle, is the identity of this SUPER.
	var origin: Vector2 = p.shoulder() + aim * 22.0
	for off in super_offsets():
		var dir: Vector2 = aim.rotated(deg_to_rad(off))
		var a := Knife.new()
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
	_sfx.play("knife_super")


## Facing follows the bow, not the opponent. With free aim that is what reads.
func _update_facing() -> void:
	for p in players:
		var f: int = p.plan.aim_side()
		if p.facing != f:
			p.facing = f
			p.queue_redraw()


func restart() -> void:
	if _ui != null: _ui._turn_review.visible = false
	_secret_triple_match = false
	if _super_freeze != null:
		_cancel_super_cutin()
	# The result tableau holds its subdued grade and winner spotlight until the
	# result screen is left; a rematch leaves it too, or the next match plays
	# under the previous match's faded palette.
	if _event_direction != null:
		_event_direction.clear()
	_replay._replay_frames.clear()
	_replay._replay_terminal_frame.clear()
	_replay._replay_frame_index = 0
	_replay._replay_accum = 0.0
	if online_mode:
		rng.seed = _online._online_seed
	for a in arrows:
		a.queue_free()
	arrows.clear()
	_next_volley = 1
	_next_arrow_id = 1
	_effects.clear_all()
	_load_level(level_index)
	for i in players.size():
		var p: Player = players[i]
		p.fighter_style = player_weapons[i]
		_sync_fighter_visual(p, i)
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
	_kill_slowmo_left = 0.0
	_kill_recover_left = 0.0
	for i in MAX_PLAYERS:
		score[i] = 0
		_last_respawn_choice[i] = -1
		super_meter[i] = 0.0
		super_armed[i] = false
	_reset_temporal_core()
	banner_time = 0.0
	if fate_trial_mode:
		fate_trial_windows_survived = 0
		fate_trial_succeeded = false
		_seed_fate_trial_threat()
	_begin_planning(true)


## A knife from an earlier, unseen exchange is already crossing the player's
## back when Trial 01 opens. It uses the ordinary persistent projectile rules,
## so its complete future is visible and it may be blocked or deflected.
func _seed_fate_trial_threat() -> void:
	var echo := Knife.new()
	echo.cfg = self
	echo.shooter = 1
	echo.volley = _next_volley
	_next_volley += 1
	echo.network_id = _next_arrow_id
	_next_arrow_id += 1
	echo.color = PLAYER_COLORS[1].lightened(0.18)
	echo.position = Vector2(92.0, 584.0)
	echo.prev_pos = echo.position
	echo.vel = Vector2(420.0, -8.0)
	echo.rotation = echo.vel.angle()
	_arrow_layer.add_child(echo)
	arrows.append(echo)


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
	_player_input._pilot_accum[i] = 0.0
	charging[i] = false
	_player_input._charge_t[i] = 0.0
	# Planning may resume long after the previous input poll. Sampling the actual
	# button prevents a stale edge from swallowing an airborne jump.
	_player_input._jump_prev[i] = _player_input._jump_input_held(i)
	_mark_ghost_path_dirty(i)


## Records exactly one tick of piloted input onto the ghost.
func _pilot_step(i: int, dir: int, jump: bool, hold: bool, drop: bool = false) -> bool:
	var pl: PlayerPlan = players[i].plan
	if pl.recorded_ticks() >= movement_tick_budget() or stamina[i] <= 0.0:
		return false
	# The tick this step LEAVES, in absolute time. The moving world is projected
	# forward from here, so the ghost meets the geometry the plan will meet.
	var from_tick: int = world_tick + pl.recorded_ticks()
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
	var velocity_path := PackedVector2Array()
	var ground_path := PackedByteArray()
	# Replay the recording from the live body state.
	var pos: Vector2 = p.position
	var vel: Vector2 = p.vel
	var og: bool = p.on_ground
	var air_jumps: int = p.air_jumps_left
	var drop: int = p.drop_ticks
	var drop_from: float = p.drop_from_y
	path.append(pos)
	velocity_path.append(vel)
	ground_path.append(1 if og else 0)
	for t in exec_ticks():
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
			jump_impulse_for(i), max_fall_speed_for(i), t < pl.recorded_ticks())
		pos = st[0]
		vel = st[1]
		og = st[2]
		if og:
			air_jumps = air_jumps_for(i)
		path.append(pos)
		velocity_path.append(vel)
		ground_path.append(1 if og else 0)
	ghost_path[i] = path
	ghost_velocity_path[i] = velocity_path
	ghost_ground_path[i] = ground_path
	_ghost_path_dirty[i] = false


## Where the ghost currently stands: the point a shot would be loosed from.
func pilot_tick(i: int) -> int:
	var pl: PlayerPlan = players[i].plan
	return pl.shot_tick if pl.has_shot() else pl.recorded_ticks()


func shot_origin(i: int) -> Vector2:
	var path: PackedVector2Array = ghost_path[i]
	if path.is_empty():
		return players[i].position
	return path[clampi(pilot_tick(i), 0, path.size() - 1)]


# ------------------------------------------------------------------- input ---
#
# Key, pointer, pad and touch handling lives in PlayerInput.gd. These are the
# plan commands it issues; the AI and tests call them too.


func _request_rematch() -> void:
	if state == Phase.GAME_OVER and _telemetry != null:
		_telemetry.note_rematch(turn)
	if state != Phase.GAME_OVER:
		return
	if interception_mode:
		restart()
		_begin_match_telemetry("ai_interception")
		_transition.play("INTERCEPTION", "READ THE NEXT LANDING",
			PLAYER_COLORS[0], reduced_flashes)
		return
	if fate_trial_mode:
		restart()
		_begin_match_telemetry("fate_trial_01")
		_transition.play("FATE TRIAL 01 // THE CROSSFIRE",
			"READ IT AGAIN", PLAYER_COLORS[0], reduced_flashes)
		return
	if online_mode:
		if _online._online_waiting_rematch:
			return
		_online._online_waiting_rematch = _online._online_client.send_rematch(rematch_level_index)
		banner_text = "REMATCH REQUESTED · WAITING FOR PLAYERS"
		banner_color = Color(0.86, 0.68, 1.0)
		banner_time = 2.0
	else:
		if demo_match and Opponents.valid(rematch_opponent):
			set_player_opponent(1, rematch_opponent)
			rematch_level_index = Opponents.arena(rematch_opponent)
		_load_level(rematch_level_index)
		restart()
		_begin_match_telemetry("tutorial" if tutorial_mode else \
			(_ai_telemetry_mode() if vs_ai else "local_2p"))


func _ai_telemetry_mode() -> String:
	if demo_opponent >= 0:
		return "ai_ladder_%s" % str(Opponents.rung(demo_opponent)["id"])
	return "ai_wide"


## An opponent who reloads the page cannot rejoin: a match in progress cannot
## be rebuilt from one turn of state. Rather than leave the survivor watching
## an empty room until it expires, let them claim it. The room refuses unless
## the opponent really is gone, so this is never a way to end a live match.
func _claim_abandoned_match() -> void:
	if not online_mode or player_count != 2 or _online.online_peer_lost == false or state == Phase.GAME_OVER:
		return
	if not _online._online_client.send_forfeit():
		banner_text = "COULD NOT REACH THE ROOM · RECONNECTING"
		banner_color = Color(1.0, 0.45, 0.35)
		banner_time = 2.0
		return
	banner_text = "CLAIMING THE MATCH…"
	banner_color = Color(0.86, 0.68, 1.0)
	banner_time = 1.6


## The room has ruled: the abandoned match is over. Land on the ordinary
## result screen so the rematch handshake still works if they come back.
func _finish_abandoned_match(claimed_by: int) -> void:
	if not online_mode:
		return
	_online.online_peer_lost = false
	winner = clampi(claimed_by, 0, player_count - 1)
	winning_team = -1
	_online._online_match_reported = true
	state = Phase.GAME_OVER
	# The same arrival every other win uses, so the result screen's gamepad
	# edges are primed and a held button cannot instantly skip past it.
	_player_input._prime_game_over_pad_state()
	_finish_match_telemetry()
	banner_text = "OPPONENT LEFT · %s TAKES THE MATCH" % player_title(winner)
	banner_color = PLAYER_COLORS[winner].lightened(0.3)
	banner_time = 3.0
	if _sfx != null:
		_sfx.play("victory")


## On the result screen of a Start Duel match the arrows pick the opponent
## among the rungs already reached, not the arena.
func _cycle_rematch_opponent(direction: int) -> void:
	if state != Phase.GAME_OVER or not demo_match or direction == 0:
		return
	var unlocked: int = mini(ladder_progress() + 1, Opponents.count())
	var current: int = rematch_opponent if rematch_opponent >= 0 else maxi(demo_opponent, 0)
	rematch_opponent = posmod(current + direction, unlocked)


func _cycle_rematch_level(direction: int) -> void:
	if demo_match:
		_cycle_rematch_opponent(direction)
		return
	# Online arenas are voted on the selection screen that a rematch opens.
	if state != Phase.GAME_OVER or direction == 0 or demo_match \
			or fate_trial_mode or interception_mode or online_mode:
		return
	rematch_level_index = posmod(rematch_level_index + direction, Levels.count())
	var selected := Levels.build(rematch_level_index)
	rematch_level_name = str(selected["name"])


## Engine input callbacks stay on this node so they keep its place in the tree
## and its event order. The handling itself lives in PlayerInput.gd.
func _unhandled_input(event: InputEvent) -> void:
	_player_input._unhandled_input(event)


func _unhandled_key_input(event: InputEvent) -> void:
	_player_input._unhandled_key_input(event)


func _toggle_super(i: int) -> void:
	if state != Phase.PLANNING or i < 0 or i >= players.size() or is_ai(i):
		return
	var p: Player = players[i]
	if not p.alive or p.plan.confirmed or p.plan.has_shot() or super_meter[i] < 1.0:
		return
	super_armed[i] = not super_armed[i]
	p.queue_redraw()
	banner_text = "%s · SUPER %s" % [player_title(i), "ARMED" if super_armed[i] else "STANDBY"]
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
	# A submitted online plan is already with the server. Editing the local copy
	# would only make the screen disagree with the turn that will actually run.
	if online_mode and i == online_player and _online._online_plan_sent:
		_undo_banner(i, "PLAN ALREADY SENT · UNDO BEFORE LOCKING")
		return
	var had_throw: bool = p.plan.has_shot() or charging[i]
	var was_locked: bool = p.plan.confirmed
	p.plan.confirmed = false
	p.plan.shot_tick = -1
	p.plan.super_shot = false
	p.plan.super_volley = -1
	charging[i] = false
	_player_input._charge_t[i] = 0.0
	p.queue_redraw()
	if had_throw:
		_undo_banner(i, "THROW UNDONE")
	elif was_locked:
		_undo_banner(i, "PLAN UNLOCKED")
	else:
		_undo_banner(i, "NO THROW TO UNDO · RESET CLEARS THE ROUTE")
	if _telemetry != null:
		_telemetry.record("undo", turn, {"player": i + 1})


## UNDO used to change the plan silently, which read as a dead button.
func _undo_banner(i: int, text: String) -> void:
	banner_text = "%s · %s" % [player_tag(i), text]
	banner_color = PLAYER_COLORS[i].lightened(0.25)
	banner_time = 1.1
	if _sfx != null:
		_sfx.play("ui_move")


## Throws the movement recording away and refills stamina. The shot goes with
## it, because its tick indexes into the path that just disappeared.
## Editing only changes an uncommitted local plan. Rebuild the ghost by replaying
## the retained input prefix, including jumps and drops, from the live body.
func _can_edit_plan(i: int) -> bool:
	return state == Phase.PLANNING and i >= 0 and i < players.size() \
		and players[i].alive and _player_input._is_locally_controlled(i) \
		and not players[i].plan.confirmed and not (online_mode and _online._online_plan_sent)


func _rewind_plan(i: int, keep_ticks: int) -> void:
	if not _can_edit_plan(i) or player_weapons[i] != Weapon.KNIVES:
		return
	var plan: PlayerPlan = players[i].plan
	var count := clampi(keep_ticks, 0, plan.recorded_ticks())
	var saved := plan.to_network_dict()
	_reset_pilot(i)
	for tick in count:
		_pilot_step(i, int(saved["dirs"][tick]) - 1, bool(saved["jumps"][tick]),
			bool(saved["holds"][tick]), bool(saved["drops"][tick]))
	# A throw at the retained boundary is still valid. Later throws are removed.
	if int(saved["shot_tick"]) >= 0 and int(saved["shot_tick"]) <= count:
		plan.shot_tick = int(saved["shot_tick"])
		plan.super_shot = bool(saved["super_shot"])
	plan.power = float(saved["power"])
	_refresh_dirty_ghost_paths()
	if _telemetry != null:
		_telemetry.record("plan_rewound", turn, {"player": i + 1, "kept_ticks": count})


func _shift_shot(i: int, ticks: int) -> void:
	if not _can_edit_plan(i) or not players[i].plan.has_shot():
		return
	var plan: PlayerPlan = players[i].plan
	var last := mini(plan.recorded_ticks(), exec_ticks() - 1)
	if plan.super_shot:
		last = mini(last, maxi(0, exec_ticks() - 1 - (super_waves - 1) * super_wave_interval_ticks))
	plan.shot_tick = clampi(plan.shot_tick + ticks, 0, last)
	_preview.queue_redraw()


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
	if online_mode and (i != online_player or _online._online_plan_sent):
		return
	var p: Player = players[i]
	if not p.alive:
		return
	if charging[i]:
		_release_charge(i)
	p.plan.confirmed = true
	p.plan.lock_permille = 500 if is_ai(i) else int(round(1000.0
		* clampf(planning_time_left / maxf(0.001, planning_window_duration), 0.0, 1.0)))
	# Readiness is public through the READY badge and the HUD status. The
	# DECIDED spotlight that used to fire here darkened the whole screen while
	# the opponent was still planning, so it was cut.
	if _telemetry != null:
		_telemetry.record("plan_locked", turn, {
			"player": i + 1,
			"planning_ms": int((planning_window_duration - planning_time_left) * 1000.0),
			"movement_ticks": p.plan.recorded_ticks(),
			"shot_tick": p.plan.shot_tick,
			"power": snappedf(p.plan.power, 0.01),
			"super": p.plan.super_shot,
			"live_knives": arrows.size(),
		})
	if online_mode:
		_online._online_plan_sent = _online._online_client.send_plan(turn, p.plan.to_network_dict())
		if _online._online_plan_sent:
			banner_text = "PLAN LOCKED · WAITING FOR OPPONENT"
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
	banner_text = "PLAYER %d · SUPER READY (TEST)" % (who + 1)
	banner_color = PLAYER_COLORS[who].lightened(0.35)
	banner_time = 1.4


func _begin_match_telemetry(mode: String) -> void:
	if _telemetry == null:
		return
	var input_name := "touch" if _touch_controls.enabled else \
		("gamepad" if not _player_input._pads.is_empty() and _player_input._pads[0] >= 0 else "keyboard_mouse")
	_telemetry.begin_match(mode, level_name, input_name)
	_telemetry_finished = false


## True while a SUPER cut-in holds the simulation. The timer is authoritative;
## cancelling the art layer (tests, menu, replay) releases the pause early.
func _super_pause_active() -> bool:
	if _super_pause_left <= 0.0:
		return false
	return _super_freeze == null or _super_freeze.is_active()


func _cancel_super_cutin() -> void:
	_super_pause_left = 0.0
	if _super_freeze != null:
		_super_freeze.cancel()


func _finish_match_telemetry() -> void:
	if _telemetry == null or _telemetry_finished:
		return
	_telemetry_finished = true
	_telemetry.finish_match(winner, score, turn, _online._online_state_digest())


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


func _clamp_planning_timer() -> void:
	planning_window_duration = _planning_duration_for_turn(turn)
	planning_time_left = minf(planning_time_left, planning_window_duration)


## A fixed, reproducible match against one rung of the opponent ladder. With no
## rung given it plays the first opponent not yet beaten. Custom setups remain
## developer tools.
func start_demo_duel(rung: int = -1) -> void:
	if not Opponents.valid(rung):
		rung = ladder_next_rung()
	if _practice != null: _practice.stop()
	_abandon_match("new_duel")
	team_mode = false
	_tuning.handle_key(KEY_BACKSPACE, false)
	planning_duration = 4.0
	planning_shrink_per_round = 0.0
	execution_duration = 0.75
	movement_budget = 0.50
	var skill := Opponents.skill(rung)
	_start_local_match(Opponents.arena(rung), 2, [Weapon.KNIVES, Weapon.KNIVES], {
		"roles": ["HUMAN", "AI"], "devices": [KEYBOARD_DEVICE, NO_DEVICE],
		"difficulties": [skill, skill], "difficulty": skill, "match_lives": 3,
		"opponents": [-1, rung],
	})
	demo_match = true
	_ui.show_controls(true)
	_transition.play("FIRST TO 3 HITS · %s" % Opponents.position_label(rung),
		Opponents.display_name(rung), PLAYER_COLORS[1], reduced_flashes)


func _abandon_match(reason: String) -> void:
	if _telemetry == null or _telemetry_finished: return
	_telemetry.abandon_match(turn, score, reason)
	_telemetry_finished = true


func open_feedback() -> void:
	_feedback.open()


func quit_demo() -> void:
	_abandon_match("quit")
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.location.reload()")
	else:
		get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_abandon_match("window_closed")
