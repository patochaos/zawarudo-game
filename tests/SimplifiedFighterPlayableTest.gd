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
			_check(visual.skin.skin_id == &"gilded_executor_animated_v1",
				"P1 must load the animated simplified skin")
			_check(visual.skin.sprite_draw_rect.size.is_equal_approx(Vector2(87.0, 58.0)),
				"the filled sprite must match the legacy fighter's perceived size")
			_check(visual.skin.ghost_texture != null,
				"the simplified fighter must provide its own planning ghost silhouette")
			_check(not visual.skin.procedural_aim_arm_enabled,
				"the proof must not draw a third arm over its baked pose")
			var expected_counts := {
				FighterVisual.IDLE: 4,
				FighterVisual.WALK: 6,
				FighterVisual.RUN: 6,
				FighterVisual.RISE: 2,
				FighterVisual.FALL: 2,
				FighterVisual.SHOT: 4,
				FighterVisual.LOCK: 2,
				FighterVisual.DEFEAT: 4,
			}
			for state: StringName in expected_counts:
				_check(visual.skin.has_sprite(state), "%s must have a review sprite" % state)
				_check(visual.skin.frame_count(state) == expected_counts[state],
					"%s must expose every authored frame" % state)
				_check(visual.skin.ghost_atlases.get(state) is Texture2D,
					"%s must have a matching animated ghost mask" % state)

			game.ghost_velocity_path[0] = PackedVector2Array([
				Vector2(180.0, 0.0), Vector2(0.0, -180.0), Vector2(0.0, 180.0),
			])
			game.ghost_ground_path[0] = PackedByteArray([1, 0, 0])
			var preview = game._preview
			var walk_ghost: Dictionary = preview._ghost_sprite_pose(executor, visual.skin, 0)
			var rise_ghost: Dictionary = preview._ghost_sprite_pose(executor, visual.skin, 1)
			var fall_ghost: Dictionary = preview._ghost_sprite_pose(executor, visual.skin, 2)
			_check(walk_ghost["state"] == FighterVisual.WALK,
				"a grounded moving ghost must use the authored WALK")
			_check(rise_ghost["state"] == FighterVisual.RISE,
				"an upward ghost must use RISE")
			_check(fall_ghost["state"] == FighterVisual.FALL,
				"a downward ghost must use FALL")
			executor.plan.shot_tick = 1
			var shot_ghost: Dictionary = preview._ghost_sprite_pose(executor, visual.skin, 1)
			_check(shot_ghost["state"] == FighterVisual.SHOT and shot_ghost["frame"] == 1,
				"the pinned release ghost must use the SHOT silhouette")
			executor.plan.shot_tick = -1

			# Exercise the authored states through the same observer logic used in play.
			executor.plan.confirmed = false
			executor.on_ground = true
			executor.vel = Vector2(180.0, 0.0)
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.WALK,
				"ordinary ground movement must select the authored WALK")
			executor.on_ground = false
			executor.vel.y = -120.0
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.RISE, "upward movement must select RISE")
			executor.vel.y = 120.0
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.FALL, "downward movement must select FALL")
			executor.on_ground = true
			executor.vel = Vector2.ZERO
			executor.plan.confirmed = true
			game.state = Phase.PLANNING
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.LOCK, "confirmation must select LOCK")
			executor.plan.shot_tick = 0
			game.state = Phase.EXECUTING
			game.exec_tick = 9
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.SHOT and visual.body_frame == 3,
				"execution must advance and clamp the SHOT sequence")
			executor.alive = false
			visual.sync_from_player()
			visual._process(0.5)
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.DEFEAT and visual.body_frame == 3,
				"the terminal DEFEAT sequence must finish after simulation stops")

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
