extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = MAIN_SCENE.instantiate()
	# Kit constants must not read the developer's saved Game Tuning profile.
	game.offline_tuning_path = "user://test-characterkitstest-tuning.cfg"
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game.start_quick_match(false, 0, 2, [game.Weapon.KNIVES, game.Weapon.KNIVES])
	game.restart()

	_test_class_movement_profiles(game)

	game.free()
	if _failures == 0:
		print("Character kits: all tests passed")
	else:
		push_error("Character kits: %d test(s) failed" % _failures)
	quit(_failures)


func _test_class_movement_profiles(game) -> void:
	var kits: Array[int] = [game.Weapon.KNIVES]
	var expected_speed: Array[float] = [1.0]
	var expected_jumps: Array[int] = [1]
	var expected_fall: Array[float] = [1.0]
	for kit_index in kits.size():
		game.player_weapons[0] = kits[kit_index]
		_check(is_equal_approx(game.movement_speed_scale(0), expected_speed[kit_index]),
			"class %d must use its authored walk-speed scale" % kits[kit_index])
		_check(game.air_jumps_for(0) == expected_jumps[kit_index],
			"class %d must use its authored air-jump count" % kits[kit_index])
		_check(is_equal_approx(game.max_fall_speed_for(0),
			game.max_fall_speed * expected_fall[kit_index]),
			"class %d must use its authored fall-speed scale" % kits[kit_index])


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
