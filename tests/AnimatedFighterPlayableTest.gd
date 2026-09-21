extends SceneTree

const GAME_MANAGER := preload("res://scripts/GameManager.gd")
const CASES := [
	[GAME_MANAGER.Weapon.DASHBLADE, &"rook_animated_v2"],
	[GAME_MANAGER.Weapon.SHOCK, &"pulse_animated_v2"],
	[GAME_MANAGER.Weapon.CHAKRAM, &"eclipse_animated_v1"],
]
var _failures := 0
var _case_name := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for fighter_case in CASES:
		_case_name = fighter_case[1]
		await _test_fighter(fighter_case[0], fighter_case[1])
	if _failures == 0:
		print("Animated fighters: all tests passed")
	else:
		push_error("Animated fighters: %d failure(s)" % _failures)
	quit(_failures)


func _test_fighter(weapon: int, skin_id: StringName) -> void:
	var game = GAME_MANAGER.new()
	game.player_weapons[0] = weapon
	root.add_child(game)
	await process_frame

	_check(game.players.size() == 2, "normal fighter match must spawn two fighters")
	if game.players.size() >= 2:
		var fighter: Player = game.players[0]
		var opponent: Player = game.players[1]
		var visual := fighter.get_node_or_null("FighterVisual") as FighterVisual
		_check(visual != null, "selected weapon must receive a fighter visual")
		_check(not fighter.draw_legacy_visual, "fighter's legacy body must be suppressed")
		var rival_visual := opponent.get_node_or_null("FighterVisual") as FighterVisual
		_check(rival_visual != null and rival_visual.skin.skin_id != skin_id,
			"the Duelist opponent must keep its own artwork")
		_check(fighter.rect().size.is_equal_approx(Vector2(32.0, 48.0)),
			"fighter artwork must not change the authoritative collision box")
		if visual != null:
			_check(visual.skin.skin_id == skin_id,
				"selected weapon must select its expected skin")
			_check(visual.skin.sprite_cell_size == Vector2i(384, 256),
				"fighter atlases must use 384x256 cells")
			_check(visual.skin.sprite_draw_rect.size.is_equal_approx(Vector2(87.0, 58.0)),
				"fighter must use the accepted 87x58 draw rectangle")
			_check(not visual.skin.procedural_aim_arm_enabled,
				"authored sprites must not receive a procedural third arm")
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
				_check(visual.skin.has_sprite(state), "%s must have a fighter atlas" % state)
				_check(visual.skin.frame_count(state) == counts[state],
					"%s must expose its required fighter frame count" % state)
				_check(visual.skin.ghost_atlases.get(state) is Texture2D,
					"%s must have an adaptive fighter ghost atlas" % state)

			fighter.plan.confirmed = false
			fighter.on_ground = true
			fighter.vel = Vector2.ZERO
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.IDLE, "standing fighter must select IDLE")
			fighter.vel.x = 180.0
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.WALK, "fighter advance must select WALK")
			fighter.vel.x = 500.0
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.RUN, "fast fighter advance must select RUN")
			fighter.on_ground = false
			fighter.vel = Vector2(0.0, -180.0)
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.RISE, "upward fighter route must select RISE")
			fighter.vel.y = 180.0
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.FALL, "downward fighter route must select FALL")
			fighter.on_ground = true
			fighter.vel = Vector2.ZERO
			fighter.plan.confirmed = true
			game.state = Phase.PLANNING
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.LOCK, "fighter confirmation must select LOCK")
			fighter.plan.shot_tick = 0
			game.state = Phase.EXECUTING
			game.exec_tick = 9
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.SHOT and visual.body_frame == 3,
				"the attack animation must advance and clamp the four-frame SHOT sequence")

			game.ghost_velocity_path[0] = PackedVector2Array([
				Vector2.ZERO, Vector2(180.0, 0.0), Vector2(500.0, 0.0),
				Vector2(0.0, -180.0), Vector2(0.0, 180.0),
			])
			game.ghost_ground_path[0] = PackedByteArray([1, 1, 1, 0, 0])
			fighter.plan.shot_tick = -1
			var preview = game._preview
			_check(preview._ghost_sprite_pose(fighter, visual.skin, 0)["state"] == FighterVisual.IDLE,
				"stationary fighter prediction must select ghost IDLE")
			_check(preview._ghost_sprite_pose(fighter, visual.skin, 1)["state"] == FighterVisual.WALK,
				"moving fighter prediction must select ghost WALK")
			_check(preview._ghost_sprite_pose(fighter, visual.skin, 2)["state"] == FighterVisual.RUN,
				"fast fighter prediction must select ghost RUN")
			_check(preview._ghost_sprite_pose(fighter, visual.skin, 3)["state"] == FighterVisual.RISE,
				"upward fighter prediction must select ghost RISE")
			_check(preview._ghost_sprite_pose(fighter, visual.skin, 4)["state"] == FighterVisual.FALL,
				"downward fighter prediction must select ghost FALL")
			fighter.plan.shot_tick = 2
			var shot_ghost: Dictionary = preview._ghost_sprite_pose(fighter, visual.skin, 2)
			_check(shot_ghost["state"] == FighterVisual.SHOT and shot_ghost["frame"] == 1,
				"pinned fighter release prediction must select the SHOT ghost")

			_check(is_equal_approx(visual.skin.sprite_draw_rect.position.x,
				-visual.skin.sprite_draw_rect.size.x * 0.5),
				"the fighter draw rectangle must be centered for lossless mirroring")

			fighter.alive = false
			visual.sync_from_player()
			visual._process(0.5)
			visual.sync_from_player()
			_check(visual.body_state == FighterVisual.DEFEAT and visual.body_frame == 3,
				"fighter DEFEAT must finish after deterministic simulation stops")

	game.player_weapons[1] = weapon
	var second_skin = game._fighter_skin_for(1)
	_check(second_skin != null and second_skin.skin_id == skin_id,
		"skin selection must follow weapon identity rather than player index")
	var first_skin = game._fighter_skin_for(0)
	_check(first_skin != null and not first_skin.sprite_tint.is_equal_approx(second_skin.sprite_tint),
		"two fighters must carry their own player accents")
	_check(second_skin.palette[&"body"].is_equal_approx(game.PLAYER_COLORS[1]),
		"fighter world markers must follow the player identity colour")
	second_skin = null
	first_skin = null

	root.remove_child(game)
	game.free()
	await process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("%s: %s" % [_case_name, message])
