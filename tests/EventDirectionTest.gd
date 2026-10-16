extends SceneTree

## Gate 3 event direction: the manager owns the SUPER pause, each beat has a
## palette preset that returns to base, reduced flashes keeps the information
## without the lift, the result holds a tableau, and none of it touches the
## simulation digest.

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
	var ed = game._event_direction
	var digest: String = game._online_state_digest()

	# Lock-in is quiet: readiness is the badge and the HUD status, not a beat.
	game._confirm(0)
	ed._process(0.05)
	check(ed.active_kinds().is_empty() and ed.current_mul().is_equal_approx(Color.WHITE),
		"confirming a plan starts no palette event")
	check(game._online_state_digest() == digest, "confirming leaves the digest alone")

	# Impact returns in hard steps.
	ed.impact(Vector2(640.0, 360.0), Color.GOLD)
	var life: float = float(ed._events[0]["life"])
	var seen := {}
	var t := 0.0
	while t < life and not ed._events.is_empty():
		ed._process(0.01)
		t += 0.01
		if not ed._events.is_empty():
			seen[snappedf(ed.strength(ed._events[0]), 0.01)] = true
	check(seen.size() <= 4 and seen.has(1.0), "the impact grade returns in a few hard steps (%s)" % [seen.keys()])
	check(game._online_state_digest() == digest, "impact theatre leaves the digest alone")

	# Reduced flashes: tint only, shorter.
	ed.clear()
	ed.reduced_flashes = true
	ed.impact(Vector2(640.0, 360.0), Color.GOLD)
	check(ed.current_add() == Color.BLACK and float(ed._events[0]["life"]) < life,
		"reduced flashes keep the hue shift only and shorten the event")
	ed.clear()
	ed.reduced_flashes = false

	# The SUPER pause is the manager's timer.
	var p: Player = game.players[0]
	game.super_meter[0] = 1.0
	game.super_armed[0] = true
	p.plan.shot_tick = 0
	p.plan.super_shot = true
	p.plan.power = 0.8
	p.plan.set_aim_from_vector(Vector2.RIGHT, game.aim_min_angle, game.aim_max_angle)
	game._begin_execution()
	game._physics_process(game.tick_dt())
	check(game._super_pause_left > 0.0 and game._super_pause_active() and game.exec_tick == 0
		and "super" in ed.active_kinds(),
		"the super launch starts a manager-owned pause and the super beats")
	game._physics_process(0.5)
	check(game.exec_tick == 0, "no tick runs while the pause holds")
	game._physics_process(1.0)
	check(is_zero_approx(game._super_pause_left) and game.exec_tick >= 1,
		"ticks resume once the pause runs out")
	var chant := " ".join(game._super_freeze.TITLE_LINES)
	check(chant == "MUDA MUDA MUDA MUDA", "the cut-in title is the four-beat MUDA chant")
	check(game._sfx._streams.has("super_chant") and not game._sfx._streams.has("muda"),
		"the chant cue carries its own name")

	# Cancelling the art releases the pause early (tests and the menu rely on it).
	game._begin_execution()
	game._physics_process(game.tick_dt())
	game._super_freeze.cancel()
	check(not game._super_pause_active(), "cancelling the cut-in releases the pause")
	game._cancel_super_cutin()

	# The final tableau: winner in the held stance, loser down.
	game.state = Phase.GAME_OVER
	game.winner = 0
	game.players[1].alive = false
	ed.tableau(0)
	ed._process(0.5)
	check(not ed.current_mul().is_equal_approx(Color.WHITE), "the result holds a subdued grade")
	var champion = _visual_of(game.players[0])
	var fallen = _visual_of(game.players[1])
	check(champion != null and fallen != null, "both fighters carry a visual")
	if champion != null and fallen != null:
		champion.sync_from_player()
		fallen.sync_from_player()
		check(champion.body_state == champion.LOCK and fallen.body_state == fallen.DEFEAT,
			"the winner holds the victory stance and the loser the real defeat pose")
	ed.clear()
	check(ed.current_mul().is_equal_approx(Color.WHITE) and ed._tableau.is_empty(),
		"leaving the result clears the tableau")

	# A rematch leaves the result screen too: the next match must not play
	# under the previous result's faded grade and winner spotlight.
	ed.tableau(0)
	ed._process(0.5)
	game._request_rematch()
	ed._process(0.0)
	check(game.state == Phase.PLANNING and ed._tableau.is_empty()
		and ed.current_mul().is_equal_approx(Color.WHITE) and not ed._mul_rect.visible,
		"a rematch clears the result tableau and its palette")

	root.remove_child(game)
	game.free()
	await process_frame
	print("Event direction: %d failures" % failures)
	quit(failures)


func _visual_of(fighter: Player):
	for child in fighter.get_children():
		if child.has_method("sync_from_player"):
			return child
	return null


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
