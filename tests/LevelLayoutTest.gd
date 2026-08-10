extends SceneTree

const PLAYER_HALF := Vector2(16.0, 24.0)
const SAMPLE_STEP := 8
const SAFE_JUMP_RISE := 195.0
var _failures: int = 0


func _init() -> void:
	for index in Levels.count():
		_test_level(index)
	if _failures == 0:
		print("Level layouts: all tests passed")
	else:
		push_error("Level layouts: %d test(s) failed" % _failures)
	quit(_failures)


func _test_level(index: int) -> void:
	var level := Levels.build(index)
	var label: String = level["name"]
	var rects: Array[Rect2] = []
	for platform in level["platforms"]:
		rects.append(platform["rect"])

	for spawn_index in 2:
		var spawn: Vector2 = level["spawns"][spawn_index]
		_check(_spawn_is_supported(spawn, rects),
			"%s: P%d spawn must stand on a surface" % [label, spawn_index + 1])
		_check(not _body_overlaps(spawn, rects),
			"%s: P%d spawn must not begin inside terrain" % [label, spawn_index + 1])

	var core_spawns: Array = level.get("core_spawns", [])
	_check(core_spawns.size() >= 3, "%s: needs at least three authored Temporal Core sockets" % label)
	for core in core_spawns:
		_check(core.x >= PLAYER_HALF.x and core.x <= Levels.ARENA_W - PLAYER_HALF.x \
				and core.y >= Levels.WRAP_TOP + PLAYER_HALF.y and core.y <= Levels.ARENA_H - PLAYER_HALF.y,
			"%s: Temporal Core socket must stay inside the playable band" % label)
		_check(not _body_overlaps(core, rects),
			"%s: Temporal Core socket must not overlap terrain" % label)

	# The knife game needs volume. This catches regressions where decorating a
	# map quietly fills the central chamber with collision rectangles.
	var open_samples := 0
	var total_samples := 0
	for y in range(240, 601, 24):
		for x in range(144, 1137, 24):
			total_samples += 1
			if not _point_in_solid(Vector2(x, y), rects):
				open_samples += 1
	_check(float(open_samples) / float(total_samples) >= 0.72,
		"%s: central knife reservoir became too crowded" % label)

	if level["wrap_x"]:
		_check(_largest_side_portal(rects) >= 48,
			"%s: side wrap needs a player-height opening" % label)
	else:
		_check(_has_visible_side_architecture(rects, true)
			and _has_visible_side_architecture(rects, false),
			"%s: walled maps need visible architecture on both sides" % label)

	if level["wrap_y"]:
		_check(_vertical_portal_width(rects) >= 48,
			"%s: floor and ceiling wrap gaps must overlap" % label)

	if label == "SACRED DUEL":
		_check(_sacred_moon_bridge_rise(level["platforms"]) <= SAFE_JUMP_RISE,
			"%s: moon bridge must be safely reachable from the approach ledges" % label)


func _spawn_is_supported(spawn: Vector2, rects: Array[Rect2]) -> bool:
	var feet := spawn.y + PLAYER_HALF.y
	for rect in rects:
		if absf(rect.position.y - feet) <= 0.1 \
				and spawn.x >= rect.position.x - PLAYER_HALF.x \
				and spawn.x <= rect.end.x + PLAYER_HALF.x:
			return true
	return false


func _body_overlaps(center: Vector2, rects: Array[Rect2]) -> bool:
	for rect in rects:
		if absf(center.x - rect.get_center().x) < PLAYER_HALF.x + rect.size.x * 0.5 \
				and absf(center.y - rect.get_center().y) < PLAYER_HALF.y + rect.size.y * 0.5:
			return true
	return false


func _point_in_solid(point: Vector2, rects: Array[Rect2]) -> bool:
	for rect in rects:
		if rect.has_point(point):
			return true
	return false


func _largest_side_portal(rects: Array[Rect2]) -> int:
	var longest := 0
	var run := 0
	for y in range(int(Levels.WRAP_TOP + PLAYER_HALF.y), int(Levels.ARENA_H - 100.0 - PLAYER_HALF.y) + 1, SAMPLE_STEP):
		var left_open := not _body_overlaps(Vector2(0.0, y), rects)
		var right_open := not _body_overlaps(Vector2(Levels.ARENA_W, y), rects)
		if left_open and right_open:
			run += SAMPLE_STEP
			longest = maxi(longest, run)
		else:
			run = 0
	return longest


func _has_visible_side_architecture(rects: Array[Rect2], left: bool) -> bool:
	for rect in rects:
		if rect.position.y < Levels.ARENA_H and rect.end.y > Levels.WRAP_TOP:
			if left and is_zero_approx(rect.position.x):
				return true
			if not left and is_equal_approx(rect.end.x, Levels.ARENA_W):
				return true
	return false


func _vertical_portal_width(rects: Array[Rect2]) -> int:
	var longest := 0
	var run := 0
	for x in range(int(PLAYER_HALF.x), int(Levels.ARENA_W - PLAYER_HALF.x) + 1, SAMPLE_STEP):
		var top_open := not _body_overlaps(Vector2(x, Levels.WRAP_TOP), rects)
		var bottom_open := not _body_overlaps(Vector2(x, Levels.ARENA_H - 100.0), rects)
		if top_open and bottom_open:
			run += SAMPLE_STEP
			longest = maxi(longest, run)
		else:
			run = 0
	return longest


func _sacred_moon_bridge_rise(platforms: Array) -> float:
	var approach_y := INF
	var bridge_y := -INF
	for platform in platforms:
		var rect: Rect2 = platform["rect"]
		if is_equal_approx(rect.size.x, 170.0) and is_equal_approx(rect.size.y, 16.0):
			approach_y = minf(approach_y, rect.position.y)
		if is_equal_approx(rect.size.x, 240.0) and is_equal_approx(rect.size.y, 16.0):
			bridge_y = maxf(bridge_y, rect.position.y)
	return approach_y - bridge_y


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
