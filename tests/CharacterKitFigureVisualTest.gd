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
	game._start_local_match(false, 0, 2,
		[game.Weapon.DASHBLADE, game.Weapon.SHOCK])
	game._transition.visible = false
	game._ui.visible = false
	game._preview.visible = false
	game.state = Phase.PLANNING

	var rook: Player = game.players[0]
	var shock: Player = game.players[1]
	rook.position = Vector2(420.0, 560.0)
	shock.position = Vector2(860.0, 560.0)
	rook.on_ground = true
	shock.on_ground = true
	rook.plan.set_aim_from_vector(Vector2.RIGHT,
		game.aim_min_angle, game.aim_max_angle)
	shock.plan.set_aim_from_vector(Vector2.LEFT,
		game.aim_min_angle, game.aim_max_angle)
	shock.plan.attack_mode = 1
	game.frame_debt_cells[0] = game.frame_debt_max_cells
	rook.queue_redraw()
	shock.queue_redraw()
	await VisualCapture.await_transition(self, game)
	var idle_error := VisualCapture.save(self,
		"res://previews/character-figures-rook-pulse.png",
		"Character figure preview")
	if idle_error != OK:
		quit(idle_error)
		return

	rook.plan.power = 0.75
	game._spawn_player_attack(rook)
	# Planning freezes the fresh action before simulation can advance it, giving
	# visual QA a deterministic look at the authored charge silhouette.
	game.state = Phase.PLANNING
	rook.queue_redraw()
	await VisualCapture.settle(self)
	var dash_error := VisualCapture.save(self,
		"res://previews/rook-shield-lance-dash.png",
		"Rook dash preview")

	if idle_error == OK and dash_error == OK:
		print("Character figure and Rook dash previews saved")
	else:
		push_error("Could not save character figure previews (%d, %d)" % [
			idle_error, dash_error])
	quit(idle_error if idle_error != OK else dash_error)
