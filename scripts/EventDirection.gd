extends Node2D
class_name EventDirection

## Event-driven palette presets, spotlights and impact crops. One grammar for
## the four theatrical beats: LOCK (a plan is confirmed), IMPACT (a fighter is
## hit), SUPER (the cut-in's three beats) and RESULT (the final tableau).
##
## Everything here is a cosmetic observer on wall time. It draws in world space
## above the fighters and below the HUD layer, and never reads back into the
## simulation, replay or the lockstep digest.
##
## A palette preset is a multiply tint (pulls the whole frame toward a hue) and
## an additive lift (crushes it toward a second value). Reduced flashes keeps
## the tint, drops the lift and shortens every transition.

const W := 1280.0
const H := 720.0
const DISPLAY_FONT := preload("res://assets/kenney/fonts/kenney-future.ttf")

## mul: multiply colour at full strength. add: additive lift at full strength.
## hold: seconds at full strength. fade: seconds back to base. steps: 0 for a
## smooth return, otherwise the return happens in that many hard steps.
const PRESETS := {
	"lock": {"mul": Color(0.74, 0.68, 0.92), "add": Color(0.015, 0.0, 0.05),
		"hold": 0.16, "fade": 0.26, "steps": 0},
	"impact": {"mul": Color(1.0, 0.70, 0.50), "add": Color(0.22, 0.05, 0.0),
		"hold": 0.09, "fade": 0.20, "steps": 3},
	"super": {"mul": Color(0.40, 0.24, 0.62), "add": Color(0.06, 0.0, 0.14),
		"hold": 0.0, "fade": 0.10, "steps": 0},
	"result": {"mul": Color(0.70, 0.66, 0.86), "add": Color(0.0, 0.0, 0.03),
		"hold": 0.0, "fade": 0.0, "steps": 0},
}
const REDUCED_TIME_SCALE := 0.6
const SPOT_RADIUS := 118.0
const TABLEAU_RADIUS := 170.0

var gm
var reduced_flashes: bool = false
## Active events: {kind, t, life, hold, fade, steps, at, color, word, player, index}
var _events: Array = []
var _tableau: Dictionary = {}
var _mul_rect: ColorRect
var _add_rect: ColorRect
var _seq: int = 0


func _ready() -> void:
	_mul_rect = _blend_rect(CanvasItemMaterial.BLEND_MODE_MUL)
	_add_rect = _blend_rect(CanvasItemMaterial.BLEND_MODE_ADD)
	set_process(true)


func _blend_rect(mode: int) -> ColorRect:
	var rect := ColorRect.new()
	rect.position = Vector2.ZERO
	rect.size = Vector2(W, H)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := CanvasItemMaterial.new()
	material.blend_mode = mode
	rect.material = material
	rect.visible = false
	add_child(rect)
	return rect


# ------------------------------------------------------------------ events --

## A confirmed plan: short spotlight on the confirming fighter and a word
## struck beside the body. Public readiness theatre only.
func lock_in(player_index: int, at: Vector2, color: Color) -> void:
	_push("lock", at, color, "DECIDED", player_index)


## A fighter is hit: warm crushed grade, a diagonal crop through the impact
## and the event's own word. Returns to base in hard steps.
func impact(at: Vector2, color: Color, word: String = "SNAP") -> void:
	_push("impact", at, color, word, -1)


## The SUPER cut-in's beats, timed to the pause GameManager owns: the world
## collapses to two values while the panel is up and tears back at release.
func super_beats(player_index: int, color: Color, duration: float) -> void:
	var event := _push("super", Vector2(W * 0.5, H * 0.5), color, "", player_index)
	event["life"] = duration
	event["hold"] = maxf(0.0, duration - float(PRESETS["super"]["fade"]))


## The final tableau: a subdued grade with an asymmetric spotlight that holds
## until the result screen is left. `winner` -1 (a draw or a team result)
## keeps the grade and skips the spotlight.
func tableau(winner: int) -> void:
	_tableau = {"winner": winner, "t": 0.0}
	queue_redraw()


func clear() -> void:
	_events.clear()
	_tableau.clear()
	_apply_palette(Color.WHITE, Color.BLACK)
	queue_redraw()


func active_kinds() -> Array:
	var out: Array = []
	for event in _events:
		out.append(event["kind"])
	return out


func _push(kind: String, at: Vector2, color: Color, word: String, player: int) -> Dictionary:
	var preset: Dictionary = PRESETS[kind]
	var scale: float = REDUCED_TIME_SCALE if reduced_flashes else 1.0
	_seq += 1
	var event := {
		"kind": kind, "t": 0.0, "at": at, "color": color, "word": word,
		"player": player, "index": _seq,
		"hold": float(preset["hold"]) * scale, "fade": float(preset["fade"]) * scale,
		"steps": 0 if reduced_flashes else int(preset["steps"]),
	}
	event["life"] = event["hold"] + event["fade"]
	_events.append(event)
	queue_redraw()
	return event


# ----------------------------------------------------------------- ageing --

func _process(delta: float) -> void:
	var live: Array = []
	for event in _events:
		event["t"] = float(event["t"]) + delta
		if float(event["t"]) < float(event["life"]):
			live.append(event)
	_events = live
	if not _tableau.is_empty():
		_tableau["t"] = float(_tableau["t"]) + delta
	_apply_palette(current_mul(), current_add())
	visible = gm == null or gm.state in [Phase.PLANNING, Phase.COMMITTING, Phase.EXECUTING,
		Phase.GAME_OVER, Phase.REPLAY, Phase.ONLINE_WAIT]
	queue_redraw()


## 1 during the hold, then down to 0 across the fade, in hard steps when the
## preset asks for them.
func strength(event: Dictionary) -> float:
	var t: float = float(event["t"])
	var hold: float = float(event["hold"])
	var fade: float = float(event["fade"])
	if event["kind"] == "super":
		# Anticipation ramps in over the first beat, then holds, then releases.
		var ramp: float = clampf(t / 0.12, 0.0, 1.0)
		if t < hold:
			return ramp
		return clampf((float(event["life"]) - t) / maxf(fade, 0.001), 0.0, 1.0) * ramp
	if t <= hold:
		return 1.0
	var remaining: float = clampf((hold + fade - t) / maxf(fade, 0.001), 0.0, 1.0)
	var steps: int = int(event["steps"])
	if steps > 0:
		return ceilf(remaining * float(steps)) / float(steps)
	return remaining


func current_mul() -> Color:
	var mul := Color.WHITE
	if not _tableau.is_empty():
		var settle: float = clampf(float(_tableau["t"]) / 0.4, 0.0, 1.0)
		mul = mul.lerp(PRESETS["result"]["mul"], settle)
	for event in _events:
		mul = mul.lerp(PRESETS[event["kind"]]["mul"], strength(event))
	return mul


func current_add() -> Color:
	var add := Color.BLACK
	if reduced_flashes:
		return add
	if not _tableau.is_empty():
		var settle: float = clampf(float(_tableau["t"]) / 0.4, 0.0, 1.0)
		add += PRESETS["result"]["add"] * settle
	for event in _events:
		add += PRESETS[event["kind"]]["add"] * strength(event)
	return add


func _apply_palette(mul: Color, add: Color) -> void:
	if _mul_rect == null:
		return
	var tinted: bool = not mul.is_equal_approx(Color.WHITE)
	_mul_rect.visible = tinted
	_mul_rect.color = Color(mul.r, mul.g, mul.b, 1.0)
	var lifted: bool = add.r + add.g + add.b > 0.001
	_add_rect.visible = lifted
	_add_rect.color = Color(add.r, add.g, add.b, 1.0)


# ---------------------------------------------------------------- drawing --

func _draw() -> void:
	for event in _events:
		var s := strength(event)
		if s <= 0.0:
			continue
		match event["kind"]:
			"lock":
				_draw_spotlight(event["at"], SPOT_RADIUS, 0.55 * s)
				_draw_word(event["word"], event["at"] + Vector2(0.0, -96.0), event["color"],
					36, s * 0.9, event["player"])
			"impact":
				_draw_crop(event["at"], s)
				_draw_word(event["word"], event["at"] + Vector2(0.0, -64.0), event["color"],
					44, s, -1)
	if not _tableau.is_empty() and gm != null:
		_draw_tableau()


## A dark pane with one circular hole: everything but the focal fighter dims.
## Built from simple pieces (four strips around the circle's box and four
## concave corners) so it stays a valid polygon set even when the circle runs
## off the screen edge.
func _draw_spotlight(at: Vector2, radius: float, alpha: float) -> void:
	if alpha <= 0.0:
		return
	var ink := Color(0.02, 0.0, 0.05, alpha)
	var box := Rect2(at - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
	draw_rect(Rect2(0.0, 0.0, W, box.position.y), ink)
	draw_rect(Rect2(0.0, box.end.y, W, H - box.end.y), ink)
	draw_rect(Rect2(0.0, box.position.y, box.position.x, box.size.y), ink)
	draw_rect(Rect2(box.end.x, box.position.y, W - box.end.x, box.size.y), ink)
	# Each corner: the box corner, the two tangent points and the arc between.
	var corners := [
		[Vector2(-1.0, -1.0), -PI * 0.5, -PI],
		[Vector2(1.0, -1.0), -PI * 0.5, 0.0],
		[Vector2(1.0, 1.0), PI * 0.5, 0.0],
		[Vector2(-1.0, 1.0), PI * 0.5, PI],
	]
	for corner in corners:
		var sign: Vector2 = corner[0]
		var from_angle: float = corner[1]
		var to_angle: float = corner[2]
		var points := PackedVector2Array([at + sign * radius])
		for i in 17:
			var angle: float = lerpf(from_angle, to_angle, float(i) / 16.0)
			points.append(at + Vector2.from_angle(angle) * radius)
		draw_colored_polygon(points, ink)
	draw_arc(at, radius, 0.0, TAU, 64, Color(1.0, 0.92, 0.70, alpha * 0.8), 1.5)


## Two dark wedges leave a diagonal band through the impact: one focal point,
## one hard shadow edge, no full-screen white.
func _draw_crop(at: Vector2, s: float) -> void:
	var half := 150.0 + (1.0 - s) * 120.0
	var angle := -PI / 7.0
	draw_set_transform(at, angle)
	var ink := Color(0.02, 0.0, 0.05, 0.62 * s)
	draw_rect(Rect2(-2400.0, -2400.0, 4800.0, 2400.0 - half), ink)
	draw_rect(Rect2(-2400.0, half, 4800.0, 2400.0), ink)
	# One hard shadow under the lower edge of the band.
	draw_rect(Rect2(-2400.0, half - 7.0, 4800.0, 7.0), Color(0.0, 0.0, 0.0, 0.85 * s))
	draw_line(Vector2(-2400.0, -half), Vector2(2400.0, -half), Color(1.0, 0.86, 0.56, 0.9 * s), 2.0)
	draw_set_transform(Vector2.ZERO)


func _draw_word(word: String, at: Vector2, color: Color, size: int, alpha: float, player: int) -> void:
	if word == "" or alpha <= 0.0:
		return
	var width := 420.0
	var origin := Vector2(clampf(at.x - width * 0.5, 8.0, W - width - 8.0), clampf(at.y, 80.0, H - 40.0))
	var accent: Color = color.lightened(0.25)
	draw_string(DISPLAY_FONT, origin + Vector2(3.0, 3.0), word, HORIZONTAL_ALIGNMENT_CENTER,
		width, size, Color(0.0, 0.0, 0.0, alpha * 0.9))
	draw_string(DISPLAY_FONT, origin, word, HORIZONTAL_ALIGNMENT_CENTER, width, size,
		Color(accent.r, accent.g, accent.b, alpha))
	if player >= 0:
		draw_line(origin + Vector2(width * 0.5 - 60.0, 8.0), origin + Vector2(width * 0.5 + 60.0, 8.0),
			Color(accent.r, accent.g, accent.b, alpha * 0.7), 2.0)


## Winner lit, loser held in the real defeat silhouette under a dimmer halo.
func _draw_tableau() -> void:
	var settle: float = clampf(float(_tableau["t"]) / 0.4, 0.0, 1.0)
	var winner: int = int(_tableau["winner"])
	if winner < 0 or winner >= gm.players.size():
		return
	var champion = gm.players[winner]
	_draw_spotlight(champion.position, TABLEAU_RADIUS, 0.42 * settle)
	var gold: Color = champion.color.lightened(0.3)
	draw_arc(champion.position, TABLEAU_RADIUS + 12.0, 0.0, TAU, 64,
		Color(gold.r, gold.g, gold.b, 0.35 * settle), 1.0)
	for p in gm.players:
		if p.index == winner:
			continue
		var dim: Color = p.color
		draw_circle(p.position, 46.0, Color(dim.r, dim.g, dim.b, 0.06 * settle))
		draw_arc(p.position, 46.0, 0.0, TAU, 32, Color(dim.r, dim.g, dim.b, 0.28 * settle), 1.0)
