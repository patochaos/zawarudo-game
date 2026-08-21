extends SceneTree

const DASHBLADE_SCRIPT := preload("res://scripts/Dashblade.gd")
var _failures: int = 0


func _init() -> void:
	_test_planned_motion_is_deterministic()
	_test_front_guard_physically_deflects()
	_test_front_guard_intercepts_energy_projectile()
	_test_guard_durability_and_body_exposure()
	_test_blade_reports_fighter_hits_once()
	_test_hard_terrain_stops_and_soft_terrain_does_not()
	_test_ground_contact_does_not_cancel_horizontal_dash()
	if _failures == 0:
		print("Dashblade: all tests passed")
	else:
		push_error("Dashblade: %d test(s) failed" % _failures)
	quit(_failures)


func _test_planned_motion_is_deterministic() -> void:
	var dash = DASHBLADE_SCRIPT.new()
	dash.begin(Vector2(10.0, 20.0), Vector2.RIGHT, 120.0, 3, 0)
	for _tick in 3:
		dash.sim_step(1.0 / 60.0)
	_check(dash.position.is_equal_approx(Vector2(16.0, 20.0)),
		"three planned ticks must produce one deterministic endpoint")
	_check(not dash.active and dash.ticks_left == 0,
		"the dash must end on its exact planned tick")
	_check(dash.velocity.is_equal_approx(Vector2(
			120.0 * Dashblade.DEFAULT_EXIT_MOMENTUM_RETENTION, 0.0)),
		"a naturally completed dash must shed attack speed before fighter integration")
	dash.free()


func _test_front_guard_physically_deflects() -> void:
	var dash = DASHBLADE_SCRIPT.new()
	dash.begin(Vector2.ZERO, Vector2.RIGHT, 120.0, 5, 0, 2)
	var arrow := _arrow(Vector2(50.0, 0.0), Vector2(10.0, 0.0), Vector2(-600.0, 0.0), 11)
	var result: Dictionary = dash.sim_step(1.0 / 60.0, [arrow])
	_check(result["deflected"].size() == 1 and arrow.clashed,
		"a projectile swept into the front blade must be physically deflected")
	_check(arrow.vel.x > 0.0,
		"the moving blade must reverse an incoming projectile in its own collision frame")
	_check(dash.guard_durability == 1,
		"each deflection must consume exactly one point of guard durability")
	_check(result["owner_hit_projectiles"].is_empty(),
		"a successful guard contact must not also report a body hit")
	arrow.free()
	dash.free()


func _test_front_guard_intercepts_energy_projectile() -> void:
	var dash = DASHBLADE_SCRIPT.new()
	dash.begin(Vector2.ZERO, Vector2.RIGHT, 600.0, 3, 0, 1)
	dash.sim_step(1.0 / 60.0)
	var contact: Dictionary = dash.swept_projectile_contact(
		Vector2(70.0, 0.0), Vector2(5.0, 0.0), ShockPlasma.COLLISION_RADIUS)
	_check(contact["guard_time"] < contact["body_time"] and dash.spend_guard() \
			and dash.guard_durability == 0,
		"the moving front blade must spend one guard point to intercept plasma before the body")
	dash.free()


func _test_guard_durability_and_body_exposure() -> void:
	var dash = DASHBLADE_SCRIPT.new()
	dash.begin(Vector2.ZERO, Vector2.RIGHT, 120.0, 5, 0, 1)
	var first := _arrow(Vector2(50.0, 0.0), Vector2(-10.0, 0.0), Vector2(-600.0, 0.0), 20)
	var second := _arrow(Vector2(50.0, 2.0), Vector2(-10.0, 2.0), Vector2(-600.0, 0.0), 21)
	var result: Dictionary = dash.sim_step(1.0 / 60.0, [second, first])
	_check(result["deflected"].size() == 1 and result["deflected"][0] == first,
		"same-time guard contacts must resolve deterministically by stable projectile ID")
	_check(result["owner_hit_projectiles"].size() == 1 \
		and result["owner_hit_projectiles"][0] == second,
		"a projectile that reaches the body after guard durability is spent must hit the dasher")

	var rear := _arrow(Vector2(-40.0, 0.0), Vector2(10.0, 0.0), Vector2(600.0, 0.0), 22)
	var rear_result: Dictionary = dash.sim_step(1.0 / 60.0, [rear])
	_check(rear_result["deflected"].is_empty() \
		and rear_result["owner_hit_projectiles"].size() == 1,
		"the front guard must never become blanket projectile invulnerability")
	first.free()
	second.free()
	rear.free()
	dash.free()


func _test_blade_reports_fighter_hits_once() -> void:
	var dash = DASHBLADE_SCRIPT.new()
	dash.begin(Vector2.ZERO, Vector2.RIGHT, 600.0, 3, 0)
	var owner := _fighter(0, Vector2.ZERO)
	var enemy := _fighter(1, Vector2(58.0, 0.0))
	var second_enemy := _fighter(2, Vector2(66.0, 0.0))
	var first: Dictionary = dash.sim_step(1.0 / 60.0, [], [owner, enemy, second_enemy])
	var second: Dictionary = dash.sim_step(1.0 / 60.0, [], [owner, enemy, second_enemy])
	_check(first["hit_fighters"] == [1],
		"the swept blade must report an opposing fighter reached during the tick")
	_check(second["hit_fighters"].is_empty(),
		"one dash must award at most one fighter hit even through a crowded line")
	owner.free()
	enemy.free()
	second_enemy.free()
	dash.free()


func _test_hard_terrain_stops_and_soft_terrain_does_not() -> void:
	var hard_dash = DASHBLADE_SCRIPT.new()
	hard_dash.begin(Vector2.ZERO, Vector2.RIGHT, 6000.0, 3, 0)
	var hard := [{"rect": Rect2(80.0, -50.0, 20.0, 100.0), "hp": -1}]
	var hard_result: Dictionary = hard_dash.sim_step(1.0 / 60.0, [], [], hard)
	_check(hard_result["stopped_by_hard"] and hard_result["hit_platform"] == 0,
		"a swept dash must report the first HARD terrain contact")
	_check(is_equal_approx(hard_dash.position.x, 63.95) and hard_result["shimmy"] \
			and hard_dash.velocity.y < 0.0,
		"a side-on HARD contact must catch and shimmy upward instead of cancelling the dash")
	var wall_y: float = hard_dash.position.y
	while hard_dash.active:
		hard_dash.sim_step(1.0 / 60.0, [], [], hard)
	_check(hard_dash.position.y < wall_y and hard_dash.velocity.is_zero_approx(),
		"the wall shimmy must gain a little height, then end without permanent climb velocity")

	var soft_dash = DASHBLADE_SCRIPT.new()
	soft_dash.begin(Vector2.ZERO, Vector2.RIGHT, 6000.0, 1, 0)
	var soft := [{"rect": Rect2(80.0, -50.0, 20.0, 100.0), "hp": 2}]
	var soft_result: Dictionary = soft_dash.sim_step(1.0 / 60.0, [], [], soft)
	_check(not soft_result["stopped_by_hard"] and is_equal_approx(soft_dash.position.x, 100.0),
		"breakable terrain must remain available for the integrating game to pierce or damage")
	hard_dash.free()
	soft_dash.free()


func _test_ground_contact_does_not_cancel_horizontal_dash() -> void:
	var dash = DASHBLADE_SCRIPT.new()
	dash.begin(Vector2(0.0, 76.0), Vector2.RIGHT, 600.0, 2, 0)
	var floor := [{"rect": Rect2(-200.0, 100.0, 400.0, 30.0), "hp": -1}]
	var result: Dictionary = dash.sim_step(1.0 / 60.0, [], [], floor)
	_check(result["active"] and not result["stopped_by_hard"] \
			and dash.position.x > 0.0,
		"resting floor contact must not cancel a horizontal body dash at tick zero")
	dash.free()


func _arrow(from: Vector2, to: Vector2, arrow_velocity: Vector2, id: int) -> Arrow:
	var arrow := Arrow.new()
	arrow.prev_pos = from
	arrow.position = to
	arrow.vel = arrow_velocity
	arrow.network_id = id
	return arrow


func _fighter(index: int, at: Vector2) -> Player:
	var fighter := Player.new()
	fighter.index = index
	fighter.position = at
	fighter.alive = true
	return fighter


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
