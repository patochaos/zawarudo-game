extends SceneTree

const MAIN := preload("res://scenes/Main.tscn")
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = MAIN.instantiate()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game.start_quick_match(false, 2, 2)
	game.set_physics_process(false)
	var backdrop = game._backdrop
	backdrop.set_process(false)
	var initial: Vector2 = backdrop.counterweight_position(false)
	game.state = Phase.EXECUTING
	for i in 30:
		game.exec_tick = i
		game._sim_tick(game.tick_dt())
	var moved: Vector2 = backdrop.counterweight_position(false)
	_check(moved != initial, "real execution ticks must move the machinery")
	game.state = Phase.PLANNING
	var digest: String = game._online_state_digest()
	for phase in [Phase.PLANNING, Phase.COMMITTING, Phase.ONLINE_WAIT, Phase.MENU, Phase.GAME_OVER]:
		game.state = phase
		backdrop._process(1.0)
		_check(backdrop.counterweight_position(false) == moved, "stopped phases must preserve machinery position")
	game.state = Phase.EXECUTING
	game._super_freeze.play(0, Color.GOLD)
	backdrop._process(1.0)
	_check(backdrop.counterweight_position(false) == moved, "SUPER pause must not advance machinery on wall time")
	game._super_freeze.cancel()
	game.state = Phase.PLANNING
	_check(game._online_state_digest() == digest, "machinery must not change the gameplay digest")
	# Replay restores the same clock, including backwards seeks.
	game.state = Phase.EXECUTING
	game._capture_replay_frame()
	var frame: Dictionary = game._replay_frames.back().duplicate(true)
	game.world_tick += 90
	_check(backdrop.counterweight_position(false) != moved, "later simulation time must have a different pose")
	game.state = Phase.REPLAY
	game._apply_replay_frame(frame)
	_check(backdrop.counterweight_position(false) == moved, "replay must restore the recorded machinery pose")
	game.state = Phase.FREEPLAY
	var free_before: Vector2 = backdrop.counterweight_position(false)
	backdrop._process(0.5)
	_check(backdrop.counterweight_position(false) != free_before, "free play must animate without world ticks")
	game.start_quick_match(false, 2, 2)
	game.set_physics_process(false)
	_check(backdrop.counterweight_position(false) == initial, "rematch must reset machinery")
	game.free()
	await process_frame
	if failures == 0:
		print("Pendulum machinery: all tests passed")
	quit(failures)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
