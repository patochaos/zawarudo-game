extends Node

## Kenney's neutral outline cursors keep mouse interactions legible without
## importing a second UI style. Hotspots match the artwork's visible tips.

const POINTER := preload("res://assets/kenney/cursor/pointer_b.png")
const POINTING_HAND := preload("res://assets/kenney/cursor/hand_thin_point.png")
const DISABLED := preload("res://assets/kenney/cursor/cursor_disabled.png")
const BUSY := preload("res://assets/kenney/cursor/cursor_busy.png")


func _ready() -> void:
	Input.set_custom_mouse_cursor(POINTER, Input.CURSOR_ARROW, Vector2(16.0, 12.0))
	Input.set_custom_mouse_cursor(POINTING_HAND, Input.CURSOR_POINTING_HAND, Vector2(9.0, 9.0))
	Input.set_custom_mouse_cursor(DISABLED, Input.CURSOR_FORBIDDEN, Vector2(16.0, 12.0))
	Input.set_custom_mouse_cursor(BUSY, Input.CURSOR_BUSY, Vector2(16.0, 12.0))


func _exit_tree() -> void:
	# Visual tests free the main scene before the rendering server shuts down.
	# Release the global cursor references with it so their textures do not leak.
	for shape in [Input.CURSOR_ARROW, Input.CURSOR_POINTING_HAND,
			Input.CURSOR_FORBIDDEN, Input.CURSOR_BUSY]:
		Input.set_custom_mouse_cursor(null, shape)
