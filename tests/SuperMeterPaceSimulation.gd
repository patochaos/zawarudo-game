extends SceneTree

## Headless pacing probe for the SUPER meter. Two production-AI Duelists play
## every arena and the run reports how many turns a fighter needs to fill the
## meter, plus how much each source contributed per fighter-turn. Use it to
## retune the `super_charge_*` shares; the target cadence is one SUPER every
## five or six rounds of ordinary play.
##
##   godot --headless --path . --script tests/SuperMeterPaceSimulation.gd -- --samples=2

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const TURN_CAP := 40

class GainLog:
	extends RefCounted
	## Stands in for Telemetry: no file writes, just the meter gains.
	var enabled := true
	var latest_report := {}
	var gains: Array[Dictionary] = []

	func begin_match(_mode: String, _arena: String, _input_name: String) -> void:
		pass

	func finish_match(_winner: int, _score: Array[int], _turn: int, _digest: String = "") -> void:
		pass

	func abandon_match(_turn: int, _score: Array[int], _reason: String) -> void:
		pass

	func note_rematch(_turn: int) -> void:
		pass

	func copy_latest_to_clipboard() -> bool:
		return false

	func record(name: String, _turn: int, data: Dictionary = {}) -> void:
		if name == "super_gain":
			gains.append(data.duplicate())


var _samples := 2
var _only_level := -1
var _fighter_turns := 0
var _fills := 0
var _gap_turns := 0
var _by_reason := {}


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--samples="):
			_samples = maxi(1, int(arg.trim_prefix("--samples=")))
		elif arg.begins_with("--level="):
			_only_level = clampi(int(arg.trim_prefix("--level=")), 0, Levels.count() - 1)
	call_deferred("_run")


func _run() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game.hit_freeze_enabled = false
	game.fighter_visuals_enabled = false
	var log := GainLog.new()
	game._telemetry = log
	var levels: Array = [_only_level] if _only_level >= 0 else range(Levels.count())
	for level in levels:
		for sample in _samples:
			await _run_match(game, level, 1000 * (level + 1) + sample)
	_print_report(game)
	game.free()
	quit(0)


func _run_match(game, level: int, seed_value: int) -> void:
	game.start_quick_match(false, level, 2, [game.Weapon.KNIVES, game.Weapon.KNIVES])
	game.hits_to_win = 99
	game.rng.seed = seed_value
	game.restart()
	var start_turn: int = game.turn
	var last_fill: Array[int] = [start_turn, start_turn]
	var was_full: Array[bool] = [false, false]

	while game.state != Phase.GAME_OVER and game.turn - start_turn < TURN_CAP:
		_plan_all(game)
		game._begin_execution()
		while game.state == Phase.EXECUTING:
			var before_tick: int = game.world_tick
			game._sim_tick(game.tick_dt())
			if game.world_tick == before_tick:
				if game._super_freeze != null:
					game._super_freeze.cancel()
				continue
			game.exec_tick += 1
			if game.state == Phase.EXECUTING and game.exec_tick >= game.exec_ticks_total:
				game._end_execution()
		for i in 2:
			_fighter_turns += 1
			var full: bool = game.super_meter[i] >= 1.0
			if full and not was_full[i]:
				_fills += 1
				_gap_turns += game.turn - last_fill[i]
				last_fill[i] = game.turn
			was_full[i] = full

	for data in game._telemetry.gains:
		var reason := str(data.get("reason", "?"))
		_by_reason[reason] = float(_by_reason.get(reason, 0.0)) + float(data.get("amount", 0.0))
	game._telemetry.gains.clear()
	await process_frame


## Mirrors _confirm for the AI: the plan locks with the fixed half-window share.
func _plan_all(game) -> void:
	for i in game.players.size():
		if not game.players[i].alive:
			continue
		var target: int = game._ai_target_for(i)
		if target < 0:
			continue
		var search := Ai.new()
		search.begin(game, i, target)
		search.finish()
		search.apply()
		game.players[i].plan.confirmed = true
		game.players[i].plan.lock_permille = 500


func _print_report(game) -> void:
	# The AI locks with a half share and rarely dodges, so it is the slow end.
	# An active human turn is the pace that matters for the five-to-six target.
	var active: float = game.super_charge_early_lock * 0.8 		+ game.super_charge_per_window_travel + game.super_charge_per_throw 		+ game.super_charge_per_clash + game.super_charge_per_dodge
	print("ACTIVE HUMAN TURN (quick lock, full route, full throw, one clash, one dodge): %.3f meter, %.1f turns per fill" % [
		active, 1.0 / maxf(0.0001, active)])
	var turns: float = float(maxi(1, _fighter_turns))
	print("SUPER PACE: %d fighter-turns, %d fills, %.1f turns per fill" % [
		_fighter_turns, _fills, float(_gap_turns) / float(maxi(1, _fills))])
	var total := 0.0
	for reason in _by_reason:
		total += float(_by_reason[reason])
	for reason in _by_reason:
		print("  %-10s %.4f per fighter-turn (%.0f%%)" % [reason,
			float(_by_reason[reason]) / turns, 100.0 * float(_by_reason[reason]) / maxf(0.0001, total)])
	print("  total      %.4f per fighter-turn" % (total / turns))
