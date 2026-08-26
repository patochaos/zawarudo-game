extends RefCounted
class_name InputPrompts

## Small, deliberately curated prompt atlas. The source pack contains every
## major controller family; Za Warudo keeps the neutral outline set so a prompt
## can inherit gold, violet or spectral meaning from its context.

const DISPLAY_FONT := preload("res://assets/kenney/fonts/kenney-future.ttf")
const HUD_FONT := preload("res://assets/kenney/fonts/kenney-future-narrow.ttf")

const ICONS := {
	&"key_a": preload("res://assets/kenney/prompts/key-a.png"),
	&"key_d": preload("res://assets/kenney/prompts/key-d.png"),
	&"key_s": preload("res://assets/kenney/prompts/key-s.png"),
	&"key_space": preload("res://assets/kenney/prompts/key-space.png"),
	&"key_shift": preload("res://assets/kenney/prompts/key-shift.png"),
	&"key_t": preload("res://assets/kenney/prompts/key-t.png"),
	&"key_r": preload("res://assets/kenney/prompts/key-r.png"),
	&"key_f": preload("res://assets/kenney/prompts/key-f.png"),
	&"key_enter": preload("res://assets/kenney/prompts/key-enter.png"),
	&"key_escape": preload("res://assets/kenney/prompts/key-escape.png"),
	&"mouse_move": preload("res://assets/kenney/prompts/mouse-move.png"),
	&"mouse_left": preload("res://assets/kenney/prompts/mouse-left.png"),
	&"mouse_right": preload("res://assets/kenney/prompts/mouse-right.png"),
	&"pad_left": preload("res://assets/kenney/prompts/pad-left-stick.png"),
	&"pad_left_down": preload("res://assets/kenney/prompts/pad-left-down.png"),
	&"pad_right": preload("res://assets/kenney/prompts/pad-right-stick.png"),
	&"pad_a": preload("res://assets/kenney/prompts/pad-a.png"),
	&"pad_b": preload("res://assets/kenney/prompts/pad-b.png"),
	&"pad_x": preload("res://assets/kenney/prompts/pad-x.png"),
	&"pad_y": preload("res://assets/kenney/prompts/pad-y.png"),
	&"pad_menu": preload("res://assets/kenney/prompts/pad-menu.png"),
	&"pad_lb": preload("res://assets/kenney/prompts/pad-lb.png"),
	&"pad_rb": preload("res://assets/kenney/prompts/pad-rb.png"),
	&"pad_rt": preload("res://assets/kenney/prompts/pad-rt.png"),
	&"touch_move": preload("res://assets/kenney/prompts/touch-move.png"),
	&"touch_down": preload("res://assets/kenney/prompts/touch-down.png"),
	&"touch_tap": preload("res://assets/kenney/prompts/touch-tap.png"),
	&"touch_hold": preload("res://assets/kenney/prompts/touch-hold.png"),
}


static func icon(id: StringName) -> Texture2D:
	return ICONS.get(id) as Texture2D


static func draw_icon(canvas: CanvasItem, id: StringName, rect: Rect2,
		tint: Color = Color.WHITE) -> void:
	var texture := icon(id)
	if texture != null:
		canvas.draw_texture_rect(texture, rect, false, tint)


static func draw_sequence(canvas: CanvasItem, ids: Array, origin: Vector2,
		tint: Color, icon_size: float = 20.0, gap: float = 3.0) -> void:
	for i in ids.size():
		draw_icon(canvas, StringName(ids[i]), Rect2(origin + Vector2(float(i) * (icon_size + gap), 0.0),
			Vector2(icon_size, icon_size)), tint)
