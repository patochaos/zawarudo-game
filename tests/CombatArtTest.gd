extends SceneTree

const MAIN := preload("res://scenes/Main.tscn")
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = MAIN.instantiate()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game.start_quick_match(false, 0, 2)
	game.set_physics_process(false)
	game._effects.set_process(false)
	var digest: String = game._online_state_digest()
	for reduced in [false, true]:
		game._effects.reduced_flashes = reduced
		for kind in [Effects.Kind.SPARK, Effects.Kind.CLASH]:
			game._effects.add(kind, Vector2(640, 360), Color.GOLD)
		game._effects._process(0.12)
		_check(game._online_state_digest() == digest, "impact animation must not alter simulation")
		game._effects._process(0.5)
		_check(game._effects._fx.is_empty(), "impact sprites must expire completely")
		game._super_freeze.play(0, Color.GOLD, 0, reduced)
		game._super_freeze._art._process(0.65)
		_check(game._online_state_digest() == digest, "SUPER art must not alter simulation")
		game._super_freeze.cancel()
	game.free()
	if failures == 0:
		print("Combat art: all tests passed")
	quit(failures)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
