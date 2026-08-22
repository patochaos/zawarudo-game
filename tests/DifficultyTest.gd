extends SceneTree

## Opponent skill. Every preset plans by the same rules and still cannot read the
## other player's plan — what changes is how much of the candidate set the search
## spends, how precisely it aims, and how long it deliberates. These checks pin
## that the three presets stay ordered and that the AI actually reads them.

const GAME_MANAGER := preload("res://scripts/GameManager.gd")
var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_presets_are_ordered()
	_test_out_of_range_is_clamped()
	await _test_search_respects_the_preset()
	if _failures == 0:
		print("Difficulty: all tests passed")
	else:
		push_error("Difficulty: %d test(s) failed" % _failures)
	quit(_failures)


## A preset is one decision, not four independent knobs. Aim gets tighter, the
## search gets wider and the deliberation gets shorter, all in the same order.
func _test_presets_are_ordered() -> void:
	var gm = GAME_MANAGER.new()
	var jitter: Array[float] = []
	var moves: Array[int] = []
	var think: Array[float] = []
	for level in [gm.Difficulty.NOVICE, gm.Difficulty.STANDARD, gm.Difficulty.RUTHLESS]:
		gm.set_difficulty(level)
		jitter.append(gm.ai_aim_jitter)
		moves.append(gm.ai_moves_searched)
		think.append(gm.ai_think_max)
	_check(jitter[0] > jitter[1] and jitter[1] > jitter[2],
		"a harder opponent must aim with strictly less slop")
	_check(moves[0] < moves[1] and moves[1] < moves[2],
		"a harder opponent must search strictly more movement candidates")
	_check(think[0] > think[1] and think[1] > think[2],
		"a harder opponent must commit strictly sooner")
	_check(moves[0] >= 1, "even the easiest opponent must search one real candidate")
	gm.set_difficulty(gm.Difficulty.STANDARD)
	_check(is_equal_approx(gm.ai_aim_jitter, 2.0) and gm.ai_moves_searched == 2,
		"STANDARD must remain the authored baseline the balance passes were tuned at")
	_check(gm.difficulty_name() == "STANDARD", "the preset must name itself for the HUD")
	gm.free()


func _test_out_of_range_is_clamped() -> void:
	var gm = GAME_MANAGER.new()
	gm.set_difficulty(-5)
	_check(gm.difficulty == gm.Difficulty.NOVICE, "a preset below the range must clamp, not wrap")
	gm.set_difficulty(99)
	_check(gm.difficulty == gm.Difficulty.RUTHLESS, "a preset above the range must clamp, not wrap")
	gm.free()


## The knob is worthless if the planner ignores it. Ai.begin ranks every movement
## candidate for safety but only shot-searches the top ai_moves_searched of them.
func _test_search_respects_the_preset() -> void:
	var gm = GAME_MANAGER.new()
	gm.vs_ai = true
	root.add_child(gm)
	await process_frame
	gm._load_level(0)
	gm.restart()

	var counts: Array[int] = []
	for level in [gm.Difficulty.NOVICE, gm.Difficulty.STANDARD, gm.Difficulty.RUTHLESS]:
		gm.set_difficulty(level)
		var search := Ai.new()
		search.begin(gm, 1, 0)
		counts.append(search._cands.size())
		_check(search._cands.size() <= gm.ai_moves_searched,
			"the search must never exceed the candidate budget its preset allows")
	_check(counts[0] < counts[2],
		"RUTHLESS must actually evaluate more shot origins than NOVICE")

	root.remove_child(gm)
	gm.free()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
