extends SceneTree

const GAME_MANAGER := preload("res://scripts/GameManager.gd")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = GAME_MANAGER.new()
	game.player_weapons[0] = game.Weapon.CHAKRAM
	root.add_child(game)
	await process_frame

	_check(game.players.size() == 2, "normal Eclipse match must spawn two fighters")
	if game.players.size() >= 2:
		var eclipse: Player = game.players[0]
		var opponent: Player = game.players[1]
		var visual := eclipse.get_node_or_null("FighterVisual") as FighterVisual
		_check(visual != null, "CHAKRAM must receive the Eclipse fighter visual")
		_check(not eclipse.draw_legacy_visual, "Eclipse's legacy body must be suppressed")
		var rival_visual := opponent.get_node_or_null("FighterVisual") as FighterVisual
		_check(rival_visual != null and rival_visual.skin.skin_id != &"eclipse_animated_v1",
			"a non-Eclipse opponent must never be drawn with Eclipse artwork")
		_check(eclipse.rect().size.is_equal_approx(Vector2(32.0, 48.0)),
			"Eclipse artwork must not change the authoritative collision box")
		if visual != null:
			_check(visual.skin.skin_id == &"eclipse_animated_v1",
				"CHAKRAM must select only the Eclipse skin")
			_check(visual.skin.sprite_cell_size == Vector2i(384, 256),
				"Eclipse atlases must use 384x256 cells")
			_check(visual.skin.sprite_draw_rect.size.is_equal_approx(Vector2(87.0, 58.0)),
				"Eclipse must use the accepted 87x58 draw rectangle")
			_check(not visual.skin.procedural_aim_arm_enabled,
				"authored Eclipse gestures must not receive a procedural third arm")
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
				_check(visual.skin.has_sprite(state), "%s must have an Eclipse atlas" % state)
				_check(visual.skin.frame_count(state) == counts[state],
					"%s must expose its required Eclipse frame count" % state)
				_check(visual.skin.ghost_atlases.get(state) is Texture2D,
					"%s must have an adaptive Eclipse ghost atlas" % state)

			eclipse.plan.confirmed = false
			eclipse.on_ground = true
			eclipse.vel = Vector2.ZERO
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.IDLE, "standing Eclipse must select IDLE")
			eclipse.vel.x = 180.0
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.WALK, "Eclipse procession must select WALK")
			eclipse.vel.x = 500.0
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.RUN, "fast Eclipse glide must select RUN")
			eclipse.on_ground = false
			eclipse.vel = Vector2(0.0, -180.0)
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.RISE, "Eclipse ascent must select RISE")
			eclipse.vel.y = 180.0
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.FALL, "Eclipse descent must select FALL")
			eclipse.on_ground = true
			eclipse.vel = Vector2.ZERO
			eclipse.plan.confirmed = true
			game.state = Phase.PLANNING
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.LOCK, "confirmation must select Eclipse LOCK")
			eclipse.plan.shot_tick = 0
			game.state = Phase.EXECUTING
			game.exec_tick = 9
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.SHOT and visual.body_frame == 3,
				"DECREE must advance and clamp the four-frame SHOT sequence")

			game.ghost_velocity_path[0] = PackedVector2Array([
				Vector2.ZERO, Vector2(180.0, 0.0), Vector2(500.0, 0.0),
				Vector2(0.0, -180.0), Vector2(0.0, 180.0),
			])
			game.ghost_ground_path[0] = PackedByteArray([1, 1, 1, 0, 0])
			eclipse.plan.shot_tick = -1
			var preview = game._preview
			_check(preview._ghost_sprite_pose(eclipse, visual.skin, 0)["state"] == FighterVisual.IDLE,
				"stationary Eclipse prediction must select ghost IDLE")
			_check(preview._ghost_sprite_pose(eclipse, visual.skin, 1)["state"] == FighterVisual.WALK,
				"moving Eclipse prediction must select ghost WALK")
			_check(preview._ghost_sprite_pose(eclipse, visual.skin, 2)["state"] == FighterVisual.RUN,
				"fast Eclipse prediction must select ghost RUN")
			_check(preview._ghost_sprite_pose(eclipse, visual.skin, 3)["state"] == FighterVisual.RISE,
				"upward Eclipse prediction must select ghost RISE")
			_check(preview._ghost_sprite_pose(eclipse, visual.skin, 4)["state"] == FighterVisual.FALL,
				"downward Eclipse prediction must select ghost FALL")
			eclipse.plan.shot_tick = 2
			var shot_ghost: Dictionary = preview._ghost_sprite_pose(eclipse, visual.skin, 2)
			_check(shot_ghost["state"] == FighterVisual.SHOT and shot_ghost["frame"] == 1,
				"pinned DECREE prediction must select the SHOT ghost")

			eclipse.facing = 1
			var right_signature := visual.body_signature()
			eclipse.facing = -1
			var left_signature := visual.body_signature()
			_check(right_signature.ends_with(":1") and left_signature.ends_with(":-1"),
				"Eclipse frames must mirror through the authoritative facing transform")
			_check(is_equal_approx(visual.skin.sprite_draw_rect.position.x,
				-visual.skin.sprite_draw_rect.size.x * 0.5),
				"the Eclipse draw rectangle must be centered for lossless mirroring")

			eclipse.alive = false
			visual.sync_from_player()
			visual._process(0.5)
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.DEFEAT and visual.body_frame == 3,
				"Eclipse DEFEAT must finish after deterministic simulation stops")

	game.player_weapons[1] = game.Weapon.CHAKRAM
	var second_skin = game._fighter_skin_for(1)
	_check(second_skin != null and second_skin.skin_id == &"eclipse_animated_v1",
		"Eclipse selection must follow CHAKRAM identity rather than player index")
	var first_skin = game._fighter_skin_for(0)
	_check(first_skin != null and not first_skin.sprite_tint.is_equal_approx(second_skin.sprite_tint),
		"two Eclipses must carry their own player accents")
	_check(second_skin.palette[&"body"].is_equal_approx(game.PLAYER_COLORS[1]),
		"Eclipse world markers must follow the player identity colour")
	second_skin = null
	first_skin = null

	root.remove_child(game)
	game.free()
	await process_frame
	if _failures == 0:
		print("Eclipse animated playable: all tests passed")
	else:
		push_error("Eclipse animated playable: %d failure(s)" % _failures)
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
