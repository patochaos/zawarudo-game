extends SceneTree

const MAIN := preload("res://scenes/Main.tscn")
const Capture := preload("res://tests/VisualCaptureHelper.gd")

class SpriteBoard extends Node2D:
	const FONT = preload("res://assets/kenney/fonts/kenney-future.ttf")
	var textures: Dictionary = {}
	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		for version in ["gilded-executor-animated-v1", "duelist-polished-v2"]:
			for pose in ["idle", "run", "shoot", "fall"]:
				textures[version + pose] = load("res://assets/art/fighters/%s/%s.png" % [version, pose])
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1280, 720), Color("12141e"))
		draw_string(FONT, Vector2(42, 45), "DUELIST / SPRITE POLISH", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("e5c978"))
		var poses := ["idle", "run", "shoot", "fall"]
		for col in 4:
			var x := 30.0 + col * 312.0
			draw_string(FONT, Vector2(x, 89), poses[col].to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
			for row in 2:
				var version := "gilded-executor-animated-v1" if row == 0 else "duelist-polished-v2"
				var atlas: Texture2D = textures[version + poses[col]]
				var frame := 1 if poses[col] == "shoot" else 0
				var source := Rect2(frame * 384, 0, 384, 256)
				var y := 110.0 + row * 292.0
				draw_string(FONT, Vector2(x, y + 18), "BEFORE" if row == 0 else "POLISHED", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("969aaa"))
				draw_texture_rect_region(atlas, Rect2(x, y + 20, 288, 192), source)
				draw_texture_rect_region(atlas, Rect2(x + 100, y + 221, 87, 58), source)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = MAIN.instantiate()
	root.add_child(game)
	await process_frame
	await Capture.pin_window(self)
	game._sfx.muted = true
	game.start_quick_match(false, 0, 2)
	game._transition.visible = false
	game.set_physics_process(false)
	game._time_stop._freeze_flash = 0.0
	game._time_stop._resume_flash = 0.0
	game.state = Phase.EXECUTING
	game.world_tick = 0
	game.exec_tick = 12
	var left: Player = game.players[0]
	var right: Player = game.players[1]
	left.position = Vector2(470, 470)
	right.position = Vector2(790, 470)
	left.facing = 1
	right.facing = -1
	for p: Player in game.players:
		p.on_ground = true
		p.vel = Vector2.ZERO
		p.plan.confirmed = false
	left.plan.shot_tick = 12
	right.plan.shot_tick = -1
	game._ui.refresh()
	for p: Player in game.players:
		p.get_node("FighterVisual").sync_from_player()
	await Capture.settle(self, 5)
	var error := Capture.save(self, "res://previews/duelist-sprite-polish-gameplay.png", "Duelist sprite polish")
	if error == OK:
		await Capture.pin_window(self, Vector2i(1024, 576))
		await Capture.settle(self, 5)
		error = Capture.save(self, "res://previews/duelist-sprite-polish-small.png", "Duelist sprite polish small")
	root.remove_child(game)
	game.free()
	await process_frame
	if error == OK:
		await Capture.pin_window(self)
		var board := SpriteBoard.new()
		root.add_child(board)
		await Capture.settle(self, 5)
		error = Capture.save(self, "res://previews/duelist-sprite-polish-comparison.png", "Duelist comparison")
		board.free()
	quit(error)
