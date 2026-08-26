extends SceneTree

const PLASMA_SCRIPT := preload("res://scripts/ShockPlasma.gd")
const ORB_SCRIPT := preload("res://scripts/ShockOrb.gd")

var _failures := 0


class TestConfig:
	extends RefCounted
	var platforms: Array = []
	var world_bounds := Rect2(-1000.0, -1000.0, 2000.0, 2000.0)
	## The lance is ballistic. These checks isolate contact and range, so they
	## fly it flat; the arc itself is covered against the real manager.
	var shock_plasma_gravity: float = 0.0

	func wrap_point(point: Vector2) -> Vector2:
		return point

	func body_rects(player) -> Array[Rect2]:
		return [player.body]


class TestPlayer:
	extends RefCounted
	var index := 0
	var alive := true
	var body := Rect2(0.0, 0.0, 20.0, 40.0)

	func is_invulnerable() -> bool:
		return false


func _init() -> void:
	_test_fast_straight_plasma_uses_swept_contacts()
	_test_plasma_charge_is_captured()
	_test_partial_plasma_fades_at_its_range_limit()
	_test_plasma_has_launch_grace_for_its_owner()
	_test_orb_arming_and_detonation_contract()
	_test_orb_lob_rests_and_resumes_when_support_breaks()
	_test_orb_lifetime_and_blast_revectoring()
	if _failures == 0:
		print("Shock weapon: all tests passed")
	else:
		push_error("Shock weapon: %d test(s) failed" % _failures)
	quit(_failures)


func _test_fast_straight_plasma_uses_swept_contacts() -> void:
	var cfg := TestConfig.new()
	var plasma = PLASMA_SCRIPT.new()
	plasma.cfg = cfg
	plasma.position = Vector2.ZERO
	plasma.configure_launch(Vector2.RIGHT, 1200.0)
	var first := plasma.sim_step(1.0 / 60.0, [])
	_check(first["alive"] and is_zero_approx(plasma.position.y),
		"plasma must travel fast and perfectly straight")
	_check(is_equal_approx(plasma.position.x, 20.0),
		"plasma travel must be deterministic from speed and fixed dt")

	var target := TestPlayer.new()
	target.index = 3
	target.body = Rect2(48.0, -10.0, 3.0, 20.0)
	var hit := plasma.sim_step(1.0 / 30.0, [target])
	_check(not hit["alive"] and hit["hit_player"] == 3,
		"fast plasma must use a swept hit and not tunnel through a thin fighter")
	plasma.free()


func _test_plasma_charge_is_captured() -> void:
	var low = PLASMA_SCRIPT.new()
	low.cfg = TestConfig.new()
	low.configure_launch(Vector2.RIGHT, 860.0, 0.0)
	var high = PLASMA_SCRIPT.new()
	high.cfg = TestConfig.new()
	high.configure_launch(Vector2.RIGHT, 1160.0, 1.0)
	_check(low.charge_power == 0.0 and high.charge_power == 1.0 \
			and high.vel.length() > low.vel.length(),
		"plasma charge must be captured and produce a faster high-charge shot")
	_check(low.lockstep_digest_fragment() != high.lockstep_digest_fragment(),
		"plasma charge must be represented in deterministic state")
	low.free()
	high.free()


func _test_partial_plasma_fades_at_its_range_limit() -> void:
	var plasma = PLASMA_SCRIPT.new()
	plasma.cfg = TestConfig.new()
	plasma.position = Vector2.ZERO
	plasma.configure_launch(Vector2.RIGHT, 600.0, 0.5, 100.0)
	var result: Dictionary = {}
	for tick in 20:
		result = plasma.sim_step(1.0 / 60.0, [])
		if plasma.distance_travelled >= 80.0:
			break
	_check(result["alive"] and plasma.fade_alpha() < 1.0,
		"a partial plasma must visibly fade during the final part of its range")
	while result["alive"]:
		result = plasma.sim_step(1.0 / 60.0, [])
	_check(result["range_expired"] and is_equal_approx(plasma.distance_travelled, 100.0),
		"a partial plasma must disappear exactly at its charge-authored range")
	plasma.free()


func _test_plasma_has_launch_grace_for_its_owner() -> void:
	var plasma = PLASMA_SCRIPT.new()
	plasma.cfg = TestConfig.new()
	plasma.shooter = 2
	plasma.position = Vector2.ZERO
	plasma.configure_launch(Vector2.RIGHT, 1200.0)
	var owner := TestPlayer.new()
	owner.index = 2
	owner.body = Rect2(-16.0, -24.0, 32.0, 48.0)
	var launch := plasma.sim_step(1.0 / 60.0, [owner])
	_check(launch["alive"] and launch["hit_player"] == -1,
		"plasma must not kill its shooter while leaving the launch volume")
	plasma.free()


func _test_orb_arming_and_detonation_contract() -> void:
	var orb = ORB_SCRIPT.new()
	orb.cfg = TestConfig.new()
	orb.shooter = 1
	orb.position = Vector2(75.0, 90.0)
	orb.arm_ticks = 2
	var early := orb.request_regular_hit(0)
	_check(not early["detonate"] and early["reason"] == "unarmed",
		"an orb must reject projectile detonations during its arming delay")
	orb.sim_step(1.0 / 60.0)
	orb.sim_step(1.0 / 60.0)
	var small := orb.request_regular_hit(0)
	var combo := orb.request_plasma_hit(2)
	_check(small["detonate"] and small["blast"] == ORB_SCRIPT.BLAST_SMALL,
		"a regular projectile must request the small detonation")
	_check(combo["detonate"] and combo["blast"] == ORB_SCRIPT.BLAST_COMBO,
		"plasma must request the large shock combo")
	_check(combo["trigger_shooter"] == 2 and combo["orb_owner"] == 1,
		"the integration layer must receive both orb owner and combo trigger for credit")
	_check(combo["revector_weapons"] and not combo["consume_weapons"],
		"shock blasts must explicitly preserve and revector nearby weapons")
	orb.free()


func _test_orb_lob_rests_and_resumes_when_support_breaks() -> void:
	var cfg := TestConfig.new()
	cfg.platforms = [{"rects": [Rect2(-100.0, 100.0, 200.0, 20.0)], "hp": -1}]
	var orb = ORB_SCRIPT.new()
	orb.cfg = cfg
	orb.position = Vector2(0.0, 87.8)
	orb.vel = Vector2(8.0, 18.0)
	orb.rest_speed = 40.0
	var landed := orb.sim_step(1.0 / 60.0)
	_check(landed["resting"] and landed["support_platform"] == 0,
		"a slow descending orb must settle on a platform and persist")
	var held_position: Vector2 = orb.position
	orb.sim_step(0.5)
	_check(orb.position.is_equal_approx(held_position) and orb.vel.is_zero_approx(),
		"a resting orb must remain available as arena setup")
	cfg.platforms.clear()
	orb.sim_step(1.0 / 60.0)
	_check(not orb.resting and orb.vel.y > 0.0,
		"an orb must resume falling when its supporting platform disappears")
	orb.free()


func _test_orb_lifetime_and_blast_revectoring() -> void:
	var orb = ORB_SCRIPT.new()
	orb.cfg = TestConfig.new()
	orb.lifetime_ticks = 2
	var first := orb.sim_step(1.0 / 60.0)
	var expired := orb.sim_step(1.0 / 60.0)
	_check(first["alive"] and not expired["alive"] and expired["expired"] \
			and not expired["detonate"],
		"an orb must report deterministic expiry so the manager can create its small pop")

	var pushed := ORB_SCRIPT.revector_velocity(Vector2.ZERO, Vector2(25.0, 0.0),
		Vector2(0.0, 100.0), 600.0, 100.0)
	_check(pushed.x > 400.0 and pushed.y > 0.0,
		"blast revectoring must relaunch a nearby weapon while retaining some momentum")
	var untouched := ORB_SCRIPT.revector_velocity(Vector2.ZERO, Vector2(150.0, 0.0),
		Vector2(30.0, 40.0), 600.0, 100.0)
	_check(untouched.is_equal_approx(Vector2(30.0, 40.0)),
		"weapons outside the blast radius must keep their velocity exactly")
	orb.free()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
