extends SceneTree

## Close Camera is a title-screen mode, not a mutation of normal Play. This
## suite pins both halves of that contract.

const GAME_MANAGER := preload("res://scripts/GameManager.gd")
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = GAME_MANAGER.new()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game._transition.visible = false

	game._menu.developer_mode = true
	game._menu._activate(game._menu.ROW_EXPERIMENTS)
	game._menu._activate(game._menu.ROW_CLOSE_CAMERA)
	game._transition.visible = false
	_check(game.close_camera_mode and game.state == Phase.PLANNING,
		"Close Camera must launch directly from the title into planning")
	_check(game.level_name == "KNIFE COURT" and game.players.size() == 2,
		"the mode must own the compact two-player Knife Court")
	var court := Levels.build_close_camera()
	var movers: Array[Dictionary] = []
	for platform: Dictionary in court["platforms"]:
		if platform.has("motion"):
			movers.append(platform)
	_check(court["wrap_x"] and not court["wrap_y"] and movers.size() == 1,
		"Knife Court must restore its horizontal seam and single high shuttle")
	_check(game._camera.enabled and is_equal_approx(game.planning_window_duration,
		game.close_camera_planning_duration),
		"only this mode must enable the close camera and brisk planning window")
	_check(is_equal_approx(game.jump_impulse_for(0), game.close_camera_jump_impulse),
		"the restored Duelist must use the prototype's lower jump")

	var right := game.knife_launch_velocities(Vector2.RIGHT, 0.5)
	var left := game.knife_launch_velocities(Vector2.LEFT, 0.5)
	_check(right.size() == 2 and right[0].normalized().is_equal_approx(Vector2.RIGHT)
		and right[1].y < right[0].y,
		"the close-mode throw must restore the direct-plus-lob pair")
	_check(left.size() == 2 and left[0].normalized().is_equal_approx(Vector2.LEFT)
		and left[1].y < left[0].y,
		"the lob must rise when the Duelist faces either direction")

	var chaser := Arrow.new()
	chaser.prev_pos = Vector2(0.0, 0.0)
	chaser.position = Vector2(12.0, 0.0)
	chaser.vel = Vector2(700.0, 0.0)
	var leader := Arrow.new()
	leader.prev_pos = Vector2(20.0, 0.0)
	leader.position = Vector2(23.0, 0.0)
	leader.vel = Vector2(300.0, 0.0)
	leader.ricochet_count = 1
	var leader_speed := leader.vel.length()
	_check(game._try_close_camera_trailing_boost(chaser, leader, Vector2(18.0, 0.0))
		and leader.boost_count == 1 and leader.vel.length() > leader_speed
		and leader.ricochet_count == 0,
		"a faster trailing knife must relay speed and restore the leader's bank")
	chaser.free()
	leader.free()

	game._camera._retarget()
	_check(is_equal_approx(game._camera._target_zoom, game._camera.PLANNING_ZOOM),
		"planning must target the close framing")
	game.state = Phase.EXECUTING
	game._camera._retarget()
	_check(is_equal_approx(game._camera._target_zoom, game._camera.EXECUTION_ZOOM),
		"execution must pull back to the whole arena")

	game.state = Phase.PLANNING
	game.players[0].plan.shot_tick = 0
	game._auto_ready_close_camera_plans(game.close_camera_ready_grace + 0.01)
	_check(game.players[0].plan.confirmed,
		"a finished close-mode action must auto-lock after its grace period")

	game._open_menu()
	game._transition.visible = false
	_check(not game.close_camera_mode and not game._camera.enabled,
		"leaving the mode must disable its camera and tuning switch")
	game._load_level(0)
	_check(game.level_name != "KNIFE COURT"
		and is_equal_approx(game.jump_impulse_for(0), game.jump_impulse),
		"normal Play must retain its own Arena 1 and authored jump")
	var normal_offsets := game.knife_offsets(0.5)
	_check(normal_offsets.size() == 2 and normal_offsets[0] < 0.0 and normal_offsets[1] > 0.0,
		"normal Play must retain the symmetric power-scaled knife fan")

	root.remove_child(game)
	game.free()
	if _failures == 0:
		print("Close Camera mode: all tests passed")
	else:
		push_error("Close Camera mode: %d test(s) failed" % _failures)
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
