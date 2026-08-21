extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const GRENADE_SCRIPT := preload("res://scripts/Grenade.gd")
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true

	game._menu.human_weapon = game.Weapon.GRENADE
	game._on_menu_start(true, 0, 2)
	_check(game.uses_grenade(0), "the Grenadier option must equip the human player")
	_check(not game.uses_grenade(1) and game.is_ai(1),
		"the AI must remain knife-only in a Grenadier match")

	game._set_grenade_fuse(0, 1)
	var fuse_one: int = game.players[0].plan.grenade_fuse_seconds
	game._set_grenade_fuse(0, 2)
	var fuse_two: int = game.players[0].plan.grenade_fuse_seconds
	game._set_grenade_fuse(0, 3)
	_check(fuse_one == 1 and fuse_two == 2 and game.players[0].plan.grenade_fuse_seconds == 3,
		"planning must expose each one-, two- and three-second fuse choice")
	_check(game.grenade_speed_max >= 680.0 and game.grenade_bounce_retention >= 0.75,
		"grenades must carry enough speed and bounce retention to threaten across the arena")
	_check(Ai.choose_grenade_fuse(180.0) == 1 \
			and Ai.choose_grenade_fuse(430.0) == 2 \
			and Ai.choose_grenade_fuse(760.0) == 3,
		"Grenadier AI must shorten or extend the fuse with target distance")
	_check(Ai.choose_grenade_fuse(760.0, true) == 1 \
			and Ai.choose_grenade_fuse(760.0, false, true) == 2,
		"Grenadier AI must use live bomb setups and crowded fights when choosing a fuse")
	game.players[0].plan.power = 0.6
	game._spawn_player_attack(game.players[0])
	_check(game.grenades.size() == 1 and game.arrows.is_empty(),
		"an ordinary Grenadier attack must launch one grenade instead of knives")
	var g = game.grenades[0]
	_check(g.fuse_ticks_left == 3 * Engine.physics_ticks_per_second,
		"the launched grenade must snapshot the selected fuse")
	game._replay_frames.clear()
	game.state = Phase.EXECUTING
	game._capture_replay_frame()
	var replay_position: Vector2 = g.position
	g.position += Vector2(120.0, 0.0)
	game._apply_replay_frame(game._replay_frames[0])
	_check(game.grenades.size() == 1 and game.grenades[0].position.is_equal_approx(replay_position) \
			and game.grenades[0].fuse_ticks_left == 3 * Engine.physics_ticks_per_second,
		"match replay must restore grenade position and fuse state")
	g = game.grenades[0]
	var frozen_fuse: int = g.fuse_ticks_left
	game.state = Phase.PLANNING
	await process_frame
	_check(g.fuse_ticks_left == frozen_fuse,
		"the fuse must not consume wall-clock time while planning is frozen")

	_clear_projectiles(game)
	game._spawn_player_attack(game.players[1])
	_check(game.arrows.size() == game.knives_per_shot and game.grenades.is_empty(),
		"the AI attack path must still launch its normal knife fan")

	_clear_projectiles(game)
	game.state = Phase.EXECUTING
	game.players[0].position = Vector2(110.0, 320.0)
	game.players[1].position = Vector2(640.0, 300.0)
	var timed = _grenade(game, Vector2(620.0, 300.0), Vector2.ZERO, 1, 0)
	game._step_grenades(game.tick_dt())
	_check(not game.grenades.has(timed), "a fuse reaching zero must detonate the grenade")
	_check(not game.players[1].alive and game.score[0] == 1,
		"an unobstructed blast must hit an opponent and award its owner")
	var blast_fx := _latest_effect(game, Effects.Kind.EXPLOSION)
	var blast_mark := _latest_aftermath(game, "BLAST")
	_check(not blast_fx.is_empty() \
			and _effect_color(blast_fx).is_equal_approx(game.PLAYER_COLORS[0]),
		"a grenade explosion must inherit its owner's player color")
	_check(not blast_mark.is_empty() \
			and _effect_color(blast_mark).is_equal_approx(game.PLAYER_COLORS[0]),
		"a frozen blast aftermath must preserve its owner's player color")

	game.players[1].alive = true
	game.players[1].invuln_turns = 0
	game.players[1].position = Vector2(650.0, 100.0)
	_clear_projectiles(game)
	var direct = _grenade(game, Vector2(560.0, 100.0), Vector2(5400.0, 0.0), 180, 0)
	game._step_grenades(game.tick_dt())
	_check(not game.grenades.has(direct) and not game.players[1].alive,
		"a grenade touching a player must detonate immediately instead of bouncing")

	game.players[1].alive = true
	game.players[1].invuln_turns = 0
	game.players[1].position = Vector2(1100.0, 300.0)
	_clear_projectiles(game)
	var struck = _grenade(game, Vector2(600.0, 190.0), Vector2.ZERO, 180, 0)
	var knife := Arrow.new()
	knife.cfg = game
	knife.shooter = 1
	knife.volley = 90
	knife.network_id = 900
	knife.position = Vector2(600.0, 190.0)
	knife.prev_pos = knife.position
	knife.vel = Vector2.ZERO
	game._arrow_layer.add_child(knife)
	game.arrows.append(knife)
	game._step_arrows(game.tick_dt())
	_check(not game.grenades.has(struck) and not game.arrows.has(knife),
		"a dagger touching a grenade must consume the dagger and detonate immediately")

	_clear_projectiles(game)
	var first = _grenade(game, Vector2(500.0, 250.0), Vector2.ZERO, 180, 0)
	var second = _grenade(game, Vector2(519.0, 250.0), Vector2.ZERO, 180, 0)
	var chained = _grenade(game, Vector2(580.0, 250.0), Vector2.ZERO, 180, 0)
	game._step_grenades(game.tick_dt())
	_check(not game.grenades.has(first) and not game.grenades.has(second) \
			and not game.grenades.has(chained),
		"two grenades colliding must detonate both and chain into nearby bombs")

	_clear_projectiles(game)
	var cluster_parent = _grenade(game, Vector2(600.0, 220.0), Vector2.ZERO, 1, 0)
	cluster_parent.fuse_ticks_total = 3 * Engine.physics_ticks_per_second
	game._step_grenades(game.tick_dt())
	var all_fragments: bool = game.grenades.size() == 3
	for fragment in game.grenades:
		all_fragments = all_fragments and fragment.cluster_fragment \
			and is_equal_approx(fragment.blast_radius_scale, game.grenade_cluster_blast_scale) \
			and fragment.color.is_equal_approx(game.PLAYER_COLORS[0])
	_check(not game.grenades.has(cluster_parent) and all_fragments,
		"a naturally matured three-second fuse must split into three owner-colored fragments")

	if _failures == 0:
		print("Grenadier: all tests passed")
	else:
		push_error("Grenadier: %d test(s) failed" % _failures)
	game._ai_searches.fill(null)
	game.free()
	quit(_failures)


func _grenade(game, at: Vector2, velocity: Vector2, fuse_ticks: int, shooter: int):
	var g = GRENADE_SCRIPT.new()
	g.cfg = game
	g.shooter = shooter
	g.network_id = 1000 + game.grenades.size()
	g.volley = g.network_id
	g.color = game.PLAYER_COLORS[shooter]
	g.position = at
	g.prev_pos = at
	g.vel = velocity
	g.fuse_ticks_left = fuse_ticks
	g.fuse_ticks_total = fuse_ticks
	game._arrow_layer.add_child(g)
	game.grenades.append(g)
	return g


func _clear_projectiles(game) -> void:
	for a in game.arrows:
		a.queue_free()
	for g in game.grenades:
		g.queue_free()
	game.arrows.clear()
	game.grenades.clear()


func _latest_effect(game, kind: int) -> Dictionary:
	for i in range(game._effects._fx.size() - 1, -1, -1):
		var effect: Dictionary = game._effects._fx[i]
		if int(effect.get("kind", -1)) == kind:
			return effect
	return {}


func _latest_aftermath(game, label: String) -> Dictionary:
	for i in range(game._effects._remembered.size() - 1, -1, -1):
		var effect: Dictionary = game._effects._remembered[i]
		if String(effect.get("label", "")) == label:
			return effect
	return {}


func _effect_color(effect: Dictionary) -> Color:
	return effect.get("col", Color.TRANSPARENT) as Color


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
