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

const KEY_ICONS := {
	KEY_A: &"key_a",
	KEY_D: &"key_d",
	KEY_S: &"key_s",
	KEY_SPACE: &"key_space",
	KEY_SHIFT: &"key_shift",
	KEY_T: &"key_t",
	KEY_R: &"key_r",
	KEY_F: &"key_f",
	KEY_ENTER: &"key_enter",
	KEY_KP_ENTER: &"key_enter",
	KEY_ESCAPE: &"key_escape",
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


static func draw_key_sequence(canvas: CanvasItem, codes: Array, origin: Vector2,
		tint: Color, icon_size: float = 20.0, gap: float = 3.0) -> void:
	for i in codes.size():
		var rect := Rect2(origin + Vector2(float(i) * (icon_size + gap), 0.0),
			Vector2(icon_size, icon_size))
		var prompt_id: StringName = KEY_ICONS.get(int(codes[i]), &"")
		if prompt_id != &"":
			draw_icon(canvas, prompt_id, rect, tint)
			continue
		# Rebound keys outside the curated icon subset still get a legible Kenney
		# keycap instead of falling back to stale default artwork.
		canvas.draw_rect(rect, Color(tint.r, tint.g, tint.b, tint.a * 0.10))
		canvas.draw_rect(rect, tint, false, 1.2)
		var key_name := OS.get_keycode_string(int(codes[i])).to_upper()
		if key_name.length() > 4:
			key_name = key_name.left(4)
		canvas.draw_string(HUD_FONT, rect.position + Vector2(1.0, icon_size * 0.68), key_name,
			HORIZONTAL_ALIGNMENT_CENTER, icon_size - 2.0, 7, tint)
