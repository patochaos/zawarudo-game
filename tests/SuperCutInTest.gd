extends SceneTree

const SUPER_CUT_IN := preload("res://scripts/SuperFreezeFrame.gd")
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var cut_in = SUPER_CUT_IN.new()
	root.add_child(cut_in)
	await process_frame
	var texture: ImageTexture = cut_in._art._tone_texture
	_check(texture != null, "the SUPER screen tone must be cached into one texture")
	if texture != null:
		_check(texture.get_width() == 1280 and texture.get_height() == 430,
			"the cached tone must cover the full animated panel")
	cut_in.play(0, Color(1.0, 0.75, 0.25))
	_check(cut_in.is_active(), "the optimized SUPER cut-in must still start normally")
	cut_in.cancel()
	_check(not cut_in.is_active(), "the optimized SUPER cut-in must still cancel normally")
	cut_in.queue_free()

	if _failures == 0:
		print("SUPER cut-in: all tests passed")
	else:
		push_error("SUPER cut-in: %d test(s) failed" % _failures)
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
