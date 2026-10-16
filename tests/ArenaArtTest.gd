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
		_check_layers(backdrop, level)
		# Planning is cold and still: no warm light, no slide, even when the
		# fighters stand off-centre. Execution lights the room and lets the far
		# layer follow the fight; both reset with the arena.
		game.players[0].position = Vector2(200.0, 300.0)
		game.players[1].position = Vector2(300.0, 320.0)
		_check(backdrop.fight_offset() != Vector2.ZERO,
			"arena %d test fighters must stand off-centre" % level)
		var moved_digest: String = game._online_state_digest()
		for phase in [Phase.PLANNING, Phase.COMMITTING, Phase.ONLINE_WAIT]:
			game.state = phase
			backdrop._process(0.25)
		_check(backdrop.warm == 0.0 and backdrop.parallax == Vector2.ZERO,
			"arena %d must stay cold and still while waiting" % level)
		game.state = Phase.EXECUTING
		backdrop._process(0.25)
		_check(backdrop.warm > 0.0 and backdrop.parallax != Vector2.ZERO,
			"arena %d execution must add warm light and slide the layers" % level)
		for _step in 40:
			backdrop._process(0.25)
		_check(backdrop.warm == 1.0 and backdrop.parallax.distance_to(backdrop.fight_offset()) < 1.0,
			"arena %d warm light and slide must settle on the fight" % level)
		_check(backdrop.parallax.length() * backdrop.FAR_PARALLAX < 16.0,
			"arena %d far layer slide must stay within its bleed" % level)
		game.state = Phase.PLANNING
		_check(game._online_state_digest() == moved_digest,
			"arena %d lighting and slide must leave gameplay state untouched" % level)
		backdrop.show_level(level)
		_check(backdrop.warm == 0.0 and backdrop.parallax == Vector2.ZERO,
			"arena %d restart must reset lighting and slide" % level)
	game.free()
	await process_frame
	if _failures == 0:
		print("Arena art: all tests passed")
	quit(_failures)


## Every layer keeps the frame's aspect plus its bleed, so the runtime rects
## scale each texture uniformly whatever resolution Blender rendered it at.
func _check_layers(backdrop, level: int) -> void:
	var far_ratio: float = backdrop.FAR_RECT.size.x / backdrop.FAR_RECT.size.y
	var mid_ratio: float = backdrop.MID_RECT.size.x / backdrop.MID_RECT.size.y
	for pair in [[backdrop.FAR, far_ratio], [backdrop.FAR_WARM, far_ratio],
			[backdrop.MID, mid_ratio], [backdrop.MID_WARM, mid_ratio]]:
		var texture: Texture2D = pair[0][backdrop.level_theme]
		var size := texture.get_size()
		_check(absf(size.x / size.y - pair[1]) < 0.01,
			"arena %d layer %s must keep its bleed aspect" % [level, texture.resource_path])
	_check(backdrop.MID[backdrop.level_theme].get_size().x >= 1312.0,
		"arena %d mid layer must be at least native resolution" % level)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
