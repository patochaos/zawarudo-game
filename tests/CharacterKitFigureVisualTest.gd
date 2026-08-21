extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")


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

	var velocity: Player = game.players[0]
	var shock: Player = game.players[1]
	velocity.position = Vector2(420.0, 560.0)
	shock.position = Vector2(860.0, 560.0)
	velocity.on_ground = true
	shock.on_ground = true
	velocity.plan.set_aim_from_vector(Vector2.RIGHT,
		game.aim_min_angle, game.aim_max_angle)
	shock.plan.set_aim_from_vector(Vector2.LEFT,
		game.aim_min_angle, game.aim_max_angle)
	shock.plan.attack_mode = 1
	game.frame_debt_cells[0] = game.frame_debt_max_cells
	velocity.queue_redraw()
	shock.queue_redraw()
	await process_frame
	await process_frame
	var idle_error := root.get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://previews/character-figures-velocity-shock.png"))

	velocity.plan.power = 0.75
	game._spawn_player_attack(velocity)
	# Planning freezes the fresh action before simulation can advance it, giving
	# visual QA a deterministic look at the authored charge silhouette.
	game.state = Phase.PLANNING
	velocity.queue_redraw()
	await process_frame
	await process_frame
	var dash_error := root.get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://previews/velocity-shield-lance-dash.png"))

	if idle_error == OK and dash_error == OK:
		print("Character figure and Velocity dash previews saved")
	else:
		push_error("Could not save character figure previews (%d, %d)" % [
			idle_error, dash_error])
	quit(idle_error if idle_error != OK else dash_error)
