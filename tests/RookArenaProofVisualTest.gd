extends SceneTree

const ATLAS_PATH := "res://assets/art/fighters/rook-animated-v1/arena-proof.png"
const VisualCapture := preload("res://tests/VisualCaptureHelper.gd")
const CELL_SIZE := Vector2(384.0, 256.0)
const DRAW_SIZE := Vector2(87.0, 58.0)


class ProofStage extends Node2D:
	func _draw() -> void:
		for band in 24:
			var amount := float(band) / 23.0
			var color := Color(0.025, 0.018, 0.055).lerp(
				Color(0.12, 0.055, 0.17), amount * amount
			)
			draw_rect(Rect2(0.0, amount * 620.0, 1280.0, 28.0), color)
		draw_circle(Vector2(930.0, 325.0), 112.0, Color(0.20, 0.75, 0.82, 0.065))
		draw_circle(Vector2(902.0, 313.0), 105.0, Color(0.035, 0.022, 0.07, 0.78))
		for platform in [
			Rect2(0.0, 620.0, 1280.0, 100.0),
			Rect2(70.0, 500.0, 230.0, 16.0),
			Rect2(980.0, 500.0, 230.0, 16.0),
			Rect2(280.0, 410.0, 190.0, 16.0),
			Rect2(810.0, 410.0, 190.0, 16.0),
			Rect2(500.0, 250.0, 280.0, 16.0),
			Rect2(520.0, 515.0, 240.0, 16.0),
		]:
			draw_rect(platform, Color(0.045, 0.025, 0.075))
			draw_rect(Rect2(platform.position, Vector2(platform.size.x, 4.0)),
				Color(0.72, 0.46, 0.13))


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var stage := ProofStage.new()
	root.add_child(stage)
	var image := Image.load_from_file(ProjectSettings.globalize_path(ATLAS_PATH))
	if image.is_empty():
		push_error("Could not load Rook arena proof atlas")
		quit(1)
		return
	var atlas := ImageTexture.create_from_image(image)
	var x_positions := [150.0, 465.0, 800.0, 1110.0]
	for index in 4:
		var region := AtlasTexture.new()
		region.atlas = atlas
		region.region = Rect2(Vector2(float(index) * CELL_SIZE.x, 0.0), CELL_SIZE)
		var sprite := Sprite2D.new()
		sprite.texture = region
		sprite.scale = DRAW_SIZE / CELL_SIZE
		sprite.position = Vector2(x_positions[index], 595.078125)
		stage.add_child(sprite)
	var title := Label.new()
	title.text = "ROOK ARENA-SCALE PROOF  /  87x58 DRAW RECT  /  51 PX BODY READ"
	title.position = Vector2(290.0, 145.0)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.34))
	title.add_theme_font_size_override("font_size", 18)
	stage.add_child(title)
	for i in 5:
		await process_frame
	var error := VisualCapture.save(self,
		"res://previews/rook-arena-scale-proof-v1.png", "Rook arena proof",
		Vector2i(1280, 720))
	root.remove_child(stage)
	stage.free()
	await process_frame
	quit(error)
