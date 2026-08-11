extends SceneTree

const GAME_MANAGER := preload("res://scripts/GameManager.gd")
var _failures := 0


class DummyEffects:
	extends RefCounted
	func add(_kind: int, _pos: Vector2, _color: Color) -> void:
		pass
	func remember(_label: String, _pos: Vector2, _color: Color) -> void:
		pass


class DummySfx:
	extends RefCounted
	func play(_which: String) -> void:
		pass


func _init() -> void:
	_test_ruleset_tuning()
	_test_direct_plus_lob_pair()
	_test_knife_court_layout()
	_test_every_platform_is_reachable()
	_test_trailing_boost()
	_test_grazing_ricochet()
	if _failures == 0:
		print("Close camera: all tests passed")
	else:
		push_error("Close camera: %d test(s) failed" % _failures)
	quit(_failures)


func _test_ruleset_tuning() -> void:
	var gm = GAME_MANAGER.new()
	var authored_speed: float = gm.player_move_speed
	var authored_jump: float = gm.jump_impulse
	gm._apply_ruleset(1)
	_check(gm.prototype_mode, "the menu ruleset must enter close camera")
	_check(gm.jump_impulse == gm.prototype_jump_impulse and gm.jump_impulse < authored_jump,
		"close camera must install its lower jump")
	_check(gm.player_move_speed == authored_speed,
		"close camera must preserve the authored ground movement")
	_check(gm.knife_offsets(0.5).size() == 2,
		"close camera must throw the fixed two-knife pair")
	gm._apply_ruleset(0)
	_check(gm.jump_impulse == authored_jump,
		"returning to ORIGINAL must restore the authored jump")
	gm.free()


func _test_direct_plus_lob_pair() -> void:
	var gm = GAME_MANAGER.new()
	gm.prototype_mode = true
	var aim := Vector2(1.0, -0.15).normalized()
	var right: Array[Vector2] = gm.knife_launch_velocities(aim, 0.5)
	_check(right.size() == 2 and right[0].normalized().is_equal_approx(aim),
		"the first knife must follow the chosen aim exactly")
	_check(right[1].y < right[0].y and is_equal_approx(right[1].length(), right[0].length()),
		"the second right-facing knife must leave at the same speed with a small upward lob")
	var left_aim := Vector2(-1.0, -0.15).normalized()
	var left: Array[Vector2] = gm.knife_launch_velocities(left_aim, 0.5)
	_check(left[0].normalized().is_equal_approx(left_aim) and left[1].y < left[0].y,
		"the upward lob must mirror correctly for a left-facing throw")
	var low: Array[Vector2] = gm.knife_launch_velocities(aim, 0.1)
	var high: Array[Vector2] = gm.knife_launch_velocities(aim, 0.9)
	_check(low[0].normalized().is_equal_approx(high[0].normalized()) \
		and low[1].normalized().is_equal_approx(high[1].normalized()),
		"power must change speed without bending either launch direction")
	gm.free()


func _test_knife_court_layout() -> void:
	var level := Levels.build_prototype()
	_check(level["wrap_x"] and not level["wrap_y"],
		"Knife Court must wrap horizontally for fighters and knives in both directions")

	var horizontal_movers: Array[Dictionary] = []
	var left_gate := false
	var right_gate := false
	var centre_blocker := false
	for platform: Dictionary in level["platforms"]:
		var rect: Rect2 = platform["rect"]
		if platform.has("motion") \
				and absf(platform["motion"].get("axis", Vector2.ZERO).x) > 0.9:
			horizontal_movers.append(platform)
		if rect.position.x == 0.0 and rect.end.y == Levels.ARENA_H \
				and rect.position.y >= 520.0 and rect.size.y <= 100.0:
			left_gate = true
		if rect.end.x == Levels.ARENA_W and rect.end.y == Levels.ARENA_H \
				and rect.position.y >= 520.0 and rect.size.y <= 100.0:
			right_gate = true
		if rect.position.x < Levels.ARENA_W * 0.5 \
				and rect.end.x > Levels.ARENA_W * 0.5 \
				and rect.position.y <= level["spawns"][0].y \
				and rect.end.y >= level["spawns"][0].y:
			centre_blocker = true

	_check(left_gate and right_gate,
		"Knife Court needs low physical barriers at both horizontal seams")
	_check(centre_blocker,
		"Knife Court needs permanent cover across the flat opening shot")
	_check(horizontal_movers.size() == 1,
		"Knife Court needs exactly one left-right platform in the upper middle")
	if horizontal_movers.size() == 1:
		var mover: Dictionary = horizontal_movers[0]
		var home: Vector2 = mover["home"]
		var later: Vector2 = home + Mover.offset(mover["motion"], 60)
		_check(later.x > home.x and is_equal_approx(later.y, home.y),
			"Knife Court's middle platform must advance left-to-right with world time")

	# Both movement systems fold through the same open horizontal seam. Keep the
	# probes above the low physical gates so this tests the intended passage.
	var gm = GAME_MANAGER.new()
	gm.wrap_x = level["wrap_x"]
	gm.wrap_y = level["wrap_y"]
	var player_right: Array = Player.step_state(
		Vector2(1278.0, 420.0), Vector2(300.0, 0.0), false, 1, false, 1.0 / 60.0, gm)
	var player_left: Array = Player.step_state(
		Vector2(2.0, 420.0), Vector2(-300.0, 0.0), false, -1, false, 1.0 / 60.0, gm)
	var knife_right: Array = Arrow.step_state(
		Vector2(1278.0, 420.0), Vector2(300.0, 0.0), 1.0 / 60.0, gm)
	var knife_left: Array = Arrow.step_state(
		Vector2(2.0, 420.0), Vector2(-300.0, 0.0), 1.0 / 60.0, gm)
	_check(player_right[0].x < 20.0 and player_left[0].x > Levels.ARENA_W - 20.0,
		"fighters must cross Knife Court's seam in both directions")
	_check(knife_right[0].x < 20.0 and knife_left[0].x > Levels.ARENA_W - 20.0,
		"knives must cross Knife Court's seam in both directions")
	gm.free()


func _test_every_platform_is_reachable() -> void:
	var gm = GAME_MANAGER.new()
	gm._apply_ruleset(1)
	var level := Levels.build_prototype()
	var surfaces: Array[Rect2] = [Rect2(0.0, 620.0, 1280.0, 100.0)]
	for platform: Dictionary in level["platforms"]:
		var rect: Rect2 = platform["rect"]
		if rect.size.x > rect.size.y:
			surfaces.append(rect)
	var reachable := [0]
	var changed := true
	var max_rise: float = gm.jump_impulse * gm.jump_impulse / (2.0 * gm.gravity)
	var horizontal_reach: float = gm.player_move_speed * (2.0 * gm.jump_impulse / gm.gravity)
	while changed:
		changed = false
		for target in range(1, surfaces.size()):
			if target in reachable:
				continue
			for source in reachable:
				var rise: float = surfaces[source].position.y - surfaces[target].position.y
				if rise < -0.1 or rise > max_rise + 0.1:
					continue
				var gap: float = maxf(0.0, maxf(
					surfaces[target].position.x - surfaces[source].end.x,
					surfaces[source].position.x - surfaces[target].end.x))
				if gap <= horizontal_reach:
					reachable.append(target)
					changed = true
					break
	_check(reachable.size() == surfaces.size(),
		"every Knife Court platform must be reachable with the lower jump (reached %s of %s: %s)" \
		% [reachable.size(), surfaces.size(), reachable])
	gm.free()


func _test_trailing_boost() -> void:
	var gm = GAME_MANAGER.new()
	gm.prototype_mode = true
	gm._effects = DummyEffects.new()
	gm._sfx = DummySfx.new()
	var chaser := _knife(Vector2(0.0, 0.0), Vector2(12.0, 0.0), Vector2(700.0, 0.0), 1)
	var leader := _knife(Vector2(20.0, 0.0), Vector2(23.0, 0.0), Vector2(300.0, 0.0), 2)
	leader.ricochet_count = 1
	var before: float = leader.vel.length()
	gm._resolve_clashes([chaser, leader])
	_check(leader.boost_count == 1 and leader.vel.length() > before,
		"a faster knife arriving from behind must accelerate the leader")
	_check(leader.ricochet_count == 0,
		"a clean trailing boost must restore one spent ricochet")
	_check(chaser.clashed and chaser.vel.length() < leader.vel.length(),
		"the trailing knife must spend its energy in the relay")
	chaser.free()
	leader.free()
	gm.free()


func _test_grazing_ricochet() -> void:
	var gm = GAME_MANAGER.new()
	gm.prototype_mode = true
	gm.platforms = [{"rects": [Rect2(100.0, 0.0, 20.0, 200.0)]}]
	var skip := _knife(Vector2(94.0, 40.0), Vector2(94.0, 40.0), Vector2(400.0, 900.0), 1)
	skip.cfg = gm
	var result := skip.sim_step(gm.tick_dt(), [])
	_check(result["alive"] and result["ricochet"] and skip.vel.x < 0.0,
		"a fast grazing wall impact must ricochet in close-camera mode")

	var square := _knife(Vector2(94.0, 40.0), Vector2(94.0, 40.0), Vector2(700.0, 0.0), 2)
	square.cfg = gm
	var square_result := square.sim_step(gm.tick_dt(), [])
	_check(not square_result["alive"] and not square_result["ricochet"],
		"a square wall impact must embed instead of bouncing")
	skip.free()
	square.free()
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
