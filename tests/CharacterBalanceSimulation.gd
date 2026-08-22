extends SceneTree

## Deterministic headless tournament for the selectable roster. Every fighter is
## driven by the production Ai planner, including slot 0, so 2P/3P/4P results
## compare kits instead of human-vs-bot roles. The matrix covers every authored
## arena and rotates roster order to expose spawn/slot bias.

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const TURN_CAP := 60
const TOURNAMENT_HITS_TO_WIN := 5

var _samples := 2
var _only_player_count := 0
## Restrict the matrix to one arena. Every match is seeded from its own
## (level, sample, pairing) triple and never reads another match's state, so
## splitting by arena across parallel processes gives byte-identical totals to
## one serial run — it just uses more than the single core this is otherwise
## pinned to. -1 runs the whole matrix.
var _only_level := -1
var _report := {
	"matches": 0,
	"unresolved": 0,
	"kits": {},
	"player_counts": {},
	"levels": {},
	"duels": {},
}


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--samples="):
			_samples = maxi(1, int(arg.trim_prefix("--samples=")))
		elif arg.begins_with("--players="):
			_only_player_count = clampi(int(arg.trim_prefix("--players=")), 2, 4)
		elif arg.begins_with("--level="):
			_only_level = clampi(int(arg.trim_prefix("--level=")), 0, Levels.count() - 1)
	call_deferred("_run")


## The arenas this process is responsible for.
func _levels() -> Array:
	return [_only_level] if _only_level >= 0 else range(Levels.count())


func _run() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game.hit_freeze_enabled = false
	game.fighter_visuals_enabled = false

	var kits := [game.Weapon.KNIVES, game.Weapon.DASHBLADE, game.Weapon.SHOCK,
		game.Weapon.CHAKRAM]
	for kit in kits:
		_report["kits"][_kit_name(game, kit)] = _empty_kit_stats()

	# Duel every pairing. Alternating the order each sample prevents the left
	# spawn or P1 colour from being mistaken for character strength.
	if _only_player_count in [0, 2]:
		for level in _levels():
			for a in kits.size():
				for b in range(a + 1, kits.size()):
					for sample in _samples:
						var roster := [kits[a], kits[b]] if sample % 2 == 0 \
							else [kits[b], kits[a]]
						await _run_match(game, level, roster, _seed(level, sample, a * 7 + b))

	# Three-player matches omit each of the four kits in turn. Four-player
	# matches field the complete roster, keeping per-kit exposure symmetrical.
	for level in _levels():
		for sample in _samples:
			if _only_player_count in [0, 3]:
				for omitted in kits.size():
					var trio := kits.duplicate()
					trio.remove_at(omitted)
					trio = _rotated(trio, sample + level + omitted)
					await _run_match(game, level, trio,
						_seed(level, sample, 40 + omitted))
			if _only_player_count in [0, 4]:
				var four := _rotated(kits, sample + level)
				await _run_match(game, level, four, _seed(level, sample, 70))

	_print_report(game)
	game.free()
	quit(0)


func _run_match(game, level: int, roster: Array, seed_value: int) -> void:
	game._start_local_match(false, level, roster.size(), roster)
	game.hits_to_win = TOURNAMENT_HITS_TO_WIN
	game.rng.seed = seed_value
	game.restart()
	var start_turn: int = game.turn

	while game.state != Phase.GAME_OVER and game.turn - start_turn < TURN_CAP:
		_plan_all(game)
		game._begin_execution()
		while game.state == Phase.EXECUTING:
			var before_tick: int = game.world_tick
			game._sim_tick(game.tick_dt())
			# SUPER portrait beats deliberately consume no simulation tick. Headless
			# play has no presentation clock, so clear the beat and retry that tick.
			if game.world_tick == before_tick:
				if game._super_freeze != null:
					game._super_freeze.cancel()
				continue
			game.exec_tick += 1
			if game.state == Phase.EXECUTING and game.exec_tick >= game.exec_ticks_total:
				game._end_execution()

	_record_match(game, level, roster)
	await process_frame


func _plan_all(game) -> void:
	for i in game.players.size():
		if not game.players[i].alive:
			continue
		var target := _nearest_target(game, i)
		if target < 0:
			continue
		var search := Ai.new()
		search.begin(game, i, target)
		search.finish()
		search.apply()


func _nearest_target(game, fighter: int) -> int:
	return game._ai_target_for(fighter)


func _record_match(game, level: int, roster: Array) -> void:
	_report["matches"] += 1
	if int(_report["matches"]) % 7 == 0:
		print("BALANCE PROGRESS: %d matches complete" % _report["matches"])
	var count_key := str(roster.size())
	var count_stats: Dictionary = _report["player_counts"].get(count_key,
		{"matches": 0, "turns": 0, "unresolved": 0})
	count_stats["matches"] += 1
	count_stats["turns"] += game.turn
	if game.winner < 0:
		count_stats["unresolved"] += 1
		_report["unresolved"] += 1
	_report["player_counts"][count_key] = count_stats

	var level_name := str(Levels.build(level)["name"])
	var level_stats: Dictionary = _report["levels"].get(level_name,
		{"matches": 0, "unresolved": 0, "wins": {}})
	level_stats["matches"] += 1
	if game.winner < 0:
		level_stats["unresolved"] += 1
	else:
		var winner_name := _kit_name(game, roster[game.winner])
		level_stats["wins"][winner_name] = int(level_stats["wins"].get(winner_name, 0)) + 1
	_report["levels"][level_name] = level_stats

	for i in roster.size():
		var name := _kit_name(game, roster[i])
		var stats: Dictionary = _report["kits"][name]
		stats["appearances"] += 1
		stats["hits"] += game.score[i]
		stats["wins"] += 1 if game.winner == i else 0
		stats["slot_appearances"][i] += 1
		stats["slot_wins"][i] += 1 if game.winner == i else 0

	if roster.size() == 2:
		var names := [_kit_name(game, roster[0]), _kit_name(game, roster[1])]
		names.sort()
		var key := "%s vs %s" % names
		var duel: Dictionary = _report["duels"].get(key,
			{"matches": 0, "unresolved": 0, "wins": {}})
		duel["matches"] += 1
		if game.winner < 0:
			duel["unresolved"] += 1
		else:
			var winner_name := _kit_name(game, roster[game.winner])
			duel["wins"][winner_name] = int(duel["wins"].get(winner_name, 0)) + 1
		_report["duels"][key] = duel


func _print_report(game) -> void:
	print("BALANCE MATRIX: %d matches, %d unresolved, %d samples, %d levels" % [
		_report["matches"], _report["unresolved"], _samples, Levels.count()])
	for name in _report["kits"]:
		var stats: Dictionary = _report["kits"][name]
		var appearances := maxi(1, int(stats["appearances"]))
		print("KIT %s: %d/%d wins (%.1f%%), %.2f hits/appearance" % [
			name, stats["wins"], stats["appearances"],
			100.0 * float(stats["wins"]) / float(appearances),
			float(stats["hits"]) / float(appearances)])
	for key in _report["duels"]:
		print("DUEL %s: %s" % [key, JSON.stringify(_report["duels"][key])])
	for key in _report["player_counts"]:
		var stats: Dictionary = _report["player_counts"][key]
		print("%sP: %d matches, %.2f average turns, %d unresolved" % [
			key, stats["matches"], float(stats["turns"]) / float(stats["matches"]),
			stats["unresolved"]])
	print("BALANCE_JSON %s" % JSON.stringify(_report))


func _empty_kit_stats() -> Dictionary:
	return {
		"appearances": 0,
		"wins": 0,
		"hits": 0,
		"slot_appearances": [0, 0, 0, 0],
		"slot_wins": [0, 0, 0, 0],
	}


func _kit_name(game, weapon: int) -> String:
	match weapon:
		game.Weapon.KNIVES: return "DAGGER"
		game.Weapon.DASHBLADE: return "VELOCITY"
		game.Weapon.CHAKRAM: return "BROODTAIL"
		game.Weapon.SHOCK: return "STATIC_WITCH"
		_: return "UNKNOWN_%d" % weapon


func _rotated(values: Array, amount: int) -> Array:
	var out := []
	for i in values.size():
		out.append(values[posmod(i + amount, values.size())])
	return out


func _seed(level: int, sample: int, salt: int) -> int:
	return 911_382 + level * 10_007 + sample * 1_009 + salt * 97
