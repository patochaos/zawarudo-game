extends SceneTree

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
	game.start_quick_match(true, 0)
	await VisualCapture.await_transition(self, game)
	var kinds := [Effects.Kind.SPARK, Effects.Kind.SHATTER, Effects.Kind.KILL,
		Effects.Kind.CLASH, Effects.Kind.AFTERMATH, Effects.Kind.EXPLOSION]
	var colors := [Color(1.0, 0.76, 0.24), Color(0.45, 0.92, 1.0),
		Color(1.0, 0.32, 0.38), Color(0.94, 0.86, 0.56),
		Color(0.75, 0.38, 1.0), Color(0.36, 0.96, 1.0)]
	for i in kinds.size():
		game._effects.add(kinds[i], Vector2(190.0 + float(i) * 178.0, 420.0), colors[i],
			1.2 if kinds[i] == Effects.Kind.EXPLOSION else 1.0)
		if kinds[i] == Effects.Kind.AFTERMATH:
			game._effects._fx[-1]["label"] = "AFTERMATH"
	await VisualCapture.settle(self)
	var error := VisualCapture.save(self, "res://previews/kenney-vfx-polish.png",
		"Kenney VFX preview")
	quit(error)
