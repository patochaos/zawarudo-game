extends SceneTree

const MAIN := preload("res://scenes/Main.tscn")
var _failures := 0


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
	var fighter: Player = game.players[0]
	var visual := fighter.get_node("FighterVisual") as FighterVisual
	visual.set_process(false)
	var digest: String = game._online_state_digest()
	var before: Vector2 = backdrop.observatory_mote_position(4)
	backdrop._process(0.5)
	_check(backdrop.observatory_mote_position(4) == before, "planning must freeze the dust")
	for phase in [Phase.COMMITTING, Phase.ONLINE_WAIT, Phase.MENU]:
		game.state = phase
		backdrop._process(0.5)
		_check(backdrop.observatory_mote_position(4) == before, "waiting and menus must freeze dust")
	game.state = Phase.EXECUTING
	backdrop._process(0.5)
	_check(backdrop.observatory_mote_position(4) != before, "execution must resume dust")
	var resumed: Vector2 = backdrop.observatory_mote_position(4)
	game.state = Phase.PLANNING
	backdrop._process(0.5)
	_check(backdrop.observatory_mote_position(4) == resumed, "next planning must preserve the new dust positions")
	_check(game._online_state_digest() == digest, "cosmetic atmosphere must not affect lockstep state")

	fighter.plan.shot_tick = 12
	fighter.plan.confirmed = false
	fighter.on_ground = true
	fighter.vel = Vector2.ZERO
	game.state = Phase.EXECUTING
	for sample in [[8, FighterVisual.IDLE, 0], [9, FighterVisual.SHOT, 0],
			[12, FighterVisual.SHOT, 1], [15, FighterVisual.SHOT, 2], [18, FighterVisual.SHOT, 3]]:
		game.exec_tick = sample[0]
		visual.sync_from_player()
		_check(visual.body_state == sample[1] and visual.body_frame == sample[2],
			"Duelist must anticipate, release and recover at tick %d" % sample[0])
	game.state = Phase.REPLAY
	game._replay_frame_index = 12
	visual.sync_from_player()
	_check(visual.body_state == FighterVisual.SHOT and visual.body_frame == 1,
		"replay must show the same extended arm at release")
	game.state = Phase.PLANNING
	game.exec_tick = 9
	visual.sync_from_player()
	_check(visual.body_state != FighterVisual.SHOT, "planning must not reveal the opponent's wind-up")
	_check(fighter.rect().size == Vector2(32, 48), "art must preserve fighter collision")
	root.remove_child(game)
	game.free()
	await process_frame
	if _failures == 0:
		print("Pendulum art: all tests passed")
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
