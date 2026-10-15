extends SceneTree

## Two players on the same fighter. The authored art is identical, so the only
## thing separating them is the silhouette aura and the palette-driven markers.

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
	game.fighter_visuals_enabled = true
	game.start_quick_match(false, 0, 2, [game.Weapon.KNIVES, game.Weapon.KNIVES])
	game._transition.visible = false
	await VisualCapture.await_transition(self, game)
	var duelists := VisualCapture.save(self, "res://previews/identity-two-duelists.png",
		"Two Duelists preview")

	game.start_quick_match(false, 0, 4,
		[game.Weapon.DASHBLADE, game.Weapon.DASHBLADE,
		game.Weapon.KNIVES, game.Weapon.KNIVES])
	game._transition.visible = false
	await VisualCapture.await_transition(self, game)
	var four := VisualCapture.save(self, "res://previews/identity-four-slots.png",
		"Four-slot identity preview")
	game.start_quick_match(false, 0, 4,
		[game.Weapon.KNIVES, game.Weapon.DASHBLADE,
		game.Weapon.CHAKRAM, game.Weapon.SHOCK])
	# Inspect every authored skin even when the public roster limits choices.
	var kits_to_check := [game.Weapon.KNIVES, game.Weapon.DASHBLADE,
		game.Weapon.CHAKRAM, game.Weapon.SHOCK]
	for i in 4:
		game.player_weapons[i] = kits_to_check[i]
		game._sync_fighter_visual(game.players[i], i)
	game._transition.visible = false
	await VisualCapture.await_transition(self, game)
	var kits := VisualCapture.save(self, "res://previews/identity-all-kits.png",
		"All fighter auras preview")
	await VisualCapture.pin_window(self, Vector2i(1024, 576))
	for i in 4:
		game.players[i].facing *= -1
		game.players[i].vel = Vector2(400.0, 0.0)
	await VisualCapture.settle(self, 3)
	var compact := VisualCapture.save(self, "res://previews/identity-all-kits-compact.png",
		"Compact fighter auras preview")
	quit(duelists if duelists != OK else (four if four != OK else (kits if kits != OK else compact)))
