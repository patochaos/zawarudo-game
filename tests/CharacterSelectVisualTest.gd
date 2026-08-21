extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game._on_menu_character_select()
	game._character_select.selections[0] = game.Weapon.DASHBLADE
	game._character_select.selections[1] = game.Weapon.SHOCK
	game._character_select.locked[0] = true
	game._character_select.locked[1] = true
	game._character_select._refresh()
	await process_frame
	await process_frame
	var select_error := root.get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://previews/character-select-dashblade-shock.png"))

	game._on_menu_roster_select(4, false)
	game._character_select.selections[0] = game.Weapon.KNIVES
	game._character_select.selections[1] = game.Weapon.DASHBLADE
	game._character_select.selections[2] = game.Weapon.SHOCK
	game._character_select.selections[3] = game.Weapon.CHAKRAM
	game._character_select.locked.fill(true)
	game._character_select.active_slot = 2
	game._character_select._refresh()
	await process_frame
	await process_frame
	var roster_error := root.get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://previews/character-select-4p-roster.png"))

	game.local_weapon_choices[0] = game.Weapon.DASHBLADE
	game.local_weapon_choices[1] = game.Weapon.SHOCK
	game._on_menu_start(false, 0, 2)
	game._transition.visible = false
	game.score[0] = 1
	game.score[1] = 2
	game.super_meter[0] = 0.45
	game.super_meter[1] = 0.72
	game.players[1].plan.attack_mode = 1
	game._ui.refresh()
	await process_frame
	await process_frame
	var hud_error := root.get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://previews/hud-dashblade-vs-shock.png"))
	if select_error == OK and roster_error == OK and hud_error == OK:
		print("Character select, four-player roster and HUD previews saved")
	else:
		push_error("Could not save character previews (%d, %d, %d)" % [
			select_error, roster_error, hud_error])
	var result := select_error if select_error != OK else roster_error
	quit(result if result != OK else hud_error)
