extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const VisualCapture := preload("res://tests/VisualCaptureHelper.gd")


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game.start_quick_match(false, 0, 2, [game.Weapon.CHAKRAM, game.Weapon.KNIVES])
	game._transition.visible = false
	game._ui.visible = false
	game._preview.visible = false
	game.state = Phase.PLANNING

	var eclipse: Player = game.players[0]
	var duelist: Player = game.players[1]
	eclipse.position = Vector2(420.0, 560.0)
	duelist.position = Vector2(820.0, 560.0)
	eclipse.on_ground = true
	duelist.on_ground = true
	eclipse.plan.set_aim_from_vector(Vector2.RIGHT,
		game.aim_min_angle, game.aim_max_angle)
	duelist.plan.set_aim_from_vector(Vector2.LEFT,
		game.aim_min_angle, game.aim_max_angle)
	eclipse.queue_redraw()
	duelist.queue_redraw()
	await VisualCapture.await_transition(self, game)
	var error := VisualCapture.save(self,
		"res://previews/character-figures-eclipse-duelist.png",
		"Eclipse and Duelist figure preview")
	quit(error)
