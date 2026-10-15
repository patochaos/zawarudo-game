extends RefCounted

## Saved local rules. The catalog is shared by validation, persistence and UI.
## Only these properties can be loaded from disk; online always restores their
## authored values without changing the saved local profile.
signal changed

## These are coherent alternatives for ordinary offline Duelist matches. Values
## use the same units as the editor, including seconds for projectile lifetime.
## Every preset begins with all authored defaults so previous edits cannot leak.
const PRESETS: Array[Dictionary] = [
	{
		"id": "tactical_duel", "name": "Tactical duel", "recommended": true,
		"description": "Commit to a jump and catch the landing. Lower air control makes routes easier to anticipate.",
		"values": {
			"planning_duration": 10.0, "double_jump_enabled": false,
			"player_air_acceleration": 600.0, "arrow_speed_min": 280.0,
			"arrow_speed_max": 680.0, "arrow_max_ticks": 9.0,
		},
	},
	{
		"id": "clear_read", "name": "Clear read", "recommended": false,
		"description": "One knife per throw and time to study it. Practice placing shots across a future route.",
		"values": {
			"planning_duration": 14.0, "execution_duration": 0.65,
			"movement_budget": 0.45, "pilot_time_scale": 0.4,
			"double_jump_enabled": false, "player_air_acceleration": 600.0,
			"knives_per_shot": 1, "arrow_speed_min": 280.0,
			"arrow_speed_max": 640.0, "arrow_max_ticks": 6.0,
			"aim_preview_duration": 0.6, "knife_ricochet_limit": 1,
			"super_waves": 3, "super_knives_per_wave": 2,
			"super_charge_per_clash": 0.15, "core_hitless_turns_to_announce": 3,
		},
	},
	{
		"id": "crossfire", "name": "Crossfire", "recommended": false,
		"description": "Three-knife fans create crossing threats. Six seconds of flight limit accumulation across freezes.",
		"values": {
			"planning_duration": 10.0, "knives_per_shot": 3,
			"arrow_speed_min": 260.0, "arrow_speed_max": 640.0,
			"arrow_max_ticks": 6.0, "knife_spread_max": 32.0,
			"knife_spread_min": 8.0, "arrow_drag": 0.5,
			"arrow_gravity": 240.0, "arrow_clashed_gravity_scale": 3.0,
			"knife_ricochet_limit": 1, "knife_ricochet_retention": 0.68,
			"super_waves": 3, "super_charge_per_clash": 0.08,
		},
	},
	{
		"id": "quick_verdict", "name": "Quick verdict", "recommended": false,
		"description": "Shorter turns and quicker charging reward a practiced read. Keep both knives and commit sooner.",
		"values": {
			"planning_duration": 6.0, "execution_duration": 0.6,
			"movement_budget": 0.4, "pilot_time_scale": 0.65,
			"commit_delay": 0.15, "charge_time": 0.8,
			"double_jump_enabled": false, "player_air_acceleration": 600.0,
			"arrow_speed_min": 320.0, "arrow_speed_max": 760.0,
			"aim_preview_duration": 0.35, "arrow_max_ticks": 6.0,
			"super_waves": 4,
		},
	},
]

var definitions: Array[Dictionary] = []
var last_save_error: Error = OK
var _gm
var _path: String
var _defaults: Dictionary = {}
var _values: Dictionary = {}


func initialize(manager, path: String = "user://offline_tuning.cfg") -> void:
	_gm = manager
	_path = path
	_build_catalog()
	for item in definitions:
		var key: String = item.key
		_defaults[key] = _gm.get(key)
	_values = _defaults.duplicate()
	var config := ConfigFile.new()
	if not path.is_empty() and config.load(path) == OK:
		for item in definitions:
			var key: String = item.key
			if config.has_section_key("offline", key):
				var value: Variant = config.get_value("offline", key)
				if _valid_type(item, value):
					_values[key] = _sanitize(item, value)
	_normalize()
	apply_offline()


func _add(group: String, key: String, label: String, help: String,
		minimum: float, maximum: float, step: float, unit: String = "",
		kind: String = "float", scale: float = 1.0) -> void:
	definitions.append({"group": group, "key": key, "label": label, "help": help,
		"min": minimum, "max": maximum, "step": step, "unit": unit,
		"kind": kind, "scale": scale})


func _build_catalog() -> void:
	definitions.clear()
	_add("Timing", "planning_duration", "Freeze duration", "Time to plan while the world is frozen. Ready players can finish early.", 1, 30, 0.5, "s")
	_add("Timing", "execution_duration", "Action duration", "How long the world runs between planning freezes.", 0.2, 2, 0.05, "s")
	_add("Timing", "movement_budget", "Movement per turn", "How much movement you can record. Cannot exceed action duration.", 0.1, 2, 0.05, "s")
	_add("Timing", "pilot_time_scale", "Planning ghost speed", "Playback speed while recording your movement. Lower gives finer control.", 0.1, 1, 0.05, "x")
	_add("Timing", "commit_delay", "Delay before action", "Pause after plans lock, before the world starts moving.", 0, 1.5, 0.05, "s")
	_add("Timing", "planning_shrink_per_round", "Freeze reduction per turn", "Shortens later planning windows. Zero keeps every freeze the same length.", 0, 2, 0.1, "s")
	_add("Timing", "planning_shrink_after_rounds", "Turns before reduction", "Number of turns with the full freeze duration.", 0, 20, 1, "turns", "int")
	_add("Timing", "minimum_planning_duration", "Shortest freeze", "Lower limit when freezes shorten. Cannot exceed freeze duration.", 1, 30, 0.5, "s")
	_add("Timing", "respawn_invuln_turns", "Respawn protection", "Action windows of invulnerability after a fighter respawns.", 0, 5, 1, "turns", "int")
	_add("Movement", "double_jump_enabled", "Double jump", "Allow extra air jumps for fighters whose kit supports them.", 0, 1, 1, "", "bool")
	_add("Movement", "jump_duration_scale", "Jump duration", "Air-time multiplier; keeps jump height. Default Duelist jump is about 1.11 s.", 0.5, 2, 0.05, "x")
	_add("Movement", "jump_impulse", "Jump strength", "Higher values raise jump height and air time before class modifiers.", 200, 1600, 20, "px/s")
	_add("Movement", "jump_cut", "Jump height on release", "Upward speed kept when you release Jump. 1x allows the full rise.", 0.1, 1, 0.05, "x")
	_add("Movement", "player_move_speed", "Run speed", "Base movement speed before each fighter's class modifier.", 40, 800, 10, "px/s")
	_add("Movement", "player_acceleration", "Ground acceleration", "How quickly you reach run speed or stop on the ground.", 200, 8000, 100, "px/s²")
	_add("Movement", "player_air_acceleration", "Air control", "How quickly you change horizontal speed in the air.", 50, 4000, 50, "px/s²")
	_add("Movement", "gravity", "Gravity", "Base downward acceleration. Jump duration scales this for fighters only.", 200, 4000, 50, "px/s²")
	_add("Movement", "max_fall_speed", "Fall speed limit", "Maximum downward speed before class and jump-duration modifiers.", 200, 3000, 50, "px/s")
	_add("Projectiles", "knives_per_shot", "Projectiles per throw", "Number of knives in a normal Duelist throw. Supers have separate counts.", 1, 3, 1, "", "int")
	_add("Projectiles", "arrow_speed_min", "Tap throw speed", "Knife speed with no charge. Raising it can also raise full-charge speed.", 100, 1800, 20, "px/s")
	_add("Projectiles", "arrow_speed_max", "Full-charge speed", "Knife speed at maximum charge. Cannot be lower than tap throw speed.", 100, 1800, 20, "px/s")
	_add("Projectiles", "charge_time", "Charge time", "Time held to reach full attack power.", 0.1, 4, 0.05, "s")
	_add("Projectiles", "arrow_max_ticks", "Projectile lifetime", "How long knives can fly in moving time. Terrain and hits can end them sooner.", 0.25, 30, 0.25, "s", "float", 60)
	_add("Projectiles", "aim_preview_duration", "Path preview duration", "How much future flight the aiming guide shows, up to the first impact.", 0.1, 4.5, 0.05, "s")
	_add("Projectiles", "knife_spread_max", "Tap throw spread", "Total angle of the knife fan at no charge.", 0, 90, 1, "°")
	_add("Projectiles", "knife_spread_min", "Full-charge spread", "Total fan angle at full charge. Cannot exceed tap spread.", 0, 90, 1, "°")
	_add("Projectiles", "real_time_throw_cooldown", "Real Time cooldown", "Minimum time between attacks in the Real Time experiment.", 0, 5, 0.05, "s")
	_add("Knife physics", "arrow_gravity", "Knife gravity", "Downward pull on flying knives. Zero gives a flat flight.", 0, 1200, 10, "px/s²")
	_add("Knife physics", "arrow_drag", "Horizontal drag", "Fraction of horizontal speed lost per second. Zero preserves speed.", 0, 3, 0.05, "/s")
	_add("Knife physics", "arrow_clashed_gravity_scale", "Deflected knife gravity", "Gravity multiplier after knives collide.", 1, 6, 0.1, "x")
	_add("Knife physics", "knife_clash_enabled", "Knife collisions", "Allow opposing knives to collide and deflect each other.", 0, 1, 1, "", "bool")
	_add("Knife physics", "knife_clash_radius", "Collision radius", "How close knife paths must pass to collide.", 2, 30, 1, "px")
	_add("Knife physics", "knife_clash_restitution", "Collision bounce", "How strongly knives separate after a collision.", 0, 1, 0.05, "x")
	_add("Knife physics", "knife_clash_damping", "Speed after collision", "Fraction of speed kept after the first knife collision.", 0.1, 1, 0.05, "x")
	_add("Knife physics", "knife_ricochet_min_speed", "Wall bounce threshold", "Minimum speed needed to ricochet from hard terrain.", 100, 1500, 20, "px/s")
	_add("Knife physics", "knife_ricochet_retention", "Speed after wall bounce", "Fraction of speed retained when bouncing off hard terrain.", 0.1, 1, 0.01, "x")
	_add("Knife physics", "knife_ricochet_limit", "Wall bounce limit", "Maximum wall ricochets per knife. Zero disables them.", 0, 6, 1, "", "int")
	_add("Supers and core", "super_charge_per_clash", "Super charge per clash", "Meter gained from a qualifying clash while moving. 1x fills the meter.", 0.01, 1, 0.005, "x")
	_add("Supers and core", "super_move_speed_min", "Speed to earn super", "Minimum fighter movement speed for a clash or dodge to award super meter.", 0, 400, 10, "px/s")
	_add("Supers and core", "super_charge_per_dodge", "Super charge per dodge", "Meter for a rival knife passing close to a moving fighter. At most three per window.", 0, 0.5, 0.01, "x")
	_add("Supers and core", "super_dodge_radius", "Dodge distance", "How close a knife must pass to count as dodged.", 4, 80, 2, "px")
	_add("Supers and core", "super_charge_per_window_travel", "Super charge for moving", "Meter for a full window of travel. Shorter routes earn a share.", 0, 0.5, 0.01, "x")
	_add("Supers and core", "super_travel_reference", "Full-travel distance", "Distance per window that earns the whole movement share.", 40, 600, 10, "px")
	_add("Supers and core", "super_charge_early_lock", "Super charge for locking early", "Meter for locking a plan the instant planning opens. Scales down with time used.", 0, 0.5, 0.01, "x")
	_add("Supers and core", "super_charge_per_throw", "Super charge per throw", "Meter for a full-charge throw. Lighter throws earn a share.", 0, 0.5, 0.01, "x")
	_add("Supers and core", "super_charge_hit_landed", "Super charge per hit landed", "Meter for scoring a hit on a rival.", 0, 1, 0.01, "x")
	_add("Supers and core", "super_charge_hit_taken", "Super charge per hit taken", "Comeback meter for being hit by a rival.", 0, 1, 0.01, "x")
	_add("Supers and core", "super_waves", "Super waves", "Number of volleys fired by a Duelist super.", 1, 8, 1, "", "int")
	_add("Supers and core", "super_knives_per_wave", "Knives per wave", "Number of knives in each super volley.", 1, 5, 1, "", "int")
	_add("Supers and core", "super_wave_interval_ticks", "Time between waves", "Moving-time delay between volleys. 60 ticks equal one second.", 1, 30, 1, "ticks", "int")
	_add("Supers and core", "super_spread", "Super spread", "Fan angle for super volleys.", 0, 60, 1, "°")
	_add("Supers and core", "super_speed_multiplier", "Super knife speed", "Multiplier applied to full-charge knife speed.", 0.5, 2, 0.01, "x")
	_add("Supers and core", "core_hitless_turns_to_announce", "Turns before core", "Hitless action windows before the temporal core is announced.", 1, 10, 1, "turns", "int")
	_add("Supers and core", "core_active_turns", "Core lifetime", "How many turns an uncollected temporal core stays active.", 1, 10, 1, "turns", "int")
	_add("Class movement", "dagger_move_speed_scale", "Duelist run speed", "Multiplier of base run speed for the Duelist.", 0.25, 2, 0.05, "x")
	_add("Class movement", "dagger_air_jump_impulse_scale", "Duelist air jump", "Air-jump strength relative to the base jump.", 0, 1.5, 0.01, "x")
	_add("Class movement", "velocity_move_speed_scale", "Rook run speed", "Run-speed multiplier for the Rook prototype.", 0.25, 2, 0.05, "x")
	_add("Class movement", "velocity_jump_impulse_scale", "Rook jump strength", "Zero preserves her dash-only traversal. Raise to enable a ground jump.", 0, 2, 0.05, "x")
	_add("Class movement", "shock_move_speed_scale", "Pulse run speed", "Run-speed multiplier for the Pulse prototype.", 0.25, 2, 0.05, "x")
	_add("Class movement", "shock_jump_impulse_scale", "Pulse jump strength", "Ground-jump multiplier for the Pulse prototype.", 0, 2, 0.05, "x")
	_add("Class movement", "chakram_move_speed_scale", "Eclipse run speed", "Run-speed multiplier for the Eclipse prototype.", 0.25, 2, 0.05, "x")
	_add("Class movement", "chakram_jump_impulse_scale", "Eclipse jump strength", "Ground-jump multiplier for the Eclipse prototype.", 0, 2, 0.05, "x")
	_add("Class movement", "chakram_air_jump_impulse_scale", "Eclipse air jump", "Air-jump strength relative to the base jump.", 0, 1.5, 0.01, "x")
	_add("Prototype attacks", "dash_speed_min", "Rook tap dash speed", "Dash speed at no charge.", 200, 1600, 20, "px/s")
	_add("Prototype attacks", "dash_speed_max", "Rook full dash speed", "Dash speed at full charge.", 200, 1600, 20, "px/s")
	_add("Prototype attacks", "dash_guard_durability", "Rook guard strength", "Number of hits the dash guard can withstand.", 1, 5, 1, "hits", "int")
	_add("Prototype attacks", "dash_exit_momentum_retention", "Rook exit momentum", "Fraction of dash speed retained when the dash ends.", 0, 1, 0.01, "x")
	_add("Prototype attacks", "chakram_speed_min", "Eclipse tap speed", "Chakram speed at no charge.", 100, 1000, 20, "px/s")
	_add("Prototype attacks", "chakram_speed_max", "Eclipse full speed", "Chakram speed at full charge.", 100, 1000, 20, "px/s")
	_add("Pulse attacks", "shock_plasma_speed_min", "Tap lance speed", "Pulse lance speed at no charge.", 100, 1800, 20, "px/s")
	_add("Pulse attacks", "shock_plasma_speed", "Full lance speed", "Pulse lance speed at full charge.", 100, 1800, 20, "px/s")
	_add("Pulse attacks", "shock_plasma_gravity", "Lance gravity", "Downward acceleration of the Pulse lance.", 0, 1200, 20, "px/s²")
	_add("Pulse attacks", "shock_orb_speed_min", "Tap orb speed", "Orb launch speed at no charge.", 100, 1000, 20, "px/s")
	_add("Pulse attacks", "shock_orb_speed_max", "Full orb speed", "Orb launch speed at full charge.", 100, 1000, 20, "px/s")
	_add("Pulse attacks", "shock_max_live_orbs", "Active orb limit", "Casting beyond this limit pops the oldest orb.", 1, 6, 1, "", "int")
	_add("Pulse attacks", "shock_orb_arm_ticks", "Orb arming delay", "Moving time before an orb becomes armed.", 0.05, 2, 0.05, "s", "float", 60)
	_add("Pulse attacks", "shock_orb_lifetime_ticks", "Orb lifetime", "Moving time before an uncollected orb expires.", 0.5, 10, 0.25, "s", "float", 60)
	_add("Pulse attacks", "shock_small_radius", "Orb blast radius", "Radius of a single orb explosion.", 20, 200, 1, "px")
	_add("Pulse attacks", "shock_combo_radius", "Full combo radius", "Blast radius when a full-power lance triggers an orb.", 190, 450, 5, "px")
	_add("Pulse attacks", "shock_small_impulse", "Orb knockback", "Push applied by a single orb explosion.", 100, 1200, 20, "px/s")
	_add("Pulse attacks", "shock_combo_impulse", "Combo knockback", "Push applied by a lance-and-orb combo.", 100, 1800, 20, "px/s")


func _definition(key: String) -> Dictionary:
	for item in definitions:
		if item.key == key:
			return item
	return {}


func get_value(key: String) -> Variant:
	var item := _definition(key)
	if item.is_empty():
		return null
	return _values[key] if item.kind == "bool" else float(_values[key]) / float(item.scale)


func default_value(key: String) -> Variant:
	var item := _definition(key)
	if item.is_empty():
		return null
	return _defaults[key] if item.kind == "bool" else float(_defaults[key]) / float(item.scale)


func get_preset(id: String) -> Dictionary:
	for preset in PRESETS:
		if preset.id == id:
			return preset.duplicate(true)
	return {}


func preset_value(id: String, key: String) -> Variant:
	var preset := get_preset(id)
	if preset.is_empty():
		return null
	return preset["values"].get(key, default_value(key))


func _preset_values(id: String) -> Dictionary:
	var preset := get_preset(id)
	if preset.is_empty():
		return {}
	var values := _defaults.duplicate()
	for key: String in preset["values"]:
		var item := _definition(key)
		var value: Variant = preset["values"][key]
		if item.is_empty() or not _valid_type(item, value):
			return {}
		values[key] = _sanitize(item, value if item.kind == "bool" else float(value) * float(item.scale))
	return values


func apply_preset(id: String) -> bool:
	if not _can_edit():
		return false
	var values := _preset_values(id)
	if values.is_empty():
		return false
	_values = values
	_normalize()
	_apply_values()
	_save()
	changed.emit()
	return true


func matching_preset_id() -> String:
	for preset in PRESETS:
		if _values_match(_values, _preset_values(preset.id)):
			return preset.id
	return ""


func _values_match(first: Dictionary, second: Dictionary) -> bool:
	if first.size() != second.size():
		return false
	for key in first:
		if not second.has(key):
			return false
		if first[key] is bool:
			if first[key] != second[key]:
				return false
		elif not is_equal_approx(float(first[key]), float(second[key])):
			return false
	return true


func profile_name() -> String:
	var id := matching_preset_id()
	if not id.is_empty():
		return get_preset(id).name
	return "Standard rules" if modified_count() == 0 else "Custom tuning"


func _can_edit() -> bool:
	return not _gm.online_mode and _gm.state != Phase.ONLINE_LOBBY


func set_value(key: String, value: Variant) -> bool:
	var item := _definition(key)
	if not _can_edit() or item.is_empty() or not _valid_type(item, value):
		return false
	_values[key] = _sanitize(item, value if item.kind == "bool" else float(value) * float(item.scale))
	_normalize(key)
	_apply_values()
	_save()
	changed.emit()
	return true


func _valid_type(item: Dictionary, value: Variant) -> bool:
	if item.kind == "bool":
		return value is bool
	return (value is float or value is int) and is_finite(float(value))


func _sanitize(item: Dictionary, stored_value: Variant) -> Variant:
	if item.kind == "bool":
		return stored_value
	var value := clampf(float(stored_value) / float(item.scale), float(item.min), float(item.max))
	value = clampf(snappedf(value, float(item.step)), float(item.min), float(item.max))
	var result := value * float(item.scale)
	if is_equal_approx(result, float(_defaults[item.key])):
		return _defaults[item.key]
	return int(round(result)) if _defaults[item.key] is int else result


func _normalize(changed_key: String = "") -> void:
	for pair in [["arrow_speed_min", "arrow_speed_max"], ["knife_spread_min", "knife_spread_max"],
			["dash_speed_min", "dash_speed_max"], ["chakram_speed_min", "chakram_speed_max"],
			["shock_plasma_speed_min", "shock_plasma_speed"], ["shock_orb_speed_min", "shock_orb_speed_max"],
			["movement_budget", "execution_duration"], ["minimum_planning_duration", "planning_duration"]]:
		if float(_values[pair[0]]) > float(_values[pair[1]]):
			if changed_key == pair[0]:
				_values[pair[1]] = _values[pair[0]]
			else:
				_values[pair[0]] = _values[pair[1]]


func _apply_values() -> void:
	for key in _values:
		_gm.set(key, _values[key])


func apply_offline(restore_defaults: bool = true) -> void:
	if not _can_edit():
		return
	# Leaving a fixed-rule mode restores the whole profile. Match setup can
	# request overrides only after assigning its own baseline.
	if restore_defaults:
		_apply_values()
		return
	for key in _values:
		if _values[key] != _defaults[key]:
			_gm.set(key, _values[key])


func apply_standard() -> void:
	for key in _defaults:
		_gm.set(key, _defaults[key])


func reset_group(group: String) -> void:
	if not _can_edit():
		return
	for item in definitions:
		if item.group == group:
			_values[item.key] = _defaults[item.key]
	_normalize()
	_apply_values()
	_save()
	changed.emit()


func reset_all() -> void:
	if not _can_edit():
		return
	_values = _defaults.duplicate()
	_apply_values()
	_save()
	changed.emit()


func modified_count() -> int:
	var count := 0
	for key in _values:
		if _values[key] != _defaults[key]:
			count += 1
	return count


func _save() -> void:
	last_save_error = OK
	if _path.is_empty():
		return
	var config := ConfigFile.new()
	for key in _values:
		if _values[key] != _defaults[key]:
			config.set_value("offline", key, _values[key])
	last_save_error = config.save(_path)
