extends RefCounted

## Shared plumbing for the tests/*VisualTest.gd screenshot capture scripts.
##
## These captures are developer tools, not CI suites. Reading a frame back needs
## a real render target, so they must be run WINDOWED — omit --headless:
##
##     Godot_v4.7.1-stable_win64_console.exe --path . --script tests/<X>VisualTest.gd
##
## Under --headless `root.get_texture().get_image()` returns null. Left
## unchecked that kills the capture coroutine mid-flight, so `quit()` is never
## reached and the run hangs forever with nothing written. `save()` below
## reports the real cause and returns a non-zero Error instead.


## Upper bound on frames spent waiting for TransitionLayer, roughly five times
## the 0.68 s wipe at 60 fps. Keeps a stuck transition from hanging a capture.
const TRANSITION_FRAME_CAP := 240


## The design resolution. A reference shot has to be comparable between two
## machines, and a maximized window is whatever the developer's monitor happens
## to be, so the menu captures pin the window instead of inheriting it.
const CAPTURE_SIZE := Vector2i(1280, 720)


static func pin_window(tree: SceneTree, size: Vector2i = CAPTURE_SIZE) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	if DisplayServer.window_get_size() != size:
		DisplayServer.window_set_size(size)
	await settle(tree, 4)


## Waits for GameManager's full-screen transition wipe to finish, then lets the
## destination settle for a few frames. Without this a capture taken right after
## a state change documents the animated wipe rather than the screen underneath.
## Returns immediately when the transition is already hidden.
static func await_transition(tree: SceneTree, game, settle_frames: int = 2) -> void:
	var frames := 0
	while frames < TRANSITION_FRAME_CAP:
		await tree.process_frame
		frames += 1
		var transition = game.get("_transition") if game != null else null
		if transition == null or not transition.visible:
			break
	if frames >= TRANSITION_FRAME_CAP:
		push_warning("Transition still visible after %d frames; capturing anyway"
			% TRANSITION_FRAME_CAP)
	await settle(tree, settle_frames)


## Lets queued redraws land before a capture. Use this only for redraws, never
## as a substitute for `await_transition()`.
static func settle(tree: SceneTree, frames: int = 2) -> void:
	for i in maxi(frames, 1):
		await tree.process_frame


## Grabs the rendered viewport and writes it to `output` (a res:// path).
## `label` names the capture in the success line, matching each script's own
## wording. `expected_size` optionally asserts the exact viewport resolution.
## Returns OK, or a non-zero Error after printing why the capture failed.
static func save(tree: SceneTree, output: String, label: String,
		expected_size: Vector2i = Vector2i.ZERO) -> Error:
	if DisplayServer.get_name() == "headless":
		# Checked up front so the engine's own "Parameter t is null" noise from
		# the dummy renderer never buries the real explanation below.
		_report_no_frame(output)
		return ERR_UNAVAILABLE
	var texture := tree.root.get_texture()
	var image := texture.get_image() if texture != null else null
	if image == null or image.is_empty():
		_report_no_frame(output)
		return ERR_UNAVAILABLE
	if expected_size != Vector2i.ZERO \
			and (image.get_width() != expected_size.x or image.get_height() != expected_size.y):
		printerr("VISUAL CAPTURE FAILED: %s must render at %dx%d, got %dx%d" % [
			output, expected_size.x, expected_size.y, image.get_width(), image.get_height()])
		push_error("%s must render at %dx%d, got %dx%d" % [
			output, expected_size.x, expected_size.y, image.get_width(), image.get_height()])
		return ERR_INVALID_DATA
	var error := image.save_png(ProjectSettings.globalize_path(output))
	if error != OK:
		printerr("VISUAL CAPTURE FAILED: could not write %s (error %d)" % [output, error])
		push_error("Could not save %s (error %d)" % [label, error])
		return error
	print("%s saved: %s" % [label, output])
	return OK


static func _report_no_frame(output: String) -> void:
	printerr("")
	printerr("VISUAL CAPTURE FAILED: the rendered frame for %s is empty." % output)
	if DisplayServer.get_name() == "headless":
		printerr("  Godot is running with --headless, which has no render target,")
		printerr("  so root.get_texture().get_image() always returns null.")
		printerr("  Re-run this capture WINDOWED, without --headless:")
		printerr("    Godot --path . --script tests/<Name>VisualTest.gd")
		printerr("  Screenshot captures are developer tools and are not run in CI.")
	else:
		printerr("  The window produced no readable frame. Check that the display")
		printerr("  server is available and the viewport has a non-zero size.")
	printerr("")
	push_error("Visual capture produced no image for %s" % output)
