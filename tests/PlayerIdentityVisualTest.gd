extends SceneTree

## Two players on the same fighter. The authored art is identical, so the only
## thing separating them is the accent wash and the palette-driven markers.

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
	game.simplified_fighter_proto_enabled = true
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
	quit(duelists if duelists != OK else four)
