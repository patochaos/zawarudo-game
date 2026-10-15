extends SceneTree

## SUPER meter sources beyond the clash. Each one rewards play the duel wants:
## locking early, moving through the window, committing a throw, landing a hit
## and dodging a rival knife while moving. Everything goes through _gain_super,
## so the meter caps at full and the SUPER READY call fires once.

const MAIN := preload("res://scenes/Main.tscn")
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = MAIN.instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game._sfx.muted = true
	game.start_quick_match(false, 0, 2)
	game._transition.visible = false
	var p0: Player = game.players[0]
	var p1: Player = game.players[1]

	# Early lock: a human earns the unused share of the window, the AI a fixed half.
	game.planning_time_left = game.planning_window_duration * 0.75
	game._confirm(0)
	check(p0.plan.lock_permille == 750, "locking with 3/4 of the window left stores 750 permille")
	game.player_roles[1] = "AI"
	game._confirm(1)
	check(p1.plan.lock_permille == 500, "the AI locks as if it had used half the window")
	game.player_roles[1] = "HUMAN"
	game._begin_execution()
	check(is_equal_approx(game.super_meter[0], game.super_charge_early_lock * 0.75),
		"the early-lock share scales with the time left (%.3f)" % game.super_meter[0])
	check(is_equal_approx(game.super_meter[1], game.super_charge_early_lock * 0.5),
		"the AI early-lock share is half the maximum (%.3f)" % game.super_meter[1])

	# Travel: a piloted run earns a share of the movement reward; standing still earns none.
	game._begin_planning(false)
	var before0: float = game.super_meter[0]
	var before1: float = game.super_meter[1]
	for _tick in game.movement_tick_budget():
		p0.plan.record(1, false, false)
	game._begin_execution()
	var guard := 0
	while game.state == Phase.EXECUTING and guard < 400:
		game._physics_process(game.tick_dt())
		guard += 1
	check(game.state == Phase.PLANNING, "the window must run to its end")
	var travel: float = game._exec_travel[0]
	check(travel > 60.0, "a piloted run covers ground (%.1f px)" % travel)
	var expected_travel: float = game.super_charge_per_window_travel \
		* clampf(travel / game.super_travel_reference, 0.0, 1.0)
	check(is_equal_approx(game.super_meter[0] - before0, expected_travel),
		"travel meter follows distance over the reference (%.3f)" % (game.super_meter[0] - before0))
	check(is_equal_approx(game.super_meter[1], before1), "a motionless fighter earns no travel meter")

	# Throw: committing an attack pays by charge.
	before0 = game.super_meter[0]
	p0.plan.power = 1.0
	game._spawn_player_attack(p0)
	check(is_equal_approx(game.super_meter[0] - before0, game.super_charge_per_throw),
		"a full-charge throw earns the whole throw share")
	for a in game.arrows:
		a.queue_free()
	game.arrows.clear()

	# Hit: the scorer is rewarded, the victim gets a smaller comeback.
	before0 = game.super_meter[0]
	before1 = game.super_meter[1]
	game._on_player_hit(1, p1.position, 0)
	check(is_equal_approx(game.super_meter[0] - before0, game.super_charge_hit_landed),
		"landing a hit earns the landed share")
	check(is_equal_approx(game.super_meter[1] - before1, game.super_charge_hit_taken),
		"taking a hit earns the comeback share")
	p1.alive = true

	# Dodge: a rival knife sweeping past a moving body, once per knife, capped per window.
	game._dodge_credits.fill(0)
	p0.vel = Vector2(120.0, 0.0)
	var miss := _knife(game, 1, p0.position + Vector2(-60.0, -16.0 - 10.0),
		p0.position + Vector2(60.0, -16.0 - 10.0))
	before0 = game.super_meter[0]
	game._credit_dodges(miss, [p0])
	check(is_equal_approx(game.super_meter[0] - before0, game.super_charge_per_dodge),
		"a knife passing just over the head of a moving fighter is a dodge")
	game._credit_dodges(miss, [p0])
	check(is_equal_approx(game.super_meter[0] - before0, game.super_charge_per_dodge),
		"the same knife never credits the same fighter twice")
	var far := _knife(game, 1, p0.position + Vector2(-60.0, -200.0), p0.position + Vector2(60.0, -200.0))
	game._credit_dodges(far, [p0])
	check(is_equal_approx(game.super_meter[0] - before0, game.super_charge_per_dodge),
		"a knife far above the body is not a dodge")
	p0.vel = Vector2.ZERO
	var still := _knife(game, 1, p0.position + Vector2(-60.0, -30.0), p0.position + Vector2(60.0, -30.0))
	game._credit_dodges(still, [p0])
	check(is_equal_approx(game.super_meter[0] - before0, game.super_charge_per_dodge),
		"a motionless fighter is not dodging")
	p0.vel = Vector2(120.0, 0.0)
	game._dodge_credits[0] = game.SUPER_DODGE_CREDITS_PER_WINDOW
	game._credit_dodges(still, [p0])
	check(is_equal_approx(game.super_meter[0] - before0, game.super_charge_per_dodge),
		"dodge credits stop at the per-window cap")
	var own := _knife(game, 0, p0.position + Vector2(-60.0, -30.0), p0.position + Vector2(60.0, -30.0))
	game._dodge_credits[0] = 0
	game._credit_dodges(own, [p0])
	check(is_equal_approx(game.super_meter[0] - before0, game.super_charge_per_dodge),
		"a fighter's own knife is never a dodge")
	for knife in [miss, far, still, own]:
		knife.free()

	# Cap and call: the meter stops at full and announces SUPER READY.
	game.super_meter[0] = 0.95
	game.banner_text = ""
	game._gain_super(0, 0.5, "test")
	check(is_equal_approx(game.super_meter[0], 1.0) and "SUPER READY" in game.banner_text,
		"filling the meter caps it at full and calls SUPER READY")
	game._gain_super(0, 0.5, "test")
	check(is_equal_approx(game.super_meter[0], 1.0), "a full meter never overflows")

	game.queue_free()
	await process_frame
	if failures == 0:
		print("Super meter rewards: all tests passed")
	else:
		push_error("Super meter rewards: %d check(s) failed" % failures)
	quit(failures)


func _knife(game, shooter: int, from: Vector2, to: Vector2) -> Arrow:
	var a := Arrow.new()
	a.cfg = game
	a.shooter = shooter
	a.prev_pos = from
	a.position = to
	a.vel = (to - from) * 60.0
	return a


func check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		failures += 1
		push_error("  FAIL " + what)
