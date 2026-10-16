extends Control

## A view of recorded simulation time, separate from the real planning clock.
## No prediction of another player's hidden plan is used here.
var gm
var FONT: Font = preload("res://assets/fonts/AtkinsonHyperlegible-Regular.ttf")
const LEFT := 54.0
const WIDTH := 300.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2(450.0, 66.0)
	size = Vector2(370.0, 72.0)


func _process(_delta: float) -> void:
	visible = gm != null and gm.state == Phase.PLANNING and not gm.close_camera_mode
	if visible:
		queue_redraw()


func visible_players() -> Array[int]:
	var result: Array[int] = []
	for p in gm.players:
		if p.alive and gm._is_locally_controlled(p.index) and gm.player_roles[p.index] != "DUMMY":
			result.append(p.index)
	return result


func _draw() -> void:
	if gm == null:
		return
	var slots := visible_players()
	if slots.is_empty():
		return
	var height := 24.0 + slots.size() * 24.0
	draw_rect(Rect2(0.0, 0.0, size.x, height), Color(0.025, 0.02, 0.045, 0.88))
	draw_string(FONT, Vector2(12.0, 16.0), "PLAN", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.83, 0.9))
	draw_string(FONT, Vector2(LEFT + WIDTH - 70.0, 16.0), "NEXT FREEZE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.83, 0.9))
	for row in slots.size():
		var i: int = slots[row]
		var plan: PlayerPlan = gm.players[i].plan
		var y := 34.0 + row * 24.0
		var col: Color = gm.PLAYER_COLORS[i]
		var total: float = maxf(1.0, gm.exec_ticks())
		var recorded := WIDTH * plan.recorded_ticks() / total
		draw_string(FONT, Vector2(12.0, y + 4.0), gm.player_tag(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
		draw_line(Vector2(LEFT, y), Vector2(LEFT + WIDTH, y), Color(0.22, 0.24, 0.3), 5.0)
		draw_line(Vector2(LEFT, y), Vector2(LEFT + recorded, y), col, 5.0)
		# Dashes indicate the part that continues under momentum and gravity.
		for x in range(int(LEFT + recorded + 4.0), int(LEFT + WIDTH), 8):
			draw_line(Vector2(x, y), Vector2(minf(x + 3.0, LEFT + WIDTH), y), Color(0.64, 0.68, 0.76), 2.0)
		var budget_x: float = LEFT + WIDTH * gm.movement_tick_budget() / total
		draw_line(Vector2(budget_x, y - 6.0), Vector2(budget_x, y + 6.0), Color(0.7, 0.74, 0.8), 1.0)
		if plan.has_shot():
			var shot_x := LEFT + WIDTH * plan.shot_tick / total
			draw_colored_polygon(PackedVector2Array([Vector2(shot_x, y - 7.0), Vector2(shot_x + 5.0, y), Vector2(shot_x, y + 7.0), Vector2(shot_x - 5.0, y)]), Color.WHITE)
