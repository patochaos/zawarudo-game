extends Control

## Read-only teaching view. Playback reads snapshots and never installs them
## into the live simulation, so closing it cannot alter the next plan.
const FONT := preload("res://assets/fonts/AtkinsonHyperlegible-Regular.ttf")
var gm
var frames: Array[Dictionary] = []
var cursor := 0.0
var paused := false


func _ready() -> void:
	size = Vector2(1280.0, 720.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	z_index = 100
	_add_button(Vector2(32, 662), Vector2(190, 42), "PLAY / PAUSE", func():
		if cursor >= frames.size() - 1: cursor = 0.0
		paused = not paused)
	_add_button(Vector2(234, 662), Vector2(150, 42), "BACK A FRAME", func(): seek(-1))
	_add_button(Vector2(396, 662), Vector2(150, 42), "NEXT FRAME", func(): seek(1))
	_add_button(Vector2(928, 662), Vector2(320, 42), "RETURN TO MY PLAN", func(): visible = false)


func open_last_turn() -> bool:
	if gm.online_mode or gm._touch_controls.enabled or gm.state != Phase.PLANNING or gm._replay_frames.is_empty():
		return false
	frames.clear()
	var previous: int = gm._replay_frames.back()["turn"]
	for frame in gm._replay_frames:
		if int(frame["turn"]) == previous:
			frames.append(frame)
	cursor = 0.0
	paused = false
	visible = not frames.is_empty()
	queue_redraw()
	return visible


func seek(ticks: int) -> void:
	cursor = clampf(cursor + ticks, 0.0, maxf(0.0, frames.size() - 1))
	paused = true
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	if gm.state != Phase.PLANNING or gm.online_mode:
		visible = false
		return
	if not paused:
		cursor = minf(cursor + delta * Engine.physics_ticks_per_second * 0.35, frames.size() - 1)
		if cursor >= frames.size() - 1:
			paused = true
	queue_redraw()


func _draw() -> void:
	if frames.is_empty():
		return
	var frame: Dictionary = frames[int(cursor)]
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.018, 0.014, 0.03, 1.0))
	for zone in gm.zones:
		draw_rect(zone["rect"], Color(0.52, 0.38, 0.92, 0.12))
		draw_rect(zone["rect"], Color(0.74, 0.62, 1.0, 0.4), false, 1.0)
	for stone in gm.lodestones:
		draw_arc(stone["at"], float(stone["radius"]), 0.0, TAU, 40, Color(1.0, 0.76, 0.34, 0.25), 1.0)
		draw_circle(stone["at"], 6.0, Color(1.0, 0.76, 0.34, 0.9))
	for pf in frame["platforms"]:
		var rect: Rect2 = pf["rect"]
		if not bool(pf.get("present", true)):
			draw_rect(rect, Color(0.42, 0.96, 0.74, 0.25), false, 1.0)
			continue
		draw_rect(rect, Color(0.07, 0.09, 0.14))
		draw_line(rect.position, Vector2(rect.end.x, rect.position.y),
			Color(0.42, 0.96, 0.74) if pf.has("cycle") else Color(0.5, 0.48, 0.35), 2.0)
	for hazard in frame["hazards"]:
		draw_arc(hazard["position"], Hazard.RADIUS, 0.0, TAU, 24,
			Color(0.4, 0.9, 1.0, 0.9 if hazard["charged"] else 0.25), 2.0)
	for i in frame["players"].size():
		var p: Dictionary = frame["players"][i]
		var col: Color = gm.PLAYER_COLORS[i]
		# A short trail keeps the route readable when stepping through a landing.
		for t in range(maxi(1, int(cursor) - 12), int(cursor) + 1):
			var a: Vector2 = frames[t - 1]["players"][i]["position"]
			var b: Vector2 = frames[t]["players"][i]["position"]
			if a.distance_squared_to(b) < 40000.0:
				draw_line(a, b, Color(col, 0.3), 2.0)
		var at: Vector2 = p["position"]
		if p["alive"]:
			if not _draw_recorded_fighter(i, p, int(frame["world_tick"])):
				draw_circle(at + Vector2(0.0, -17.0), 6.0, col)
				draw_line(at + Vector2(0.0, -10.0), at + Vector2(0.0, 8.0), col, 4.0)
				for side in [-1.0, 1.0]:
					draw_line(at + Vector2(0.0, 8.0), at + Vector2(side * 9.0, 24.0), col, 3.0)
					draw_line(at + Vector2(0.0, -5.0), at + Vector2(side * 13.0, 4.0), col, 3.0)
		else:
			draw_line(at - Vector2(10, 10), at + Vector2(10, 10), col, 3.0)
			draw_line(at + Vector2(-10, 10), at + Vector2(10, -10), col, 3.0)
		draw_string(FONT, at + Vector2(-10, -31), "P%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	for arrow in frame["arrows"]:
		var at: Vector2 = arrow["position"]
		var dir: Vector2 = arrow["vel"].normalized()
		var col: Color = arrow["color"]
		draw_line(at - dir * 10.0, at + dir * 10.0, col.lightened(0.3), 3.0)
		draw_line(at + dir * 10.0, at + dir * 4.0 + dir.orthogonal() * 4.0, col, 2.0)
		draw_line(at + dir * 10.0, at + dir * 4.0 - dir.orthogonal() * 4.0, col, 2.0)
	for effect in frame["effects"]:
		if effect["kind"] == Effects.Kind.KILL:
			draw_arc(effect["pos"], 22.0, 0.0, TAU, 24, Color(1.0, 0.38, 0.32), 3.0)
			draw_string(FONT, effect["pos"] + Vector2(25, -10), "HIT", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.6, 0.5))
	var title := "LAST TURN %d  ·  %.2fs  ·  %s" % [frame["turn"], cursor * gm.tick_dt(), "PAUSED" if paused else "SLOW REVIEW"]
	draw_rect(Rect2(0, 0, 1280, 58), Color(0.04, 0.03, 0.065))
	draw_string(FONT, Vector2(32, 25), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	draw_string(FONT, Vector2(32, 47), "SPACE PLAY / PAUSE · , / . STEP · V / ESC RETURN TO YOUR PLAN", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.77, 0.85))


func _draw_recorded_fighter(i: int, p: Dictionary, tick: int) -> bool:
	var visual = gm.players[i].get_node_or_null("FighterVisual")
	if visual == null or visual.skin == null:
		return false
	var skin: FighterSkin = visual.skin
	var velocity: Vector2 = p["vel"]
	var pose: StringName = FighterVisual.IDLE
	if not p["on_ground"]:
		pose = FighterVisual.RISE if velocity.y < 0.0 else FighterVisual.FALL
	elif absf(velocity.x) > 24.0:
		pose = FighterVisual.WALK if skin.has_sprite(FighterVisual.WALK) else FighterVisual.RUN
	if not skin.has_sprite(pose):
		return false
	var cell := Vector2(skin.sprite_cell_size)
	var number := skin.motion_frame(pose, tick, velocity)
	var source := Rect2(Vector2(number * cell.x, 0.0), cell)
	draw_set_transform(p["position"], 0.0, Vector2(float(p["facing"]), 1.0))
	draw_texture_rect_region(skin.sprite_atlases[pose], skin.sprite_draw_rect, source, skin.sprite_tint)
	draw_set_transform(Vector2.ZERO)
	return true


func _add_button(at: Vector2, dimensions: Vector2, text: String, action: Callable) -> void:
	var button := Button.new()
	button.position = at
	button.size = dimensions
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 17)
	button.pressed.connect(action)
	add_child(button)
