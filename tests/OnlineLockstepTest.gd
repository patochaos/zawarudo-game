extends SceneTree

const GAME_MANAGER := preload("res://scripts/GameManager.gd")
var _failures: int = 0


func _init() -> void:
	_test_plan_roundtrip()
	_test_remote_slot_uses_local_controls()
	_test_plan_legality()
	if _failures == 0:
		print("Online lockstep: all tests passed")
	else:
		push_error("Online lockstep: %d test(s) failed" % _failures)
	quit(_failures)


func _test_plan_roundtrip() -> void:
	var original := PlayerPlan.new()
	original.record(-1, false, false)
	original.record(1, true, true)
	original.shot_tick = 2
	original.aim_angle = 133.5
	original.power = 0.8
	original.super_shot = true
	var restored := PlayerPlan.new()
	restored.apply_network_dict(original.to_network_dict())
	_check(restored.dirs == original.dirs and restored.jumps == original.jumps \
		and restored.holds == original.holds, "network plan must preserve every recorded input byte")
	_check(restored.shot_tick == 2 and is_equal_approx(restored.aim_angle, 133.5) \
		and is_equal_approx(restored.power, 0.8) and restored.super_shot,
		"network plan must preserve shot timing, aim, power and SUPER")
	_check(restored.confirmed, "a relayed network plan must arrive locked")


func _test_remote_slot_uses_local_controls() -> void:
	var gm = GAME_MANAGER.new()
	gm.online_mode = true
	gm.online_player = 1
	var controls: Dictionary = gm._input_map_for(1)
	_check(KEY_A in controls["left"] and KEY_D in controls["right"],
		"online Player 2 must use A/D on their own keyboard")
	_check(KEY_SPACE in controls["charge"],
		"online Player 2 must use the local P1 charge binding")
	gm.free()


func _test_plan_legality() -> void:
	var gm = GAME_MANAGER.new()
	var legal := PlayerPlan.new().to_network_dict()
	_check(gm._online_plan_is_legal(0, legal), "an empty legal plan must be accepted")
	var budget: int = gm.movement_tick_budget()
	_check(budget == 30, "the default 0.5 second movement budget must be exactly 30 ticks")
	var full_budget: Dictionary = legal.duplicate(true)
	for i in budget:
		full_budget["dirs"].append(1)
		full_budget["jumps"].append(0)
		full_budget["holds"].append(0)
	_check(gm._online_plan_is_legal(0, full_budget),
		"a plan that consumes the full movement budget must be accepted")
	var legacy_float_tick: Dictionary = full_budget.duplicate(true)
	legacy_float_tick["dirs"].append(1)
	legacy_float_tick["jumps"].append(0)
	legacy_float_tick["holds"].append(0)
	_check(gm._online_plan_is_legal(0, legacy_float_tick),
		"one float-residue tick from the previous web build must remain compatible")
	var impossible: Dictionary = legal.duplicate(true)
	for i in budget + 2:
		impossible["dirs"].append(1)
		impossible["jumps"].append(0)
		impossible["holds"].append(0)
	_check(not gm._online_plan_is_legal(0, impossible),
		"a remote plan cannot exceed the movement budget")
	gm.free()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
