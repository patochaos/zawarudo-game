extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game._transition.visible = false
	game._on_menu_team_battle()
	game._team_select.debug_join_device(7, "XBOX CONTROLLER")
	game._team_select.debug_join_device(8, "DUALSENSE")
	game._team_select.debug_set_side(TeamSelectLayer.KEYBOARD_DEVICE,
		TeamSelectLayer.SIDE_CRIMSON, true)
	game._team_select.debug_set_side(7, TeamSelectLayer.SIDE_AZURE, false)
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path("res://previews/team-select-2v2.png"))
	if error == OK:
		print("Team select preview saved")
	else:
		push_error("Could not save team select preview (error %d)" % error)
	game.free()
	quit(error)
