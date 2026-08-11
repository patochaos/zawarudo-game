extends Node2D

## Draws every planning-phase visualization: player ghosts + motion arcs, the
## always-on potential-shot trajectory, and the frozen state / future path of
## existing knives. Hidden entirely during EXECUTION.

var gm


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
	var col: Color = p.color
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
	var c := Color(p.color.r, p.color.g, p.color.b, 0.95)
	draw_arc(foot, 10.0, 0.0, TAU, 20, c, 2.2)
	draw_circle(foot, 2.5, c)
	draw_line(foot - Vector2(16.0, 0.0), foot - Vector2(8.0, 0.0), c, 1.5)
	draw_line(foot + Vector2(8.0, 0.0), foot + Vector2(16.0, 0.0), c, 1.5)
	_label(foot + Vector2(14.0, -8.0), "END", c, 11)


func _draw_ghost_figure(at: Vector2, p: Player, alpha: float) -> void:
	var pose := Player.idle_pose_points(p.facing, p.aim_dir())
	var c := Color(p.color.r, p.color.g, p.color.b, alpha)
	var faint := Color(p.color.r, p.color.g, p.color.b, alpha * 0.16)
	var segments := [
		[pose["hip"], pose["chest"]], [pose["chest"], pose["neck"]],
		[pose["hip"], pose["knee_a"]], [pose["knee_a"], pose["foot_a"]],
		[pose["hip"], pose["knee_b"]], [pose["knee_b"], pose["foot_b"]],
		[pose["free_shoulder"], pose["free_elbow"]],
		[pose["free_elbow"], pose["free_hand"]],
		[pose["shoulder"], pose["aim_elbow"]], [pose["aim_elbow"], pose["grip"]],
	]
	for segment in segments:
		draw_line(at + segment[0], at + segment[1], c, 2.2, true)
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
## Shows the fan: which way it points and how hard it is drawn. Deliberately
## NOT where the knives land — you get direction and power, and you estimate the
## rest. Predicting your own shot was making the aiming a solved problem.
##
## Power is encoded in the aim line itself: it lengthens, thickens and brightens
## as the draw builds, with notches every 25%.
const AIM_LEN_MIN := 34.0
const AIM_LEN_MAX := 132.0


func _draw_shot_preview(p: Player, origin: Vector2) -> void:
	var col: Color = p.color
	var armed: bool = p.plan.has_shot()
	var charging: bool = gm.charging[p.index]
	var live: bool = armed or charging
	var shoulder: Vector2 = Player.shoulder_at(origin)
	var power: float = clampf(p.plan.power, 0.0, 1.0)
	var launches: Array[Vector2] = gm.knife_launch_velocities(p.aim_dir(), power)
	var dir: Vector2 = launches[0].normalized()

	var length: float = lerpf(AIM_LEN_MIN, AIM_LEN_MAX, power)
	var tip: Vector2 = shoulder + dir * length
	var body: Color = col.lightened(0.35) if live else Color(col.r, col.g, col.b, 0.5)
	var knife_dirs: Array[Vector2] = []
	for launch in launches:
		knife_dirs.append(launch.normalized())

	# The two rays expose the actual fan without solving the ballistic arc. A
	# weak wedge makes the low-power coverage readable at a glance.
	if knife_dirs.size() >= 2:
		var left: Vector2 = knife_dirs[0]
		var right: Vector2 = knife_dirs[knife_dirs.size() - 1]
		draw_colored_polygon(PackedVector2Array([
			shoulder, shoulder + left * length, shoulder + right * length,
		]), Color(col.r, col.g, col.b, 0.045 if live else 0.025))
	for knife_dir in knife_dirs:
		var knife_tip: Vector2 = shoulder + knife_dir * length
		draw_line(shoulder, shoulder + knife_dir * AIM_LEN_MAX,
			Color(col.r, col.g, col.b, 0.12), 1.5)
		draw_line(shoulder, knife_tip, body, 3.0 if live else 2.0)
		_draw_knife_head(knife_tip, knife_dir, body)

	# The centre spine carries the power notches; the fan carries direction.
	draw_line(shoulder, tip, Color(body.r, body.g, body.b, body.a * 0.45), 1.0)

	# quarter notches along the track
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

	var actual_elevation: float = rad_to_deg(atan2(-dir.y, absf(dir.x)))
	var tag := "%d° · %d%%" % [int(round(actual_elevation)), int(round(power * 100.0))]
	if armed:
		tag = ("SUPER · " if p.plan.super_shot else "FIRED · ") + tag
	elif charging:
		if gm.super_meter[p.index] >= 1.0:
			tag = ("SUPER ARMED · " if gm.super_armed[p.index] else "SUPER STANDBY · ") + tag
		else:
			tag = "DRAWING · " + tag
	_shot_tag(p, tip, dir, tag, col.lightened(0.4) if live else Color(col.r, col.g, col.b, 0.65),
		14 if live else 12)
	_draw_power_bar(origin, p, charging)


func _draw_knife_head(tip: Vector2, dir: Vector2, col: Color) -> void:
	var side := dir.orthogonal()
	draw_colored_polygon(PackedVector2Array([
		tip + dir * 11.0, tip - dir * 3.0 + side * 3.6,
		tip - dir * 6.0, tip - dir * 3.0 - side * 3.6,
	]), col)
	draw_line(tip - dir * 7.0 - side * 5.0, tip - dir * 7.0 + side * 5.0, col, 1.5)


## Marks the point along the path where the bow releases.
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
	var fill: Color = Color(1.0, 0.85, 0.3) if charging else Color(p.color.r, p.color.g, p.color.b, 0.7)
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
	for a in gm.arrows:
		var pred := PredictionSystem.predict_arrow(a.position, a.vel, gm,
			gm.trajectory_preview_time, gm.world_tick, a.clashed)
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
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
