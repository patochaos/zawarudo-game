extends Node2D
class_name FighterVisual

## Cosmetic observer for Player. Body state is sampled manually from the
## authoritative player and world tick; there is no autonomous animation clock,
## root motion or write back into gameplay state.

const IDLE: StringName = &"IDLE"
const RUN: StringName = &"RUN"
const RISE: StringName = &"RISE"
const FALL: StringName = &"FALL"
const SHOT: StringName = &"SHOT"
const LOCK: StringName = &"LOCK"
const DEFEAT: StringName = &"DEFEAT"

var skin: FighterSkin
var body_state: StringName = IDLE
var body_frame: int = 0
var _fighter: Player
var _aim_arm: Node2D


class AimArm extends Node2D:
	var visual: FighterVisual

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if visual != null:
			visual._draw_aim_arm(self)


func configure(fighter: Player, fighter_skin: FighterSkin) -> void:
	_fighter = fighter
	skin = fighter_skin


func _ready() -> void:
	if _fighter == null:
		_fighter = get_parent() as Player
	if skin == null and _fighter != null:
		skin = FighterSkin.greybox(_fighter.index)
	_aim_arm = AimArm.new()
	_aim_arm.name = "AimArm"
	_aim_arm.visual = self
	add_child(_aim_arm)
	sync_from_player()


func _process(_delta: float) -> void:
	sync_from_player()
	queue_redraw()


func sync_from_player() -> void:
	if _fighter == null:
		_fighter = get_parent() as Player
	if _fighter == null or skin == null:
		return
	body_state = _derive_state()
	var frame_count := skin.frame_count(body_state)
	if frame_count <= 0:
		body_frame = 0
		return
	var tick := 0
	if _fighter.cfg != null:
		tick = int(_fighter.cfg.world_tick)
	var frame_step: int = tick / maxi(1, skin.ticks_per_frame)
	if body_state == SHOT:
		frame_step = maxi(0, _presentation_exec_tick() - _fighter.plan.shot_tick) \
			/ maxi(1, skin.ticks_per_frame)
		body_frame = mini(frame_count - 1, frame_step)
	else:
		body_frame = posmod(frame_step, frame_count)


func _derive_state() -> StringName:
	if not _fighter.alive:
		return DEFEAT
	var phase := Phase.FREEPLAY if _fighter.cfg == null else int(_fighter.cfg.state)
	if _shot_is_visible(phase):
		return SHOT
	if _fighter.plan.confirmed and phase in [Phase.PLANNING, Phase.COMMITTING, Phase.ONLINE_WAIT]:
		return LOCK
	if not _fighter.on_ground:
		return RISE if _fighter.vel.y < 0.0 else FALL
	if absf(_fighter.vel.x) > 24.0:
		return RUN
	return IDLE


func _presentation_exec_tick() -> int:
	if _fighter == null or _fighter.cfg == null:
		return 0
	if int(_fighter.cfg.state) == Phase.REPLAY:
		return int(_fighter.cfg._replay_frame_index)
	return int(_fighter.cfg.exec_tick)


func _shot_is_visible(phase: int) -> bool:
	if _fighter == null or not _fighter.plan.has_shot() \
			or phase not in [Phase.EXECUTING, Phase.REPLAY]:
		return false
	var elapsed := _presentation_exec_tick() - _fighter.plan.shot_tick
	return elapsed >= 0 and elapsed < skin.frame_count(SHOT) * maxi(1, skin.ticks_per_frame)


func body_signature() -> String:
	if _fighter == null:
		return "%s:%d" % [body_state, body_frame]
	return "%s:%d:%d" % [body_state, body_frame, _fighter.facing]


func aim_segment_local() -> PackedVector2Array:
	if _fighter == null:
		return PackedVector2Array()
	return PackedVector2Array([
		_fighter.shoulder() - _fighter.position,
		_fighter.muzzle() - _fighter.position,
	])


func aim_shoulder_global() -> Vector2:
	var segment := aim_segment_local()
	return to_global(segment[0]) if segment.size() == 2 else global_position


func aim_muzzle_global() -> Vector2:
	var segment := aim_segment_local()
	return to_global(segment[1]) if segment.size() == 2 else global_position


func _current_pose() -> Dictionary:
	if skin == null:
		return {}
	var state_frames: Array = skin.frames.get(body_state, [])
	if state_frames.is_empty():
		return {}
	return state_frames[clampi(body_frame, 0, state_frames.size() - 1)]


func _draw() -> void:
	if _fighter == null or skin == null:
		return
	var uses_sprite := skin.has_sprite(body_state)
	var pose := {} if uses_sprite else _current_pose()
	if not uses_sprite and pose.is_empty():
		return
	_draw_world_markers()
	if uses_sprite:
		_draw_sprite_body()
	elif skin.render_style == &"cel_modular":
		if body_state == DEFEAT:
			_draw_cel_hit_pose(pose)
		else:
			_draw_cel_body(pose)
	elif body_state == DEFEAT:
		_draw_defeat(pose)
	else:
		_draw_body(pose)
	_draw_player_label()


func _draw_sprite_body() -> void:
	var atlas: Texture2D = skin.sprite_atlases.get(body_state)
	if atlas == null:
		return
	var cell := Vector2(skin.sprite_cell_size)
	var source := Rect2(Vector2(float(body_frame) * cell.x, 0.0), cell)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(float(_fighter.facing), 1.0))
	draw_texture_rect_region(atlas, skin.sprite_draw_rect, source, skin.sprite_tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_world_markers() -> void:
	var body: Color = skin.palette.get(&"body", _fighter.color)
	if _fighter.on_ground:
		_draw_ellipse_shape(Vector2(0.0, Player.HALF.y + 2.0), Vector2(19.0, 4.5),
			Color(0.0, 0.0, 0.0, 0.30))
	if _fighter.is_invulnerable():
		draw_circle(Vector2.ZERO, 35.0, Color(body.r, body.g, body.b, 0.10))
		draw_arc(Vector2.ZERO, 35.0, 0.0, TAU, 32, Color(0.95, 0.97, 1.0, 0.76), 2.0)
	if _fighter.cfg != null and _fighter.index < _fighter.cfg.super_meter.size() \
			and _fighter.cfg.super_meter[_fighter.index] >= 1.0:
		var armed: bool = _fighter.index < _fighter.cfg.super_armed.size() \
			and _fighter.cfg.super_armed[_fighter.index]
		draw_arc(Vector2.ZERO, 40.0, 0.0, TAU, 32,
			Color(1.0, 0.97, 0.64, 1.0) if armed else Color(1.0, 0.82, 0.36, 0.72),
			4.0 if armed else 2.0)


func _draw_ellipse_shape(center: Vector2, radii: Vector2, fill: Color) -> void:
	var points := PackedVector2Array()
	for i in 20:
		var angle := TAU * float(i) / 20.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, fill)


func _draw_body(pose: Dictionary) -> void:
	var f := float(_fighter.facing)
	var bob := float(pose.get(&"bob", 0.0))
	var lean := float(pose.get(&"lean", 0.0))
	var stride := float(pose.get(&"stride", 0.0))
	var coat := float(pose.get(&"coat", 0.0))
	var ink: Color = skin.palette.get(&"ink", Color(0.02, 0.02, 0.04))
	var body: Color = skin.palette.get(&"body", _fighter.color)
	var secondary: Color = skin.palette.get(&"secondary", body.darkened(0.25))
	var shoulder_width := float(skin.silhouette.get(&"shoulder_width", 21.0))
	var waist_width := float(skin.silhouette.get(&"waist_width", 8.0))
	var hip := Vector2(lean * 0.15 * f, 5.0 + bob)
	var shoulders := Vector2(lean * f, -29.0 + bob)
	var head := Vector2((lean - 3.0) * f, -52.0 + bob)

	# Back leg, front leg and heavy footwear establish contact at the unchanged
	# collision feet line (local y = +24).
	_draw_limb(hip, Vector2(-stride * 0.45 * f, 14.0 + bob),
		Vector2(-stride * f, 24.0), 8.0, secondary, ink)
	_draw_limb(hip, Vector2(stride * 0.42 * f, 14.0 + bob),
		Vector2(stride * 0.85 * f, 24.0), 9.0, body, ink)

	var torso := PackedVector2Array([
		Vector2((-shoulder_width + lean) * f, -31.0 + bob),
		Vector2((shoulder_width + lean) * f, -29.0 + bob),
		Vector2((waist_width + lean * 0.2) * f, 7.0 + bob),
		Vector2((-waist_width + lean * 0.2) * f, 7.0 + bob),
	])
	_draw_shape(torso, body, ink, 2.5)

	var profile: StringName = skin.silhouette.get(&"profile", &"EXECUTOR")
	if profile == &"EXECUTOR":
		_draw_executor_shapes(shoulders, hip, head, coat, f, body, secondary, ink)
	else:
		_draw_witness_shapes(shoulders, hip, head, coat, f, body, secondary, ink)

	# The free arm is part of the authored body pose. The authoritative aiming
	# arm is drawn by the dedicated AimArm child above it.
	var free_hand := Vector2((-18.0 + lean) * f, -42.0 + bob)
	_draw_limb(shoulders + Vector2(-9.0 * f, 4.0),
		Vector2((-24.0 + lean) * f, -24.0 + bob), free_hand, 7.0, secondary, ink)


func _draw_executor_shapes(shoulders: Vector2, hip: Vector2, head: Vector2, coat: float,
		f: float, body: Color, secondary: Color, ink: Color) -> void:
	var tails := PackedVector2Array([
		hip + Vector2(-8.0 * f, -1.0),
		hip + Vector2((-22.0 - coat) * f, 22.0),
		hip + Vector2(-2.0 * f, 14.0),
		hip + Vector2((18.0 - coat) * f, 23.0),
		hip + Vector2(8.0 * f, -1.0),
	])
	_draw_shape(tails, secondary, ink, 2.5)
	var collar := PackedVector2Array([
		shoulders + Vector2(-17.0 * f, 2.0),
		shoulders + Vector2(-9.0 * f, -12.0),
		shoulders + Vector2(1.0 * f, 1.0),
		shoulders + Vector2(15.0 * f, -8.0),
		shoulders + Vector2(18.0 * f, 5.0),
	])
	_draw_shape(collar, secondary, ink, 2.0)
	_draw_head(head, f, body, ink, true)
	draw_circle(shoulders + Vector2(0.0, 13.0), 4.5, ink)
	draw_circle(shoulders + Vector2(0.0, 13.0), 2.6, Color(1.0, 0.84, 0.35))


func _draw_witness_shapes(shoulders: Vector2, hip: Vector2, head: Vector2, coat: float,
		f: float, body: Color, secondary: Color, ink: Color) -> void:
	var jacket := PackedVector2Array([
		shoulders + Vector2(-15.0 * f, 5.0),
		shoulders + Vector2(17.0 * f, 7.0),
		hip + Vector2(10.0 * f, -2.0),
		hip + Vector2(-14.0 * f, 5.0),
	])
	_draw_shape(jacket, secondary, ink, 2.0)
	# The long hooked scarf is the second silhouette's grayscale identity anchor.
	var scarf := PackedVector2Array([
		head + Vector2(-5.0 * f, 5.0),
		head + Vector2((-18.0 + coat) * f, 0.0),
		head + Vector2((-28.0 + coat) * f, 13.0),
		head + Vector2((-21.0 + coat) * f, 31.0),
		head + Vector2((-14.0 + coat) * f, 17.0),
		head + Vector2(-1.0 * f, 10.0),
	])
	_draw_shape(scarf, secondary, ink, 2.0)
	_draw_head(head + Vector2(2.0 * f, 0.0), f, body, ink, false)
	var flare := PackedVector2Array([
		hip + Vector2(-5.0 * f, 4.0), hip + Vector2(-16.0 * f, 24.0),
		hip + Vector2(-5.0 * f, 22.0), hip + Vector2(3.0 * f, 4.0),
	])
	_draw_shape(flare, secondary, ink, 2.0)


func _draw_cel_body(pose: Dictionary) -> void:
	var f := float(_fighter.facing)
	var bob := float(pose.get(&"bob", 0.0))
	var lean := float(pose.get(&"lean", 0.0))
	var stride := float(pose.get(&"stride", 0.0))
	var coat := float(pose.get(&"coat", 0.0))
	var recoil := float(pose.get(&"recoil", 0.0))
	var ink: Color = skin.palette[&"ink"]
	var ivory: Color = skin.palette[&"body"]
	var light: Color = skin.palette[&"light"]
	var shadow: Color = skin.palette[&"shadow"]
	var gold: Color = skin.palette[&"gold"]
	var hip := Vector2((1.0 + lean * 0.12) * f, 5.0 + bob)
	var chest := Vector2((-2.0 + lean * 0.52 - recoil * 0.25) * f, -8.0 + bob)
	var neck := Vector2((-4.0 + lean * 0.65 - recoil * 0.32) * f, -15.0 + bob)
	var head := Vector2((-5.0 + lean * 0.72 - recoil * 0.42) * f, -23.0 + bob)

	# Two narrow tails and long tapered legs retain the clarity of the stick
	# prototype while giving the silhouette a tailored, theatrical identity.
	_draw_shape(PackedVector2Array([
		hip + Vector2(-7.0 * f, -1.0),
		hip + Vector2((-11.0 - coat * 0.45) * f, 18.0),
		hip + Vector2(-2.0 * f, 13.0),
		hip + Vector2(1.0 * f, 0.0),
	]), shadow, ink, 1.7)
	_draw_shape(PackedVector2Array([
		hip + Vector2(-1.0 * f, 0.0),
		hip + Vector2((9.0 - coat * 0.35) * f, 20.0),
		hip + Vector2(11.0 * f, 12.0),
		hip + Vector2(7.0 * f, -1.0),
	]), ivory, ink, 1.7)

	var back_knee := Vector2((-5.0 - stride * 0.34) * f, 14.0 + bob)
	var back_foot := Vector2((-9.0 - stride * 0.72) * f, 24.0)
	var front_knee := Vector2((6.0 + stride * 0.34) * f, 13.0 + bob)
	var front_foot := Vector2((10.0 + stride * 0.72) * f, 24.0)
	_draw_cel_segment(self, hip, back_knee, 3.9, 3.1, shadow, shadow.darkened(0.18), ink)
	_draw_cel_segment(self, back_knee, back_foot, 3.2, 2.5, shadow, shadow.darkened(0.18), ink)
	_draw_cel_segment(self, hip, front_knee, 4.2, 3.2, ivory, shadow, ink)
	_draw_cel_segment(self, front_knee, front_foot, 3.3, 2.5, light, shadow, ink)
	_draw_cel_boot(back_foot, f, ink, gold)
	_draw_cel_boot(front_foot, f, ink, gold)

	var torso := PackedVector2Array([
		chest + Vector2(-11.0 * f, -3.0),
		chest + Vector2(10.0 * f, -2.0),
		hip + Vector2(7.0 * f, 2.0),
		hip + Vector2(-7.0 * f, 2.0),
	])
	_draw_shape(torso, ivory, ink, 2.0)
	var torso_shadow := PackedVector2Array([
		chest + Vector2(-11.0 * f, -3.0),
		chest + Vector2(-5.0 * f, -1.0),
		hip + Vector2(-1.0 * f, 2.0),
		hip + Vector2(-7.0 * f, 2.0),
	])
	draw_colored_polygon(torso_shadow, shadow)

	# The lapels form one bold gold chevron; tiny costume details were
	# intentionally removed because they disappear at gameplay scale.
	_draw_shape(PackedVector2Array([
		neck + Vector2(-1.0 * f, 2.0),
		chest + Vector2(-7.0 * f, -1.0),
		chest + Vector2(-1.0 * f, 7.0),
		chest + Vector2(1.0 * f, 1.0),
		chest + Vector2(7.0 * f, 0.0),
		neck + Vector2(2.0 * f, 2.0),
	]), gold, ink, 1.5)

	var free_shoulder := chest + Vector2(-8.0 * f, -1.0)
	var free_elbow := Vector2((-13.0 + lean * 0.25) * f, -10.0 + bob)
	var free_hand := Vector2((-9.0 + lean * 0.35) * f, -19.0 + bob)
	if body_state == SHOT:
		free_elbow += Vector2(-recoil * 0.8 * f, 3.0)
		free_hand += Vector2(-recoil * 1.3 * f, 6.0)
	_draw_cel_segment(self, free_shoulder, free_elbow, 3.3, 2.8, shadow, shadow.darkened(0.18), ink)
	_draw_cel_segment(self, free_elbow, free_hand, 2.9, 2.1, ivory, shadow, ink)
	draw_circle(free_hand, 2.2, ink)
	draw_circle(free_hand, 1.3, skin.palette[&"skin"])

	var collar := PackedVector2Array([
		neck + Vector2(-7.0 * f, 3.0),
		neck + Vector2(-7.5 * f, -3.0),
		neck + Vector2(-1.0 * f, 1.0),
		neck + Vector2(6.0 * f, -4.0),
		neck + Vector2(7.0 * f, 3.0),
	])
	_draw_shape(collar, ink, ink, 1.0)
	_draw_cel_head(head, f, ink, light, gold)

	if body_state == SHOT and body_frame <= 1:
		for offset_y in [-10.0, -3.0, 5.0]:
			draw_line(chest + Vector2((-20.0 - recoil) * f, offset_y),
				chest + Vector2((-11.0 - recoil * 0.4) * f, offset_y * 0.65),
				gold, 1.3, true)


func _draw_cel_head(center: Vector2, f: float, ink: Color, light: Color, gold: Color) -> void:
	var skin_tone: Color = skin.palette[&"skin"]
	var face := PackedVector2Array([
		center + Vector2(-5.0 * f, -5.0), center + Vector2(3.5 * f, -5.0),
		center + Vector2(6.0 * f, -1.0), center + Vector2(3.0 * f, 6.0),
		center + Vector2(-3.5 * f, 5.0), center + Vector2(-6.0 * f, 0.0),
	])
	_draw_shape(face, skin_tone, ink, 1.8)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-5.0 * f, 1.0), center + Vector2(-1.0 * f, 5.0),
		center + Vector2(-3.5 * f, 5.0), center + Vector2(-6.0 * f, 0.0),
	]), gold.darkened(0.22))

	# One swept mass plus three large spikes. It is bizarre in silhouette, but
	# still behaves like a logo rather than noisy individual hair strands.
	var hair := PackedVector2Array([
		center + Vector2(4.0 * f, -4.0), center + Vector2(1.0 * f, -13.0),
		center + Vector2(-2.0 * f, -7.0), center + Vector2(-8.0 * f, -12.0),
		center + Vector2(-7.0 * f, -5.0), center + Vector2(-15.0 * f, -7.0),
		center + Vector2(-10.0 * f, 0.0), center + Vector2(-15.0 * f, 5.0),
		center + Vector2(-5.0 * f, 4.0), center + Vector2(-4.0 * f, -2.0),
	])
	_draw_shape(hair, skin.palette[&"hair"], ink, 1.8)
	draw_line(center + Vector2(-8.0 * f, -5.0), center + Vector2(-2.0 * f, -7.0),
		gold, 1.5, true)
	# A single eye/brow wedge reads more cleanly than a miniature face.
	draw_line(center + Vector2(0.5 * f, -2.0), center + Vector2(4.5 * f, -1.0), ink, 1.5, true)
	draw_circle(center + Vector2(3.4 * f, -0.4), 0.9, light)


func _draw_cel_boot(at: Vector2, f: float, ink: Color, gold: Color) -> void:
	_draw_shape(PackedVector2Array([
		at + Vector2(-2.8 * f, -2.0), at + Vector2(2.0 * f, -2.0),
		at + Vector2(6.0 * f, 1.0), at + Vector2(-3.0 * f, 1.0),
	]), ink, ink, 1.0)
	draw_line(at + Vector2(1.0 * f, -1.0), at + Vector2(4.5 * f, 0.0), gold, 1.2, true)


func _draw_cel_segment(canvas: Node2D, start: Vector2, finish: Vector2,
		start_half: float, finish_half: float, fill: Color, shade: Color, ink: Color) -> void:
	var axis := finish - start
	if axis.is_zero_approx():
		return
	var side := axis.normalized().orthogonal()
	var shape := PackedVector2Array([
		start + side * start_half, finish + side * finish_half,
		finish - side * finish_half, start - side * start_half,
	])
	canvas.draw_colored_polygon(shape, fill)
	var shade_side := -side
	canvas.draw_line(start + shade_side * (start_half - 0.7),
		finish + shade_side * (finish_half - 0.7), shade, 1.4, true)
	var outline := shape.duplicate()
	outline.append(shape[0])
	canvas.draw_polyline(outline, ink, 1.7, true)


func _draw_cel_hit_pose(_pose: Dictionary) -> void:
	var f := float(_fighter.facing)
	var ink: Color = skin.palette[&"ink"]
	var ivory: Color = skin.palette[&"body"]
	var shadow: Color = skin.palette[&"shadow"]
	var gold: Color = skin.palette[&"gold"]
	var impact: Color = skin.palette[&"impact"]
	var hip := Vector2(2.0 * f, 8.0)
	var chest := Vector2(-8.0 * f, -3.0)
	var head := Vector2(-16.0 * f, -12.0)
	_draw_shape(PackedVector2Array([
		hip + Vector2(-5.0 * f, -2.0), hip + Vector2(-18.0 * f, 17.0),
		hip + Vector2(-2.0 * f, 12.0), hip + Vector2(5.0 * f, 0.0),
	]), shadow, ink, 1.7)
	_draw_cel_segment(self, hip, Vector2(-4.0 * f, 16.0), 4.0, 3.0, shadow, shadow.darkened(0.2), ink)
	_draw_cel_segment(self, Vector2(-4.0 * f, 16.0), Vector2(-13.0 * f, 24.0), 3.0, 2.3, shadow, shadow.darkened(0.2), ink)
	_draw_cel_segment(self, hip, Vector2(9.0 * f, 14.0), 4.2, 3.0, ivory, shadow, ink)
	_draw_cel_segment(self, Vector2(9.0 * f, 14.0), Vector2(18.0 * f, 22.0), 3.0, 2.3, ivory, shadow, ink)
	_draw_cel_segment(self, hip, chest, 7.0, 9.5, ivory, shadow, ink)
	_draw_cel_segment(self, chest, Vector2(-22.0 * f, 1.0), 3.5, 2.2, shadow, shadow.darkened(0.2), ink)
	_draw_cel_segment(self, chest, Vector2(3.0 * f, -15.0), 3.5, 2.2, ivory, shadow, ink)
	_draw_cel_head(head, f, ink, skin.palette[&"light"], gold)

	var burst_center := chest + Vector2(7.0 * f, -1.0)
	var burst := PackedVector2Array()
	for i in 12:
		var radius := 8.0 if i % 2 == 0 else 3.5
		var angle := TAU * float(i) / 12.0
		burst.append(burst_center + Vector2(cos(angle), sin(angle)) * radius)
	_draw_shape(burst, impact, ink, 1.4)
	for y in [-10.0, 0.0, 10.0]:
		draw_line(burst_center + Vector2(8.0 * f, y * 0.15),
			burst_center + Vector2(22.0 * f, y), impact, 1.8, true)


func _draw_head(center: Vector2, f: float, body: Color, ink: Color, angular: bool) -> void:
	var radius := float(skin.silhouette.get(&"head_radius", 8.0))
	draw_circle(center, radius + 2.0, ink)
	draw_circle(center, radius, body.lightened(0.12))
	if angular:
		var crest := PackedVector2Array([
			center + Vector2(-7.0 * f, -4.0), center + Vector2(-13.0 * f, -9.0),
			center + Vector2(-10.0 * f, 0.0), center + Vector2(-15.0 * f, 3.0),
			center + Vector2(-5.0 * f, 5.0),
		])
		_draw_shape(crest, ink, ink, 1.0)
	else:
		draw_line(center + Vector2(-2.0 * f, -9.0), center + Vector2(-8.0 * f, 9.0),
			ink, 4.0, true)
	draw_line(center + Vector2(1.0 * f, -2.0), center + Vector2(5.0 * f, -1.0),
		ink, 1.5, true)


func _draw_defeat(pose: Dictionary) -> void:
	var ink: Color = skin.palette.get(&"ink", Color(0.02, 0.02, 0.04))
	var fallen: Color = skin.palette.get(&"defeat", Color(0.3, 0.3, 0.34, 0.78))
	var f := float(_fighter.facing)
	var base := Vector2(-5.0 * f, 17.0)
	_draw_limb(base, Vector2(5.0 * f, 18.0), Vector2(21.0 * f, 23.0), 9.0, fallen, ink)
	_draw_limb(base, Vector2(-14.0 * f, 16.0), Vector2(-24.0 * f, 22.0), 8.0, fallen, ink)
	_draw_shape(PackedVector2Array([
		Vector2(-17.0 * f, 9.0), Vector2(12.0 * f, 10.0),
		Vector2(18.0 * f, 21.0), Vector2(-14.0 * f, 22.0),
	]), fallen, ink, 2.5)
	draw_circle(Vector2(-25.0 * f, 14.0), 10.0, ink)
	draw_circle(Vector2(-25.0 * f, 14.0), 7.5, fallen)
	draw_line(Vector2(-31.0 * f, 5.0), Vector2(27.0 * f, 24.0),
		Color(1.0, 0.24, 0.28, 0.9), 2.5, true)


func _draw_aim_arm(canvas: Node2D) -> void:
	if _fighter == null or skin == null or not _fighter.alive:
		return
	if skin.render_style == &"cel_modular":
		_draw_cel_aim_arm(canvas)
		return
	var segment := aim_segment_local()
	if segment.size() != 2:
		return
	var shoulder := segment[0]
	var muzzle := segment[1]
	var direction := (muzzle - shoulder).normalized()
	var bend := direction.orthogonal() * (4.0 * float(_fighter.facing))
	var elbow := shoulder.lerp(muzzle, 0.52) + bend
	var ink: Color = skin.palette.get(&"ink", Color(0.02, 0.02, 0.04))
	var body: Color = skin.palette.get(&"body", _fighter.color)
	canvas.draw_line(shoulder, elbow, ink, 10.0, true)
	canvas.draw_line(elbow, muzzle, ink, 10.0, true)
	canvas.draw_line(shoulder, elbow, body.lightened(0.08), 6.0, true)
	canvas.draw_line(elbow, muzzle, body, 6.0, true)
	canvas.draw_circle(shoulder, 5.0, ink)
	canvas.draw_circle(shoulder, 3.2, body)
	canvas.draw_circle(muzzle, 5.0, ink)
	canvas.draw_circle(muzzle, 3.0, body.lightened(0.2))
	# The greybox weapon begins at the authoritative muzzle; launch origin and
	# direction remain owned by Player/GameManager and are never inferred here.
	var side := direction.orthogonal()
	var tip := muzzle + direction * 14.0
	canvas.draw_colored_polygon(PackedVector2Array([
		tip, muzzle + side * 2.5, muzzle - direction * 3.0, muzzle - side * 2.5,
	]), Color(0.90, 0.93, 1.0, 0.96))


func _draw_cel_aim_arm(canvas: Node2D) -> void:
	var segment := aim_segment_local()
	if segment.size() != 2:
		return
	var shoulder := segment[0]
	var muzzle := segment[1]
	var direction := (muzzle - shoulder).normalized()
	var side := direction.orthogonal()
	var elbow := shoulder.lerp(muzzle, 0.52) + side * (3.0 * float(_fighter.facing))
	var ink: Color = skin.palette[&"ink"]
	var ivory: Color = skin.palette[&"body"]
	var shadow: Color = skin.palette[&"shadow"]
	var gold: Color = skin.palette[&"gold"]
	_draw_cel_segment(canvas, shoulder, elbow, 3.8, 3.1, ivory, shadow, ink)
	_draw_cel_segment(canvas, elbow, muzzle, 3.2, 2.3, ivory, shadow, ink)
	canvas.draw_circle(shoulder, 3.2, ink)
	canvas.draw_circle(shoulder, 1.8, gold)
	canvas.draw_line(muzzle - direction * 3.2 - side * 2.7,
		muzzle - direction * 3.2 + side * 2.7, ink, 2.8, true)
	canvas.draw_circle(muzzle, 2.0, ink)
	canvas.draw_circle(muzzle, 1.1, skin.palette[&"skin"])

	# Knife begins exactly at the authoritative muzzle. A larger diamond flash
	# appears only on deterministic SHOT frames; planning keeps a clean aim read.
	var tip := muzzle + direction * 14.0
	canvas.draw_colored_polygon(PackedVector2Array([
		tip, muzzle + side * 2.2, muzzle - direction * 2.0,
		muzzle - side * 2.2,
	]), skin.palette[&"light"])
	canvas.draw_polyline(PackedVector2Array([
		tip, muzzle + side * 2.2, muzzle - direction * 2.0,
		muzzle - side * 2.2, tip,
	]), ink, 1.3, true)
	if body_state == SHOT and body_frame <= 1:
		var flash := PackedVector2Array()
		for i in 8:
			var radius := 7.0 if i % 2 == 0 else 2.8
			var angle := TAU * float(i) / 8.0
			flash.append(tip + Vector2(cos(angle), sin(angle)) * radius)
		canvas.draw_colored_polygon(flash, gold)
		var flash_outline := flash.duplicate()
		flash_outline.append(flash[0])
		canvas.draw_polyline(flash_outline, ink, 1.2, true)


func _draw_limb(start: Vector2, joint: Vector2, finish: Vector2, width: float,
		fill: Color, ink: Color) -> void:
	draw_line(start, joint, ink, width + 4.0, true)
	draw_line(joint, finish, ink, width + 4.0, true)
	draw_line(start, joint, fill, width, true)
	draw_line(joint, finish, fill, width, true)
	draw_circle(joint, width * 0.55, fill)


func _draw_shape(points: PackedVector2Array, fill: Color, ink: Color, width: float) -> void:
	if points.size() < 3:
		return
	draw_colored_polygon(points, fill)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, ink, width, true)


func _draw_player_label() -> void:
	var body: Color = skin.palette.get(&"body", _fighter.color)
	var label_y := minf(-Player.HALF.y - 48.0, skin.visual_bounds.position.y - 6.0)
	draw_string(ThemeDB.fallback_font, Vector2(-12.0, label_y),
		"P%d" % (_fighter.index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14,
		body.lightened(0.45))
