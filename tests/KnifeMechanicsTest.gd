extends SceneTree

const GAME_MANAGER := preload("res://scripts/GameManager.gd")
var _failures: int = 0


class DummyEffects:
	extends RefCounted
	var calls: int = 0

	func add(_kind: int, _pos: Vector2, _color: Color) -> void:
		calls += 1


class DummySfx:
	extends RefCounted
	var calls: int = 0

	func play(_which: String) -> void:
		calls += 1


class DummyCutIn:
	extends RefCounted
	var active: bool = false
	var calls: int = 0

	func play(_who: int, _tint: Color, _grenadier: bool = false) -> void:
		active = true
		calls += 1

	func is_active() -> bool:
		return active


func _init() -> void:
	_test_synchronised_sweep()
	_test_velocity_response()
	_test_secret_triple_fan()
	_test_drag_collapses_the_arc()
	_test_deflected_knives_fall_as_debris()
	_test_preview_uses_platform_material_for_ricochet()
	_test_volley_filter_and_manager_resolution()
	_test_super_charge_requires_movement()
	_test_super_toggle_controls_upgrade()
	_test_super_cutin_gates_first_wave()
	_test_super_waves_share_one_volley()
	_test_temporal_core_lifecycle()
	_test_temporal_core_same_tick_collection()
	if _failures == 0:
		print("Knife mechanics: all tests passed")
	else:
		push_error("Knife mechanics: %d test(s) failed" % _failures)
	quit(_failures)


func _test_synchronised_sweep() -> void:
	var head_on := Arrow.moving_points_closest(
		Vector2(0.0, 0.0), Vector2(12.0, 0.0),
		Vector2(24.0, 0.0), Vector2(12.0, 0.0))
	_check(is_zero_approx(head_on[0]), "head-on swept knives must meet")

	# These segments cross spatially, but each knife reaches the crossing point
	# at a different fraction of the tick. A generic segment test false-hits it.
	var different_times := Arrow.moving_points_closest(
		Vector2(0.0, 0.0), Vector2(10.0, 0.0),
		Vector2(8.0, -10.0), Vector2(8.0, 0.0))
	_check(different_times[0] > 1.0, "different-time crossing must retain separation")


func _test_velocity_response() -> void:
	var bounced := Arrow.clash_velocities(
		Vector2(100.0, 0.0), Vector2(-100.0, 0.0), Vector2.LEFT, 0.35, 0.55)
	_check(bounced[0].x < 0.0 and bounced[1].x > 0.0, "head-on knives must bounce apart")
	_check(bounced[0].length() < 55.0 and bounced[1].length() < 55.0,
		"clashed knives must lose enough force to become floaty")


func _test_secret_triple_fan() -> void:
	var gm = GAME_MANAGER.new()
	var aim := Vector2(1.0, -0.35).normalized()
	var normal: Array[Vector2] = gm.knife_launch_velocities(aim, 0.6)
	var secret: Array[Vector2] = gm.knife_launch_velocities(aim, 0.6, true)
	_check(normal.size() == 2 and secret.size() == 3,
		"the secret rule must change the ordinary fan from two knives to three")
	_check(secret[0].is_equal_approx(normal[0]) and secret[2].is_equal_approx(normal[1]),
		"the outer secret knives must preserve the normal fan edges")
	var base: Vector2 = gm.knife_launch_velocity(aim, 0.6)
	_check(secret[1].is_equal_approx(base),
		"the added third knife must travel directly along the player's aim")
	_check(is_equal_approx(secret[0].length(), base.length()) \
		and is_equal_approx(secret[1].length(), base.length()) \
		and is_equal_approx(secret[2].length(), base.length()),
		"all three knives must use identical ordinary speed and physics")
	var left: Array[Vector2] = gm.knife_launch_velocities(Vector2(-aim.x, aim.y), 0.6, true)
	_check(left.size() == 3 and left[0].x < 0.0 and left[1].x < 0.0 and left[2].x < 0.0,
		"the normal three-knife fan must mirror when aiming left")
	gm.free()


## Drag has to bleed the throw, not the fall. If it damped both components it
## would cap the descent and turn a spent knife into a parachute, which is the
## opposite of the read being bought here.
func _test_drag_collapses_the_arc() -> void:
	var gm = GAME_MANAGER.new()
	var dt: float = gm.tick_dt()
	var ticks: int = gm.exec_ticks()

	var dragged := _fly(Vector2.ZERO, Vector2(gm.arrow_speed_max, 0.0), ticks, dt, gm, false)
	gm.arrow_drag = 0.0
	var free_flight := _fly(Vector2.ZERO, Vector2(gm.arrow_speed_max, 0.0), ticks, dt, gm, false)

	_check(dragged["vel"].x < free_flight["vel"].x * 0.85,
		"drag must visibly bleed forward speed inside a single execution window")
	_check(dragged["pos"].x < free_flight["pos"].x,
		"a dragged knife must fall short of an undragged one over the same window")
	_check(is_equal_approx(dragged["vel"].y, free_flight["vel"].y),
		"drag must never touch the fall, or the arc flattens instead of collapsing")

	# The collapse itself: the ratio of fall to forward travel has to grow.
	var dragged_slope: float = dragged["pos"].y / maxf(dragged["pos"].x, 0.001)
	var free_slope: float = free_flight["pos"].y / maxf(free_flight["pos"].x, 0.001)
	_check(dragged_slope > free_slope * 1.05,
		"drag must steepen the trajectory, not merely shorten it")
	gm.free()


func _test_deflected_knives_fall_as_debris() -> void:
	var gm = GAME_MANAGER.new()
	var dt: float = gm.tick_dt()
	var ticks: int = gm.exec_ticks()
	_check(gm.arrow_clashed_gravity_scale > 1.0,
		"a struck knife must fall harder than an aimed one")

	var aimed := _fly(Vector2.ZERO, Vector2(300.0, 0.0), ticks, dt, gm, false)
	var debris := _fly(Vector2.ZERO, Vector2(300.0, 0.0), ticks, dt, gm, true)
	_check(debris["pos"].y > aimed["pos"].y * 1.5,
		"a deflected knife must drop out of the air far sooner than a live shot")
	_check(is_equal_approx(debris["pos"].x, aimed["pos"].x),
		"the debris rule must change the fall only, leaving drag to handle the forward speed")
	gm.free()


func _test_preview_uses_platform_material_for_ricochet() -> void:
	var gm = GAME_MANAGER.new()
	gm.platforms = [{"rect": Rect2(100.0, 0.0, 20.0, 200.0), "hp": -1}]
	gm._rebuild_solids()
	var hard := PredictionSystem.predict_arrow(
		Vector2(90.0, 40.0), Vector2(700.0, 0.0), gm, 0.25)
	_check(not hard["blocked"] and hard["path"].size() > 3 \
			and hard["path"][hard["path"].size() - 1].x < 100.0,
		"known trajectory preview must draw a forceful bank from HARD terrain")

	gm.platforms = [{"rect": Rect2(100.0, 0.0, 20.0, 200.0), "hp": 2}]
	gm._rebuild_solids()
	var breakable := PredictionSystem.predict_arrow(
		Vector2(90.0, 40.0), Vector2(700.0, 0.0), gm, 0.25)
	_check(breakable["blocked"],
		"known trajectory preview must terminate the same throw on BREAK terrain")
	gm.free()


func _fly(pos: Vector2, vel: Vector2, ticks: int, dt: float, cfg, clashed: bool) -> Dictionary:
	for i in ticks:
		var st := Arrow.step_state(pos, vel, dt, cfg, clashed)
		pos = st[0]
		vel = st[1]
	return {"pos": pos, "vel": vel}


func _test_volley_filter_and_manager_resolution() -> void:
	var gm = GAME_MANAGER.new()
	gm._effects = DummyEffects.new()
	gm._sfx = DummySfx.new()
	var a := _knife(Vector2(0.0, 0.0), Vector2(12.0, 0.0), Vector2(100.0, 0.0), 7)
	var b := _knife(Vector2(24.0, 0.0), Vector2(12.0, 0.0), Vector2(-100.0, 0.0), 7)
	gm._resolve_clashes([a, b])
	_check(not a.clashed and not b.clashed, "siblings in one fan must never clash")

	b.volley = 8
	gm._resolve_clashes([a, b])
	_check(a.clashed and b.clashed, "knives from different volleys must clash")
	_check(a.clash_cooldown == gm.knife_clash_cooldown,
		"resolved clash must arm the repeat-contact cooldown")
	_check(gm._effects.calls == 1 and gm._sfx.calls == 1,
		"one clash must emit one visual and one sound cue")

	# The same pair is suppressed while separating, even if their swept paths
	# still overlap on the next tick.
	a.prev_pos = Vector2(0.0, 0.0)
	a.position = Vector2(12.0, 0.0)
	a.vel = Vector2(100.0, 0.0)
	b.prev_pos = Vector2(24.0, 0.0)
	b.position = Vector2(12.0, 0.0)
	b.vel = Vector2(-100.0, 0.0)
	gm._resolve_clashes([a, b])
	_check(a.clash_count == 1 and b.clash_count == 1,
		"the same pair must not grind through its cooldown")

	# A previously deflected knife can be struck again. The second blow retains
	# more energy, accumulates tumble and leaves the original collision plane —
	# even while its cooldown with the first knife is still active.
	a.prev_pos = Vector2(0.0, 0.0)
	a.position = Vector2(12.0, 0.0)
	a.vel = Vector2(100.0, 0.0)
	var c := _knife(Vector2(24.0, 0.0), Vector2(12.0, 0.0), Vector2(-100.0, 0.0), 9)
	gm._resolve_clashes([a, c])
	_check(a.clash_count == 2, "a re-hit knife must remember both impacts")
	_check(absf(a.vel.y) > 0.1, "a re-clash must introduce a deterministic glancing angle")
	_check(absf(a.spin) > gm.knife_clash_spin,
		"successive impacts must accumulate angular momentum")
	_check(gm._effects.calls == 2 and gm._sfx.calls == 2,
		"the second impact must emit its own feedback")
	a.free()
	b.free()
	c.free()
	gm.free()


func _test_super_charge_requires_movement() -> void:
	var gm = GAME_MANAGER.new()
	gm._effects = DummyEffects.new()
	gm._sfx = DummySfx.new()
	for i in 2:
		var p := Player.new()
		p.cfg = gm
		p.index = i
		p.vel = Vector2(100.0, 0.0) if i == 0 else Vector2.ZERO
		gm.players.append(p)

	var a := _knife(Vector2(0.0, 0.0), Vector2(12.0, 0.0), Vector2(100.0, 0.0), 1)
	var b := _knife(Vector2(24.0, 0.0), Vector2(12.0, 0.0), Vector2(-100.0, 0.0), 2)
	a.shooter = 0
	b.shooter = 1
	gm._resolve_clashes([a, b])
	_check(is_equal_approx(gm.super_meter[0], gm.super_charge_per_clash),
		"a moving knife owner must gain super meter from a clean opposing clash")
	_check(is_zero_approx(gm.super_meter[1]),
		"a stationary knife owner must not gain super meter")

	# Even after the stationary player begins moving, striking an already
	# deflected knife is a re-clash and must not become a meter farm.
	gm.players[1].vel = Vector2(100.0, 0.0)
	var c := _knife(Vector2(24.0, 0.0), Vector2(12.0, 0.0), Vector2(-100.0, 0.0), 3)
	c.shooter = 1
	gm._resolve_clashes([a, c])
	_check(is_zero_approx(gm.super_meter[1]), "re-clashes must not award super meter")
	a.free()
	b.free()
	c.free()
	for p in gm.players:
		p.free()
	gm.free()


func _test_super_waves_share_one_volley() -> void:
	var gm = GAME_MANAGER.new()
	gm._effects = DummyEffects.new()
	gm._sfx = DummySfx.new()
	gm._arrow_layer = Node2D.new()
	gm.add_child(gm._arrow_layer)
	var p := Player.new()
	p.cfg = gm
	p.index = 0
	p.position = Vector2(200.0, 300.0)
	p.plan.set_aim_from_vector(Vector2.RIGHT, gm.aim_min_angle, gm.aim_max_angle)
	gm.players.append(p)
	gm.super_meter[0] = 1.0
	gm.super_armed[0] = true
	_check(gm.super_waves == 5 and gm.super_wave_interval_ticks == 8,
		"the super must read as five consecutive, clearly separated waves")

	for wave in gm.super_waves:
		gm._spawn_super_wave(p, wave)
	_check(gm.arrows.size() == gm.super_knives_per_wave * gm.super_waves,
		"the complete super must spawn every configured wave and knife")
	var volley: int = gm.arrows[0].volley
	for knife in gm.arrows:
		_check(knife.volley == volley, "every wave in one super must share a volley id")
	for wave in range(1, gm.super_waves):
		for knife_index in gm.super_knives_per_wave:
			var first: Arrow = gm.arrows[knife_index]
			var repeated: Arrow = gm.arrows[wave * gm.super_knives_per_wave + knife_index]
			_check(first.vel.distance_to(repeated.vel) < 0.001,
				"consecutive super waves must repeat the same narrow firing lane")
	gm._resolve_clashes(gm.arrows)
	for knife in gm.arrows:
		_check(not knife.clashed, "a super burst must never clash with itself at launch")
	_check(is_zero_approx(gm.super_meter[0]), "the first super wave must spend the full meter")
	_check(not gm.super_armed[0], "releasing the super must return its toggle to standby")
	p.free()
	gm.free()


func _test_super_cutin_gates_first_wave() -> void:
	var gm = GAME_MANAGER.new()
	gm._effects = DummyEffects.new()
	gm._sfx = DummySfx.new()
	gm._super_freeze = DummyCutIn.new()
	gm._arrow_layer = Node2D.new()
	gm.add_child(gm._arrow_layer)
	var p := Player.new()
	p.cfg = gm
	p.index = 0
	p.position = Vector2(200.0, 300.0)
	p.plan.shot_tick = 0
	p.plan.super_shot = true
	p.plan.set_aim_from_vector(Vector2.RIGHT, gm.aim_min_angle, gm.aim_max_angle)
	gm.players.append(p)
	gm.super_meter[0] = 1.0
	gm.super_armed[0] = true
	gm.exec_tick = 0

	gm._sim_tick(gm.tick_dt())
	_check(gm._super_freeze.calls == 1 and gm._super_freeze.active,
		"a super launch tick must begin its freeze-frame cut-in")
	_check(gm.arrows.is_empty() and is_equal_approx(gm.super_meter[0], 1.0),
		"the cut-in must run before knives spawn or the super meter is spent")

	gm._super_freeze.active = false
	gm._sim_tick(gm.tick_dt())
	_check(gm._super_freeze.calls == 1,
		"resuming the same tick must not replay an already shown cut-in")
	_check(gm.arrows.size() == gm.super_knives_per_wave,
		"the first super wave must spawn as soon as the cut-in clears")
	_check(is_zero_approx(gm.super_meter[0]),
		"the meter must be spent by the resumed first wave")
	p.free()
	gm.free()


func _test_super_toggle_controls_upgrade() -> void:
	var gm = GAME_MANAGER.new()
	var p := Player.new()
	p.cfg = gm
	p.index = 0
	gm.players.append(p)
	gm.super_meter[0] = 1.0
	for _tick in gm.exec_ticks():
		p.plan.record(1, false, false)

	gm.charging[0] = true
	gm._release_charge(0)
	_check(not p.plan.super_shot,
		"a full meter must not upgrade a shot while the SUPER toggle is off")
	gm._rollback(0)
	gm._toggle_super(0)
	_check(gm.super_armed[0], "the SUPER button must arm a full meter")
	gm.charging[0] = true
	gm._release_charge(0)
	var runway: int = (gm.super_waves - 1) * gm.super_wave_interval_ticks
	_check(p.plan.super_shot, "an armed full meter must upgrade the placed shot")
	_check(p.plan.shot_tick == gm.exec_ticks() - 1 - runway,
		"a late super must be pulled forward enough to fit every wave")
	_check(is_equal_approx(gm.super_meter[0], 1.0),
		"toggling or rolling back a super must not spend its meter before launch")
	p.free()
	gm.free()


func _test_temporal_core_lifecycle() -> void:
	var gm = GAME_MANAGER.new()
	var sockets: Array[Vector2] = [Vector2(640.0, 400.0)]
	gm.core_spawn_points = sockets
	gm._advance_temporal_core()
	_check(gm.hitless_execution_streak == 1 and not gm.core_announced,
		"the core must stay hidden after the first hitless execution")
	gm._advance_temporal_core()
	_check(gm.core_announced and not gm.core_active,
		"the core location must be telegraphed one turn before activation")
	gm._advance_temporal_core()
	_check(gm.core_active and gm.core_turns_left == gm.core_active_turns,
		"a further hitless execution must materialize the core")
	gm._advance_temporal_core()
	_check(gm.core_active and gm.core_turns_left == 1,
		"the active core must persist into a second execution")
	gm._advance_temporal_core()
	_check(not gm.core_active and not gm.core_announced,
		"an unclaimed core must expire after its configured lifetime")

	gm._advance_temporal_core()
	gm._advance_temporal_core()
	gm._hit_this_execution = true
	gm._advance_temporal_core()
	_check(not gm.core_active and not gm.core_announced and gm.hitless_execution_streak == 0,
		"a hit during the warning turn must cancel the incoming core")
	gm.free()


func _test_temporal_core_same_tick_collection() -> void:
	var gm = GAME_MANAGER.new()
	gm._effects = DummyEffects.new()
	gm._sfx = DummySfx.new()
	gm.core_active = true
	gm.core_position = Vector2(400.0, 400.0)
	for i in 2:
		var p := Player.new()
		p.cfg = gm
		p.index = i
		p.position = gm.core_position
		gm.players.append(p)

	gm._check_core_collection()
	_check(is_equal_approx(gm.super_meter[0], 1.0) and is_equal_approx(gm.super_meter[1], 1.0),
		"same-tick core contact must fill both players' super meters")
	_check(not gm.core_active and gm._core_collected_this_execution,
		"a collected core must leave the arena immediately")
	_check(not gm.super_armed[0] and not gm.super_armed[1],
		"collecting a core must leave the new full meters in standby")
	_check(gm._effects.calls == 1 and gm._sfx.calls == 1,
		"core collection must emit one shared audiovisual cue")
	for p in gm.players:
		p.free()
	gm.free()


func _knife(from: Vector2, to: Vector2, velocity: Vector2, volley: int) -> Arrow:
	var knife := Arrow.new()
	knife.prev_pos = from
	knife.position = to
	knife.vel = velocity
	knife.volley = volley
	return knife


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
