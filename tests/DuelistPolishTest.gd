extends SceneTree

const MAIN := preload("res://scenes/Main.tscn")
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = MAIN.instantiate()
	# Planning-time checks must not read the developer's saved Game Tuning profile.
	game.offline_tuning_path = "user://test-duelistpolishtest-tuning.cfg"
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game.start_quick_match(false, 0, 2)
	_check(game._planning_duration_for_turn(1) == 4.0 and game._planning_duration_for_turn(30) == 4.0, "Planning remains four seconds")
	var plan: PlayerPlan = game.players[0].plan
	for tick in 18:
		game._pilot_step(0, 1, tick == 0, tick < 9)
	game._rebuild_ghost_path(0)
	var retained_position: Vector2 = game.ghost_path[0][12]
	var retained_velocity: Vector2 = game.ghost_velocity_path[0][12]
	plan.shot_tick = 6
	plan.power = 0.72
	game._rewind_plan(0, 12)
	_check(plan.recorded_ticks() == 12 and game.ghost_pos[0].is_equal_approx(retained_position)
		and game.ghost_vel[0].is_equal_approx(retained_velocity), "Rewind reproduces the airborne prefix exactly")
	_check(plan.shot_tick == 6 and is_equal_approx(plan.power, 0.72), "Rewind preserves an earlier throw and its charge")
	_check(is_equal_approx(game.stamina[0], game.movement_budget - 12 * game.tick_dt()), "Rewind refunds only removed movement")
	game._shift_shot(0, 999)
	_check(plan.shot_tick == 12, "Throw cannot be retimed past the recording")
	game._rewind_plan(0, 6)
	_check(not plan.has_shot(), "Rewinding past a throw removes it")
	plan.shot_tick = 4
	plan.confirmed = true
	game._rewind_plan(0, 0)
	game._shift_shot(0, -2)
	_check(plan.recorded_ticks() == 6 and plan.shot_tick == 4, "Locked plans cannot be edited")
	plan.confirmed = false
	game.online_mode = true
	game.online_player = 0
	game._online_plan_sent = true
	game._rewind_plan(0, 0)
	_check(plan.recorded_ticks() == 6, "A submitted online plan is immutable")
	_check(game._ui._planning_timeline.visible_players() == [0], "Timeline never exposes the remote plan")
	game.online_mode = false
	game._online_plan_sent = false
	game._rewind_plan(0, 0)
	_check(plan.recorded_ticks() == 0 and game.ghost_pos[0] == game.players[0].position, "Full rewind restores live start state")
	# Force a bank on the left wall; a sample must still represent exactly one tick.
	var start := Vector2(5.0, 580.0)
	var velocity := Vector2(-720.0, 0.0)
	var prediction := PredictionSystem.predict_arrow(start, velocity, game, game.tick_dt(), game.world_tick)
	_check(prediction.path.size() == 2 and not prediction.blocked, "A ricochet consumes one preview tick")
	var exhausted := PredictionSystem.predict_arrow(start, velocity, game, game.tick_dt(), game.world_tick, false, game.knife_ricochet_limit)
	_check(exhausted.blocked, "Preview respects an existing knife's exhausted ricochet budget")
	game._effects.clear_all()
	game._effects.remember("HIT", Vector2.ZERO, Color.WHITE)
	for i in 8:
		game._effects.remember("CLASH", Vector2(i, 0), Color.WHITE)
	_check(game._effects._remembered.size() == 3 and game._effects._remembered.any(func(e): return e.label == "HIT"), "Incidental clashes cannot evict hit feedback")
	# Review must freeze the planning clock and leave the live digest untouched.
	game._begin_execution()
	for tick in 12:
		game._sim_tick(game.tick_dt())
		game._capture_replay_frame()
	game._end_execution()
	var digest: String = game._online_state_digest()
	var timer: float = game.planning_time_left
	_check(game._ui._turn_review.open_last_turn(), "Offline last-turn review opens")
	game._ui._turn_review.seek(4)
	game._physics_process(0.5)
	_check(game.planning_time_left == timer and game._online_state_digest() == digest,
		"Review pauses planning without installing historical state")
	game._ui._turn_review.visible = false
	game.online_mode = true
	_check(not game._ui._turn_review.open_last_turn(), "Online matches cannot pause for a private review")
	game.online_mode = false
	root.remove_child(game)
	game.free()
	await process_frame
	if failures == 0:
		print("Duelist polish: all tests passed")
	quit(failures)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
