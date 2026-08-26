extends SceneTree

## Reference shots of the two pre-match screens: the lineup as a table first
## sees it, a full four-slot table mid-decision, and the rules screen with the
## arena drawn beside the name that selects it.

const MAIN_SCENE := preload("res://scenes/Main.tscn")
const VisualCapture := preload("res://tests/VisualCaptureHelper.gd")


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	await VisualCapture.pin_window(self)
	game._sfx.muted = true
	game._transition.visible = false
	var roster = game._roster
	var setup = game._setup

	# What a table sees on arrival: one keyboard player, one CPU, two open seats.
	game._menu._activate(game._menu.ROW_PLAY)
	roster.cursor_slot = 0
	roster.row = roster.ROW_FIGHTER
	roster._refresh()
	await VisualCapture.await_transition(self, game)
	var open_error := VisualCapture.save(self,
		"res://previews/roster-lineup-open.png", "Lineup screen preview")

	# A full table: two humans, two CPUs, one seat still choosing.
	roster._debug_pads.clear()
	roster._debug_pads.append(7)
	roster._set_role(1, roster.ROLE_PLAYER)
	roster.devices[1] = 7
	roster._set_role(2, roster.ROLE_CPU_FIRST + 2)
	roster._set_role(3, roster.ROLE_CPU_FIRST + 0)
	roster.weapons[1] = roster.CHAKRAM
	roster.weapons[2] = roster.SHOCK
	roster.weapons[3] = roster.DASHBLADE
	roster.ready_slots[0] = true
	roster.cursor_slot = 1
	roster.row = roster.ROW_ROLE
	roster._refresh()
	await VisualCapture.await_transition(self, game)
	var full_error := VisualCapture.save(self,
		"res://previews/roster-four-fighters.png", "Four-fighter lineup preview")

	# The rules screen, on the arena row, drawing the level it is offering.
	roster.close()
	game.state = Phase.MATCH_SETUP
	setup.open(roster.build_lineup())
	setup.battle_mode = setup.BattleMode.TEAM_BATTLE
	setup.level = 5
	setup.row = setup.ROW_ARENA
	setup._refresh()
	await VisualCapture.await_transition(self, game)
	var setup_error := VisualCapture.save(self,
		"res://previews/match-setup-arena.png", "Match setup preview")

	if open_error == OK and full_error == OK and setup_error == OK:
		print("Pre-match screen previews saved")
	else:
		push_error("Could not save pre-match previews (%d, %d, %d)" % [
			open_error, full_error, setup_error])
	var result := open_error if open_error != OK else full_error
	quit(result if result != OK else setup_error)
