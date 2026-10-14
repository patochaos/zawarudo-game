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
	game._menu.developer_mode = true
	game._menu._activate(game._menu.ROW_EXPERIMENTS)
	game._menu._activate(game._menu.ROW_REAL_TIME)
	game.set_physics_process(false)
	game._transition.visible = false
	_check(game.real_time_mode and game.state == Phase.FREEPLAY and game.is_ai(1), "Menu opens a continuous duel against CPU")
	_check(not game._tuning.visible and not game._ui.visible, "No tuning panel or planning HUD in real time")
	_check(game.player_weapons == [0, 0, 0, 0], "Both fighters use Duelist")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	Input.parse_input_event(mouse)
	Input.flush_buffered_events()
	game._freeplay_tick(game.tick_dt())
	_check(game.charging[0], "A held mouse button charges immediately in live play")
	for tick in 12:
		game._freeplay_tick(game.tick_dt())
	var before: int = game._next_arrow_id
	mouse = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = false
	Input.parse_input_event(mouse)
	Input.flush_buffered_events()
	game._freeplay_tick(game.tick_dt())
	_check(game._next_arrow_id >= before + 2 and not game.charging[0], "Release throws two daggers without confirming a plan")
	_check(game.throw_cooldown_left[0] > 0.0, "A throw starts the reload")
	mouse = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	Input.parse_input_event(mouse)
	Input.flush_buffered_events()
	game._freeplay_tick(game.tick_dt())
	_check(not game.charging[0], "Holding during the reload does not draw")
	var reload_ticks := int(ceil(game.real_time_throw_cooldown / game.tick_dt())) + 1
	for tick in reload_ticks:
		game._freeplay_tick(game.tick_dt())
	_check(game.charging[0] and game.state == Phase.FREEPLAY, "A held draw starts when the reload ends, without freezing time")
	mouse = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = false
	Input.parse_input_event(mouse)
	Input.flush_buffered_events()
	game._freeplay_tick(game.tick_dt())
	var cpu_fired := false
	var cpu_volleys: Array[int] = []
	for tick in 240:
		game._freeplay_tick(game.tick_dt())
		for arrow in game.arrows:
			cpu_fired = cpu_fired or arrow.shooter == 1
			if arrow.shooter == 1 and not cpu_volleys.has(arrow.volley):
				cpu_volleys.append(arrow.volley)
	_check(cpu_fired and game.state == Phase.FREEPLAY, "CPU attacks while the world remains continuous")
	_check(cpu_volleys.size() <= int(240 * game.tick_dt() / game.real_time_throw_cooldown) + 1,
		"CPU throws are limited by the same reload")
	game._on_player_hit(0, game.players[0].position, 1)
	game._freeplay_tick(game.tick_dt())
	_check(game.players[0].alive and game.state == Phase.FREEPLAY, "Hits respawn without a planning or result phase")
	var key := InputEventKey.new()
	key.keycode = KEY_H
	key.pressed = true
	game._unhandled_key_input(key)
	_check(not game.real_time_aim_guide, "H removes the subtle guide")
	key.keycode = KEY_R
	game._unhandled_key_input(key)
	_check(game.real_time_mode and not game._tuning.visible, "Reset keeps real-time presentation")
	key.keycode = KEY_ESCAPE
	game._unhandled_key_input(key)
	_check(not game.real_time_mode and game.state == Phase.MENU, "Escape clears mode state")
	game.start_sandbox()
	_check(not game.real_time_mode and game._tuning.visible, "Sandbox retains its original tuning and previews")
	root.remove_child(game)
	game.free()
	await process_frame
	if failures == 0:
		print("Real-time mode: all tests passed")
	quit(failures)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
