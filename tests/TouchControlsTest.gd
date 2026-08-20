extends SceneTree

const TOUCH_SCRIPT := preload("res://scripts/TouchControls.gd")
const GAME_MANAGER := preload("res://scripts/GameManager.gd")
const PLAYER_PLAN := preload("res://scripts/PlayerPlan.gd")
var _failures: int = 0


class MockPlan:
	extends RefCounted
	var power: float = 0.5


class MockPlayer:
	extends RefCounted
	var plan := MockPlan.new()


class MockManager:
	extends Node
	var state: int = Phase.PLANNING
	var online_mode: bool = false
	var online_player: int = -1
	var rematch_level_index: int = 0
	var rematch_level_name: String = "SACRED DUEL"
	var players: Array = [MockPlayer.new(), MockPlayer.new()]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var manager := MockManager.new()
	root.add_child(manager)
	var controls := TOUCH_SCRIPT.new()
	root.add_child(controls)
	controls.configure(manager, true)
	await process_frame

	var up_left := controls.STICK_CENTER + Vector2(-70.0, -70.0)
	controls._press_touch(1, up_left)
	_check(controls.left_held and not controls.jump_held,
		"pushing the joystick upward must move left without jumping")
	controls._drag_touch(1, controls.STICK_CENTER + Vector2(70.0, 70.0))
	_check(controls.right_held and controls.wait_held and not controls.left_held,
		"a down-right joystick diagonal must walk and let time run")
	controls._release_touch(1)
	_check(controls.stick_vector == Vector2.ZERO and not controls.right_held and not controls.wait_held,
		"releasing the joystick must return every movement axis to neutral")
	controls._press_touch(6, controls.JUMP_CENTER)
	_check(controls.jump_held, "holding JUMP must expose jump state")
	controls._release_touch(6)
	_check(not controls.jump_held, "releasing JUMP must clear jump state")
	var plan := PLAYER_PLAN.new()
	plan.aim_angle = 32.0
	plan.set_aim_side(-1)
	_check(plan.aim_side() == -1 and is_equal_approx(plan.elevation(), 32.0),
		"walking left must flip the default aim side without changing elevation")
	plan.set_aim_side(1)
	_check(plan.aim_side() == 1 and is_equal_approx(plan.elevation(), 32.0),
		"walking right must face right without changing elevation")
	_check(not GAME_MANAGER.should_accept_mouse_aim(true, true),
		"an emulated mouse move from the joystick must never replace touch aim")
	_check(GAME_MANAGER.should_accept_mouse_aim(false, true),
		"desktop mouse aiming must remain available when touch controls are off")

	var aim_start := Vector2(850.0, 350.0)
	var aim_end := Vector2(1040.0, 280.0)
	controls._press_touch(2, aim_start)
	controls._drag_touch(2, aim_end)
	_check(controls.aim_active and controls.aim_latched and controls.aim_position == aim_end,
		"the aim finger must track its latest drag position")
	controls._release_touch(2)
	_check(not controls.aim_active and controls.aim_latched,
		"releasing the aim finger must preserve the deliberate aim side")

	controls._press_touch(3, controls.FIRE_CENTER)
	_check(controls.charge_held, "holding DRAW must expose charge state")
	# The joystick and DRAW must remain independent multitouch targets.
	controls._press_touch(4, controls.STICK_CENTER + Vector2(70.0, 0.0))
	_check(controls.charge_held and controls.right_held,
		"movement and DRAW must work with separate fingers")
	controls._release_touch(4)
	controls._release_touch(3)
	_check(not controls.charge_held, "releasing DRAW must expose a fire edge")

	var confirmed := [false]
	controls.confirm_requested.connect(func(): confirmed[0] = true)
	controls._press_touch(5, controls.LOCK_RECT.get_center())
	_check(confirmed[0], "LOCK must emit the confirm action")
	controls._release_touch(5)

	manager.state = Phase.EXECUTING
	await process_frame
	_check(not controls.visible and not controls.has_active_touches() and not controls.aim_latched,
		"the overlay must disappear and clear touch state during execution")

	var result_actions := [false, false, false, false, false]
	controls.level_previous_requested.connect(func(): result_actions[0] = true)
	controls.level_next_requested.connect(func(): result_actions[1] = true)
	controls.replay_requested.connect(func(): result_actions[2] = true)
	controls.rematch_requested.connect(func(): result_actions[3] = true)
	controls.report_requested.connect(func(): result_actions[4] = true)
	manager.state = Phase.GAME_OVER
	await process_frame
	controls._press_touch(10, controls.LEVEL_PREV_RECT.get_center())
	controls._release_touch(10)
	controls._press_touch(11, controls.LEVEL_NEXT_RECT.get_center())
	controls._release_touch(11)
	controls._press_touch(12, controls.REPLAY_RECT.get_center())
	controls._release_touch(12)
	controls._press_touch(13, controls.REMATCH_RECT.get_center())
	controls._release_touch(13)
	controls._press_touch(14, controls.REPORT_RECT.get_center())
	controls._release_touch(14)
	_check(result_actions == [true, true, true, true, true],
		"the result overlay must expose level, report, replay and rematch actions")
	manager.state = Phase.REPLAY
	await process_frame
	_check(controls.visible \
		and controls._action_at(controls.REPLAY_EXIT_RECT.get_center()) == "replay",
		"touch replay must expose a way back to the result screen")
	controls.queue_free()
	manager.queue_free()
	await process_frame

	if _failures == 0:
		print("Touch controls: all tests passed")
	else:
		push_error("Touch controls: %d test(s) failed" % _failures)
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
