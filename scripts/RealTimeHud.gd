extends CanvasLayer

var gm
var title: Label
var hint: Label
const FONT := preload("res://assets/kenney/fonts/kenney-future-narrow.ttf")


func _ready() -> void:
	layer = 5
	title = _label(Vector2(260, 12), Vector2(760, 26), 16)
	title.text = "REAL TIME // DUELIST VS CPU"
	hint = _label(Vector2(100, 670), Vector2(1080, 45), 12)
	visible = false


func _label(at: Vector2, dimensions: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.size = dimensions
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.86, 0.84, 0.75))
	label.add_theme_color_override("font_outline_color", Color(0.01, 0.01, 0.025))
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	return label


func _process(_delta: float) -> void:
	visible = (gm.real_time_mode and gm.state == Phase.FREEPLAY) or gm.class_lab
	title.position.y = 143.0 if gm.class_lab and not gm.real_time_mode else 12.0
	if gm.class_lab:
		title.text = "CLASS LAB // %s VS %s // %s" % [Roster.short_name(gm.player_weapons[0]), Roster.short_name(gm.player_weapons[1]), "REAL TIME" if gm.real_time_mode else "PLANNING"]
		hint.text = "1–4 P1 · 5–8 CPU: DUELIST / ROOK / PULSE / ECLIPSE · T SWITCH MODE (RESTART) · ESC MENU\n" + ClassLab.COPY[ClassLab.ORDER.find(gm.player_weapons[0])]
		return
	title.text = "REAL TIME // DUELIST VS CPU"
	if visible:
		hint.text = "A/D MOVE · SPACE JUMP · HOLD/RELEASE LMB THROW (%.1fS RELOAD) · H GUIDE %s · R RESET · ESC MENU" % [gm.real_time_throw_cooldown, "ON" if gm.real_time_aim_guide else "OFF"]
