extends SceneTree

const GAME_MANAGER := preload("res://scripts/GameManager.gd")

var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = GAME_MANAGER.new()
	game.simplified_fighter_proto_enabled = true
	game.fighter_visuals_enabled = true
	root.add_child(game)
	await process_frame

	_check(game.players.size() == 2, "prototype match must spawn both duelists")
	if game.players.size() >= 2:
		var executor: Player = game.players[0]
		var opponent: Player = game.players[1]
		var visual := executor.get_node_or_null("FighterVisual") as FighterVisual
		_check(visual != null, "P1 must receive the simplified fighter visual")
		_check(not executor.draw_legacy_visual, "P1 legacy body must be suppressed")
		_check(opponent.draw_legacy_visual, "opponents must retain distinct legacy silhouettes")
		_check(opponent.get_node_or_null("FighterVisual") == null,
			"opponents must not receive a recolored Executor")
		_check(executor.rect().size.is_equal_approx(Vector2(32.0, 48.0)),
			"the simplified sprite must not change collision")
		if visual != null:
			_check(visual.skin.skin_id == &"gilded_executor_simplified_proof_v1",
				"P1 must load the simplified proof skin")
			_check(not visual.skin.procedural_aim_arm_enabled,
				"the proof must not draw a third arm over its baked pose")
			for state in [FighterVisual.IDLE, FighterVisual.RUN, FighterVisual.RISE,
					FighterVisual.FALL, FighterVisual.SHOT, FighterVisual.LOCK]:
				_check(visual.skin.has_sprite(state), "%s must have a review sprite" % state)

	root.remove_child(game)
	game.free()
	await process_frame
	if _failures == 0:
		print("Simplified fighter playable: all tests passed")
	else:
		push_error("Simplified fighter playable: %d failure(s)" % _failures)
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
