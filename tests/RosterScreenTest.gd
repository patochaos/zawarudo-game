extends SceneTree

## The two pre-match screens are the only way into a local match, so this suite
## covers the whole path: filling slots with players and CPUs, cycling fighters
## inside a slot, the rules screen behind it, and the kits arriving in play
## exactly as they were picked.

const MAIN_SCENE := preload("res://scenes/Main.tscn")
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true

	var roster = game._roster
	var setup = game._setup
	game._menu._activate(game._menu.ROW_PLAY)
	_check(game.state == Phase.ROSTER and roster.visible and not game._menu.visible \
			and not setup.visible,
		"Play must open the lineup screen and nothing else")
	_check(roster.cursor_slot == 0 and roster.row == roster.ROW_FIGHTER,
		"the screen must open on Player 1's fighter")
	_check(roster.kinds == [roster.SlotKind.PLAYER, roster.SlotKind.CPU,
			roster.SlotKind.OPEN, roster.SlotKind.OPEN],
		"the default table must be one keyboard player, one CPU and two open slots")
	_check(roster.devices[0] == roster.KEYBOARD_DEVICE and roster.filled_slots() == 2,
		"Player 1 must hold the keyboard seat without anyone choosing a head count")

	# A fighter is cycled inside its own slot, so the cast can outgrow the
	# screen without the screen changing shape.
	roster.handle_key(KEY_D)
	_check(roster.weapons[0] == roster.DASHBLADE,
		"left and right must step the focused slot's own fighter")
	roster.handle_key(KEY_A)
	roster.handle_key(KEY_A)
	_check(roster.weapons[0] == roster.CHAKRAM,
		"the carousel must wrap around the roster rather than stop at its end")

	# The control tile under a slot is where a seat becomes a player, a CPU of a
	# chosen skill, or nothing at all.
	roster.handle_key(KEY_S)
	roster.handle_key(KEY_TAB)
	_check(roster.row == roster.ROW_ROLE and roster.cursor_slot == 1,
		"Tab must carry the cursor to the next column without leaving the row")
	roster.handle_key(KEY_D)
	_check(roster.kinds[1] == roster.SlotKind.CPU and roster.difficulties[1] == 2,
		"CPU skill must be part of the same tile that chose the CPU")

	# An empty column is filled by pressing it; nobody pre-chooses a head count.
	roster.handle_key(KEY_TAB)
	roster.handle_key(KEY_W)
	roster.handle_key(KEY_ENTER)
	_check(roster.kinds[2] == roster.SlotKind.CPU and roster.filled_slots() == 3,
		"pressing an open slot must add a fighter to it")
	roster.handle_key(KEY_S)
	roster.handle_key(KEY_D)
	roster.handle_key(KEY_D)
	_check(roster.kinds[2] == roster.SlotKind.OPEN and roster.filled_slots() == 2,
		"the same tile must be able to empty the slot again")

	# Two fighters is the floor, so the open option is skipped rather than
	# offered and then refused.
	roster.handle_key(KEY_TAB)
	roster.handle_key(KEY_TAB)
	roster.handle_key(KEY_TAB)
	_check(roster.cursor_slot == 1 and roster.row == roster.ROW_ROLE,
		"Tab must wrap back around the four columns")
	roster.handle_key(KEY_D)
	_check(roster.kinds[1] == roster.SlotKind.PLAYER and roster.devices[1] == roster.NO_DEVICE,
		"a two-fighter table must step over the open option instead of emptying")
	_check(not roster._can_advance(),
		"a human seat with no device must hold the screen open")
	roster.handle_key(KEY_A)
	_check(roster.kinds[1] == roster.SlotKind.CPU and roster.difficulties[1] == 2,
		"stepping back must restore the CPU and its skill, not a different one")

	_pick(roster, 0, roster.DASHBLADE)
	_pick(roster, 1, roster.SHOCK)
	roster.cursor_slot = 0
	roster.row = roster.ROW_FIGHTER
	roster.handle_key(KEY_ENTER)
	_check(roster.ready_slots[0] and roster.row == roster.ROW_NEXT,
		"committing the last human must put the host on the confirm bar")
	roster.handle_key(KEY_ENTER)
	_check(game.state == Phase.MATCH_SETUP and setup.visible and not roster.visible,
		"the lineup must hand over to the rules screen, not straight to the arena")
	_check(setup.player_count() == 2,
		"the rules screen must be told how many fighters it is writing rules for")

	# Rules and arena live here, one row each, with the arena drawn beside them.
	setup.handle_key(KEY_S)
	setup.handle_key(KEY_D)
	setup.handle_key(KEY_D)
	_check(setup.row == setup.ROW_ARENA and setup.level == 2,
		"the arena must be chosen on the rules screen")
	_check(setup._plan.layout["name"] == Levels.build(2, 2)["name"],
		"the arena drawing must follow the selected level")
	setup.handle_key(KEY_S)
	setup.handle_key(KEY_D)
	_check(setup.match_lives == 7, "match length must sit beside the arena that hosts it")

	# Stepping back is a step, not a reset.
	setup.handle_key(KEY_ESCAPE)
	_check(game.state == Phase.ROSTER and roster.visible \
			and roster.ready_slots[0] and roster.weapons[0] == roster.DASHBLADE,
		"backing out of the rules must return the lineup exactly as it was left")
	roster.handle_key(KEY_S)
	roster.handle_key(KEY_S)
	roster.handle_key(KEY_ENTER)
	_check(game.state == Phase.MATCH_SETUP and setup.level == 2 and setup.match_lives == 7,
		"returning to the rules must find them where they were left")

	setup.handle_key(KEY_S)
	setup.handle_key(KEY_S)
	setup.handle_key(KEY_S)
	setup.handle_key(KEY_ENTER)
	await _idle()
	_check(game.state == Phase.PLANNING and not setup.visible,
		"Start must enter the arena directly from the rules screen")
	_check(game.uses_dashblade(0) and game.uses_shock(1) and game.is_ai(1),
		"the picked kits and slot ownership must reach gameplay unchanged")
	_check(game.level_index == 2 and game.hits_to_win == 7,
		"the chosen arena and match length must become the match rules")
	_check(game.player_difficulty(1) == game.Difficulty.RUTHLESS,
		"each CPU's skill preset must reach its own live search")

	game._ui.refresh()
	_check(game._ui._fighter_seals[0].fighter_name == "ROOK" \
			and game._ui._fighter_seals[1].fighter_name == "PULSE",
		"the duel HUD must identify both selected character kits")
	_check(game._ui._fighter_seals[0].portrait == game._ui.ROOK_PORTRAIT \
			and game._ui._fighter_seals[1].portrait == game._ui.PULSE_PORTRAIT,
		"each new fighter must use its own HUD portrait")

	game.players[0].plan.power = 0.5
	game._spawn_player_attack(game.players[0])
	_check(game.dashblades.size() == 1 and game.dashblades[0].owner_index == 0,
		"a Dashblade normal attack must start a physical dash action")

	await _test_human_duel(game)
	await _test_four_fighters(game)
	await _test_duplicates_and_teams(game)
	await _test_free_play(game)
	await _test_pad_claiming(game)

	if _failures == 0:
		print("Roster screen: all tests passed")
	else:
		push_error("Roster screen: %d test(s) failed" % _failures)
	game._ai_searches.fill(null)
	game.free()
	quit(_failures)


## Handing a controller to a specific column: the tile says that seat is human,
## and the pad that presses A lands in it rather than in the next empty slot.
func _test_human_duel(game) -> void:
	var roster = game._roster
	var setup = game._setup
	_reopen(game)
	roster.cursor_slot = 1
	roster.row = roster.ROW_ROLE
	roster.handle_key(KEY_A)
	roster.handle_key(KEY_A)
	_check(roster.kinds[1] == roster.SlotKind.PLAYER and roster.devices[1] == roster.NO_DEVICE,
		"a seat may be declared human before any pad is holding it")
	roster.debug_join_device(7)
	_check(roster.devices[1] == 7 and roster.filled_slots() == 2,
		"a joining pad must take the seat that was waiting for it")
	_pick(roster, 0, roster.DASHBLADE)
	_pick(roster, 1, roster.SHOCK)
	roster._set_ready(0, true)
	roster._set_ready(1, true)
	_check(roster._can_advance(), "two ready humans must be enough to move on")
	roster._confirm()
	setup._start_match()
	await _idle()
	_check(game.state == Phase.PLANNING and not game.vs_ai and not game.is_ai(1),
		"two claimed slots must start a local duel with no CPU in it")

	game._set_shock_attack_mode(1, 1)
	game._ui.refresh()
	_check(game.players[1].plan.attack_mode == 1 and "P2 ORB" in game._ui._level_label.text,
		"Player 2's Shock mode must propagate into the HUD")
	game.players[1].plan.power = 0.5
	game._spawn_player_attack(game.players[1])
	_check(game.shock_orbs.size() == 1 and game.shock_orbs[0].shooter == 1,
		"Shock secondary fire must launch its persistent orb")
	roster._debug_pads.clear()


func _test_four_fighters(game) -> void:
	var roster = game._roster
	var setup = game._setup
	_reopen(game)
	_fill(roster, 2, roster.SlotKind.CPU, 1)
	_fill(roster, 3, roster.SlotKind.CPU, 1)
	_check(roster.filled_slots() == 4,
		"filling the last two columns must be all a four-fighter match needs")
	_pick(roster, 0, roster.DUELIST)
	_pick(roster, 1, roster.DASHBLADE)
	_pick(roster, 2, roster.SHOCK)
	_pick(roster, 3, roster.CHAKRAM)
	roster._set_ready(0, true)
	roster._confirm()
	setup._start_match()
	await _idle()
	_check(game.players.size() == 4 and game.vs_ai,
		"four filled slots must start a four-fighter match")
	_check(game.uses_dashblade(1) and game.uses_shock(2) and game.uses_chakram(3) \
			and game.is_ai(1) and game.is_ai(2) and game.is_ai(3),
		"AI roster slots must retain all four selected prototype kits")

	# The Chakram is the kit whose behaviour spans turns, so it is worth pinning
	# that the slot that picked it is the slot that throws it.
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
			and is_equal_approx(game.chakram_speed_min, 230.0) \
			and is_equal_approx(game.chakram_speed_max, 420.0),
		"the throw must use the extended Chakram launch-speed range")
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


func _test_duplicates_and_teams(game) -> void:
	var roster = game._roster
	var setup = game._setup
	_reopen(game)
	_fill(roster, 2, roster.SlotKind.CPU, 1)
	_fill(roster, 3, roster.SlotKind.CPU, 1)
	for slot in 4:
		_pick(roster, slot, roster.CHAKRAM)
	_check(roster.weapons == [roster.CHAKRAM, roster.CHAKRAM, roster.CHAKRAM, roster.CHAKRAM],
		"two slots must be able to claim the same fighter")
	roster._set_ready(0, true)
	roster._confirm()
	setup.row = setup.ROW_MODE
	setup.handle_key(KEY_D)
	_check(setup.battle_mode == setup.BattleMode.TEAM_BATTLE,
		"Team Battle must be a rule on the rules screen rather than a screen of its own")
	_check(setup.build_config()["teams"] == [0, 1, 0, 1],
		"sides must alternate by slot so the arena's authored team spawns hold")
	setup._start_match()
	await _idle()
	_check(game.team_mode and game.player_teams == [0, 1, 0, 1],
		"team identities must reach gameplay unchanged")
	_check(game.uses_chakram(0) and game.uses_chakram(1),
		"duplicate picks must arm both fighters with the same kit")


func _test_free_play(game) -> void:
	var roster = game._roster
	var setup = game._setup
	_reopen(game)
	_pick(roster, 0, roster.SHOCK)
	_pick(roster, 1, roster.DUELIST)
	roster._set_ready(0, true)
	roster._confirm()
	setup.row = setup.ROW_MODE
	setup.handle_key(KEY_D)
	setup.handle_key(KEY_D)
	_check(setup.battle_mode == setup.BattleMode.FREE_PLAY \
			and setup.build_config()["roles"] == ["HUMAN", "DUMMY"],
		"Free Play must turn every unheld seat into a training dummy")
	setup.row = setup.ROW_LIVES
	setup.handle_key(KEY_D)
	_check(setup.match_lives == 5,
		"Free Play must retire match length instead of pretending to score")
	setup._start_match()
	await _idle()
	_check(game.state == Phase.FREEPLAY and game.uses_shock(0) and not game.uses_shock(1),
		"Free Play must start with the selected player and dummy characters")


func _test_pad_claiming(game) -> void:
	var roster = game._roster
	_reopen(game)
	_check("A  TO JOIN" in roster._ready_label(2),
		"an open slot must say how a pad takes it")
	roster.debug_join_device(7)
	_check(roster.kinds[2] == roster.SlotKind.PLAYER and roster.devices[2] == 7,
		"a pad pressing A must claim the first open slot")
	_check(roster._slot_for_device(7) == 2 and roster.filled_slots() == 3,
		"a claimed slot must belong to its pad and count as a fighter")

	roster.handle_joy_button(7, JOY_BUTTON_DPAD_RIGHT)
	roster.handle_joy_button(7, JOY_BUTTON_DPAD_RIGHT)
	_check(roster.weapons[2] == roster.SHOCK and roster.weapons[0] == roster.DUELIST,
		"each pad must move its own cursor without touching Player 1's")
	roster.handle_joy_button(7, JOY_BUTTON_A)
	_check(roster.ready_slots[2], "A must commit the pad's own slot")
	roster.handle_joy_button(7, JOY_BUTTON_B)
	_check(not roster.ready_slots[2], "B must release a committed slot before it leaves")
	roster.handle_joy_button(7, JOY_BUTTON_B)
	_check(roster.kinds[2] == roster.SlotKind.OPEN and roster.devices[2] == roster.NO_DEVICE,
		"backing out of an open-slot claim must empty the slot again")

	roster.debug_join_device(7)
	roster.refresh_connections()
	_check(roster.kinds[2] == roster.SlotKind.PLAYER,
		"a still-connected pad must keep the slot it claimed")
	roster._debug_pads.clear()
	roster.refresh_connections()
	_check(roster.kinds[2] == roster.SlotKind.CPU and roster.devices[2] == roster.NO_DEVICE,
		"a pad that disconnects must leave a CPU behind rather than a dead seat")
	_fill(roster, 2, roster.SlotKind.OPEN, 1)


## Return to a clean lineup screen: one keyboard player, one CPU, two open
## slots, so each case starts from what a player actually sees on arrival.
func _reopen(game) -> void:
	var roster = game._roster
	game._open_menu()
	game._transition.visible = false
	game._menu._activate(game._menu.ROW_PLAY)
	roster._debug_pads.clear()
	for slot in roster.MAX_SLOTS:
		if slot == 0:
			roster.kinds[slot] = roster.SlotKind.PLAYER
		elif slot == 1:
			roster.kinds[slot] = roster.SlotKind.CPU
		else:
			roster.kinds[slot] = roster.SlotKind.OPEN
		roster.devices[slot] = roster.KEYBOARD_DEVICE if slot == 0 else roster.NO_DEVICE
		roster.difficulties[slot] = 1
		roster.ready_slots[slot] = false
		roster.weapons[slot] = roster.DUELIST
	game._setup.battle_mode = game._setup.BattleMode.VS
	game._setup.level = 0
	game._setup.match_lives = 5
	roster._normalize()
	roster._refresh()


## Put a fighter under a slot's cursor the way a player does.
func _pick(roster, slot: int, weapon: int) -> void:
	roster.ready_slots[slot] = false
	var steps: int = roster.ROSTER.find(weapon) - roster.ROSTER.find(roster.weapons[slot])
	for _i in absi(steps):
		roster._cycle_fighter(slot, signi(steps))


func _fill(roster, slot: int, kind: int, skill: int) -> void:
	roster.difficulties[slot] = skill
	roster._set_role(slot, roster.ROLE_OPEN if kind == roster.SlotKind.OPEN \
		else (roster.ROLE_PLAYER if kind == roster.SlotKind.PLAYER \
		else roster.ROLE_CPU_FIRST + skill))


func _idle() -> void:
	await process_frame
	await process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
