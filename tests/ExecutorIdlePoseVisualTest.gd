extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const VisualCapture := preload("res://tests/VisualCaptureHelper.gd")
const EXECUTOR_IDLE := preload("res://assets/art/fighters/gilded-executor-idle-v1.png")
const TARGET_HEIGHT := 128.0


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game.start_quick_match(false, 0, 2)
	game._transition.visible = false
	game.vs_ai = false
	game.state = Phase.PLANNING
	game._preview.visible = false

	var player: Player = game.players[0]
	player.draw_legacy_visual = false
	var sprite := Sprite2D.new()
	sprite.name = "ExecutorIdleArtPreview"
	sprite.texture = EXECUTOR_IDLE
	sprite.z_index = 4
	var used := EXECUTOR_IDLE.get_image().get_used_rect()
	var art_scale := TARGET_HEIGHT / float(used.size.y)
	sprite.scale = Vector2.ONE * art_scale
	# Sprite2D is centered on the full source canvas. Offset it so the lowest
	# non-transparent pixel meets the unchanged local collision foot line y=24.
	var used_bottom_from_center := float(used.end.y) - EXECUTOR_IDLE.get_height() * 0.5
	sprite.position.y = Player.HALF.y - used_bottom_from_center * art_scale
	player.add_child(sprite)

	game.banner_text = "ART PREVIEW — EXECUTOR IDLE V1 / 128 PX"
	game.banner_color = Color(1.0, 0.82, 0.34)
	game.banner_time = 4.0
	game._ui.refresh()
	await VisualCapture.await_transition(self, game, 5)

	var error := VisualCapture.save(self, "res://previews/executor-idle-pose-v1.png",
		"Executor idle preview")
	root.remove_child(game)
	game.free()
	await process_frame
	quit(error)
