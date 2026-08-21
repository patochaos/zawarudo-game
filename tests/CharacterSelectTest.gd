extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true

	game._menu._activate(game._menu.ROW_PLAY)
	game._menu._select(game._menu.SETUP_FIRST_FIGHTER)
	game._menu.handle_key(KEY_RIGHT)
	game._menu._select(game._menu.SETUP_FIRST_FIGHTER + 1)
	game._menu.handle_key(KEY_RIGHT)
	game._menu.handle_key(KEY_RIGHT)
	game._menu._select(game._menu._setup_arena_row())
	game._menu.handle_key(KEY_RIGHT)
	game._menu.handle_key(KEY_RIGHT)
	var expect_ai := Input.get_connected_joypads().is_empty()
	game._menu._activate(game._menu._setup_start_row())
	_check(game.state == Phase.PLANNING and game.vs_ai == expect_ai and game.level_index == 2,
		"the one-screen match card must start the selected arena directly")
	_check(game.uses_dashblade(0) and game.uses_shock(1) \
			and game.is_ai(1) == expect_ai,
		"the configured duel must retain classes and controller-aware P2 ownership")
	game.local_weapon_choices.fill(game.Weapon.KNIVES)
	game._open_menu()

	game._on_menu_character_select()
	game._character_select.handle_key(KEY_D)
	game._character_select.handle_key(KEY_SHIFT)
	game._character_select.handle_key(KEY_RIGHT)
	game._character_select.handle_key(KEY_RIGHT)
	game._character_select.handle_key(KEY_ENTER)
	_check(game.state == Phase.PLANNING and not game.vs_ai,
		"locking both fighters must start a local duel")
	_check(game.uses_dashblade(0) and game.uses_shock(1),
		"the local duel must independently select Dashblade and Shock fighters")

	game._ui.refresh()
	_check(game._ui._fighter_seals[0].fighter_name == "VELOCITY" \
			and game._ui._fighter_seals[1].fighter_name == "STATIC WITCH",
		"the duel HUD must identify both selected character kits")
	_check(game._ui._fighter_seals[0].portrait == game._ui.DASHBLADE_PORTRAIT \
			and game._ui._fighter_seals[1].portrait == game._ui.SHOCK_PORTRAIT,
		"each new fighter must use its own HUD portrait")

	game._set_shock_attack_mode(1, 1)
	game._ui.refresh()
	_check(game.players[1].plan.attack_mode == 1 and "P2 ORB" in game._ui._level_label.text,
		"Player 2's Shock mode must propagate into the HUD")
	game.players[0].plan.power = 0.5
	game._spawn_player_attack(game.players[0])
	_check(game.dashblades.size() == 1 and game.dashblades[0].owner_index == 0,
		"a Dashblade normal attack must start a physical dash action")
	game.players[1].plan.power = 0.5
	game._spawn_player_attack(game.players[1])
	_check(game.shock_orbs.size() == 1 and game.shock_orbs[0].shooter == 1,
		"Shock secondary fire must launch its persistent orb")

	game._on_menu_roster_select(4, false)
	_check(game.state == Phase.CHARACTER_SELECT and game._character_select.participant_count == 4 \
			and game._character_select.roster_mode,
		"four-player mode must open the compact formation selector")
	_check(game._character_select.roles == ["HUMAN", "AI", "AI", "AI"],
		"the formation selector must identify the human and every AI slot")
	game._character_select.selections[0] = game.Weapon.KNIVES
	game._character_select.selections[1] = game.Weapon.DASHBLADE
	game._character_select.selections[2] = game.Weapon.SHOCK
	game._character_select.selections[3] = game.Weapon.CHAKRAM
	for i in 4:
		game._character_select._confirm(i)
	_check(game.state == Phase.PLANNING and game.players.size() == 4 and game.vs_ai,
		"locking the four formation slots must start the four-player match")
	_check(game.uses_dashblade(1) and game.uses_shock(2) and game.uses_chakram(3) \
			and game.is_ai(1) and game.is_ai(2) and game.is_ai(3),
		"AI roster slots must retain all four selected prototype kits")
	game.players[3].plan.set_aim_from_vector(Vector2.RIGHT,
		game.aim_min_angle, game.aim_max_angle)
	game.players[3].plan.power = 0.5
	var preview_launches: Array[Vector2] = game.chakram_launch_velocities(
		game.players[3].aim_dir(), game.players[3].plan.power)
	game._spawn_player_attack(game.players[3])
	_check(game.chakrams.size() == 1 and game.chakrams[0].shooter == 3,
		"the fourth roster fighter must launch one returning chakram")
	_check(game.chakrams[0].vel.normalized().is_equal_approx(Vector2.RIGHT),
		"the chakram must follow the player's exact aim direction")
	_check(is_equal_approx(game.chakrams[0].vel.length(), lerpf(
		game.chakram_speed_min, game.chakram_speed_max, 0.5)) \
			and game.chakrams[0].vel.length() <= 360.0,
		"the throw must use the halved Chakram launch-speed range")
	_check(preview_launches.size() == 1 \
			and preview_launches[0].is_equal_approx(game.chakrams[0].vel),
		"the planning preview must use the exact live Chakram launch")
	var first_generation: Array = game.chakrams.duplicate()
	game.turn += 1
	game._advance_chakrams_for_turn()
	_check(first_generation.all(func(chakram): return chakram.is_holding()),
		"a launch-turn chakram must hold throughout the following turn")
	game._spawn_player_attack(game.players[3])
	var second_generation: Array = game.chakrams.slice(1)
	game.turn += 1
	game._advance_chakrams_for_turn()
	_check(first_generation.all(func(chakram): return chakram.is_returning()) \
			and second_generation.all(func(chakram): return chakram.is_holding()),
		"an older chakram must return while the next turn's throw remains held")
	game.turn += 1
	game._advance_chakrams_for_turn()
	_check(second_generation.all(func(chakram): return chakram.is_returning()) \
			and game.chakrams.size() == 1,
		"each chakram must recall and expire according to its own launch turn")

	game._on_menu_roster_select(2, true)
	_check(game._character_select.roles[0] == "HUMAN" \
			and game._character_select.roles[1] == "DUMMY",
		"Freeplay must label its controllable fighter and training dummy")
	game._character_select.selections[0] = game.Weapon.SHOCK
	game._character_select.selections[1] = game.Weapon.KNIVES
	game._character_select._confirm(0)
	game._character_select._confirm(1)
	_check(game.state == Phase.FREEPLAY and game.uses_shock(0) and not game.uses_shock(1),
		"Freeplay must start with the selected player and dummy characters")

	if _failures == 0:
		print("Character selection: all tests passed")
	else:
		push_error("Character selection: %d test(s) failed" % _failures)
	game.free()
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
