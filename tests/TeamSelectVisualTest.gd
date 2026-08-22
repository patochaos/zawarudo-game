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
	game._transition.visible = false
	game._on_menu_team_battle()
	game._team_select.debug_join_device(7, "XBOX CONTROLLER")
	game._team_select.debug_join_device(8, "DUALSENSE")
	game._team_select.debug_set_side(TeamSelectLayer.KEYBOARD_DEVICE,
		TeamSelectLayer.SIDE_CRIMSON, true)
	game._team_select.debug_set_side(7, TeamSelectLayer.SIDE_AZURE, false)
	await VisualCapture.await_transition(self, game)
	var error := VisualCapture.save(self, "res://previews/team-select-2v2.png",
		"Team select preview")
	game.free()
	quit(error)
