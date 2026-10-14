extends SceneTree

## The named opponent ladder behind Start Duel: rungs stay ordered, the planner
## reads each rung's style, progress survives a restart, and the result screen
## only offers the next rung once the current one is beaten.

const MAIN := preload("res://scenes/Main.tscn")
const SETTINGS_PATH := "user://test-opponent-ladder-settings.cfg"
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_ladder_shape()
	await _test_styles_change_the_plan()
	await _test_progress_and_result_flow()
	print("Opponent ladder: %d failures" % failures)
	quit(failures)


func _test_ladder_shape() -> void:
	check(Opponents.count() >= 4, "the ladder needs several opponents to climb")
	var ids := {}
	for i in Opponents.count():
		var rung: Dictionary = Opponents.rung(i)
		ids[rung["id"]] = true
		for key in rung["style"]:
			check(Opponents.NEUTRAL_STYLE.has(key), "style key %s on %s must be one the planner reads" % [key, rung["id"]])
		if i > 0:
			check(Opponents.skill(i) >= Opponents.skill(i - 1), "skill must not drop climbing the ladder")
			check(Opponents.tuning(i)["aim_jitter"] <= Opponents.tuning(i - 1)["aim_jitter"], "aim must not get looser climbing the ladder")
	check(ids.size() == Opponents.count(), "opponent ids must be unique")
	for i in Opponents.count():
		check(Opponents.arena(i) >= 0 and Opponents.arena(i) < Levels.count()
			and Levels.build(Opponents.arena(i), 2)["name"] == Opponents.arena_name(i),
			"every rung must name a real arena")
	check(Opponents.style(-1) == Opponents.NEUTRAL_STYLE, "an unnamed slot plans with neutral weights")


## The same board, two opponents: the rusher ends closer to the rival than the
## sniper, and the sniper draws harder. The patient opponent keeps its knife
## when no throw covers a hypothesis.
func _test_styles_change_the_plan() -> void:
	var game = MAIN.instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game._sfx.muted = true
	game.settings_path = SETTINGS_PATH
	# The wrap arena gives the rusher and the sniper different routes to prefer.
	game.start_demo_duel(4)
	game._transition.visible = false
	var rival: Player = game.players[0]
	var cpu: Player = game.players[1]

	var hound := _rung_named("hound")
	var spire := _rung_named("spire")
	var warden := _rung_named("warden")
	check(hound >= 0 and spire >= 0 and warden >= 0, "the ladder must keep its three styled opponents")

	game.rng.seed = 7
	var hound_end := _planned_end(game, hound)
	game.rng.seed = 7
	var spire_end := _planned_end(game, spire)
	var hound_dist: float = game.wrap_delta(hound_end, rival.position).length()
	var spire_dist: float = game.wrap_delta(spire_end, rival.position).length()
	check(hound_dist < spire_dist, "the rusher must end its route nearer the rival than the sniper (%0.0f vs %0.0f)" % [hound_dist, spire_dist])

	game.rng.seed = 7
	game.set_player_opponent(1, warden)
	cpu.plan = PlayerPlan.new()
	var search := Ai.new()
	search.begin(game, 1, 0)
	check(search._best.get("withheld_by_style", false) and search._best_total > -INF, "the patient opponent seeds its search with a no-throw plan")

	root.remove_child(game)
	game.free()
	await process_frame


func _planned_end(game, rung: int) -> Vector2:
	game.set_player_opponent(1, rung)
	var cpu: Player = game.players[1]
	cpu.plan = PlayerPlan.new()
	var search := Ai.new()
	search.begin(game, 1, 0)
	check(search._cands.size() <= game.ai_moves_searched_for(1), "a rung's search budget must be honoured")
	var path: PackedVector2Array = search._cands[0]["path"]
	return path[path.size() - 1]


func _test_progress_and_result_flow() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	var game = MAIN.instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game._sfx.muted = true
	game.settings_path = SETTINGS_PATH
	game._settings["ladder_progress"] = 0

	game.start_demo_duel()
	game._transition.visible = false
	check(game.demo_opponent == 0 and game.player_opponent(1) == 0, "a fresh ladder starts on the first rung")
	check(game._telemetry._match.get("mode", "") == "ai_ladder_%s" % Opponents.rung(0)["id"], "telemetry must name the ladder opponent")
	game._ui.refresh()
	check(game._ui._fighter_seals[1].opponent_name == Opponents.display_name(0), "the HUD seal must name the opponent")

	# Losing unlocks nothing.
	game.state = Phase.GAME_OVER
	game.winner = 1
	game._record_ladder_result(1)
	game._ui.refresh()
	check(game.ladder_progress() == 0 and not game.next_opponent_available(), "a loss must not unlock the next opponent")
	check(not game._ui._next_opponent_button.visible and not game._ui._arena_next_button.visible, "no next or cycle controls before the first win")
	check(Opponents.display_name(0) in game._ui._over_label.text, "the result names the winning opponent")

	# Winning unlocks the next rung and saves.
	game.winner = 0
	game._record_ladder_result(0)
	check(game.ladder_progress() == 1 and game.next_opponent_available(), "a win must unlock the next rung")
	var saved := ConfigFile.new()
	check(saved.load(SETTINGS_PATH) == OK and int(saved.get_value("options", "ladder_progress", 0)) == 1, "progress must persist in settings")

	# Rematch keeps the beaten opponent; the arrows choose among reached rungs.
	game._cycle_rematch_level(1)
	check(game.rematch_opponent == 1, "right arrow moves to the newly reached rung")
	game._cycle_rematch_level(1)
	check(game.rematch_opponent == 0, "cycling wraps within the reached rungs only")
	game._cycle_rematch_level(1)
	game._request_rematch()
	game._transition.visible = false
	check(game.state == Phase.PLANNING and game.demo_opponent == 1 and game.player_opponent(1) == 1, "rematch plays the chosen opponent")
	check(game.level_index == Opponents.arena(1), "rematch moves to the chosen opponent's arena")
	check(game.ai_moves_searched_for(1) == int(Opponents.tuning(1)["moves_searched"]), "the chosen rung's preset drives the planner")

	# Replaying an earlier rung does not move the ladder, and Start Duel resumes
	# at the next unbeaten opponent.
	game.start_demo_duel(0)
	game._transition.visible = false
	game.state = Phase.GAME_OVER
	game.winner = 0
	game._record_ladder_result(0)
	check(game.ladder_progress() == 1, "beating an earlier rung again changes nothing")
	game.start_demo_duel()
	check(game.demo_opponent == 1, "Start Duel resumes at the first unbeaten opponent")

	# The last rung never offers a next opponent.
	game._settings["ladder_progress"] = Opponents.count()
	game.start_demo_duel()
	check(game.demo_opponent == Opponents.count() - 1, "a complete ladder replays its last opponent")
	game.state = Phase.GAME_OVER
	game.winner = 0
	game._record_ladder_result(0)
	check(game.ladder_progress() == Opponents.count() and not game.next_opponent_available(), "the last rung has no next opponent")

	game._open_menu()
	check(game._menu.ladder_line != "", "the menu reports the ladder position")
	root.remove_child(game)
	game.free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))


func _rung_named(id: String) -> int:
	for i in Opponents.count():
		if Opponents.rung(i)["id"] == id:
			return i
	return -1


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
