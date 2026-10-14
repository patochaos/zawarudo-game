extends SceneTree
## Captures the twist arenas during planning so gate clocks and stasis fields
## can be judged at match scale. Run windowed:
##   godot --path . --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/ArenaTwistsVisualTest.gd --quit-after 600
const MAIN := preload("res://scenes/Main.tscn")
const Capture := preload("res://tests/VisualCaptureHelper.gd")
var game
var error := OK


func _init() -> void:
	call_deferred("run")


func snap(name: String) -> void:
	game._transition.visible = false
	game._time_stop._freeze_flash = 0.0
	game._time_stop._resume_flash = 0.0
	game._preview.queue_redraw()
	game._ui.refresh()
	await Capture.settle(self, 3)
	error = Capture.save(self, "res://previews/twist-" + name + ".png", "Arena twists")
	if error != OK:
		quit(error)


func start(level: int) -> void:
	game._start_local_match(level, 2, [0, 0], {
		"roles": ["HUMAN", "AI"], "devices": [-2, -1],
		"difficulties": [1, 1], "difficulty": 1, "match_lives": 3,
	})
	game._transition.visible = false


func execute_window() -> void:
	game._begin_execution()
	while game.exec_tick < game.exec_ticks_total:
		game._sim_tick(game.tick_dt())
		game.exec_tick += 1
	game._end_execution()


func aim(direction: Vector2, power: float, shot_tick: int = 0) -> void:
	var plan = game.players[0].plan
	plan.set_aim_from_vector(direction, game.aim_min_angle, game.aim_max_angle)
	plan.power = power
	plan.shot_tick = shot_tick


func run() -> void:
	game = MAIN.instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game._sfx.muted = true
	game.settings_path = "user://test-arenatwistsvisual-settings.cfg"
	await Capture.pin_window(self)

	start(1)
	for tick in 20:
		game._pilot_step(0, 1, tick == 0, true)
	aim(Vector2(1.0, -0.6), 0.7, 10)
	await snap("gallery-planning")
	for i in 3:
		execute_window()
	await snap("gallery-later")

	start(2)
	var knife := Arrow.new()
	knife.cfg = game
	knife.position = Vector2(520.0, 390.0)
	knife.vel = Vector2(220.0, -60.0)
	knife.shooter = 1
	knife.network_id = 900
	game._arrow_layer.add_child(knife)
	game.arrows.append(knife)
	aim(Vector2(1.0, -0.55), 0.85)
	await snap("hall-planning")

	quit(0)
