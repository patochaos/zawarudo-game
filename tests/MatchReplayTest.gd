extends SceneTree

const GAME_MANAGER := preload("res://scripts/GameManager.gd")

var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var gm = GAME_MANAGER.new()
	root.add_child(gm)
	await process_frame

	gm._replay_frames.clear()
	gm.state = Phase.PLANNING
	gm._capture_replay_frame()
	_check(gm._replay_frames.is_empty(), "planning time must never enter the replay")

	gm.state = Phase.EXECUTING
	gm.players[0].position = Vector2(120.0, 300.0)
	gm.score[0] = 1
	gm._capture_replay_frame()
	gm.players[0].position = Vector2(420.0, 300.0)
	gm.score[0] = 3
	gm.winner = 0
	gm.state = Phase.GAME_OVER
	gm._capture_replay_frame()
	await process_frame
	_check(gm.state == Phase.GAME_OVER,
		"finishing a match must stay on the result screen instead of auto-playing replay")

	gm._start_match_replay()
	_check(gm.state == Phase.REPLAY, "a finished match must enter replay playback")
	_check(gm.players[0].position.is_equal_approx(Vector2(120.0, 300.0)),
		"replay must begin at its first execution snapshot")
	_check(gm.score[0] == 1, "replay must restore the historical score")

	var one_replay_tick: float = gm.tick_dt() / gm.replay_speed * 1.01
	gm._tick_match_replay(one_replay_tick)
	_check(gm.players[0].position.is_equal_approx(Vector2(420.0, 300.0)),
		"replay must advance through recorded snapshots at the configured speed")
	_check(gm.score[0] == 3, "replay must reach the terminal score")
	gm._tick_match_replay(one_replay_tick)
	_check(gm.state == Phase.GAME_OVER, "replay must return to the match-over screen")
	_check(not gm._replay_frames.is_empty(), "finished replay data must remain available on demand")
	gm._start_match_replay()
	_check(gm.state == Phase.REPLAY, "the result screen must allow replay to be watched again")
	gm._finish_match_replay()

	gm._replay_frames.clear()
	gm.replay_history_seconds = 2.0 / float(Engine.physics_ticks_per_second)
	gm.state = Phase.EXECUTING
	var frames_to_force_compaction: int = int(ceil(gm.REPLAY_COMPACTION_SLACK_SECONDS \
		* float(Engine.physics_ticks_per_second))) + 3
	for i in frames_to_force_compaction:
		gm.score[0] = i
		gm._capture_replay_frame()
	_check(gm._replay_frames.size() <= gm.replay_frame_capacity(),
		"long matches must compact replay snapshots to the configured memory bound")
	_check(gm._replay_frames.back()["score"][0] == frames_to_force_compaction - 1,
		"replay compaction must preserve the newest execution snapshot")
	gm.replay_history_seconds = 30.0
	gm.state = Phase.GAME_OVER

	var previous_level: int = gm.level_index
	gm._cycle_rematch_level(1)
	_check(gm.level_index == previous_level and gm.rematch_level_index != previous_level,
		"choosing a rematch level must not replace the frozen result arena")
	var selected_level: int = gm.rematch_level_index
	gm._request_rematch()
	_check(gm.level_index == selected_level and gm.state == Phase.PLANNING,
		"rematch must start on the level selected from the result screen")

	gm.free()
	if _failures == 0:
		print("Match replay: all tests passed")
	else:
		push_error("Match replay: %d test(s) failed" % _failures)
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
