extends SceneTree

const CHAKRAM_SCRIPT := preload("res://scripts/Chakram.gd")

var _failures := 0


class DummyConfig:
	extends RefCounted
	var platforms: Array = []
	var world_bounds := Rect2(-2000.0, -2000.0, 4000.0, 4000.0)

	func wrap_point(point: Vector2) -> Vector2:
		return point

	func body_rects(player) -> Array[Rect2]:
		return [Rect2(player.position - Vector2(8.0, 16.0), Vector2(16.0, 32.0))]


class DummyPlayer:
	extends RefCounted
	var index: int
	var position: Vector2
	var alive := true

	func _init(new_index: int, new_position: Vector2) -> void:
		index = new_index
		position = new_position

	func is_invulnerable() -> bool:
		return false


func _init() -> void:
	_test_turn_lifecycle_is_deterministic()
	_test_forced_recall_returns_and_is_caught()
	_test_hard_terrain_bounces_once_then_sticks()
	_test_breakable_terrain_sticks_without_bouncing()
	_test_projectile_clash_contract()
	if _failures == 0:
		print("Chakram: all tests passed")
	else:
		push_error("Chakram: %d test(s) failed" % _failures)
	quit(_failures)


func _test_turn_lifecycle_is_deterministic() -> void:
	var cfg := DummyConfig.new()
	var owner := DummyPlayer.new(0, Vector2.ZERO)
	var a = _chakram(cfg, Vector2.ZERO, Vector2(210.0, -40.0), 4)
	var b = _chakram(cfg, Vector2.ZERO, Vector2(210.0, -40.0), 4)
	for tick in 8:
		var ra: Dictionary = a.sim_step(1.0 / 60.0, [owner], 4)
		var rb: Dictionary = b.sim_step(1.0 / 60.0, [owner], 4)
		_check(a.position.is_equal_approx(b.position) and a.vel.is_equal_approx(b.vel) \
			and ra == rb, "equal inputs must produce identical chakram state and results")
		if tick == 2:
			_check(a.vel.y > -40.0, "outbound gravity must bend the launch into an arc")
	var held_at: Vector2 = a.position
	_check(a.advance_to_turn(5) and a.is_holding(),
		"the turn after launch must hold the chakram in place")
	for tick in 8:
		a.sim_step(1.0 / 60.0, [owner], 5)
	_check(a.position.is_equal_approx(held_at) and a.vel.is_zero_approx(),
		"a midair chakram must remain stationary for its additional turn")
	_check(a.advance_to_turn(6) and a.is_returning(),
		"the third turn must begin recall")
	var before_return: float = a.position.distance_to(owner.position)
	for tick in 12:
		a.sim_step(1.0 / 60.0, [owner], 6)
		if not is_instance_valid(a) or a.position.distance_to(owner.position) < 1.0:
			break
	_check(a.position.distance_to(owner.position) < before_return,
		"the third-turn recall must move toward the owner")
	_check(not a.advance_to_turn(7),
		"an uncaught chakram must expire before a fourth arena turn")
	a.free()
	b.free()


func _test_forced_recall_returns_and_is_caught() -> void:
	var cfg := DummyConfig.new()
	var owner := DummyPlayer.new(0, Vector2.ZERO)
	var chakram = _chakram(cfg, Vector2(180.0, 0.0), Vector2(120.0, 0.0), 2)
	chakram.age_ticks = 20
	chakram.force_recall()
	var caught := false
	for _tick in 180:
		var result: Dictionary = chakram.sim_step(1.0 / 60.0, [owner])
		if result["caught"]:
			caught = true
			_check(not result["alive"], "a caught return must leave the live projectile array")
			break
	_check(caught, "forced recall must steer back to the owner and be catchable")
	chakram.free()


func _test_hard_terrain_bounces_once_then_sticks() -> void:
	var cfg := DummyConfig.new()
	cfg.platforms = [
		{"rects": [Rect2(100.0, -100.0, 20.0, 200.0)], "hp": -1},
		{"rects": [Rect2(30.0, -100.0, 10.0, 200.0)], "hp": -1},
	]
	var chakram = _chakram(cfg, Vector2(70.0, 0.0), Vector2(450.0, 0.0), 3)
	chakram.outbound_gravity = 0.0
	chakram.outbound_drag = 0.0
	var result: Dictionary = chakram.sim_step(1.0 / 15.0, [], 3)
	_check(result["bounced"] and not result["stuck"] and result["hit_platform"] == 0,
		"the first swept HARD-terrain contact must report a ricochet")
	_check(result["alive"] and not chakram.is_holding() and chakram.vel.x < 0.0 \
			and is_equal_approx(chakram.vel.length(), 450.0 * chakram.bounce_retention),
		"a HARD ricochet must reverse the surface-normal velocity and retain tuned speed")
	result = chakram.sim_step(0.15, [], 3)
	_check(result["stuck"] and not result["bounced"] and result["hit_platform"] == 1,
		"a second terrain contact must spend the one-bounce allowance and pin the chakram")
	var stuck_at: Vector2 = chakram.position
	_check(result["alive"] and chakram.is_holding() and chakram.vel.is_zero_approx(),
		"the post-ricochet terrain contact must leave a persistent holding hazard")
	cfg.platforms[1]["rects"][0].position.x += 24.0
	chakram.sim_step(1.0 / 60.0, [], 4)
	_check(is_equal_approx(chakram.position.x, stuck_at.x + 24.0),
		"a stuck chakram must remain attached to a moving hard platform")
	chakram.free()


func _test_breakable_terrain_sticks_without_bouncing() -> void:
	var cfg := DummyConfig.new()
	cfg.platforms = [{
		"rects": [Rect2(100.0, -100.0, 20.0, 200.0)],
		"hp": 2,
	}]
	var chakram = _chakram(cfg, Vector2(70.0, 0.0), Vector2(450.0, 0.0), 3)
	chakram.outbound_gravity = 0.0
	var result: Dictionary = chakram.sim_step(1.0 / 15.0, [], 3)
	_check(result["stuck"] and not result["bounced"] and chakram.is_holding(),
		"breakable cover must absorb and pin a chakram instead of ricocheting it")
	chakram.free()


func _test_projectile_clash_contract() -> void:
	var cfg := DummyConfig.new()
	var chakram = _chakram(cfg, Vector2.ZERO, Vector2(200.0, 0.0), 1)
	chakram.network_id = 77
	var first: Dictionary = chakram.resolve_projectile_clash(Vector2(-500.0, 0.0), 91)
	_check(first["accepted"] and not first["alive"] \
			and first["kind"] == CHAKRAM_SCRIPT.ClashKind.BROKEN,
		"the first projectile impact must destroy the chakram")
	_check(first["other_velocity"] == Vector2(-500.0, 0.0),
		"destroying a chakram must not consume or redirect the striking projectile")
	_check(chakram.lockstep_digest_fragment().begins_with("77,"),
		"lockstep digest must include the stable projectile identity")
	chakram.free()


func _chakram(cfg, at: Vector2, velocity: Vector2, launch_turn: int):
	var chakram = CHAKRAM_SCRIPT.new()
	chakram.cfg = cfg
	chakram.shooter = 0
	chakram.begin_lifecycle(launch_turn)
	chakram.position = at
	chakram.prev_pos = at
	chakram.vel = velocity
	return chakram


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
