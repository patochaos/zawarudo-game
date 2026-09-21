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
	for level in Levels.count():
		game.start_quick_match(false, level, 2)
		game.set_physics_process(false)
		var backdrop = game._backdrop
		backdrop.set_process(false)
		var digest: String = game._online_state_digest()
		var p: Vector2 = backdrop.observatory_mote_position(5)
		for phase in [Phase.PLANNING, Phase.COMMITTING, Phase.ONLINE_WAIT]:
			game.state = phase
			backdrop._process(0.25)
			_check(backdrop.observatory_mote_position(5) == p,
				"arena %d air must remain frozen while waiting" % level)
		game.state = Phase.EXECUTING
		backdrop._process(0.25)
		_check(backdrop.observatory_mote_position(5) != p,
			"arena %d air must resume" % level)
		game.state = Phase.PLANNING
		_check(game._online_state_digest() == digest,
			"arena %d atmosphere must leave gameplay state untouched" % level)
		backdrop.show_level(level)
		_check(backdrop.observatory_mote_position(5) == p,
			"arena %d restart must reset cosmetic air" % level)
	game.free()
	await process_frame
	if _failures == 0:
		print("Arena art: all tests passed")
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
