extends SceneTree

const GAME_MANAGER := preload("res://scripts/GameManager.gd")
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for index in [4, 3]:
		var gm = GAME_MANAGER.new()
		root.add_child(gm)
		await process_frame
		gm._sfx.muted = true
		gm.start_quick_match(false, index, 2)
		gm.set_physics_process(false)
		if index == 4:
			_check(_jump_reaches(gm, Vector2(275, 446), Vector2(195, 276)), "Descent intact left climb is clear")
			_check(_jump_reaches(gm, Vector2(1005, 446), Vector2(1085, 276)), "Descent intact right climb is clear")
		# Every required climb must survive destruction of all fragile cover.
		gm.platforms = gm.platforms.filter(func(pf): return int(pf["hp"]) < 0)
		gm._rebuild_solids()
		if index == 4:
			for side in [-1, 1]:
				var x := 100.0 if side == -1 else 1180.0
				var state: Array = [Vector2(x, 596), Vector2.ZERO, true]
				for tick in 90:
					state = Player.step_state(state[0], state[1], state[2], side, false, gm.tick_dt(), gm)
				_check(state[0].x >= 86.0 and state[0].x <= 1194.0,
					"Descent lower walls must prevent horizontal wrapping")
				state = Player.step_state(Vector2(2 if side == -1 else 1278, 220),
					Vector2(side * 300, 0), false, side, false, gm.tick_dt(), gm)
				_check(state[0].x > 1200 if side == -1 else state[0].x < 80,
					"Descent upper side passages must wrap in both directions")
			for dir in [-1, 1]:
				var state := Player.step_state(Vector2(490, 2 if dir == -1 else 718),
					Vector2(0, dir * 400), false, 0, true, gm.tick_dt(), gm)
				_check(state[0].y > 680 if dir == -1 else state[0].y < 40,
					"Descent shaft must wrap in both vertical directions")
			_check(_jump_reaches(gm, Vector2(310, 596), Vector2(250, 446)), "Descent first stair is reachable")
			_check(_jump_reaches(gm, Vector2(275, 446), Vector2(195, 276)), "Descent upper passage is reachable")
			_check(_jump_reaches(gm, Vector2(1005, 446), Vector2(1085, 276)), "Descent right climb is reachable")
		else:
			_check(_jump_reaches(gm, Vector2(325, 596), Vector2(250, 476)), "Pulse first stair is reachable")
			_check(_jump_reaches(gm, Vector2(310, 476), Vector2(375, 316)), "Pulse left inner perch is reachable")
			_check(_jump_reaches(gm, Vector2(970, 476), Vector2(905, 316)), "Pulse right inner perch is reachable")
			for orb in gm.hazards:
				for p in gm.players:
					_check(p.position.distance_to(orb.position) > orb.blast_radius + Player.HALF.length(),
						"Opening fighters must start outside hazard footprints")
		gm.free()
	print("Prototype arenas: %s" % ("all tests passed" if failures == 0 else "%d failures" % failures))
	quit(failures)


func _jump_reaches(gm, start: Vector2, landing: Vector2) -> bool:
	var state: Array = [start, Vector2(0, -gm.jump_impulse_for(0)), false]
	var cleared := false
	for tick in 150:
		# Platforms are solid on their undersides: jump beside the lip before
		# steering over it, exactly as a player must in the live game.
		cleared = cleared or state[0].y < landing.y - 1.0
		var dx: float = landing.x - state[0].x
		var dir := int(signf(dx)) if cleared and absf(dx) > 8.0 else 0
		state = Player.step_state(state[0], state[1], state[2], dir, true, gm.tick_dt(), gm)
		if state[2]:
			return absf(state[0].y - landing.y) < 1.0 and absf(state[0].x - landing.x) < 65.0
	return false


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
