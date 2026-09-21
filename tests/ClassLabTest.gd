extends SceneTree

var failures := 0
var game

func _init() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func shot(kind: int, power: float = 0.5):
	return ClassLab.make_projectile(game, kind, Vector2(500, 240), Vector2.RIGHT, power)

func run() -> void:
	game = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game._sfx.muted = true
	game._menu.developer_mode = true
	game._menu._activate(game._menu.ROW_EXPERIMENTS)
	game._menu._activate(game._menu.ROW_CLASS_LAB)
	check(game.class_lab and game.state == Phase.PLANNING, "Menu enters planning lab")
	check(game.player_weapons[0] == Roster.CHAKRAM, "Lab starts with Eclipse")
	check(Roster.ORDER == [Roster.DUELIST], "Normal roster remains Duelist only")
	for kind in ClassLab.ORDER:
		game.player_weapons[0] = kind
		check(game.air_jumps_for(0) == game.air_jumps_for(1), "Shared air jumps")
		check(is_equal_approx(game.jump_impulse_for(0), game.jump_impulse_for(1)), "Shared jump impulse")
		check(is_equal_approx(game.movement_speed_scale(0), game.movement_speed_scale(1)), "Shared walking speed")
		check(not game.uses_dashblade(0) and not game.uses_shock(0) and not game.uses_chakram(0), "Legacy mechanics disabled in lab")
	game.platforms = []
	var dt: float = game.tick_dt()
	var corona = shot(Roster.CHAKRAM)
	var prediction: PackedVector2Array = corona.prediction(81)
	for tick in 81:
		game.players[0].position += Vector2(2, 0)
		corona.sim_step(dt, [])
		check(corona.position.is_equal_approx(prediction[tick + 1]), "Corona preview follows simulation")
	check(corona.position.is_equal_approx(corona.origin), "Corona returns to launch point independent of owner")
	corona.free()
	var carrier = shot(Roster.SHOCK, 1.0)
	var short_carrier = shot(Roster.SHOCK, 0.0)
	check(carrier.delay_ticks > short_carrier.delay_ticks, "Charge increases Pulse delay")
	short_carrier.free()
	game.players[1].position = carrier.position
	for tick in carrier.delay_ticks:
		var result: Dictionary = carrier.sim_step(dt, [game.players[1]])
		check(result.hit_player == -1, "Carrier never harms bodies")
		check(result.burst == (tick == carrier.delay_ticks - 1), "Burst happens on chosen simulation tick")
	var darts: Array = []
	ClassLab.split(game, carrier, darts)
	check(darts.size() == 2 and darts[0].volley == darts[1].volley, "Pulse creates exactly two sibling daggers")
	for dart in darts:
		dart.free()
	carrier.free()
	var lance = shot(Roster.DASHBLADE)
	game.platforms = [{"hp": 1, "rects": [Rect2(503, 220, 10, 40)]}]
	var hit: Dictionary = lance.sim_step(dt, [])
	check(hit.alive and hit.hit_platform == 0 and lance.pierced, "Lance pierces one fragile cover")
	check(lance.vel.length() < lance.speed, "Piercing spends momentum")
	game.platforms = [{"hp": -1, "rects": [Rect2(503, 220, 10, 40)]}]
	hit = lance.sim_step(dt, [])
	check(not hit.alive, "Lance stops at permanent terrain")
	lance.free()
	game.platforms = []
	for kind in [Roster.CHAKRAM, Roster.SHOCK, Roster.DASHBLADE]:
		var first = shot(kind)
		first.volley = 100
		first.prev_pos = Vector2(490, 240)
		var second := Arrow.new()
		second.cfg = game
		second.volley = 101
		second.prev_pos = Vector2(510, 240)
		second.position = Vector2(500, 240)
		second.vel = Vector2(-500, 0)
		game._arrow_layer.add_child(first)
		game._arrow_layer.add_child(second)
		game._resolve_clashes([first, second])
		check(first.is_queued_for_deletion() and second.is_queued_for_deletion(), "Each prototype can be intercepted")
	ClassLab.start(game, true, Roster.CHAKRAM)
	game.set_physics_process(false)
	game._spawn_player_attack(game.players[0])
	game._spawn_player_attack(game.players[0])
	check(game.arrows.size() == 1, "Eclipse has one active corona")
	check(game.class_lab and game.real_time_mode and game.state == Phase.FREEPLAY, "Lab supports real time")
	game.state = Phase.EXECUTING
	game._replay_frames.clear()
	game._capture_replay_frame()
	var frame: Dictionary = game._replay_frames.back()
	var launch_point: Vector2 = game.arrows[0].origin
	game.arrows[0].free()
	game.arrows.clear()
	game._apply_replay_frame(frame)
	check(game.arrows[0] is InterceptProjectile and game.arrows[0].origin == launch_point,
		"Replay reconstructs the prototype and its anchored route")
	ClassLab.handle_key(game, KEY_3)
	check(game.player_weapons[0] == Roster.SHOCK and game.real_time_mode, "P1 selection preserves real time")
	ClassLab.handle_key(game, KEY_6)
	check(game.player_weapons[1] == Roster.DASHBLADE, "CPU selection changes kit")
	ClassLab.handle_key(game, KEY_T)
	check(game.state == Phase.PLANNING and game.class_lab and not game.real_time_mode, "T switches to planning")
	game._open_menu()
	check(not game.class_lab, "Leaving lab restores normal mechanics")
	game.queue_free()
	await process_frame
	print("ClassLabTest: %d failures" % failures)
	quit(1 if failures else 0)
