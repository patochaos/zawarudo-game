extends SceneTree

const GAME_MANAGER := preload("res://scripts/GameManager.gd")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = GAME_MANAGER.new()
	game.player_weapons[0] = game.Weapon.SHOCK
	root.add_child(game)
	await process_frame

	_check(game.players.size() == 2, "normal Pulse match must spawn two fighters")
	if game.players.size() >= 2:
		var pulse: Player = game.players[0]
		var opponent: Player = game.players[1]
		var visual := pulse.get_node_or_null("FighterVisual") as FighterVisual
		_check(visual != null, "SHOCK must receive the Pulse fighter visual")
		_check(not pulse.draw_legacy_visual, "Pulse's legacy body must be suppressed")
		var rival_visual := opponent.get_node_or_null("FighterVisual") as FighterVisual
		_check(rival_visual != null and rival_visual.skin.skin_id != &"pulse_animated_v2",
			"a non-Pulse opponent must never be drawn with Pulse artwork")
		_check(pulse.rect().size.is_equal_approx(Vector2(32.0, 48.0)),
			"Pulse artwork must not change the authoritative collision box")
		if visual != null:
			_check(visual.skin.skin_id == &"pulse_animated_v2",
				"SHOCK must select only the Pulse skin")
			_check(visual.skin.sprite_cell_size == Vector2i(384, 256),
				"Pulse atlases must use 384x256 cells")
			_check(visual.skin.sprite_draw_rect.size.is_equal_approx(Vector2(87.0, 58.0)),
				"Pulse must use the accepted 87x58 draw rectangle")
			_check(not visual.skin.procedural_aim_arm_enabled,
				"the authored tuning-fork baton must not receive a procedural third arm")
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
				_check(visual.skin.has_sprite(state), "%s must have a Pulse atlas" % state)
				_check(visual.skin.frame_count(state) == counts[state],
					"%s must expose its required Pulse frame count" % state)
				_check(visual.skin.ghost_atlases.get(state) is Texture2D,
					"%s must have an adaptive Pulse ghost atlas" % state)

			pulse.plan.confirmed = false
			pulse.on_ground = true
			pulse.vel = Vector2.ZERO
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.IDLE, "standing Pulse must select IDLE")
			pulse.vel.x = 180.0
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.WALK, "Pulse advance must select WALK")
			pulse.vel.x = 500.0
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.RUN, "fast Pulse advance must select RUN")
			pulse.on_ground = false
			pulse.vel = Vector2(0.0, -180.0)
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.RISE, "upward Pulse route must select RISE")
			pulse.vel.y = 180.0
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.FALL, "downward Pulse route must select FALL")
			pulse.on_ground = true
			pulse.vel = Vector2.ZERO
			pulse.plan.confirmed = true
			game.state = Phase.PLANNING
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.LOCK, "Pulse confirmation must select LOCK")
			pulse.plan.shot_tick = 0
			game.state = Phase.EXECUTING
			game.exec_tick = 9
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.SHOT and visual.body_frame == 3,
				"Pulse conductor cut must advance and clamp the four-frame SHOT sequence")

			game.ghost_velocity_path[0] = PackedVector2Array([
				Vector2.ZERO, Vector2(180.0, 0.0), Vector2(500.0, 0.0),
				Vector2(0.0, -180.0), Vector2(0.0, 180.0),
			])
			game.ghost_ground_path[0] = PackedByteArray([1, 1, 1, 0, 0])
			pulse.plan.shot_tick = -1
			var preview = game._preview
			_check(preview._ghost_sprite_pose(pulse, visual.skin, 0)["state"] == FighterVisual.IDLE,
				"stationary Pulse prediction must select ghost IDLE")
			_check(preview._ghost_sprite_pose(pulse, visual.skin, 1)["state"] == FighterVisual.WALK,
				"moving Pulse prediction must select ghost WALK")
			_check(preview._ghost_sprite_pose(pulse, visual.skin, 2)["state"] == FighterVisual.RUN,
				"fast Pulse prediction must select ghost RUN")
			_check(preview._ghost_sprite_pose(pulse, visual.skin, 3)["state"] == FighterVisual.RISE,
				"upward Pulse prediction must select ghost RISE")
			_check(preview._ghost_sprite_pose(pulse, visual.skin, 4)["state"] == FighterVisual.FALL,
				"downward Pulse prediction must select ghost FALL")
			pulse.plan.shot_tick = 2
			var shot_ghost: Dictionary = preview._ghost_sprite_pose(pulse, visual.skin, 2)
			_check(shot_ghost["state"] == FighterVisual.SHOT and shot_ghost["frame"] == 1,
				"pinned Pulse release prediction must select the SHOT ghost")

			pulse.facing = 1
			var right_signature := visual.body_signature()
			pulse.facing = -1
			var left_signature := visual.body_signature()
			_check(right_signature.ends_with(":1") and left_signature.ends_with(":-1"),
				"Pulse frames must mirror through the authoritative facing transform")
			_check(is_equal_approx(visual.skin.sprite_draw_rect.position.x,
				-visual.skin.sprite_draw_rect.size.x * 0.5),
				"the Pulse draw rectangle must be centered for lossless mirroring")

			pulse.alive = false
			visual.sync_from_player()
			visual._process(0.5)
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.DEFEAT and visual.body_frame == 3,
				"Pulse DEFEAT must finish after deterministic simulation stops")

	game.player_weapons[1] = game.Weapon.SHOCK
	var second_skin = game._fighter_skin_for(1)
	_check(second_skin != null and second_skin.skin_id == &"pulse_animated_v2",
		"Pulse selection must follow SHOCK identity rather than player index")
	var first_skin = game._fighter_skin_for(0)
	_check(first_skin != null and not first_skin.sprite_tint.is_equal_approx(second_skin.sprite_tint),
		"two Pulses must carry their own player accents")
	_check(second_skin.palette[&"body"].is_equal_approx(game.PLAYER_COLORS[1]),
		"Pulse world markers must follow the player identity colour")
	second_skin = null
	first_skin = null

	root.remove_child(game)
	game.free()
	await process_frame
	if _failures == 0:
		print("Pulse animated playable: all tests passed")
	else:
		push_error("Pulse animated playable: %d failure(s)" % _failures)
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
