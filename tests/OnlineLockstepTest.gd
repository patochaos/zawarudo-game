extends SceneTree

const GAME_MANAGER := preload("res://scripts/GameManager.gd")
var _failures: int = 0


func _init() -> void:
	_test_plan_roundtrip()
	_test_remote_slot_uses_local_controls()
	_test_plan_legality()
	_test_abandoned_match_claim()
	if _failures == 0:
		print("Online lockstep: all tests passed")
	else:
		push_error("Online lockstep: %d test(s) failed" % _failures)
	quit(_failures)


func _test_plan_roundtrip() -> void:
	var original := PlayerPlan.new()
	original.record(-1, false, false)
	original.record(1, true, true)
	original.record(0, false, false, true)
	original.shot_tick = 2
	original.aim_angle = 133.5
	original.power = 0.8
	original.attack_mode = 1
	original.super_shot = true
	var restored := PlayerPlan.new()
	restored.apply_network_dict(original.to_network_dict())
	_check(restored.dirs == original.dirs and restored.jumps == original.jumps \
		and restored.holds == original.holds and restored.drops == original.drops,
		"network plan must preserve every recorded input byte")
	_check(restored.drop_at(2) and not restored.jump_at(2),
		"a relayed drop must arrive as a drop and never as a jump")
	_check(restored.shot_tick == 2 and is_equal_approx(restored.aim_angle, 133.5) \
		and is_equal_approx(restored.power, 0.8) \
		and restored.attack_mode == 1 and restored.super_shot,
		"network plan must preserve shot timing, aim, kit settings and SUPER")
	_check(restored.confirmed, "a relayed network plan must arrive locked")
	var wire := original.to_network_dict()
	_check(not wire.has("grenade_fuse_seconds"),
		"the retired Grenadier fuse must not travel on the wire")
	_check(wire["drops"].size() == wire["dirs"].size(),
		"drops is a required channel and must match the recording length")


func _test_remote_slot_uses_local_controls() -> void:
	var gm = GAME_MANAGER.new()
	gm.online_mode = true
	gm.online_player = 1
	var controls: Dictionary = gm._input_map_for(1)
	_check(KEY_A in controls["left"] and KEY_D in controls["right"],
		"online Player 2 must use A/D on their own keyboard")
	_check(KEY_SPACE in controls["jump"] and KEY_W in controls["jump"] \
			and KEY_UP in controls["jump"],
		"online Player 2 must be able to jump with SPACE, W, or UP")
	_check(KEY_SPACE not in controls["charge"],
		"SPACE must be reserved for jumping and never charge or fire")
	gm.online_mode = false
	var p2_controls: Dictionary = gm._input_map_for(1)
	_check(p2_controls.values().all(func(bindings): return bindings.is_empty()),
		"local Player 2 must be gamepad-only with no keyboard bindings")
	gm.free()


func _test_plan_legality() -> void:
	var gm = GAME_MANAGER.new()
	var legal := PlayerPlan.new().to_network_dict()
	_check(gm._online_plan_is_legal(0, legal), "an empty legal plan must be accepted")
	var without_drops := legal.duplicate(true)
	without_drops.erase("drops")
	without_drops["dirs"] = [1]
	without_drops["jumps"] = [0]
	without_drops["holds"] = [0]
	_check(not gm._online_plan_is_legal(0, without_drops),
		"drops is a required channel and a plan without it must be rejected")
	var budget: int = gm.movement_tick_budget()
	_check(budget == 30, "the default 0.5 second movement budget must be exactly 30 ticks")
	var full_budget: Dictionary = legal.duplicate(true)
	for i in budget:
		full_budget["dirs"].append(1)
		full_budget["jumps"].append(0)
		full_budget["holds"].append(0)
		full_budget["drops"].append(0)
	_check(gm._online_plan_is_legal(0, full_budget),
		"a plan that consumes the full movement budget must be accepted")
	var one_over: Dictionary = full_budget.duplicate(true)
	one_over["dirs"].append(1)
	one_over["jumps"].append(0)
	one_over["holds"].append(0)
	one_over["drops"].append(0)
	_check(not gm._online_plan_is_legal(0, one_over),
		"a single tick over the movement budget must be rejected, as the server does")
	var impossible: Dictionary = legal.duplicate(true)
	for i in budget + 2:
		impossible["dirs"].append(1)
		impossible["jumps"].append(0)
		impossible["holds"].append(0)
		impossible["drops"].append(0)
	_check(not gm._online_plan_is_legal(0, impossible),
		"a remote plan cannot exceed the movement budget")
	var bad_kit := legal.duplicate(true)
	bad_kit["attack_mode"] = 2
	_check(not gm._online_plan_is_legal(0, bad_kit),
		"a remote plan cannot inject an unknown character attack mode")
	gm.free()


## A player whose browser reloads cannot rejoin a match in progress, so the
## survivor has to be able to end it. The claim is only offered while the room
## has actually reported the opponent gone.
func _test_abandoned_match_claim() -> void:
	var gm = GAME_MANAGER.new()
	gm.online_mode = true
	gm.online_player = 0
	_check(not gm.online_peer_lost,
		"a fresh online match must not start out looking abandoned")
	gm._on_online_message({"type": "peer_status", "player": 1, "connected": false})
	_check(gm.online_peer_lost,
		"a peer dropping out of a live match must latch, not just flash a banner")
	gm._on_online_message({"type": "peer_status", "player": 1, "connected": true})
	_check(not gm.online_peer_lost,
		"a reconnecting opponent must clear the claim offer")
	gm._on_online_message({"type": "peer_status", "player": 0, "connected": false})
	_check(not gm.online_peer_lost,
		"our own socket status must never be mistaken for the opponent leaving")

	gm._on_online_message({"type": "peer_status", "player": 1, "connected": false})
	gm._on_online_message({"type": "opponent_left", "winner": 0, "turn": 4})
	_check(gm.state == Phase.GAME_OVER and gm.winner == 0,
		"a granted claim must land on the ordinary result screen")
	_check(not gm.online_peer_lost,
		"the claim offer must go away once the room has ruled")

	# Desync is not claimable: neither side can be trusted as the winner.
	var broken = GAME_MANAGER.new()
	broken.online_mode = true
	broken.online_player = 1
	broken._on_online_message({"type": "desync", "turn": 2})
	_check(broken.online_match_broken and not broken.online_peer_lost,
		"a desync must offer the menu, never a claimed win")
	broken.free()
	gm.free()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
