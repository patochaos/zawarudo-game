extends SceneTree

const PLAYER_HALF := Vector2(16.0, 24.0)
const SAMPLE_STEP := 8
const SAFE_JUMP_RISE := 195.0
## Moving geometry is sampled rather than assumed: an arena has to be legal in
## every configuration its movers can actually reach at the same moment, not
## just at the position it was authored in.
const POSE_STEP := 12
const MAX_POSE_TICKS := 2520
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

	_check(level["spawns"].size() >= 4, "%s: needs four supported spawn sockets" % label)
	for spawn_index in level["spawns"].size():
		var spawn: Vector2 = level["spawns"][spawn_index]
		_check(_spawn_is_supported(spawn, rects),
			"%s: P%d spawn must stand on a surface" % [label, spawn_index + 1])
		_check(not _body_overlaps(spawn, rects),
			"%s: P%d spawn must not begin inside terrain" % [label, spawn_index + 1])
	_validate_four_corner_spawns(level)
	_check(_vertical_tier_count(level["platforms"]) >= 5,
		"%s: four-player layout needs at least five useful vertical tiers" % label)

	var core_spawns: Array = level.get("core_spawns", [])
	_check(core_spawns.size() >= 3, "%s: needs at least three authored Temporal Core sockets" % label)
	for core in core_spawns:
		_check(core.x >= PLAYER_HALF.x and core.x <= Levels.ARENA_W - PLAYER_HALF.x \
				and core.y >= Levels.WRAP_TOP + PLAYER_HALF.y and core.y <= Levels.ARENA_H - PLAYER_HALF.y,
			"%s: Temporal Core socket must stay inside the playable band" % label)

	if not level["wrap_x"]:
		_check(_has_visible_side_architecture(rects, true)
			and _has_visible_side_architecture(rects, false),
			"%s: walled maps need visible architecture on both sides" % label)

	if level["wrap_y"]:
		_check(_vertical_portal_width(rects) >= 48,
			"%s: floor and ceiling wrap gaps must overlap" % label)

	for tick in _pose_ticks(level["platforms"]):
		_test_pose(level, tick)

	if label == "SHATTERED SANCTUM":
		_check(_opening_shot_is_blocked(level),
			"%s: permanent centre shrine must deny the opening shot" % label)
		_check(_has_platform_material_mix(level["platforms"]),
			"%s: needs both permanent and breakable authored platforms" % label)
		_check(_sanctum_routes_are_reachable(level["platforms"]),
			"%s: side, inner and crown tiers must stay within jump reach" % label)
		_check(_sanctum_passages_are_wide(level["platforms"]),
			"%s: authored passages need at least 55px of movement clearance" % label)
		_check(_sanctum_has_high_side_gates(level, rects),
			"%s: side seam must open high and remain blocked near the ground" % label)


## Absolute ticks worth checking. A static arena has exactly one configuration;
## a kinetic one is sampled across the full cycle of all its movers together, so
## the poses tested are ones the game can genuinely produce.
func _pose_ticks(platforms: Array) -> PackedInt32Array:
	var cycle := 1
	for platform: Dictionary in platforms:
		if not platform.has("motion"):
			continue
		cycle = _lcm(cycle, maxi(2, int(platform["motion"].get("period", Mover.DEFAULT_PERIOD))))
	var out := PackedInt32Array()
	if cycle <= 1:
		out.append(0)
		return out
	for tick in range(0, mini(cycle, MAX_POSE_TICKS), POSE_STEP):
		out.append(tick)
	return out


func _lcm(a: int, b: int) -> int:
	var x := a
	var y := b
	while y != 0:
		var t := y
		y = x % y
		x = t
	return a / maxi(x, 1) * b


## Everything that has to hold at every moment of the arena's cycle, not just in
## the configuration the level was authored in.
func _test_pose(level: Dictionary, tick: int) -> void:
	var label: String = level["name"]
	var where := "" if tick == 0 else " at tick %d" % tick
	var platforms: Array = level["platforms"]
	var rects: Array[Rect2] = []
	var moving: Array[Rect2] = []
	for platform: Dictionary in platforms:
		var rect := _posed_rect(platform, tick)
		rects.append(rect)
		if platform.has("motion"):
			moving.append(rect)

	for spawn_index in level["spawns"].size():
		_check(not _body_overlaps(level["spawns"][spawn_index], rects),
			"%s: P%d spawn must not begin inside terrain%s" % [label, spawn_index + 1, where])
	for core in level.get("core_spawns", []):
		_check(not _body_overlaps(core, rects),
			"%s: Temporal Core socket must not overlap terrain%s" % [label, where])

	# A mover that grinds through another platform is a hole in the arena, not a
	# mechanic: collision would resolve a rider into the intersection.
	for mover_rect in moving:
		for other: Dictionary in platforms:
			var other_rect := _posed_rect(other, tick)
			if other_rect == mover_rect or not other.has("motion") and _is_boundary(other_rect):
				continue
			if mover_rect.intersects(other_rect):
				_check(false, "%s: moving platform overlaps other geometry%s" % [label, where])
				return

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
		"%s: central knife reservoir became too crowded%s" % [label, where])

	if level["wrap_x"]:
		_check(_largest_side_portal(rects) >= 48,
			"%s: side wrap needs a player-height opening%s" % [label, where])


func _posed_rect(platform: Dictionary, tick: int) -> Rect2:
	var rect: Rect2 = platform["rect"]
	if not platform.has("motion"):
		return rect
	return Rect2(platform["home"] + Mover.offset(platform["motion"], tick), rect.size)


## Ground, ceiling and the invisible side walls legitimately extend past the
## arena, so a mover reaching them is not an authoring mistake to report here.
func _is_boundary(rect: Rect2) -> bool:
	return rect.position.x < 0.0 or rect.end.x > Levels.ARENA_W or rect.size.y >= 70.0


func _spawn_is_supported(spawn: Vector2, rects: Array[Rect2]) -> bool:
	var feet := spawn.y + PLAYER_HALF.y
	for rect in rects:
		if absf(rect.position.y - feet) <= 0.1 \
				and spawn.x >= rect.position.x - PLAYER_HALF.x \
				and spawn.x <= rect.end.x + PLAYER_HALF.x:
			return true
	return false


func _validate_four_corner_spawns(level: Dictionary) -> void:
	var label: String = level["name"]
	var spawns: Array = level["spawns"]
	_check(spawns[0].y >= 520.0 and spawns[1].y >= 520.0,
		"%s: P1/P2 must retain the lower corners" % label)
	_check(spawns[2].y <= 320.0 and spawns[3].y <= 320.0,
		"%s: P3/P4 must spawn in the upper corners" % label)
	_check(spawns[2].x <= 280.0 and spawns[3].x >= Levels.ARENA_W - 280.0,
		"%s: P3/P4 upper spawns must stay near opposite side walls" % label)
	_check(absf(spawns[3].x - spawns[2].x) >= 800.0,
		"%s: P3/P4 must not spawn beside one another" % label)
	for a in spawns.size():
		for b in range(a + 1, spawns.size()):
			_check(spawns[a].distance_to(spawns[b]) >= 260.0,
				"%s: P%d and P%d spawn too close together" % [label, a + 1, b + 1])
	for upper in [2, 3]:
		var support := _spawn_support(level["platforms"], spawns[upper])
		_check(not support.is_empty() and int(support.get("hp", 0)) == -1,
			"%s: P%d upper spawn needs permanent support" % [label, upper + 1])
	_check(_surface_route_exists(level["platforms"], spawns[0], spawns[2]),
		"%s: lower-left spawn needs a permanent-height route to upper-left" % label)
	_check(_surface_route_exists(level["platforms"], spawns[1], spawns[3]),
		"%s: lower-right spawn needs a permanent-height route to upper-right" % label)
	_check(_upper_opening_shot_is_blocked(level),
		"%s: P3/P4 must not receive a free horizontal opening shot" % label)


func _spawn_support(platforms: Array, spawn: Vector2) -> Dictionary:
	var feet := spawn.y + PLAYER_HALF.y
	for platform: Dictionary in platforms:
		var rect: Rect2 = platform["rect"]
		if absf(rect.position.y - feet) <= 0.1 \
				and spawn.x >= rect.position.x - PLAYER_HALF.x \
				and spawn.x <= rect.end.x + PLAYER_HALF.x:
			return platform
	return {}


func _surface_route_exists(platforms: Array, from_spawn: Vector2, to_spawn: Vector2) -> bool:
	var start: Dictionary = _spawn_support(platforms, from_spawn)
	var goal: Dictionary = _spawn_support(platforms, to_spawn)
	if start.is_empty() or goal.is_empty():
		return false
	var start_idx := platforms.find(start)
	var goal_idx := platforms.find(goal)
	var frontier: Array[int] = [start_idx]
	var visited := {start_idx: true}
	while not frontier.is_empty():
		var current: int = frontier.pop_front()
		if current == goal_idx:
			return true
		var from_rect: Rect2 = platforms[current]["rect"]
		for next in platforms.size():
			if visited.has(next):
				continue
			var to_rect: Rect2 = platforms[next]["rect"]
			var rise: float = from_rect.position.y - to_rect.position.y
			if rise < -0.1 or rise > SAFE_JUMP_RISE:
				continue
			var gap: float = maxf(0.0, maxf(
				to_rect.position.x - from_rect.end.x,
				from_rect.position.x - to_rect.end.x))
			if gap > 220.0:
				continue
			visited[next] = true
			frontier.append(next)
	return false


func _upper_opening_shot_is_blocked(level: Dictionary) -> bool:
	var a: Vector2 = level["spawns"][2] + Vector2(0.0, -6.0)
	var b: Vector2 = level["spawns"][3] + Vector2(0.0, -6.0)
	for platform: Dictionary in level["platforms"]:
		if int(platform["hp"]) != -1:
			continue
		var rect: Rect2 = platform["rect"]
		if rect.position.x > a.x and rect.end.x < b.x \
				and a.y >= rect.position.y and a.y <= rect.end.y:
			return true
	return false


func _vertical_tier_count(platforms: Array) -> int:
	var tiers := {}
	for platform: Dictionary in platforms:
		var rect: Rect2 = platform["rect"]
		if rect.size.x >= 70.0 and rect.size.y <= 20.0 \
				and rect.position.y >= 250.0 and rect.position.y <= 620.0:
			tiers[int(round(rect.position.y))] = true
	return tiers.size()


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


func _opening_shot_is_blocked(level: Dictionary) -> bool:
	var a: Vector2 = level["spawns"][0] + Vector2(0.0, -6.0)
	var b: Vector2 = level["spawns"][1] + Vector2(0.0, -6.0)
	for platform in level["platforms"]:
		if platform["hp"] != -1:
			continue
		var rect: Rect2 = platform["rect"]
		if rect.position.x > a.x and rect.end.x < b.x \
				and a.y >= rect.position.y and a.y <= rect.end.y:
			return true
	return false


func _has_platform_material_mix(platforms: Array) -> bool:
	var permanent := 0
	var breakable := 0
	for platform in platforms:
		var rect: Rect2 = platform["rect"]
		# Ignore the implicit ground and invisible boundary walls.
		if rect.size.y >= 100.0 and (rect.position.x <= 0.0 or rect.end.x >= Levels.ARENA_W):
			continue
		if platform["hp"] == -1:
			permanent += 1
		else:
			breakable += 1
	return permanent >= 5 and breakable >= 6


func _sanctum_routes_are_reachable(platforms: Array) -> bool:
	var required_heights := [470.0, 420.0, 320.0, 285.0, 270.0]
	for height in required_heights:
		var found := false
		for platform in platforms:
			var rect: Rect2 = platform["rect"]
			if is_equal_approx(rect.position.y, height):
				found = true
				break
		if not found:
			return false
	for i in range(required_heights.size() - 1):
		if required_heights[i] - required_heights[i + 1] > SAFE_JUMP_RISE:
			return false
	return true


func _sanctum_passages_are_wide(platforms: Array) -> bool:
	var left_gallery := _platform_rect_at(platforms, 0.0, 470.0)
	var left_inner := _platform_rect_at(platforms, 290.0, 420.0)
	var left_satellite := _platform_rect_at(platforms, 290.0, 270.0)
	var crown := _platform_rect_at(platforms, 535.0, 285.0)
	var left_shoulder := _platform_rect_at(platforms, 475.0, 500.0)
	var shrine := _platform_rect_at(platforms, 610.0, 390.0)
	if left_gallery.size == Vector2.ZERO or left_inner.size == Vector2.ZERO \
			or left_satellite.size == Vector2.ZERO or crown.size == Vector2.ZERO \
			or left_shoulder.size == Vector2.ZERO or shrine.size == Vector2.ZERO:
		return false
	return left_inner.position.x - left_gallery.end.x >= 55.0 \
		and crown.position.x - left_satellite.end.x >= 55.0 \
		and shrine.position.x - left_shoulder.end.x >= 55.0


func _platform_rect_at(platforms: Array, x: float, y: float) -> Rect2:
	for platform in platforms:
		var rect: Rect2 = platform["rect"]
		if is_equal_approx(rect.position.x, x) and is_equal_approx(rect.position.y, y):
			return rect
	return Rect2()


func _sanctum_has_high_side_gates(level: Dictionary, rects: Array[Rect2]) -> bool:
	if not level["wrap_x"]:
		return false
	var high_y := 296.0
	var low_y := 560.0
	var high_open := not _body_overlaps(Vector2(0.0, high_y), rects) \
		and not _body_overlaps(Vector2(Levels.ARENA_W, high_y), rects)
	var low_blocked := _body_overlaps(Vector2(0.0, low_y), rects) \
		and _body_overlaps(Vector2(Levels.ARENA_W, low_y), rects)
	return high_open and low_blocked


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
