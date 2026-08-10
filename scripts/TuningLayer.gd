extends CanvasLayer

## Live tuning readout for the free-play sandbox. Values are edited on the
## GameManager directly, so anything changed here is immediately what the real
## simulation uses — walk out of free play and the match plays with your numbers.
##
## Derived figures (apex, hang time, distance covered in one window) are the ones
## that actually decide how the game feels, so they are shown alongside the raw
## values rather than left for you to work out.

const PARAMS := [
	{"label": "move speed",      "prop": "player_move_speed",       "step": 10.0,  "min": 40.0,  "max": 800.0,  "dp": 0},
	{"label": "ground accel",    "prop": "player_acceleration",     "step": 100.0, "min": 200.0, "max": 8000.0, "dp": 0},
	{"label": "air accel",       "prop": "player_air_acceleration", "step": 50.0,  "min": 50.0,  "max": 4000.0, "dp": 0},
	{"label": "jump impulse",    "prop": "jump_impulse",            "step": 20.0,  "min": 200.0, "max": 1600.0, "dp": 0},
	{"label": "jump cut",        "prop": "jump_cut",                "step": 0.05,  "min": 0.10,  "max": 1.0,    "dp": 2},
	{"label": "gravity",         "prop": "gravity",                 "step": 50.0,  "min": 200.0, "max": 4000.0, "dp": 0},
	{"label": "max fall speed",  "prop": "max_fall_speed",          "step": 50.0,  "min": 200.0, "max": 3000.0, "dp": 0},
	{"label": "knife speed min", "prop": "arrow_speed_min",         "step": 20.0,  "min": 100.0, "max": 1200.0, "dp": 0},
	{"label": "knife speed max", "prop": "arrow_speed_max",         "step": 20.0,  "min": 200.0, "max": 2000.0, "dp": 0},
	{"label": "knife gravity",   "prop": "arrow_gravity",           "step": 10.0,  "min": 0.0,   "max": 1200.0, "dp": 0},
	{"label": "charge time",     "prop": "charge_time",             "step": 0.05,  "min": 0.10,  "max": 4.0,    "dp": 2},
	{"label": "exec window",     "prop": "execution_duration",      "step": 0.05,  "min": 0.20,  "max": 2.00,   "dp": 2},
]

const DIM := Color(0.60, 0.65, 0.74)
const HOT := Color(1.0, 0.93, 0.60)

var gm
var cursor: int = 0

var _rows: Array[Label] = []
var _title: Label
var _derived: Label
var _live: Label
var _hint: Label
var _defaults: Dictionary = {}


func build(manager) -> void:
	gm = manager
	layer = 5

	var bg := ColorRect.new()
	bg.position = Vector2(16.0, 12.0)
	bg.size = Vector2(340.0, 470.0)
	bg.color = Color(0.07, 0.08, 0.12, 0.90)
	add_child(bg)

	_title = _label(Vector2(30.0, 20.0), 320.0, 20, Color(0.92, 0.95, 1.0))
	_title.text = "FREE PLAY — TUNING"

	for i in PARAMS.size():
		_rows.append(_label(Vector2(30.0, 52.0 + float(i) * 24.0), 316.0, 16, DIM))

	# _derived runs to four lines, so _live has to clear all of them
	_derived = _label(Vector2(30.0, 326.0), 316.0, 15, Color(0.55, 0.85, 0.70))
	_live = _label(Vector2(30.0, 428.0), 316.0, 15, Color(0.70, 0.76, 0.86))

	_hint = _label(Vector2(16.0, 672.0), 1248.0, 14, Color(0.55, 0.60, 0.70))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.text = "A/D run · W jump · MOUSE aim · hold LMB draw, release to fire     " \
		+ "↑/↓ pick value · ←/→ change (SHIFT = ×5) · BACKSPACE reset all · R reset arena · ESC menu"

	for p in PARAMS:
		_defaults[p["prop"]] = gm.get(p["prop"])
	refresh()


func _label(pos: Vector2, w: float, size: int, col: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(w, 120.0)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	add_child(l)
	return l


func handle_key(code: int, shift: bool) -> bool:
	match code:
		KEY_UP:
			cursor = posmod(cursor - 1, PARAMS.size())
		KEY_DOWN:
			cursor = posmod(cursor + 1, PARAMS.size())
		KEY_LEFT:
			_nudge(-1.0, shift)
		KEY_RIGHT:
			_nudge(1.0, shift)
		KEY_BACKSPACE:
			for p in PARAMS:
				gm.set(p["prop"], _defaults[p["prop"]])
		_:
			return false
	refresh()
	return true


func _nudge(sign_: float, shift: bool) -> void:
	var p: Dictionary = PARAMS[cursor]
	var v: float = float(gm.get(p["prop"])) + sign_ * p["step"] * (5.0 if shift else 1.0)
	gm.set(p["prop"], clampf(v, p["min"], p["max"]))
	# keep the knife speed range from inverting
	if gm.arrow_speed_max < gm.arrow_speed_min:
		if p["prop"] == "arrow_speed_min":
			gm.arrow_speed_max = gm.arrow_speed_min
		else:
			gm.arrow_speed_min = gm.arrow_speed_max


func refresh() -> void:
	for i in PARAMS.size():
		var p: Dictionary = PARAMS[i]
		var v: float = float(gm.get(p["prop"]))
		var txt := "%-16s %s" % [p["label"], String.num(v, p["dp"])]
		_rows[i].text = ("> " + txt) if i == cursor else ("  " + txt)
		_rows[i].add_theme_color_override("font_color", HOT if i == cursor else DIM)

	# what the numbers actually mean in play
	var apex: float = gm.jump_impulse * gm.jump_impulse / (2.0 * maxf(gm.gravity, 1.0))
	var hang: float = 2.0 * gm.jump_impulse / maxf(gm.gravity, 1.0)
	var run: float = gm.player_move_speed * gm.execution_duration
	var spin: float = gm.player_move_speed / maxf(gm.player_acceleration, 1.0)
	# best-case range for a half-drawn shot, i.e. launched at 45 degrees
	var mid: float = lerpf(gm.arrow_speed_min, gm.arrow_speed_max, 0.5)
	_derived.text = "jump apex  %.0f px      hang %.2f s\nrun in one window  %.0f px\ntime to top speed  %.2f s\nbest range at 50%% draw  %.0f px" % [
		apex, hang, run, spin, mid * mid / maxf(gm.arrow_gravity, 1.0),
	]

	var pl = gm.players[0]
	_live.text = "speed %4.0f,%4.0f   %s   knives %d" % [
		pl.vel.x, pl.vel.y, "grounded" if pl.on_ground else "airborne", gm.arrows.size(),
	]
