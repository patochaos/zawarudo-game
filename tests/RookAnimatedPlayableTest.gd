extends SceneTree

const GAME_MANAGER := preload("res://scripts/GameManager.gd")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = GAME_MANAGER.new()
	game.simplified_fighter_proto_enabled = true
	game.fighter_visuals_enabled = true
	game.player_weapons[0] = game.Weapon.DASHBLADE
	root.add_child(game)
	await process_frame

	_check(game.players.size() == 2, "Rook prototype match must spawn two fighters")
	if game.players.size() >= 2:
		var rook: Player = game.players[0]
		var opponent: Player = game.players[1]
		var visual := rook.get_node_or_null("FighterVisual") as FighterVisual
		_check(visual != null, "DASHBLADE must receive the Rook fighter visual")
		_check(opponent.get_node_or_null("FighterVisual") == null,
			"a non-Duelist opponent must not receive recolored Rook artwork")
		_check(rook.rect().size.is_equal_approx(Vector2(32.0, 48.0)),
			"Rook artwork must not change the authoritative collision box")
		if visual != null:
			_check(visual.skin.skin_id == &"rook_animated_v1",
				"DASHBLADE must select only the Rook skin")
			_check(visual.skin.sprite_cell_size == Vector2i(384, 256),
				"Rook atlases must use 384x256 cells")
			_check(visual.skin.sprite_draw_rect.size.is_equal_approx(Vector2(87.0, 58.0)),
				"Rook must use the accepted 87x58 draw rectangle")
			_check(not visual.skin.procedural_aim_arm_enabled,
				"authored Rook equipment must not receive a procedural third arm")
			var counts := {
				FighterVisual.IDLE: 4,
				FighterVisual.WALK: 6,
				FighterVisual.RUN: 6,
				FighterVisual.RISE: 2,
				FighterVisual.FALL: 2,
				FighterVisual.LOCK: 2,
				FighterVisual.SHOT: 4,
				FighterVisual.DEFEAT: 4,
			}
			for state: StringName in counts:
				_check(visual.skin.has_sprite(state), "%s must have a Rook atlas" % state)
				_check(visual.skin.frame_count(state) == counts[state],
					"%s must expose its required Rook frame count" % state)
				_check(visual.skin.ghost_atlases.get(state) is Texture2D,
					"%s must have an adaptive ghost atlas" % state)

			rook.plan.confirmed = false
			rook.on_ground = true
			rook.vel = Vector2.ZERO
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.IDLE, "standing Rook must select IDLE")
			rook.vel.x = 180.0
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.WALK, "heavy advance must select WALK")
			rook.vel.x = 500.0
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.RUN, "fast advance must select RUN")
			rook.on_ground = false
			rook.vel = Vector2(0.0, -180.0)
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.RISE, "upward route must select RISE")
			rook.vel.y = 180.0
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.FALL, "downward route must select FALL")
			rook.on_ground = true
			rook.vel = Vector2.ZERO
			rook.plan.confirmed = true
			game.state = Phase.PLANNING
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.LOCK, "confirmation must select LOCK")
			rook.plan.shot_tick = 0
			game.state = Phase.EXECUTING
			game.exec_tick = 9
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.SHOT and visual.body_frame == 3,
				"BREAK LINE must advance and clamp the four-frame SHOT sequence")

			game.ghost_velocity_path[0] = PackedVector2Array([
				Vector2.ZERO, Vector2(180.0, 0.0), Vector2(500.0, 0.0),
				Vector2(0.0, -180.0), Vector2(0.0, 180.0),
			])
			game.ghost_ground_path[0] = PackedByteArray([1, 1, 1, 0, 0])
			rook.plan.shot_tick = -1
			var preview = game._preview
			_check(preview._ghost_sprite_pose(rook, visual.skin, 0)["state"] == FighterVisual.IDLE,
				"stationary prediction must select ghost IDLE")
			_check(preview._ghost_sprite_pose(rook, visual.skin, 1)["state"] == FighterVisual.WALK,
				"moving prediction must select ghost WALK")
			_check(preview._ghost_sprite_pose(rook, visual.skin, 2)["state"] == FighterVisual.RUN,
				"fast prediction must select ghost RUN")
			_check(preview._ghost_sprite_pose(rook, visual.skin, 3)["state"] == FighterVisual.RISE,
				"upward prediction must select ghost RISE")
			_check(preview._ghost_sprite_pose(rook, visual.skin, 4)["state"] == FighterVisual.FALL,
				"downward prediction must select ghost FALL")
			rook.plan.shot_tick = 2
			var shot_ghost: Dictionary = preview._ghost_sprite_pose(rook, visual.skin, 2)
			_check(shot_ghost["state"] == FighterVisual.SHOT and shot_ghost["frame"] == 1,
				"pinned BREAK LINE prediction must select the SHOT ghost")

			rook.facing = 1
			var right_signature := visual.body_signature()
			rook.facing = -1
			var left_signature := visual.body_signature()
			_check(right_signature.ends_with(":1") and left_signature.ends_with(":-1"),
				"Rook frames must mirror through the authoritative facing transform")
			_check(is_equal_approx(visual.skin.sprite_draw_rect.position.x,
				-visual.skin.sprite_draw_rect.size.x * 0.5),
				"the draw rectangle must be centered for lossless mirroring")

			rook.alive = false
			visual.sync_from_player()
			visual._process(0.5)
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.DEFEAT and visual.body_frame == 3,
				"DEFEAT must finish after deterministic simulation stops")

	game.player_weapons[1] = game.Weapon.DASHBLADE
	var second_skin = game._fighter_skin_for(1)
	_check(second_skin != null and second_skin.skin_id == &"rook_animated_v1",
		"Rook selection must follow DASHBLADE identity rather than player index")
	second_skin = null

	root.remove_child(game)
	game.free()
	await process_frame
	if _failures == 0:
		print("Rook animated playable: all tests passed")
	else:
		push_error("Rook animated playable: %d failure(s)" % _failures)
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
