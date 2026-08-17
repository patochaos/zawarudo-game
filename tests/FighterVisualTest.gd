extends SceneTree

const GAME_MANAGER := preload("res://scripts/GameManager.gd")
const FIGHTER_VISUAL := preload("res://scripts/FighterVisual.gd")
const FIGHTER_SKIN := preload("res://scripts/FighterSkin.gd")

var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var isolated := Player.new()
	_check(isolated.draw_legacy_visual, "isolated Player.new() must retain the legacy renderer")
	_check(isolated.get_node_or_null("FighterVisual") == null,
		"isolated Player.new() must not attach cosmetic children")
	isolated.free()

	var default_gm = GAME_MANAGER.new()
	root.add_child(default_gm)
	await process_frame
	_check(default_gm.fighter_visuals_enabled,
		"the rigged Executor prototype must default on for playtesting")
	for p: Player in default_gm.players:
		_check(not p.draw_legacy_visual,
			"default prototype players must suppress the legacy renderer")
		var default_visual := p.get_node_or_null("FighterVisual") as FighterVisual
		_check(default_visual != null,
			"default manager players must attach the rigged prototype")
		if default_visual != null:
			_check(default_visual.skin.skin_id == &"gilded_executor_prototype_v1",
				"default fighters must use the generated Executor atlas")
	root.remove_child(default_gm)
	default_gm.free()

	var gm = GAME_MANAGER.new()
	gm.fighter_visuals_enabled = true
	root.add_child(gm)
	await process_frame

	_check(gm.fighter_visuals_enabled, "the focused fixture must enable fighter visuals")
	_check(gm.players.size() == 2, "the focused fixture must spawn a duel")
	for p: Player in gm.players:
		var child := p.get_node_or_null("FighterVisual")
		_check(child is FighterVisual, "GameManager._add_player() must attach FighterVisual")
		_check(not p.draw_legacy_visual, "attached visuals must suppress only legacy _draw")
		_check(p.rect().size.is_equal_approx(Vector2(32.0, 48.0)),
			"fighter collision rect must remain exactly 32x48")
		if child is FighterVisual:
			_check(child.get_node_or_null("AimArm") != null,
				"FighterVisual must keep aim on a separate child layer")
			_check(child.skin.visual_bounds.size.is_equal_approx(Vector2(128.0, 128.0)),
				"sprite art must use the authored 128x128 gameplay draw bounds")
			_check(child.skin.has_sprite(FIGHTER_VISUAL.IDLE),
				"the rigged prototype must expose an imported idle atlas")

	var player: Player = gm.players[0]
	var visual: FighterVisual = player.get_node("FighterVisual")
	_test_state_contract(gm, player, visual)
	_test_shot_state(gm, player, visual)
	_test_planning_freeze_and_aim(gm, player, visual)
	_test_cosmetics_are_digest_inert(gm, player, visual)
	_test_replay_restoration(gm, player, visual)
	_test_principal_aim_directions(player, visual)
	_test_fallback(gm)

	gm.free()
	if _failures == 0:
		print("Fighter visual: all tests passed")
	else:
		push_error("Fighter visual: %d test(s) failed" % _failures)
	quit(_failures)


func _test_state_contract(gm, player: Player, visual: FighterVisual) -> void:
	for state_name in [FIGHTER_VISUAL.IDLE, FIGHTER_VISUAL.RUN, FIGHTER_VISUAL.RISE,
			FIGHTER_VISUAL.FALL, FIGHTER_VISUAL.SHOT, FIGHTER_VISUAL.LOCK]:
		_check(visual.skin.has_sprite(state_name) and visual.skin.frame_count(state_name) > 0,
			"FighterSkin must provide an imported %s atlas" % state_name)
		var atlas: Texture2D = visual.skin.sprite_atlases[state_name]
		_check(atlas.get_width() == visual.skin.sprite_cell_size.x * visual.skin.frame_count(state_name)
				and atlas.get_height() == visual.skin.sprite_cell_size.y,
			"%s atlas dimensions must match its authored frame count" % state_name)
	_check(visual.skin.frame_count(FIGHTER_VISUAL.DEFEAT) > 0,
		"FighterSkin must retain a defeat fallback")

	gm.state = Phase.PLANNING
	player.alive = true
	player.plan.confirmed = false
	player.on_ground = true
	player.vel = Vector2.ZERO
	visual.sync_from_player()
	_check(visual.body_state == FIGHTER_VISUAL.IDLE, "standing body must select IDLE")
	player.vel = Vector2(80.0, 0.0)
	visual.sync_from_player()
	_check(visual.body_state == FIGHTER_VISUAL.RUN, "ground movement must select RUN")
	player.on_ground = false
	player.vel = Vector2(0.0, -80.0)
	visual.sync_from_player()
	_check(visual.body_state == FIGHTER_VISUAL.RISE, "upward air movement must select RISE")
	player.vel.y = 80.0
	visual.sync_from_player()
	_check(visual.body_state == FIGHTER_VISUAL.FALL, "downward air movement must select FALL")
	player.on_ground = true
	player.plan.confirmed = true
	visual.sync_from_player()
	_check(visual.body_state == FIGHTER_VISUAL.LOCK, "confirmed planning must select LOCK")
	player.alive = false
	visual.sync_from_player()
	_check(visual.body_state == FIGHTER_VISUAL.DEFEAT, "dead body must select DEFEAT")


func _test_shot_state(gm, player: Player, visual: FighterVisual) -> void:
	gm.state = Phase.EXECUTING
	gm.exec_tick = 12
	player.alive = true
	player.on_ground = true
	player.vel = Vector2.ZERO
	player.plan.confirmed = true
	player.plan.shot_tick = 12
	visual.sync_from_player()
	_check(visual.body_state == FIGHTER_VISUAL.SHOT and visual.body_frame == 0,
		"the authoritative launch tick must start SHOT on frame zero")
	gm.exec_tick += visual.skin.ticks_per_frame
	visual.sync_from_player()
	_check(visual.body_state == FIGHTER_VISUAL.SHOT and visual.body_frame == 1,
		"SHOT must advance from the authoritative execution tick")
	gm.state = Phase.REPLAY
	gm._replay_frame_index = player.plan.shot_tick + visual.skin.ticks_per_frame
	visual.sync_from_player()
	_check(visual.body_state == FIGHTER_VISUAL.SHOT and visual.body_frame == 1,
		"replay must reconstruct SHOT from its captured frame index")
	gm.state = Phase.EXECUTING
	gm.exec_tick = player.plan.shot_tick \
		+ visual.skin.frame_count(FIGHTER_VISUAL.SHOT) * visual.skin.ticks_per_frame
	visual.sync_from_player()
	_check(visual.body_state == FIGHTER_VISUAL.IDLE,
		"SHOT must return to locomotion after its deterministic window")
	player.plan.shot_tick = -1


func _test_planning_freeze_and_aim(gm, player: Player, visual: FighterVisual) -> void:
	gm.state = Phase.PLANNING
	gm.world_tick = 17
	player.alive = true
	player.on_ground = true
	player.vel = Vector2(120.0, 0.0)
	player.plan.confirmed = false
	player.plan.aim_angle = 0.0
	visual.sync_from_player()
	var frozen_body := visual.body_signature()
	var old_muzzle := visual.aim_muzzle_global()
	player.plan.aim_angle = 90.0
	visual.sync_from_player()
	_check(visual.body_signature() == frozen_body,
		"planning aim changes must not advance or replace the body frame")
	_check(visual.aim_muzzle_global().distance_to(old_muzzle) > 10.0,
		"planning must still allow the separate aim arm to update")


func _test_cosmetics_are_digest_inert(gm, player: Player, visual: FighterVisual) -> void:
	var before: String = gm._online_state_digest()
	visual.skin.palette[&"body"] = Color(0.02, 0.98, 0.47)
	visual.skin.visual_bounds = Rect2(-200.0, -200.0, 400.0, 400.0)
	visual.skin.frames[FIGHTER_VISUAL.IDLE] = [
		{&"bob": 99.0, &"lean": 99.0, &"stride": 99.0, &"coat": 99.0},
	]
	visual.body_frame = 37
	var after: String = gm._online_state_digest()
	_check(after == before, "skin, palette and visual frame changes must not alter online digest")
	_check(player.rect().size.is_equal_approx(Vector2(32.0, 48.0)),
		"extreme cosmetic bounds must not alter the 32x48 player rect")
	# Restore representative data for the remaining visual checks.
	visual.skin = FIGHTER_SKIN.executor_prototype(player.index)
	visual.sync_from_player()


func _test_replay_restoration(gm, player: Player, visual: FighterVisual) -> void:
	gm._replay_frames.clear()
	gm.state = Phase.EXECUTING
	gm.world_tick = 27
	player.alive = true
	player.on_ground = true
	player.vel = Vector2(-140.0, 0.0)
	player.facing = -1
	player.plan.confirmed = true
	player.plan.aim_angle = 135.0
	gm._capture_replay_frame()
	visual.sync_from_player()
	var expected_body := visual.body_signature()
	var expected_muzzle := player.muzzle()

	player.vel = Vector2.ZERO
	player.facing = 1
	player.plan.aim_angle = 0.0
	gm.world_tick = 2
	gm.state = Phase.REPLAY
	gm._apply_replay_frame(gm._replay_frames.back())
	visual.sync_from_player()
	_check(visual.body_signature() == expected_body,
		"replay frame restoration must reproduce visual state and stepped frame")
	_check(visual.aim_muzzle_global().distance_to(expected_muzzle) <= 1.0,
		"replay frame restoration must reproduce the authoritative visual muzzle")


func _test_principal_aim_directions(player: Player, visual: FighterVisual) -> void:
	for angle in range(0, 360, 45):
		player.plan.aim_angle = float(angle)
		visual.sync_from_player()
		_check(visual.aim_shoulder_global().distance_to(player.shoulder()) <= 1.0,
			"aim arm shoulder must match authoritative shoulder within 1 px at %d degrees" % angle)
		_check(visual.aim_muzzle_global().distance_to(player.muzzle()) <= 1.0,
			"aim arm muzzle must match authoritative muzzle within 1 px at %d degrees" % angle)


func _test_fallback(gm) -> void:
	gm.fighter_visuals_enabled = false
	gm._add_player(2)
	var fallback: Player = gm.players.back()
	_check(fallback.draw_legacy_visual, "disabled feature flag must retain stick renderer")
	_check(fallback.get_node_or_null("FighterVisual") == null,
		"disabled feature flag must not attach FighterVisual")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
