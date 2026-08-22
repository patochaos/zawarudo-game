extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game._start_local_match(false, 0, 2,
		[game.Weapon.DASHBLADE, game.Weapon.SHOCK])

	_check(game.players[0].fighter_style == game.Weapon.DASHBLADE \
			and game.players[1].fighter_style == game.Weapon.SHOCK,
		"selected kits must reach the procedural fighter renderer")
	var velocity_plan: PlayerPlan = game.players[0].plan
	var velocity_stamina: float = game.stamina[0]
	_check(game.can_pilot_move(0) and game._pilot_step(0, 1, true, true) \
			and velocity_plan.recorded_ticks() == 1 \
			and not velocity_plan.jump_at(0) \
			and game.stamina[0] < velocity_stamina,
		"The Rook must record ground movement while rejecting ordinary jumps")
	_check(is_equal_approx(game.movement_speed_scale(0), 0.90) \
			and is_equal_approx(game.movement_speed_scale(1), 0.90),
		"Rook and Pulse must use the authored 90% walk profile")
	_test_class_movement_profiles(game)
	var debt_threshold: int = game._frame_debt_threshold_units()
	game.frame_debt_units[0] = debt_threshold - 1000
	game._accrue_frame_debt(0, Vector2.ZERO, Vector2(9.0, 0.0), 1)
	_check(game.frame_debt_cells[0] == 1 and game.frame_debt_units[0] == 0,
		"The Rook must turn her denied horizontal movement into a completed Lost Frame")
	game._accrue_frame_debt(0, Vector2.ZERO, Vector2.ZERO, 1)
	_check(game.frame_debt_cells[0] == 1,
		"pressing into a wall without displacement must not manufacture Frame Debt")
	game.frame_debt_cells[0] = 0
	game.frame_debt_units[0] = 0
	game._reset_pilot(0)
	game.players[0].position = Vector2(170.0, 180.0)
	game.players[0].plan.set_aim_from_vector(Vector2.RIGHT,
		game.aim_min_angle, game.aim_max_angle)
	game.players[0].plan.power = 0.75
	game._spawn_player_attack(game.players[0])
	_check(game.dashblades.size() == 1 and game.arrows.is_empty(),
		"Dashblade must create a body action instead of a projectile fan")
	var dash = game.dashblades[0]
	var start: Vector2 = dash.position
	game._step_dashblades(game.tick_dt(), game.arrows)
	_check(game.players[0].position.x > start.x and dash.guard_durability == game.dash_guard_durability,
		"the integrated dash must advance the real fighter without synthetic invulnerability")

	game._clear_character_projectiles()
	game.frame_debt_cells[0] = game.frame_debt_max_cells
	var base_dash: Dictionary = game.dash_parameters(0.75, false, 0)
	var debt_dash: Dictionary = game.dash_parameters(0.75, false, game.frame_debt_max_cells)
	game._spawn_player_attack(game.players[0])
	var edited_dash = game.dashblades[0]
	_check(edited_dash.frame_debt_spent == game.frame_debt_max_cells \
			and edited_dash.ticks_left == int(debt_dash["ticks"]) \
			and int(debt_dash["ticks"]) == int(base_dash["ticks"]) \
				+ game.frame_debt_max_cells * game.frame_debt_dash_ticks_per_cell,
		"a dash must cash every stored frame into deterministic extra route ticks")
	_check(edited_dash.guard_durability == game.dash_guard_durability \
			+ game.frame_debt_full_guard_bonus and game.frame_debt_cells[0] == 0,
		"a full Frame Debt cut must gain its guard bonus and spend the stored cells")
	game.state = Phase.EXECUTING
	game.frame_debt_units[0] = debt_threshold - 1000
	game._accrue_frame_debt(0, Vector2.ZERO, Vector2(3.0, 0.0), 1)
	_check(game.frame_debt_cells[0] == 0 \
			and game.frame_debt_units[0] == debt_threshold - 1000,
		"movement after CUT TO END must not immediately reload Frame Debt")
	game.state = Phase.PLANNING
	_test_velocity_dash_time_stop_preview(game)

	game._clear_character_projectiles()
	game.players[1].position = Vector2(1050.0, 300.0)
	game.players[1].plan.set_aim_from_vector(Vector2.LEFT,
		game.aim_min_angle, game.aim_max_angle)
	game._set_shock_attack_mode(1, 1)
	game._spawn_player_attack(game.players[1])
	_check(game.shock_orbs.size() == 1 and game.shock_plasmas.is_empty(),
		"Shock mode 2 must create the slow persistent orb")
	game._clear_character_projectiles()
	game.players[1].plan.attack_mode = 0
	game.players[1].plan.power = 0.0
	game._spawn_shock_plasma(game.players[1], Vector2.LEFT)
	var low_plasma = game.shock_plasmas[0]
	game.players[1].plan.power = 1.0
	game._spawn_shock_plasma(game.players[1], Vector2.LEFT)
	var high_plasma = game.shock_plasmas[1]
	_check(high_plasma.vel.length() > low_plasma.vel.length() \
			and high_plasma.charge_power > low_plasma.charge_power,
		"a high-charge Shock plasma must be faster and carry more combo charge")
	_check(game.shock_combo_radius_for_power(1.0) > game.shock_combo_radius_for_power(0.0),
		"plasma charge must visibly increase the shock combo's lethal radius")
	_check(game.shock_plasma_range_for_power(0.9999) < game.ARENA_W \
			and game.shock_plasma_range_for_power(1.0) >= game.ARENA_W,
		"only a fully charged plasma shot may span the entire screen")

	game._clear_character_projectiles()
	game._set_shock_attack_mode(1, 1)
	game.players[1].plan.power = 1.0
	game._spawn_player_attack(game.players[1])
	var orb = game.shock_orbs[0]
	orb.position = Vector2(760.0, 280.0)
	orb.prev_pos = orb.position
	orb.vel = Vector2.ZERO
	orb.age_ticks = orb.arm_ticks
	game.players[1].plan.attack_mode = 0
	# The lance falls, so hitting a fixed point means aiming above it. This is the
	# same lead the planner and the preview use; the check is about the combo
	# resolving, not about whether a flat shot happens to connect.
	game.players[1].plan.set_aim_from_vector(
		Ai.plasma_launch_direction(game, game.players[1].position, orb.position),
		game.aim_min_angle, game.aim_max_angle)
	game._spawn_player_attack(game.players[1])
	_check(game.shock_plasmas.size() == 1,
		"Shock mode 1 must create the fast straight plasma projectile")
	game.state = Phase.EXECUTING
	game._blasts_this_execution = 0
	for tick in 30:
		game._step_shock_weapons(game.tick_dt())
		if game.shock_orbs.is_empty():
			break
	_check(game.shock_orbs.is_empty() and game._blasts_this_execution == 1,
		"an armed orb struck by plasma must resolve one large shock combo")
	# The enlarged full-charge combo can legitimately catch its own Witch here;
	# revive her to isolate the owner-safe small-pop contract below.
	game.players[1].alive = true
	game.players[1].invuln_turns = 0
	game._spawn_shock_orb(game.players[1], Vector2.LEFT, false)
	var defensive_orb = game.shock_orbs[0]
	defensive_orb.position = game.players[1].position
	defensive_orb.age_ticks = defensive_orb.arm_ticks
	game._detonate_shock_orb(defensive_orb, false, 0)
	_check(game.players[1].alive,
		"a denied small orb pop must be owner-safe while the large combo remains dangerous")

	game._clear_character_projectiles()
	game.players[1].alive = true
	game._spawn_shock_orb(game.players[1], Vector2.LEFT, false)
	var expiring_orb = game.shock_orbs[0]
	expiring_orb.position = game.players[1].position
	expiring_orb.prev_pos = expiring_orb.position
	expiring_orb.age_ticks = expiring_orb.arm_ticks
	expiring_orb.lifetime_ticks = expiring_orb.age_ticks + 1
	game._blasts_this_execution = 0
	game._step_shock_weapons(game.tick_dt())
	_check(game.shock_orbs.is_empty() and game._blasts_this_execution == 1 \
			and game.players[1].alive,
		"an expiring secondary orb must make its small owner-safe explosion")

	game._spawn_shock_orb(game.players[1], Vector2.LEFT, false)
	var lethal_orb = game.shock_orbs[0]
	lethal_orb.position = Vector2(600.0, 300.0)
	lethal_orb.prev_pos = lethal_orb.position
	lethal_orb.age_ticks = lethal_orb.arm_ticks
	game.players[0].alive = true
	game.players[0].invuln_turns = 0
	game.players[0].position = lethal_orb.position \
		+ Vector2(game.shock_combo_radius + Player.HALF.x - 2.0, 0.0)
	# Isolate radial contact from the authored arena's hard-cover check.
	game.solid_rects.clear()
	var redirected_arrow := Arrow.new()
	redirected_arrow.cfg = game
	redirected_arrow.position = lethal_orb.position + Vector2(48.0, 0.0)
	redirected_arrow.prev_pos = redirected_arrow.position
	redirected_arrow.vel = Vector2(0.0, 80.0)
	game._arrow_layer.add_child(redirected_arrow)
	game.arrows = [redirected_arrow]
	game._detonate_shock_orb(lethal_orb, true, 1, 1.0)
	_check(not game.players[0].alive,
		"a fighter whose body touches the charged combo edge must be killed")
	_check(redirected_arrow.vel.x > 0.0,
		"a shock combo must redirect other projectile families such as daggers")
	game.players[0].alive = true
	game.arrows.clear()
	redirected_arrow.queue_free()

	game._clear_character_projectiles()
	game.players[1].plan.power = 1.0
	game._spawn_shock_orb(game.players[1], Vector2.LEFT, false)
	var first_field_orb = game.shock_orbs[0]
	game._spawn_shock_orb(game.players[1], Vector2.UP, false)
	_check(game.shock_orbs.size() == 2 and game.shock_orbs.has(first_field_orb),
		"casting a second Shock orb must preserve the first field setup")
	_check(is_equal_approx(game.shock_orbs[1].vel.length(), game.shock_orb_speed_max) \
			and game.shock_orb_speed_max >= 500.0,
		"a fully charged Shock orb must use the extended long-range launch speed")

	game._clear_character_projectiles()
	var intercepting_dagger := Arrow.new()
	intercepting_dagger.cfg = game
	intercepting_dagger.shooter = 0
	intercepting_dagger.network_id = 9001
	intercepting_dagger.prev_pos = Vector2(490.0, 300.0)
	intercepting_dagger.position = Vector2(510.0, 300.0)
	intercepting_dagger.vel = Vector2(1200.0, 0.0)
	game._arrow_layer.add_child(intercepting_dagger)
	game.arrows = [intercepting_dagger]
	var intercepted_plasma := ShockPlasma.new()
	intercepted_plasma.cfg = game
	intercepted_plasma.shooter = 1
	intercepted_plasma.network_id = 9002
	intercepted_plasma.position = Vector2(530.0, 300.0)
	intercepted_plasma.configure_launch(Vector2.LEFT, 1200.0)
	game._arrow_layer.add_child(intercepted_plasma)
	game.shock_plasmas = [intercepted_plasma]
	# The contract is the retained fraction, not an absolute number: a ballistic
	# bolt has picked up some fall speed by the time the blade reaches it.
	var speed_before_intercept: float = intercepted_plasma.vel.length()
	game._step_shock_weapons(game.tick_dt())
	_check(game.arrows.is_empty() and game.shock_plasmas.size() == 1 \
			and intercepted_plasma.vel.length() < speed_before_intercept * 0.5 \
			and intercepted_plasma.vel.length() > speed_before_intercept * 0.4,
		"a dagger interception must spend the dagger and heavily attenuate plasma")

	game._clear_character_projectiles()
	game.player_weapons[1] = game.Weapon.KNIVES
	game.platforms = []
	game.solid_rects.clear()
	game.wrap_x = false
	game.wrap_y = false
	game.gravity = 0.0
	game.players[0].position = Vector2(300.0, 260.0)
	game.players[1].position = Vector2(535.0, 260.0)
	for fighter: Player in game.players:
		fighter.vel = Vector2.ZERO
		fighter.on_ground = false
	var counter_ai := Ai.new()
	counter_ai.begin(game, 1, 0)
	var hold_path: PackedVector2Array = counter_ai._walk(game.players[1], 0, false, 0)
	var frontal_risk: float = counter_ai._velocity_front_parry_risk(
		game.players[1].position, Vector2.LEFT, game.arrow_speed_max, 0,
		{"path": hold_path})
	_check(counter_ai._velocity_dash_danger(hold_path) > 0.0,
		"AI safety must recognize a plausible hidden Rook dash as a body threat")
	_check(frontal_risk > 0.8 and counter_ai._best.get("withheld_for_velocity", false),
		"AI must treat a close frontal shot as parry fuel and retain a movement-only plan")
	counter_ai.finish()
	_check(float(counter_ai._best.get("velocity_parry_risk", 0.0)) < 0.8,
		"AI must reject a high-risk frontal shot when evasion or an off-angle attack exists")

	_test_plasma_planner_respects_its_range(game)
	_test_orb_field_is_bounded(game)

	game.free()
	if _failures == 0:
		print("Character kits: all tests passed")
	else:
		push_error("Character kits: %d test(s) failed" % _failures)
	quit(_failures)


## The orb field used to be unbounded in both directions: nothing capped how many
## could be live, and an uncollected orb held its square for 360 execution ticks —
## eight planning phases. The two orbs the AI keeps came from a planner constant
## a human was never bound by, so the field a person could build was strictly
## larger than anything the balance matrix ever measured.
func _test_orb_field_is_bounded(game) -> void:
	var original_weapons: Array[int] = game.player_weapons.duplicate()
	game.player_weapons[1] = game.Weapon.SHOCK
	game._clear_character_projectiles()

	var caster: Player = game.players[1]
	caster.plan.attack_mode = 1
	caster.plan.power = 0.6
	for cast in game.shock_max_live_orbs + 3:
		game._set_shock_attack_mode(1, 1)
		caster.plan.attack_mode = 1
		game._spawn_player_attack(caster)
		_check(game.shock_orb_count(1) <= game.shock_max_live_orbs,
			"the live orb count must never exceed the cap, however often she casts")
	_check(game.shock_orb_count(1) == game.shock_max_live_orbs,
		"casting past the cap must retire the oldest orb rather than refuse the throw")

	var survivor = null
	for orb in game.shock_orbs:
		if orb.shooter == 1:
			survivor = orb
			break
	_check(survivor != null and survivor.lifetime_ticks == game.shock_orb_lifetime_ticks,
		"an orb must take its lifetime from the tuning rather than its own default")
	_check(game.shock_orb_lifetime_ticks < 360,
		"the authored lifetime must be shorter than the eight-window original")

	game._clear_character_projectiles()
	game.player_weapons = original_weapons


## The Witch's planner walks her bolt forward tick by tick to see what it covers.
## It used to walk as far as the search window allowed and ignore the weapon's
## authored range entirely, so it scored shots that expire in mid-air as though
## they had arrived. Harmless only while the range exceeded the arena; the moment
## the range is tuned below it, the planner starts lying to itself.
func _test_plasma_planner_respects_its_range(game) -> void:
	var original_weapons: Array[int] = game.player_weapons.duplicate()
	var original_range: float = game.shock_plasma_range_full
	var original_positions := [game.players[0].position, game.players[1].position]

	game.player_weapons[0] = game.Weapon.SHOCK
	game.player_weapons[1] = game.Weapon.KNIVES
	game.players[0].position = Vector2(200.0, 560.0)
	game.players[1].position = Vector2(1000.0, 560.0)
	var separation: float = game.wrap_delta(
		game.players[0].position, game.players[1].position).length()

	game.shock_plasma_range_full = separation * 2.0
	var reaching := Ai.new()
	reaching.begin(game, 0, 1)
	reaching.finish()
	var reaching_score: float = float(reaching._best.get("score", -INF))

	game.shock_plasma_range_full = separation * 0.35
	var short := Ai.new()
	short.begin(game, 0, 1)
	short.finish()
	var short_score: float = float(short._best.get("score", -INF))

	_check(reaching_score > short_score,
		"a bolt that cannot physically arrive must score below one that can")

	game.shock_plasma_range_full = original_range
	game.player_weapons = original_weapons
	game.players[0].position = original_positions[0]
	game.players[1].position = original_positions[1]


func _test_class_movement_profiles(game) -> void:
	var original_weapons: Array[int] = game.player_weapons.duplicate()
	var kits: Array[int] = [game.Weapon.KNIVES, game.Weapon.DASHBLADE,
		game.Weapon.SHOCK, game.Weapon.CHAKRAM]
	var expected_speed: Array[float] = [1.0, 0.90, 0.90, 1.05]
	var expected_jumps: Array[int] = [1, 0, 0, 1]
	var expected_fall: Array[float] = [1.0, 1.10, 0.85, 0.90]
	for kit_index in kits.size():
		game.player_weapons[0] = kits[kit_index]
		_check(is_equal_approx(game.movement_speed_scale(0), expected_speed[kit_index]),
			"class %d must use its authored walk-speed scale" % kits[kit_index])
		_check(game.air_jumps_for(0) == expected_jumps[kit_index],
			"class %d must use its authored air-jump count" % kits[kit_index])
		_check(is_equal_approx(game.max_fall_speed_for(0),
			game.max_fall_speed * expected_fall[kit_index]),
			"class %d must use its authored fall-speed scale" % kits[kit_index])

	game.player_weapons[0] = game.Weapon.DASHBLADE
	var denied := Player.apply_jump(Vector2.ZERO, true, game.air_jumps_for(0), true,
		game.jump_impulse_for(0), game.air_jump_impulse_for(0), game.air_jumps_for(0))
	_check(not denied[3] and denied[0] == Vector2.ZERO,
		"The Rook must have no ground jump, not merely a very short one")

	game.player_weapons[0] = game.Weapon.CHAKRAM
	_check(game.jump_impulse_for(0) > game.jump_impulse \
			and game.air_jump_impulse_for(0) < game.jump_impulse_for(0),
		"Eclipse must have the highest takeoff and a weaker second jump")
	game.player_weapons = original_weapons


func _test_velocity_dash_time_stop_preview(game) -> void:
	game._clear_character_projectiles()
	var saved_platforms: Array = game.platforms.duplicate(true)
	var saved_wrap_x: bool = game.wrap_x
	var saved_wrap_y: bool = game.wrap_y
	game.platforms = []
	game._rebuild_solids()
	game.wrap_x = false
	game.wrap_y = false

	var p: Player = game.players[0]
	p.position = Vector2(100.0, 100.0)
	p.vel = Vector2.ZERO
	p.on_ground = false
	p.air_jumps_left = game.air_jumps_for(0)
	p.plan.start_new_turn()
	p.plan.set_aim_from_vector(Vector2.RIGHT, game.aim_min_angle, game.aim_max_angle)
	p.plan.power = 1.0
	game.frame_debt_cells[0] = game.frame_debt_max_cells
	game._spawn_player_attack(p)
	var dash = game.dashblades[0]
	while dash.ticks_left > 1:
		game._step_dashblades(game.tick_dt(), game.arrows)
	var full_dash_speed: float = dash.velocity.x

	game._begin_planning(false)
	var piloted: bool = game._pilot_step(0, 1, true, true)
	_check(piloted and not p.plan.jump_at(0) \
			and is_equal_approx(game.ghost_vel[0].x,
				full_dash_speed * game.dash_exit_momentum_retention),
		"a ghost must spend a pending dash tick before accepting locomotion or a jump")
	game._rebuild_ghost_paths()
	var promised: PackedVector2Array = game.ghost_path[0].duplicate()

	game.state = Phase.EXECUTING
	game.exec_tick = 0
	game.exec_ticks_total = game.exec_ticks()
	var actual := PackedVector2Array([p.position])
	for tick in game.exec_ticks():
		game._sim_tick(game.tick_dt())
		game.exec_tick += 1
		actual.append(p.position)
	var worst := 0.0
	for i in mini(promised.size(), actual.size()):
		worst = maxf(worst, promised[i].distance_to(actual[i]))
	_check(promised.size() == actual.size() and worst < 0.001,
		"a Rook dash crossing time stop must execute exactly where its ghost promised (drift %.4fpx)" % worst)

	game._clear_character_projectiles()
	game.platforms = saved_platforms
	game._rebuild_solids()
	game.wrap_x = saved_wrap_x
	game.wrap_y = saved_wrap_y
	game.state = Phase.PLANNING


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
