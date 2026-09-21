extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	_check(Roster.ORDER == [Roster.DUELIST], "Only Duelist is playable")
	for weapon in [Roster.DASHBLADE, Roster.SHOCK, Roster.CHAKRAM]:
		game._roster.weapons.fill(weapon)
		game._roster._normalize()
		_check(game._roster.weapons == [0, 0, 0, 0], "Stale local picks become Duelist")
		game._online_lobby.open(0, weapon)
		game._online_lobby._cycle_fighter(1)
		game._online_lobby._cycle_fighter(-1)
		_check(game._online_lobby.weapon == Roster.DUELIST, "Online selection excludes benched kits")
		game._start_local_match(0, 2, [weapon, weapon], {})
		_check(game.player_weapons == [0, 0, 0, 0], "Local entry rejects benched kits")
		game._start_freeplay(0, [weapon, weapon])
		_check(game.player_weapons == [0, 0, 0, 0], "Free play entry rejects benched kits")
		game._open_menu()
		game._online_lobby.open(0)
		game._start_online_match(0, 42, 1, [0, weapon])
		_check(not game.online_mode and game._online_lobby.visible,
			"An older online lineup must not begin a mismatched simulation")
	_check(game._online_lobby._fighter_buttons.size() == 1, "Online lobby exposes one fighter")
	game._start_online_match(0, 42, 1, [0, 0])
	_check(game.online_mode and game.player_weapons == [0, 0, 0, 0],
		"A Duelist-only online lineup can start")
	root.remove_child(game)
	game.free()
	await process_frame
	if failures == 0:
		print("Active roster: all tests passed")
	quit(failures)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
