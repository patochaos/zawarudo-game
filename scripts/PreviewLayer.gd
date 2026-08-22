extends Node2D

## Draws every planning-phase visualization: player ghosts + motion arcs, the
## always-on potential-shot trajectory, and the frozen state / future path of
## existing knives. Hidden entirely during EXECUTION.

var gm
var high_contrast: bool = false
var _arrow_prediction_tick: int = -1
var _arrow_prediction_cache: Dictionary = {}


func _draw() -> void:
	if gm == null:
		return
	# Free play is continuous, so there is no ghost and nothing is frozen — just
	# the knife fan, so you can still see where you are pointing and how hard.
	if gm.state == Phase.FREEPLAY:
		var me: Player = gm.players[0]
		if me.alive:
			_draw_shot_preview(me, me.position)
		return

	if gm.state == Phase.EXECUTING or gm.state == Phase.REPLAY \
			or gm.state == Phase.GAME_OVER or gm.state == Phase.MENU:
		return

	# Where the moving world will be when this window closes is public and
	# knowable, so it is drawn rather than left as a memory test.
	_draw_kinetics()
	# Knives already in the air are public information — they were fired in the
	# open. Only the pending plan is secret.
	_draw_existing_arrows()
	for p in gm.players:
		if p.alive and not gm.hides_plan(p.index):
			_draw_player_preview(p)
	# Readiness is public even when the plan behind it is not — knowing the
	# opponent is done is what lets a short turn feel like a race rather than a
	# wait. Drawn in world space, over the fighter, so it survives a camera that
	# has pushed in past the HUD.
	for p in gm.players:
		if p.alive and p.plan.confirmed:
			_draw_ready_badge(p)


# ---------------------------------------------------------------- players ----

func _draw_player_preview(p: Player) -> void:
	var col: Color = _player_preview_color(p)
	var i: int = p.index
	var path: PackedVector2Array = gm.ghost_path[i]
	if path.size() < 2:
		return
	var recorded: int = p.plan.recorded_ticks()

	# The piloted stretch is solid; the coasted tail after the stamina runs out
	# is dotted, because the player is no longer steering it.
	var driven := PackedVector2Array()
	for t in range(0, mini(recorded, path.size() - 1) + 1):
		driven.append(path[t])
	if driven.size() > 1:
		_solid_runs(driven, Color(col.r, col.g, col.b, 0.8), 2.5)
	if path.size() - 1 > recorded:
		var coasted := PackedVector2Array()
		for t in range(recorded, path.size()):
			coasted.append(path[t])
		_dotted_runs(coasted, Color(col.r, col.g, col.b, 0.5), 2.0, 6.0, 5.0)

	# where the stamina ran out
	if recorded > 0 and recorded < path.size():
		draw_circle(path[recorded], 3.5, Color(col.r, col.g, col.b, 0.9))

	# Ghosts use the same stick-figure pose as the live body. This keeps the
	# planning view expressive without hiding the exact collision-sized path.
	var end_pos: Vector2 = path[path.size() - 1]
	var here: Vector2 = gm.shot_origin(i)
	var same_marker: bool = here.distance_to(end_pos) <= 2.0
	_draw_destination(end_pos, p)
	_draw_ghost_figure(end_pos, p, 0.85)

	# live ghost head, i.e. the point the player is currently piloting
	if not same_marker:
		_draw_ghost_figure(here, p, 0.45)

	_draw_stamina(p, here)
	_draw_shot_preview(p, here)


func _draw_ready_badge(p: Player) -> void:
	# Clears the stack already above a fighter: the "P1" tag, then the stamina bar.
	var at: Vector2 = p.position + Vector2(0.0, -Player.HALF.y - 54.0)
	var col := Color(0.42, 1.0, 0.62)
	var half := Vector2(31.0, 10.0)
	draw_rect(Rect2(at - half, half * 2.0), Color(0.04, 0.10, 0.07, 0.86))
	draw_rect(Rect2(at - half, half * 2.0), col, false, 1.6)
	_label(at + Vector2(-24.0, 5.0), "READY", col, 13)
	# A tick mark either side keeps it legible at a glance without reading a word.
	for side in [-1.0, 1.0]:
		var tip: Vector2 = at + Vector2(side * (half.x + 7.0), 0.0)
		draw_line(tip - Vector2(side * 5.0, 4.0), tip, col, 1.8)
		draw_line(tip - Vector2(side * 5.0, -4.0), tip, col, 1.8)


## The final position is the most important promise made by the plan. A small
## ground target reads more clearly than another box around the ghost body.
func _draw_destination(at: Vector2, p: Player) -> void:
	var foot := at + Vector2(0.0, Player.HALF.y + 7.0)
	var base := _player_preview_color(p)
	var c := Color(base.r, base.g, base.b, 0.95)
	if high_contrast:
		var ink := Color(0.015, 0.02, 0.035, 0.96)
		draw_arc(foot, 10.0, 0.0, TAU, 20, ink, 5.2)
		draw_circle(foot, 4.5, ink)
		draw_line(foot - Vector2(17.0, 0.0), foot - Vector2(7.0, 0.0), ink, 4.5)
		draw_line(foot + Vector2(7.0, 0.0), foot + Vector2(17.0, 0.0), ink, 4.5)
	draw_arc(foot, 10.0, 0.0, TAU, 20, c, 2.2)
	draw_circle(foot, 2.5, c)
	draw_line(foot - Vector2(16.0, 0.0), foot - Vector2(8.0, 0.0), c, 1.5)
	draw_line(foot + Vector2(8.0, 0.0), foot + Vector2(16.0, 0.0), c, 1.5)
	_label(foot + Vector2(14.0, -8.0), "END", c, 11)


func _draw_ghost_figure(at: Vector2, p: Player, alpha: float) -> void:
	var pose := Player.idle_pose_points(p.facing, p.aim_dir())
	var base := _player_preview_color(p)
	var c := Color(base.r, base.g, base.b, minf(1.0, alpha + (0.1 if high_contrast else 0.0)))
	var faint := Color(base.r, base.g, base.b, alpha * (0.24 if high_contrast else 0.16))
	var segments := [
		[pose["hip"], pose["chest"]], [pose["chest"], pose["neck"]],
		[pose["hip"], pose["knee_a"]], [pose["knee_a"], pose["foot_a"]],
		[pose["hip"], pose["knee_b"]], [pose["knee_b"], pose["foot_b"]],
		[pose["free_shoulder"], pose["free_elbow"]],
		[pose["free_elbow"], pose["free_hand"]],
		[pose["shoulder"], pose["aim_elbow"]], [pose["aim_elbow"], pose["grip"]],
	]
	for segment in segments:
		if high_contrast:
			draw_line(at + segment[0], at + segment[1], Color(0.015, 0.02, 0.035, alpha), 5.2, true)
		draw_line(at + segment[0], at + segment[1], c, 2.2, true)
	if high_contrast:
		draw_circle(at + pose["head"], 9.0, Color(0.015, 0.02, 0.035, alpha))
	draw_circle(at + pose["head"], 7.0, faint)
	draw_arc(at + pose["head"], 6.0, 0.0, TAU, 16, c, 2.0, true)
	for joint in [pose["hip"], pose["knee_a"], pose["knee_b"], pose["grip"]]:
		draw_circle(at + joint, 2.0, c)


## One shot per turn. While the shot is still yours to place, the reticle tracks
## the aim and the arc updates live. The moment it is fired the reticle vanishes
## and only the committed path remains — rollback brings the reticle back.
##
## `origin` is the point on the piloted path the bow releases from: the ghost's
## live head while you are still placing the shot, or the pinned tick once you
## have fired. Angle and power lock on release; only the origin can still move,
## and only by re-piloting.
## Shows the fan: which way it points and how hard it is drawn. The Duelist's
## compact reticle follows the opening section of the real ballistic arc, but
## stops well before a landing prediction so aiming does not become solved.
##
## Power is encoded in the aim line itself: it lengthens, thickens and brightens
## as the draw builds, with notches every 25%.
const AIM_LEN_MIN := 34.0
const AIM_LEN_MAX := 132.0


func _draw_shot_preview(p: Player, origin: Vector2) -> void:
	var col: Color = _player_preview_color(p)
	var armed: bool = p.plan.has_shot()
	var charging: bool = gm.charging[p.index]
	var live: bool = armed or charging
	var shoulder: Vector2 = Player.shoulder_at(origin)
	var power: float = clampf(p.plan.power, 0.0, 1.0)
	if gm.uses_dashblade(p.index):
		_draw_dash_preview(p, origin, col, armed, charging)
		return
	if gm.uses_shock(p.index):
		_draw_shock_preview(p, origin, col, armed, charging)
		return
	var chakram_preview: bool = gm.uses_chakram(p.index)
	var chakram_super: bool = chakram_preview and (p.plan.super_shot or (not armed \
		and gm.super_meter[p.index] >= 1.0 and gm.super_armed[p.index]))
	var launches: Array[Vector2] = []
	if chakram_preview:
		launches = gm.chakram_launch_velocities(p.aim_dir(), power, chakram_super)
	else:
		launches = gm.knife_launch_velocities(p.aim_dir(), power)
	# The chosen aim remains the reticle spine even when a weapon branches around
	# it. For the Duelist this sits naturally between the two real dagger arcs.
	var dir: Vector2 = p.aim_dir().normalized()

	var length: float = lerpf(AIM_LEN_MIN, AIM_LEN_MAX, power)
	var tip: Vector2 = shoulder + dir * length
	var body: Color = col.lightened(0.35) if live else Color(col.r, col.g, col.b, 0.5)
	if not chakram_preview:
		var dagger_reticle := _draw_dagger_trajectory_reticle(
			shoulder, launches, gm.knife_launch_velocity(p.aim_dir(), power),
			length, power, body, col, live)
		tip = dagger_reticle["tip"]
		dir = dagger_reticle["tangent"]
	else:
		var shot_dirs: Array[Vector2] = []
		for launch in launches:
			shot_dirs.append(launch.normalized())
		if shot_dirs.size() >= 2:
			var left: Vector2 = shot_dirs[0]
			var right: Vector2 = shot_dirs[shot_dirs.size() - 1]
			draw_colored_polygon(PackedVector2Array([
				shoulder, shoulder + left * length, shoulder + right * length,
			]), Color(col.r, col.g, col.b, 0.045 if live else 0.025))
		for shot_dir in shot_dirs:
			var shot_tip: Vector2 = shoulder + shot_dir * length
			draw_line(shoulder, shoulder + shot_dir * AIM_LEN_MAX,
				Color(col.r, col.g, col.b, 0.12), 1.5)
			draw_line(shoulder, shot_tip, body, 3.0 if live else 2.0)
			_draw_chakram_head(shot_tip, shot_dir, body)

		# The centre spine carries the power notches; the fan carries direction.
		draw_line(shoulder, tip, Color(body.r, body.g, body.b, body.a * 0.45), 1.0)
		var perp: Vector2 = dir.orthogonal()
		for q in range(1, 5):
			var at: Vector2 = shoulder + dir * (AIM_LEN_MAX * float(q) * 0.25)
			var lit: bool = power >= float(q) * 0.25 - 0.001
			draw_line(at - perp * 5.0, at + perp * 5.0,
				Color(col.r, col.g, col.b, 0.85 if lit else 0.18), 2.0)

	var shot_tick: int = p.plan.shot_tick if armed else p.plan.recorded_ticks()
	var shot_time: float = float(maxi(shot_tick, 0)) / float(Engine.physics_ticks_per_second)
	_launch_marker(shoulder, col, 1.0 if live else 0.55,
		"FIRE %.2fs" % shot_time if live else "")

	var aimed: Vector2 = p.aim_dir().normalized()
	var actual_elevation: float = rad_to_deg(atan2(-aimed.y, absf(aimed.x)))
	var tag := "%d° · %d%%" % [int(round(actual_elevation)), int(round(power * 100.0))]
	if chakram_preview:
		tag = ("TRIPLE CHAKRAM · " if chakram_super else \
			"CHAKRAM · DIRECT · ") + tag
	if armed:
		tag = ("SUPER · " if p.plan.super_shot else "ARMED · ") + tag
	elif charging:
		if gm.super_meter[p.index] >= 1.0:
			tag = ("SUPER ARMED · " if gm.super_armed[p.index] else "SUPER STANDBY · ") + tag
		else:
			tag = "DRAWING · " + tag
	_shot_tag(p, tip, dir, tag, col.lightened(0.4) if live else Color(col.r, col.g, col.b, 0.65),
		14 if live else 12)
	_draw_power_bar(origin, p, charging)


## Curves the Duelist's compact fan reticle through the same per-tick drag and
## gravity integration as a live dagger. Arc length still encodes charge, so a
## weak throw droops inside a short rail while a full draw reaches farther and
## reads flatter. Terrain is intentionally omitted: this is an aiming aid, not
## a complete impact or ricochet solution.
func _draw_dagger_trajectory_reticle(shoulder: Vector2, launches: Array[Vector2],
		spine_launch: Vector2, length: float, power: float, body: Color,
		col: Color, live: bool) -> Dictionary:
	var full_paths: Array[PackedVector2Array] = []
	var active_paths: Array[PackedVector2Array] = []
	for launch in launches:
		var full_path := _dagger_reticle_path(shoulder, launch, AIM_LEN_MAX)
		full_paths.append(full_path)
		active_paths.append(_polyline_prefix(full_path, length))

	if active_paths.size() >= 2:
		var fill := PackedVector2Array()
		for point in active_paths[0]:
			fill.append(point)
		var last: PackedVector2Array = active_paths[active_paths.size() - 1]
		for i in range(last.size() - 1, -1, -1):
			fill.append(last[i])
		if fill.size() >= 3:
			draw_colored_polygon(fill,
				Color(col.r, col.g, col.b, 0.045 if live else 0.025))

	for i in full_paths.size():
		var full_path: PackedVector2Array = full_paths[i]
		var active_path: PackedVector2Array = active_paths[i]
		if full_path.size() >= 2:
			draw_polyline(full_path, Color(col.r, col.g, col.b, 0.12), 1.5, true)
		if active_path.size() >= 2:
			draw_polyline(active_path, body, 3.0 if live else 2.0, true)
			var dagger_tip := active_path[active_path.size() - 1]
			var dagger_dir := (dagger_tip - active_path[active_path.size() - 2]).normalized()
			_draw_knife_head(dagger_tip, dagger_dir, body)

	var spine_path := _dagger_reticle_path(shoulder, spine_launch, AIM_LEN_MAX)
	for q in range(1, 5):
		var sample := _polyline_point_and_tangent(
			spine_path, AIM_LEN_MAX * float(q) * 0.25)
		var at: Vector2 = sample[0]
		var perp: Vector2 = Vector2(sample[1]).orthogonal()
		var lit: bool = power >= float(q) * 0.25 - 0.001
		draw_line(at - perp * 5.0, at + perp * 5.0,
			Color(col.r, col.g, col.b, 0.85 if lit else 0.18), 2.0)

	var active_spine := _polyline_prefix(spine_path, length)
	var tip: Vector2 = active_spine[active_spine.size() - 1]
	var tangent: Vector2 = (tip - active_spine[active_spine.size() - 2]).normalized()
	return {"tip": tip, "tangent": tangent}


func _dagger_reticle_path(start: Vector2, launch: Vector2,
		target_length: float) -> PackedVector2Array:
	var path := PackedVector2Array([start])
	var pos := start
	var vel := launch
	var travelled := 0.0
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	for tick in 180:
		var st := Arrow.step_state(pos, vel, dt, gm)
		var raw: Vector2 = st[2]
		var segment := raw - pos
		var segment_length := segment.length()
		var remaining := target_length - travelled
		if segment_length >= remaining and segment_length > 0.0:
			path.append(pos + segment * (remaining / segment_length))
			break
		path.append(raw)
		travelled += segment_length
		pos = raw
		vel = st[1]
		if travelled >= target_length:
			break
	return path


func _polyline_prefix(path: PackedVector2Array, target_length: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if path.is_empty():
		return out
	out.append(path[0])
	var travelled := 0.0
	for i in range(1, path.size()):
		var segment := path[i] - path[i - 1]
		var segment_length := segment.length()
		if travelled + segment_length >= target_length and segment_length > 0.0:
			out.append(path[i - 1] + segment \
				* ((target_length - travelled) / segment_length))
			return out
		out.append(path[i])
		travelled += segment_length
	return out


func _polyline_point_and_tangent(path: PackedVector2Array, target_length: float) -> Array:
	if path.size() < 2:
		return [path[0] if not path.is_empty() else Vector2.ZERO, Vector2.RIGHT]
	var travelled := 0.0
	for i in range(1, path.size()):
		var segment := path[i] - path[i - 1]
		var segment_length := segment.length()
		if travelled + segment_length >= target_length and segment_length > 0.0:
			return [path[i - 1] + segment \
				* ((target_length - travelled) / segment_length), segment.normalized()]
		travelled += segment_length
	var tangent := (path[path.size() - 1] - path[path.size() - 2]).normalized()
	return [path[path.size() - 1], tangent]


func _draw_shock_preview(p: Player, origin: Vector2, base: Color,
		armed: bool, charging: bool) -> void:
	var shoulder := Player.shoulder_at(origin)
	var dir := p.aim_dir().normalized()
	var power := clampf(p.plan.power, 0.0, 1.0)
	var live := armed or charging
	var mode := p.plan.attack_mode
	var weapon_col := Color(1.0, 0.28, 0.88) if mode == 1 else Color(0.28, 0.96, 1.0)
	var body := weapon_col if live else Color(weapon_col.r, weapon_col.g, weapon_col.b, 0.55)
	var length := lerpf(54.0, 145.0, power) if mode == 0 else lerpf(80.0, 220.0, power)
	var tip := shoulder + dir * length
	if mode == 0:
		# A single rail and lightning diamond: unmistakably the fast straight shot.
		draw_line(shoulder, shoulder + dir * AIM_LEN_MAX, Color(body.r, body.g, body.b, 0.16), 2.0)
		draw_line(shoulder, tip, body, 4.0 if live else 2.5)
		var side := dir.orthogonal()
		draw_colored_polygon(PackedVector2Array([
			tip + dir * 12.0, tip + side * 7.0, tip - dir * 7.0,
			tip - side * 7.0,
		]), Color(body.r, body.g, body.b, 0.92))
		draw_line(tip - dir * 5.0 + side * 8.0, tip + dir * 7.0 - side * 8.0,
			Color(0.96, 1.0, 1.0, body.a), 2.0)
	else:
		# A short rising curve communicates "lob" without solving its final landing.
		var curve := PackedVector2Array()
		for step in 17:
			var t := float(step) / 16.0
			curve.append(shoulder + dir * length * t + Vector2(0.0, 42.0 * t * t))
		draw_polyline(curve, Color(body.r, body.g, body.b, body.a * 0.75), 3.0, true)
		tip = curve[curve.size() - 1]
		draw_circle(tip, 11.0, Color(body.r, body.g, body.b, 0.18))
		draw_arc(tip, 9.0, 0.0, TAU, 24, body, 3.0)
		draw_circle(tip, 3.5, Color(1.0, 0.78, 0.96, body.a))
		for spoke in 4:
			var a := TAU * float(spoke) / 4.0
			draw_line(tip + Vector2.from_angle(a) * 11.0,
				tip + Vector2.from_angle(a) * 16.0, body, 1.5)

	var shot_tick: int = p.plan.shot_tick if armed else p.plan.recorded_ticks()
	var shot_time := float(maxi(shot_tick, 0)) / float(Engine.physics_ticks_per_second)
	_launch_marker(shoulder, base, 1.0 if live else 0.55,
		"FIRE %.2fs" % shot_time if live else "")
	var tag := ("ORB FIELD · %d LIVE · RMB" % gm.shock_orb_count(p.index) \
		if mode == 1 else "PLASMA · LMB") \
		+ " · %d%%" % int(round(power * 100.0))
	if armed:
		tag = ("SUPER COMBO · " if p.plan.super_shot else "ARMED · ") + tag
	elif charging:
		tag = "CHARGING · " + tag
	_shot_tag(p, tip, dir, tag, body.lightened(0.25), 14 if live else 12)
	_draw_power_bar(origin, p, charging)


func _draw_dash_preview(p: Player, origin: Vector2, base: Color,
		armed: bool, charging: bool) -> void:
	var dir := p.aim_dir().normalized()
	var power := clampf(p.plan.power, 0.0, 1.0)
	var empowered: bool = p.plan.super_shot or (not armed \
		and gm.super_meter[p.index] >= 1.0 and gm.super_armed[p.index])
	var shot_tick: int = p.plan.shot_tick if armed else p.plan.recorded_ticks()
	var lost_frames: int = gm.frame_debt_max_cells if empowered \
		else gm.projected_frame_debt(p.index, shot_tick)
	var params: Dictionary = gm.dash_parameters(power, empowered, lost_frames)
	var path: PackedVector2Array = gm.dash_preview_path(
		origin, dir, power, empowered, lost_frames)
	var end: Vector2 = path[path.size() - 1]
	var live := armed or charging
	var aura := Color(0.22, 0.93, 1.0, 0.16 if live else 0.08)
	if path.size() > 1:
		draw_polyline(path, aura, 24.0, true)
		draw_polyline(path, Color(base.r, base.g, base.b, 0.9 if live else 0.48), 3.0, true)
		# Storyboard cells replace ordinary speed dots: the route reads as a
		# sequence of authored cuts which will collapse during execution.
		for i in range(2, path.size(), 3):
			var tangent := (path[i] - path[maxi(0, i - 1)]).normalized()
			if tangent.is_zero_approx():
				tangent = dir
			var side := tangent.orthogonal()
			var panel := PackedVector2Array([
				path[i] - tangent * 7.0 - side * 12.0,
				path[i] + tangent * 7.0 - side * 12.0,
				path[i] + tangent * 7.0 + side * 12.0,
				path[i] - tangent * 7.0 + side * 12.0,
			])
			draw_polyline(panel + PackedVector2Array([panel[0]]),
				Color(0.76, 1.0, 1.0, 0.62 if live else 0.34), 1.5, true)

	# The extra body is the promised post-dash position—not a projectile head.
	_draw_destination(end, p)
	_draw_ghost_figure(end, p, 1.0 if live else 0.66)
	draw_circle(end, 35.0, Color(0.18, 0.92, 1.0, 0.10 if live else 0.05))
	var shield_center := end + dir * 24.0
	draw_arc(shield_center, 29.0, dir.angle() - 1.05, dir.angle() + 1.05, 22,
		Color(0.84, 1.0, 1.0, 0.96 if live else 0.62), 5.0)
	draw_arc(shield_center, 23.0, dir.angle() - 0.95, dir.angle() + 0.95, 18,
		Color(base.r, base.g, base.b, 0.42), 2.0)
	for offset in [-16.0, 0.0, 16.0]:
		draw_line(end - dir * 12.0 + dir.orthogonal() * offset,
			end - dir * 34.0 + dir.orthogonal() * offset,
			Color(0.30, 0.92, 1.0, 0.35), 2.0)

	var shoulder := Player.shoulder_at(origin)
	_launch_marker(shoulder, base, 1.0 if live else 0.55, "DASH RELEASE" if live else "")
	var tag := "CUT TO END · %d/%d LOST FRAMES · GUARD %d · %d%%" % [
		lost_frames, gm.frame_debt_max_cells, int(params["durability"]),
		int(round(power * 100.0))]
	if armed:
		tag = ("SUPER · " if p.plan.super_shot else "ARMED · ") + tag
	elif charging and power >= 0.995:
		tag = "FULL · RELEASE TO COMMIT · " + tag
	elif charging:
		tag = "CHARGING · " + tag
	_shot_tag(p, end, dir, tag, Color(0.76, 1.0, 1.0, 0.96), 14 if live else 12)
	_draw_power_bar(origin, p, charging)


func _draw_knife_head(tip: Vector2, dir: Vector2, col: Color) -> void:
	var side := dir.orthogonal()
	draw_colored_polygon(PackedVector2Array([
		tip + dir * 11.0, tip - dir * 3.0 + side * 3.6,
		tip - dir * 6.0, tip - dir * 3.0 - side * 3.6,
	]), col)
	draw_line(tip - dir * 7.0 - side * 5.0, tip - dir * 7.0 + side * 5.0, col, 1.5)


func _draw_chakram_head(tip: Vector2, dir: Vector2, col: Color) -> void:
	var side := dir.orthogonal()
	draw_circle(tip, 8.0, Color(0.02, 0.015, 0.035, col.a * 0.9))
	draw_arc(tip, 7.0, 0.0, TAU, 20, col, 2.4, true)
	draw_arc(tip, 3.5, 0.0, TAU, 16, Color(col.r, col.g, col.b, col.a * 0.65), 1.4, true)
	draw_line(tip - side * 8.0, tip + side * 8.0, Color(col.r, col.g, col.b, col.a * 0.32), 1.0)


func _launch_marker(at: Vector2, col: Color, alpha: float, caption: String) -> void:
	var c := Color(col.r, col.g, col.b, alpha)
	draw_circle(at, 4.0, c)
	draw_arc(at, 7.0, 0.0, TAU, 14, Color(c.r, c.g, c.b, alpha * 0.55), 1.2)
	if not caption.is_empty():
		_label(at + Vector2(10.0, 17.0), caption, c, 11)


## Places the readout so it never runs back across the player's body.
func _shot_tag(p: Player, muzzle: Vector2, launch_dir: Vector2, text: String,
		col: Color, size: int) -> void:
	var at: Vector2 = muzzle + launch_dir * 16.0 + Vector2(0.0, -10.0)
	at.y += -16.0 if (p.index & 1) == 0 else 12.0
	if launch_dir.x > 0.0:
		at.x += 8.0
	else:
		at.x -= ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 8.0
	_label(at, text, col, size)


func _draw_power_bar(origin: Vector2, p: Player, charging: bool) -> void:
	var w := 54.0
	var h := 6.0
	var at: Vector2 = origin + Vector2(-w * 0.5, -Player.HALF.y - 22.0)
	var bg := Color(0.10, 0.11, 0.14, 0.85 if charging else 0.5)
	draw_rect(Rect2(at, Vector2(w, h)), bg)
	var base := _player_preview_color(p)
	var fill: Color = Color(1.0, 0.85, 0.3) if charging else Color(base.r, base.g, base.b, 0.7)
	draw_rect(Rect2(at, Vector2(w * clampf(p.plan.power, 0.0, 1.0), h)), fill)
	draw_rect(Rect2(at, Vector2(w, h)), Color(1, 1, 1, 0.35 if charging else 0.18), false, 1.0)


## Movement budget left, drawn on the ghost head so the player watches it drain
## where they are looking.
func _draw_stamina(p: Player, at_pos: Vector2) -> void:
	var w := 54.0
	var h := 5.0
	var frac: float = clampf(gm.stamina[p.index] / maxf(gm.movement_budget, 0.001), 0.0, 1.0)
	var at: Vector2 = at_pos + Vector2(-w * 0.5, -Player.HALF.y - 32.0)
	draw_rect(Rect2(at, Vector2(w, h)), Color(0.10, 0.11, 0.14, 0.7))
	var c := Color(0.35, 0.95, 0.55).lerp(Color(1.0, 0.35, 0.3), 1.0 - frac)
	draw_rect(Rect2(at, Vector2(w * frac, h)), c)
	draw_rect(Rect2(at, Vector2(w, h)), Color(1, 1, 1, 0.20), false, 1.0)
	if frac <= 0.0:
		_label(at + Vector2(w + 5.0, h), "SPENT", Color(1.0, 0.45, 0.4), 11)


# ---------------------------------------------------------------- kinetics ---

## Moving geometry and orbs, projected to the end of the coming window.
##
## The rail is the honest part of the promise: it shows the whole sweep, so a
## player can see that a lift passes a height without being told when. The ghost
## outline is the specific part: this is exactly where the piece will be when
## time stops again. Together they answer "what will this do to my plan?"
## without answering "what will happen?".
func _draw_kinetics() -> void:
	var end_tick: int = gm.world_tick + gm.exec_ticks()

	for pf in gm.platforms:
		if not pf.has("motion"):
			continue
		var here: Rect2 = pf["rect"]
		var there: Rect2 = gm.platform_rect_at(pf, end_tick)
		var rail_col := Color(0.62, 0.52, 0.86, 0.30)
		var ends: Array = Mover.travel_ends(pf["motion"])
		var home: Vector2 = pf["home"] + here.size * 0.5
		_dotted_polyline(PackedVector2Array([home + ends[0], home + ends[1]]), rail_col, 2.0, 7.0, 6.0)
		for e in ends:
			draw_circle(home + e, 3.0, rail_col)
		if there.position.distance_to(here.position) > 1.0:
			var ghost := Color(0.72, 0.62, 0.98, 0.55)
			draw_rect(there, ghost, false, 2.0)
			_arrow_between(here.get_center(), there.get_center(), ghost)

	for h in gm.hazards:
		var to: Vector2 = h.centre_at(end_tick)
		if to.distance_to(h.position) > 1.0:
			var col := Color(0.55, 0.92, 1.0, 0.5)
			_dotted_polyline(PackedVector2Array([h.position, to]), col, 1.8, 6.0, 5.0)
			draw_arc(to, Hazard.RADIUS, 0.0, TAU, 20, col, 1.6)


func _arrow_between(from: Vector2, to: Vector2, col: Color) -> void:
	var d: Vector2 = to - from
	if d.length() < 12.0:
		return
	var n: Vector2 = d.normalized()
	var tip: Vector2 = to - n * 4.0
	var back: Vector2 = tip - n * 11.0
	var perp: Vector2 = n.orthogonal() * 5.5
	draw_colored_polygon(PackedVector2Array([tip, back + perp, back - perp]), col)


# ----------------------------------------------------------------- arrows ----

func _draw_existing_arrows() -> void:
	_validate_arrow_prediction_cache()
	for a in gm.arrows:
		var pred: Dictionary = _prediction_for_arrow(a)
		var immediate: bool = _is_immediate_threat(pred["path"])
		if immediate:
			_draw_immediate_warning(a.position, pred["path"])
		# current velocity vector
		var v: Vector2 = a.vel
		if v.length() > 1.0:
			var tip: Vector2 = a.position + v.normalized() * clampf(v.length() * 0.10, 24.0, 70.0)
			draw_line(a.position, tip, Color(1, 1, 1, 0.92 if immediate else 0.62),
				3.0 if immediate else 1.7)
			var perp := v.normalized().orthogonal() * 5.0
			var back: Vector2 = tip - v.normalized() * 9.0
			draw_colored_polygon(PackedVector2Array([tip, back + perp, back - perp]),
				Color(1, 1, 1, 0.92 if immediate else 0.62))

		_draw_trajectory(pred["path"], a.color, true, true, gm.exec_ticks())


## Existing knives and the world are frozen throughout planning, so their full
## 4.5-second predictions are identical on every redraw. Cache them until the
## world tick or live knife set changes; threat checks still use the live ghosts.
func _validate_arrow_prediction_cache() -> void:
	var valid: bool = _arrow_prediction_tick == gm.world_tick \
		and _arrow_prediction_cache.size() == gm.arrows.size()
	if valid:
		for a in gm.arrows:
			if not _arrow_prediction_cache.has(a.get_instance_id()):
				valid = false
				break
	if not valid:
		_arrow_prediction_cache.clear()
		_arrow_prediction_tick = gm.world_tick


func _prediction_for_arrow(a: Arrow) -> Dictionary:
	var id := a.get_instance_id()
	if not _arrow_prediction_cache.has(id):
		_arrow_prediction_cache[id] = PredictionSystem.predict_arrow(a.position, a.vel, gm,
			gm.trajectory_preview_time, gm.world_tick, a.clashed)
	return _arrow_prediction_cache[id]


func _is_immediate_threat(arrow_path: PackedVector2Array) -> bool:
	var limit: int = mini(gm.exec_ticks(), arrow_path.size() - 1)
	for p in gm.players:
		if not p.alive or p.invuln_turns > 0 or gm.hides_plan(p.index):
			continue
		var player_path: PackedVector2Array = gm.ghost_path[p.index]
		var shared: int = mini(limit, player_path.size() - 1)
		for tick in range(shared + 1):
			var delta: Vector2 = arrow_path[tick] - player_path[tick]
			if absf(delta.x) <= Player.HALF.x + 9.0 and absf(delta.y) <= Player.HALF.y + 9.0:
				return true
	return false


func _draw_immediate_warning(at: Vector2, path: PackedVector2Array) -> void:
	var warning := Color(1.0, 0.34, 0.24, 0.82)
	draw_arc(at, 16.0, 0.0, TAU, 20, warning, 2.2)
	_label(at + Vector2(18.0, -12.0), "THREAT", warning, 11)
	var near := PackedVector2Array()
	for i in range(mini(gm.exec_ticks(), path.size() - 1) + 1):
		near.append(path[i])
	if near.size() > 1:
		_solid_runs(near, Color(warning.r, warning.g, warning.b, 0.28), 5.0)


# ------------------------------------------------------------------ shared ---

## First execution window is drawn bright/solid, the rest dotted and faded.
## Small rings mark each future execution-phase boundary. `live` separates a
## real threat from the "if you fired now" preview; `end_marker` is suppressed
## while aiming because the reticle already marks the impact point.
##
## `first_boundary` is how many ticks of FLIGHT remain until the current window
## closes. A shot loosed partway through the window reaches +1 sooner than a
## full window of travel, so this cannot be assumed to be one whole phase.
func _draw_trajectory(path: PackedVector2Array, col: Color, live: bool, end_marker: bool,
		first_boundary: int) -> void:
	if path.size() < 2:
		return
	var gain: float = 1.0 if live else 0.42
	var per_phase: int = gm.exec_ticks()
	var split: int = mini(maxi(first_boundary, 1), path.size() - 1)

	var near := PackedVector2Array()
	for i in range(0, split + 1):
		near.append(path[i])
	if near.size() > 1:
		if live:
			_solid_runs(near, Color(col.r, col.g, col.b, 0.95), 2.5)
		else:
			_dotted_runs(near, Color(col.r, col.g, col.b, 0.55), 2.0, 5.0, 4.0)

	if path.size() - 1 > split:
		var far := PackedVector2Array()
		for i in range(split, path.size()):
			far.append(path[i])
		_dotted_runs(far, Color(col.r, col.g, col.b, 0.55 * gain), 2.0, 7.0, 7.0)

	var phase := 1
	var idx: int = maxi(first_boundary, 1)
	while idx < path.size():
		var alpha: float = (0.95 if phase == 1 else 0.6) * gain
		draw_circle(path[idx], 5.0, Color(col.r, col.g, col.b, alpha * 0.35))
		draw_arc(path[idx], 5.0, 0.0, TAU, 12, Color(col.r, col.g, col.b, alpha), 1.5)
		_label(path[idx] + Vector2(7.0, -9.0), "+%d" % phase, Color(col.r, col.g, col.b, alpha), 11)
		phase += 1
		idx += per_phase

	if end_marker:
		var last: Vector2 = path[path.size() - 1]
		draw_arc(last, 7.0, 0.0, TAU, 16, Color(col.r, col.g, col.b, 0.9 * gain), 2.0)


## Splits a path wherever it jumped across a wrapping seam. A body moves at most
## a few pixels per tick and an arrow a couple of dozen, so any gap this large is
## a wrap, not motion — drawing through it would streak a line across the arena.
const SEAM_JUMP_SQ := 40000.0    # (200 px)^2


func _runs(path: PackedVector2Array) -> Array:
	var out: Array = []
	var run := PackedVector2Array()
	for i in path.size():
		if run.size() > 0 and run[run.size() - 1].distance_squared_to(path[i]) > SEAM_JUMP_SQ:
			out.append(run)
			run = PackedVector2Array()
		run.append(path[i])
	if run.size() > 0:
		out.append(run)
	return out


func _solid_runs(path: PackedVector2Array, col: Color, width: float) -> void:
	for run in _runs(path):
		if run.size() > 1:
			if high_contrast:
				draw_polyline(run, Color(0.015, 0.02, 0.035, maxf(col.a, 0.82)), width + 3.5)
			draw_polyline(run, col, width)


func _dotted_runs(path: PackedVector2Array, col: Color, width: float, dash: float, gap: float) -> void:
	for run in _runs(path):
		if run.size() > 1:
			_dotted_polyline(run, col, width, dash, gap)


func _dotted_polyline(pts: PackedVector2Array, col: Color, width: float, dash: float, gap: float) -> void:
	var carry := 0.0
	var drawing := true
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg: float = a.distance_to(b)
		if seg <= 0.0001:
			continue
		var dir: Vector2 = (b - a) / seg
		var t := 0.0
		while t < seg:
			var span: float = (dash if drawing else gap) - carry
			var step: float = minf(span, seg - t)
			if drawing:
				if high_contrast:
					draw_line(a + dir * t, a + dir * (t + step),
						Color(0.015, 0.02, 0.035, maxf(col.a, 0.82)), width + 3.5)
				draw_line(a + dir * t, a + dir * (t + step), col, width)
			t += step
			carry += step
			if carry >= (dash if drawing else gap) - 0.0001:
				carry = 0.0
				drawing = not drawing


func _dotted_rect(r: Rect2, col: Color, width: float) -> void:
	var p := PackedVector2Array([
		r.position,
		Vector2(r.end.x, r.position.y),
		r.end,
		Vector2(r.position.x, r.end.y),
		r.position,
	])
	_dotted_polyline(p, col, width, 6.0, 5.0)


func _label(at: Vector2, text: String, col: Color, size: int) -> void:
	if high_contrast:
		draw_string(ThemeDB.fallback_font, at + Vector2(2.0, 2.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.015, 0.02, 0.035, 0.96))
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _player_preview_color(p: Player) -> Color:
	if not high_contrast:
		return p.color
	return Color(1.0, 0.86, 0.28) if (p.index & 1) == 0 else Color(0.30, 0.90, 1.0)
