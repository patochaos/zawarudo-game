extends SceneTree

const PLAYER_HALF := Vector2(16.0, 24.0)
const SAMPLE_STEP := 8
## Moving geometry is sampled rather than assumed: an arena has to be legal in
## every configuration its movers can actually reach at the same moment, not
## just at the position it was authored in.
const POSE_STEP := 12
const MAX_POSE_TICKS := 2520
var _failures: int = 0


func _init() -> void:
	_check(is_zero_approx(Levels.WRAP_TOP),
		"Vertical wrapping must happen at the actual top edge of the screen")
	for index in Levels.count():
		_test_level(index)
	_test_level_progression()
	if _failures == 0:
		print("Level layouts: all tests passed")
	else:
		push_error("Level layouts: %d test(s) failed" % _failures)
	quit(_failures)


func _test_level(index: int) -> void:
	_test_player_scaling(index)
	var level := Levels.build(index, 4)
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
	_validate_spawn_set(level)
	var respawns: Array = level.get("respawn_points", [])
	_check(respawns.size() >= 7, "%s: needs a varied authored respawn pool" % label)
	for respawn: Vector2 in respawns:
		_check(_spawn_is_supported(respawn, rects),
			"%s: respawn socket %s needs support" % [label, respawn])
		_check(not _body_overlaps(respawn, rects),
			"%s: respawn socket %s overlaps terrain" % [label, respawn])
		var support := _spawn_support(level["platforms"], respawn)
		_check(not support.is_empty() and int(support["hp"]) < 0 and not support.has("motion"),
			"%s: respawn socket %s must use permanent stationary support" % [label, respawn])
	_check(_vertical_tier_count(level["platforms"]) >= 3,
		"%s: four-player layout needs at least three useful vertical tiers" % label)

	var core_spawns: Array = level.get("core_spawns", [])
	_check(core_spawns.size() >= 3, "%s: needs at least three authored Temporal Core sockets" % label)
	for core in core_spawns:
		_check(core.x >= PLAYER_HALF.x and core.x <= Levels.ARENA_W - PLAYER_HALF.x \
				and core.y >= Levels.STAGE_TOP + PLAYER_HALF.y \
				and core.y <= Levels.ARENA_H - PLAYER_HALF.y,
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
		_check(_has_platform_material_mix(level["platforms"]),
			"%s: needs both permanent and breakable authored platforms" % label)


## The sequence should add new topology, not repeat one symmetric scaffold with
## a different prop in the middle. These are identity contracts, not coordinates.
func _test_level_progression() -> void:
	var intro := Levels.build(0, 2)
	var descent := Levels.build(1, 2)
	var pendulum := Levels.build(2, 2)
	var pulse := Levels.build(3, 2)
	var sanctum := Levels.build(4, 2)
	var foundry := Levels.build(5, 2)
	var finale := Levels.build(6, 2)
	_check(not intro["wrap_x"] and not intro["wrap_y"]
		and _mover_count(intro["platforms"]) == 0 and intro["hazards"].is_empty(),
		"Level 1 must remain the quiet, walled introduction")
	_check(descent["wrap_x"] and descent["wrap_y"],
		"Level 2 must retain its four-way wrap identity")
	_check(not pendulum["wrap_x"] and pendulum["wrap_y"]
		and _mover_count(pendulum["platforms"]) == 1,
		"Level 3 must be a vertical-only loop around one lift")
	_check(pulse["wrap_x"] and not pulse["wrap_y"] and pulse["hazards"].size() >= 2,
		"Level 4 must be a horizontal slingshot built around paired hazards")
	_check(sanctum["wrap_x"] and sanctum["wrap_y"]
		and _breakable_count(sanctum["platforms"]) >= 5,
		"Level 5 must be a destructible four-way-wrap arena")
	_check(foundry["wrap_x"] and not foundry["wrap_y"]
		and _has_tall_mover(foundry["platforms"]),
		"Level 6 must be divided by a roaming wall")
	_check(finale["wrap_x"] and finale["wrap_y"]
		and _mover_count(finale["platforms"]) >= 2 and not finale["hazards"].is_empty(),
		"Level 7 must combine four-way wrap, ferries and a pulse launcher")


## Every extra simultaneous plan gets extra landing space. The variants remain
## authored subsets of one arena rather than separate maps, so movement rules,
## wrap and defining feature cannot drift between player counts.
func _test_player_scaling(index: int) -> void:
	var duel := Levels.build(index, 2)
	var trio := Levels.build(index, 3)
	var crowd := Levels.build(index, 4)
	var label: String = crowd["name"]
	_check(duel["platforms"].size() < trio["platforms"].size(),
		"%s: 3P needs more platforms than 2P" % label)
	_check(trio["platforms"].size() < crowd["platforms"].size(),
		"%s: 4P needs more platforms than 3P" % label)
	_check(duel.get("feature", "") == trio.get("feature", "") \
			and trio.get("feature", "") == crowd.get("feature", ""),
		"%s: player scaling must preserve the arena's defining feature" % label)
	for variant in [duel, trio, crowd]:
		var rects: Array[Rect2] = []
		for platform: Dictionary in variant["platforms"]:
			rects.append(platform["rect"])
		for spawn_index in int(variant["player_count"]):
			var spawn: Vector2 = variant["spawns"][spawn_index]
			_check(_spawn_is_supported(spawn, rects),
				"%s %dP: active spawn P%d needs support" % [label, variant["player_count"], spawn_index + 1])
			_check(not _body_overlaps(spawn, rects),
				"%s %dP: active spawn P%d overlaps terrain" % [label, variant["player_count"], spawn_index + 1])


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


func _validate_spawn_set(level: Dictionary) -> void:
	var label: String = level["name"]
	var spawns: Array = level["spawns"]
	var min_y := INF
	var max_y := -INF
	var supports := {}
	for spawn: Vector2 in spawns:
		min_y = minf(min_y, spawn.y)
		max_y = maxf(max_y, spawn.y)
		var support := _spawn_support(level["platforms"], spawn)
		_check(not support.is_empty() and int(support.get("hp", 0)) == -1
			and not support.has("motion"),
			"%s: every opening spawn needs permanent stationary support" % label)
		if not support.is_empty():
			supports[level["platforms"].find(support)] = true
	_check(max_y - min_y >= 180.0,
		"%s: opening spawns need meaningfully different elevations" % label)
	_check(supports.size() >= 3,
		"%s: four fighters need at least three distinct opening surfaces" % label)
	for a in spawns.size():
		for b in range(a + 1, spawns.size()):
			_check(_spawn_distance(level, spawns[a], spawns[b]) >= 190.0,
				"%s: P%d and P%d spawn too close together" % [label, a + 1, b + 1])


func _spawn_distance(level: Dictionary, a: Vector2, b: Vector2) -> float:
	var delta := b - a
	if level["wrap_x"] and absf(delta.x) > Levels.ARENA_W * 0.5:
		delta.x -= signf(delta.x) * Levels.ARENA_W
	if level["wrap_y"] and absf(delta.y) > Levels.ARENA_H * 0.5:
		delta.y -= signf(delta.y) * Levels.ARENA_H
	return delta.length()


func _spawn_support(platforms: Array, spawn: Vector2) -> Dictionary:
	var feet := spawn.y + PLAYER_HALF.y
	for platform: Dictionary in platforms:
		var rect: Rect2 = platform["rect"]
		if absf(rect.position.y - feet) <= 0.1 \
				and spawn.x >= rect.position.x - PLAYER_HALF.x \
				and spawn.x <= rect.end.x + PLAYER_HALF.x:
			return platform
	return {}


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
	for y in range(int(Levels.STAGE_TOP + PLAYER_HALF.y),
			int(Levels.ARENA_H - 100.0 - PLAYER_HALF.y) + 1, SAMPLE_STEP):
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
		if rect.position.y < Levels.ARENA_H and rect.end.y > Levels.STAGE_TOP:
			if left and is_zero_approx(rect.position.x):
				return true
			if not left and is_equal_approx(rect.end.x, Levels.ARENA_W):
				return true
	return false


func _vertical_portal_width(rects: Array[Rect2]) -> int:
	var longest := 0
	var run := 0
	for x in range(int(PLAYER_HALF.x), int(Levels.ARENA_W - PLAYER_HALF.x) + 1, SAMPLE_STEP):
		var top_open := not _body_overlaps(Vector2(x, Levels.STAGE_TOP), rects)
		var bottom_open := not _body_overlaps(Vector2(x, Levels.ARENA_H - 100.0), rects)
		if top_open and bottom_open:
			run += SAMPLE_STEP
			longest = maxi(longest, run)
		else:
			run = 0
	return longest


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


func _mover_count(platforms: Array) -> int:
	var count := 0
	for platform: Dictionary in platforms:
		if platform.has("motion"):
			count += 1
	return count


func _breakable_count(platforms: Array) -> int:
	var count := 0
	for platform: Dictionary in platforms:
		if int(platform["hp"]) > 0:
			count += 1
	return count


func _has_tall_mover(platforms: Array) -> bool:
	for platform: Dictionary in platforms:
		var rect: Rect2 = platform["rect"]
		if platform.has("motion") and rect.size.y >= 200.0:
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
