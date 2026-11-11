extends RefCounted
class_name PlayerInput

## Player input, split out of GameManager: key and pointer events, device to
## slot mapping, touch buttons, and the per-frame polling that pilots each
## ghost, aims and charges. GameManager owns one instance as `_player_input`
## and keeps the engine callbacks `_unhandled_input` and
## `_unhandled_key_input`, which forward here, so input order and
## `set_input_as_handled` behave exactly as before. `gm` is that GameManager.
#
# Raw key handling keeps the project free of an input-map file. Rebind by
# editing the keycodes below.
#
#   Move  : held, drives the ghost in real time (stamina drains)
#   Jump  : press, inserts a jump impulse at the ghost's current tick
#   Aim   : mouse (P1) / right stick (P2)
#   Power : hold to charge (the ghost FREEZES while charging), release to fire
#           from wherever the ghost is standing
#   Super : toggles whether a full meter upgrades the next placed shot
#   Rollback   : un-fires the shot and drops the confirmation, keeps the path
#   Reset path : throws the recorded movement away and refills stamina

var gm

enum AimSrc { MOUSE, PAD, KEYS, TOUCH }
var aim_source: Array[int] = [AimSrc.MOUSE, AimSrc.KEYS, AimSrc.KEYS, AimSrc.KEYS]
var _pads: Array[int] = [-1, -1, -1, -1]
var _pad_btn_prev: Array[Dictionary] = [{}, {}, {}, {}]
var _jump_prev: Array[bool] = [false, false, false, false]
var _charge_t: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _pilot_accum: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _prev_mouse := Vector2.ZERO

## The shipped layout. `key_bindings` starts here and is replaced, action by
## action, by whatever the player sets on the controls screen.
const DEFAULT_BINDINGS := {
	"left": [KEY_A], "right": [KEY_D], "jump": [KEY_SPACE, KEY_W, KEY_UP], "wait": [KEY_S],
	"charge": [], "rollback": [KEY_R], "reset": [KEY_F],
	"super": [KEY_T],
	"aim_up": [KEY_Q], "aim_down": [KEY_E],
}
var key_bindings: Dictionary = DEFAULT_BINDINGS.duplicate(true)

const K_GAMEPAD_ONLY := {
	"left": [], "right": [], "jump": [], "wait": [],
	"charge": [], "rollback": [], "reset": [], "super": [],
	"aim_up": [], "aim_down": [],
}

## Explicit opt-in for developer match cheats; ordinary source play is clean too.
var developer_shortcuts_enabled: bool = "--dev-tools" in OS.get_cmdline_user_args()


func _init(owner) -> void:
	gm = owner


func _assign_pads() -> void:
	var list := Input.get_connected_joypads()
	_pads.fill(-1)
	if list.is_empty():
		return
	# Online maps the first pad to the server-assigned local fighter, because
	# there is only ever one person on this machine.
	if gm.online_mode and gm.online_player >= 0:
		_pads[gm.online_player] = list[0]
		return
	# Local play follows what the roster screen recorded: a pad drives the slot
	# it claimed. Entry points with no roster behind them (tutorial, free play
	# defaults) keep the old split of P1 keyboard, first pad on P2.
	var claimed := false
	for i in mini(gm.players.size(), gm.player_devices.size()):
		var device: int = gm.player_devices[i]
		if device >= 0 and device in list and not gm.is_ai(i):
			_pads[i] = device
			claimed = true
	if claimed:
		return
	# A lone person against AI or a dummy (LEARN TO PLAY, the ladder from the
	# menu) gets the first pad alongside the keyboard. The old P2 split only
	# makes sense when a second person could be holding that pad.
	var humans: Array[int] = []
	for i in mini(gm.players.size(), gm.player_roles.size()):
		if gm.player_roles[i] == "HUMAN":
			humans.append(i)
	if humans.size() == 1:
		_pads[humans[0]] = list[0]
	elif gm.players.size() > 1:
		_pads[1] = list[0]


func _is_locally_controlled(i: int) -> bool:
	return i == gm.online_player if gm.online_mode else not gm.is_ai(i)


func _input_map_for(i: int) -> Dictionary:
	# In an online room both people get the natural P1 bindings on their own
	# machine, regardless of whether the server assigned them slot 0 or slot 1.
	# In a local duel P2 is gamepad-only so the two players never fight over one
	# keyboard or accidentally drive each other's plan.
	return key_bindings if gm.online_mode \
		else (key_bindings if i == _keyboard_player() else K_GAMEPAD_ONLY)


## Whoever claimed the keyboard seat on the roster screen drives it in play,
## in every mode. Slot 0 is the fallback for entry points with no roster.
func _keyboard_player() -> int:
	if gm.online_mode:
		return gm.online_player
	for i in gm.player_devices.size():
		if gm.player_devices[i] == gm.KEYBOARD_DEVICE and gm.player_roles[i] == "HUMAN":
			return i
	return 0


func _slot_for_device(device_id: int) -> int:
	for i in gm.player_devices.size():
		if gm.player_devices[i] == device_id and gm.player_roles[i] == "HUMAN":
			return i
	return -1


func _touch_player() -> int:
	# A phone controls its own lockstep slot online and Player 1 everywhere else.
	return gm.online_player if gm.online_mode else 0


func _on_touch_confirm() -> void:
	gm._confirm(_touch_player())


func _on_touch_rollback() -> void:
	gm._rollback(_touch_player())


func _on_touch_reset() -> void:
	gm._reset_path(_touch_player())


func _on_touch_super() -> void:
	gm._toggle_super(_touch_player())


func _on_touch_menu() -> void:
	if gm.online_mode:
		gm._online._leave_online()
	else:
		gm._open_menu()


func _on_touch_rematch() -> void:
	gm._request_rematch()


func _on_touch_replay() -> void:
	if gm.state == Phase.REPLAY:
		gm._replay._finish_match_replay()
	else:
		gm._replay._start_match_replay()


func _unhandled_input(event: InputEvent) -> void:
	if gm._feedback != null and gm._feedback.visible: return
	if gm._offline_tuning_layer != null and gm._offline_tuning_layer.visible:
		if event.is_action_pressed("ui_cancel"):
			gm._offline_tuning_layer.handle_key(KEY_ESCAPE)
			gm.get_viewport().set_input_as_handled()
		return
	if gm.state == Phase.ROSTER or gm.state == Phase.MATCH_SETUP:
		var joy := event as InputEventJoypadButton
		if joy != null and joy.pressed:
			if gm.state == Phase.ROSTER:
				gm._roster.handle_joy_button(joy.device, joy.button_index)
			else:
				gm._setup.handle_joy_button(joy.device, joy.button_index)
		return
	if gm.state == Phase.ONLINE_SELECT:
		var pad := event as InputEventJoypadButton
		if pad != null and pad.pressed:
			if gm._online._online_setup.visible:
				gm._online._online_setup.handle_joy_button(pad.device, pad.button_index)
			else:
				gm._online._online_roster.handle_joy_button(pad.device, pad.button_index)
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		gm._rollback(_keyboard_player())


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if gm.demo_match and gm.state == Phase.PLANNING and gm._transition.visible: return
	if gm._feedback != null and gm._feedback.visible:
		if k.keycode == KEY_ESCAPE: gm._feedback.close()
		return
	if gm.state == Phase.PLANNING and gm._ui._turn_review.visible:
		match k.keycode:
			KEY_V, KEY_ESCAPE:
				gm._ui._turn_review.visible = false
			KEY_COMMA:
				gm._ui._turn_review.seek(-1)
			KEY_PERIOD:
				gm._ui._turn_review.seek(1)
			KEY_SPACE:
				if gm._ui._turn_review.cursor >= gm._ui._turn_review.frames.size() - 1:
					gm._ui._turn_review.cursor = 0.0
				gm._ui._turn_review.paused = not gm._ui._turn_review.paused
		return
	if gm.state == Phase.PLANNING and k.keycode == KEY_V and not gm._practice.active:
		gm._ui._turn_review.open_last_turn()
		return
	if gm._feedback != null and gm._feedback.visible:
		if k.keycode == KEY_ESCAPE: gm._feedback.close()
		return
	if gm._practice != null and gm._practice.active and gm._practice.handle_key(k.keycode):
		return
	if gm.state == Phase.ROSTER:
		gm._roster.handle_key(k.keycode)
		return
	if gm.state == Phase.MATCH_SETUP:
		gm._setup.handle_key(k.keycode)
		return
	if gm.state == Phase.TUTORIAL:
		gm._tutorial.handle_key(k.keycode)
		return

	if gm.state == Phase.MENU:
		if gm._offline_tuning_layer != null and gm._offline_tuning_layer.visible:
			gm._offline_tuning_layer.handle_key(k.keycode)
		else:
			gm._menu.handle_key(k.keycode)
		return
	if gm.state == Phase.ONLINE_LOBBY:
		gm._online._online_lobby.handle_key(k.keycode)
		return
	if gm.state == Phase.ONLINE_SELECT:
		if gm._online._online_setup.visible:
			gm._online._online_setup.handle_key(k.keycode)
		else:
			gm._online._online_roster.handle_key(k.keycode)
		return

	if gm.state == Phase.FREEPLAY:
		match k.keycode:
			KEY_ESCAPE:
				gm._open_menu()
			KEY_R:
				gm._reset_freeplay()
			KEY_M:
				gm._sfx.toggle_mute()
			KEY_F10:
				gm._load_level(gm.level_index + 1)
				gm._reset_freeplay()
			KEY_F7:
				gm._activate_secret_triple_match()
			KEY_F8:
				gm._fill_test_super(k.shift_pressed)
			_:
				gm._tuning.handle_key(k.keycode, k.shift_pressed)
		return

	if gm.state == Phase.REPLAY:
		match k.keycode:
			KEY_ESCAPE:
				gm._replay._finish_match_replay()
				if gm.online_mode:
					gm._online._leave_online()
				else:
					gm._open_menu()
			KEY_ENTER, KEY_KP_ENTER, KEY_R:
				gm._replay._finish_match_replay()
			KEY_M:
				gm._sfx.toggle_mute()
			KEY_H:
				gm._ui.toggle_help()
		return

	if gm.online_mode:
		match k.keycode:
			KEY_ESCAPE:
				gm._online._leave_online()
				return
			KEY_M:
				var online_muted: bool = gm._sfx.toggle_mute()
				gm.banner_text = "SOUND OFF" if online_muted else "SOUND ON"
				gm.banner_color = Color(0.62, 0.68, 0.78)
				gm.banner_time = 1.1
				return
			KEY_H:
				gm._ui.toggle_help()
				return

		if gm.state == Phase.GAME_OVER:
			if k.keycode in [KEY_ENTER, KEY_KP_ENTER]:
				gm._request_rematch()
			elif k.keycode == KEY_N:
				gm.start_next_opponent()
			elif k.keycode == KEY_R:
				gm._replay._start_match_replay()
			elif k.keycode == KEY_LEFT:
				gm._cycle_rematch_level(-1)
			elif k.keycode == KEY_RIGHT:
				gm._cycle_rematch_level(1)
			elif k.keycode == KEY_C:
				gm.copy_match_report()
			return

		if k.keycode in [KEY_ENTER, KEY_KP_ENTER] and gm._online.online_peer_lost:
			gm._claim_abandoned_match()
			return
		if k.keycode == KEY_SHIFT:
			gm._confirm(gm.online_player)
			return
		if gm.state != Phase.PLANNING:
			return
		var online_map := key_bindings
		if k.keycode in online_map["super"]:
			gm._toggle_super(gm.online_player)
		elif k.keycode in online_map["rollback"]:
			gm._rollback(gm.online_player)
		elif k.keycode in online_map["reset"]:
			gm._reset_path(gm.online_player)
		return

	if gm.state == Phase.GAME_OVER:
		match k.keycode:
			KEY_ESCAPE:
				gm._open_menu()
			KEY_ENTER, KEY_KP_ENTER:
				gm._request_rematch()
			KEY_R:
				gm._replay._start_match_replay()
			KEY_LEFT:
				gm._cycle_rematch_level(-1)
			KEY_RIGHT:
				gm._cycle_rematch_level(1)
			KEY_M:
				gm._sfx.toggle_mute()
			KEY_C:
				gm.copy_match_report()
		return

	match k.keycode:
		KEY_ESCAPE:
			gm._open_menu()
			return
		KEY_F1:
			if not developer_shortcuts_enabled: return
			gm.planning_duration = 5.0
			gm._clamp_planning_timer()
			return
		KEY_F2:
			if not developer_shortcuts_enabled: return
			gm.planning_duration = 8.0
			gm._clamp_planning_timer()
			return
		KEY_F3:
			if not developer_shortcuts_enabled: return
			gm.planning_duration = 10.0
			gm._clamp_planning_timer()
			return
		KEY_F5:
			if not developer_shortcuts_enabled: return
			gm.execution_duration = 0.40
			return
		KEY_F6:
			if not developer_shortcuts_enabled: return
			gm.execution_duration = 0.75
			return
		KEY_F7:
			if not developer_shortcuts_enabled: return
			gm._activate_secret_triple_match()
			return
		KEY_F8:
			if not developer_shortcuts_enabled: return
			gm._fill_test_super(k.shift_pressed)
			return
		KEY_F9:
			if not developer_shortcuts_enabled: return
			gm.restart()
			return
		KEY_F10:
			if not developer_shortcuts_enabled: return
			gm.next_level()
			return
		KEY_M:
			var m: bool = gm._sfx.toggle_mute()
			gm.banner_text = "SOUND OFF" if m else "SOUND ON"
			gm.banner_color = Color(0.62, 0.68, 0.78)
			gm.banner_time = 1.1
			return
		KEY_H:
			gm._ui.toggle_help()
			return

	# Local P1 owns keyboard + mouse. Right Shift used to confirm P2, but local P2
	# is now deliberately gamepad-only and confirms with Start.
	var keyboard_player := _keyboard_player()
	if k.keycode == KEY_SHIFT:
		if k.location != KEY_LOCATION_RIGHT and not gm.is_ai(keyboard_player):
			gm._confirm(keyboard_player)
		return

	if gm.state != Phase.PLANNING:
		return

	if k.keycode == KEY_BACKSPACE:
		gm._rewind_plan(keyboard_player, gm.players[keyboard_player].plan.recorded_ticks() - 6)
		return
	if k.keycode in [KEY_COMMA, KEY_PERIOD]:
		gm._shift_shot(keyboard_player, -1 if k.keycode == KEY_COMMA else 1)
		return

	for i in gm.players.size():
		if gm.is_ai(i):
			continue
		var map: Dictionary = _input_map_for(i)
		if k.keycode in map["super"]:
			gm._toggle_super(i)
		elif k.keycode in map["rollback"]:
			gm._rollback(i)
		elif k.keycode in map["reset"]:
			gm._reset_path(i)


# ---------------------------------------------------------- polled planning --

func _poll_game_over_pad() -> void:
	for i in gm.players.size():
		var pad: int = _pads[i]
		if pad < 0:
			continue
		var rematch_pressed := _pad_edge(i, pad, JOY_BUTTON_A)
		var replay_pressed := _pad_edge(i, pad, JOY_BUTTON_Y)
		var report_pressed := _pad_edge(i, pad, JOY_BUTTON_X)
		var previous_pressed := _pad_edge(i, pad, JOY_BUTTON_DPAD_LEFT)
		var next_pressed := _pad_edge(i, pad, JOY_BUTTON_DPAD_RIGHT)
		if replay_pressed:
			gm._replay._start_match_replay()
			return
		if report_pressed:
			gm.copy_match_report()
			return
		if rematch_pressed:
			gm._request_rematch()
			return
		if previous_pressed:
			gm._cycle_rematch_level(-1)
		elif next_pressed:
			gm._cycle_rematch_level(1)


func _poll_replay_pad() -> void:
	for i in gm.players.size():
		var pad: int = _pads[i]
		if pad < 0:
			continue
		var a := _pad_edge(i, pad, JOY_BUTTON_A)
		var b := _pad_edge(i, pad, JOY_BUTTON_B)
		var y := _pad_edge(i, pad, JOY_BUTTON_Y)
		if a or b or y:
			gm._replay._finish_match_replay()
			return


func _prime_game_over_pad_state() -> void:
	# A may still be held from the final jump. Seed result-screen edges so that
	# carrying a gameplay button through the kill never starts an instant rematch.
	for i in gm.players.size():
		var pad: int = _pads[i]
		if pad < 0:
			continue
		for button in [JOY_BUTTON_A, JOY_BUTTON_X, JOY_BUTTON_Y,
				JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
			_pad_btn_prev[i][button] = Input.is_joy_button_pressed(pad, button)


func _poll_planning_input(delta: float) -> void:
	var mouse: Vector2 = gm.get_viewport().get_mouse_position()
	var mouse_moved: bool = mouse.distance_to(_prev_mouse) > 0.5
	_prev_mouse = mouse

	for i in gm.players.size():
		var p: Player = gm.players[i]
		if not p.alive or not _is_locally_controlled(i):
			continue
		_poll_pad_meta(i)
		if p.plan.confirmed:
			continue
		# Explicit aim edit retains shot timing and charge; incidental mouse motion
		# after placing a throw must not change it.
		var edit_aim: bool = (i == _keyboard_player() and Input.is_physical_key_pressed(KEY_ALT)) or \
			(_pads[i] >= 0 and Input.is_joy_button_pressed(_pads[i], JOY_BUTTON_RIGHT_SHOULDER))
		if p.plan.has_shot() and edit_aim:
			_poll_aim(i, delta, mouse_moved)
		if not p.plan.has_shot():
			_poll_aim(i, delta, mouse_moved)
			_poll_charge(i, delta)
		_poll_pilot(i, delta)


## Confirm / rollback work even while confirmed, so they are polled separately.
func _poll_pad_meta(i: int) -> void:
	var pad: int = _pads[i]
	if pad < 0:
		return
	# Every edge must be sampled each frame, so no short-circuiting here.
	var start := _pad_edge(i, pad, JOY_BUTTON_START)
	var back := _pad_edge(i, pad, JOY_BUTTON_BACK)
	var b := _pad_edge(i, pad, JOY_BUTTON_B)
	var x := _pad_edge(i, pad, JOY_BUTTON_X)
	var y := _pad_edge(i, pad, JOY_BUTTON_Y)
	var fuse_previous := _pad_edge(i, pad, JOY_BUTTON_LEFT_SHOULDER)
	if start:
		gm._confirm(i)
	if back or b:
		gm._rollback(i)
	if x:
		gm._reset_path(i)
	if y:
		gm._toggle_super(i)
	if fuse_previous:
		gm._rewind_plan(i, gm.players[i].plan.recorded_ticks() - 6)


func _pad_edge(i: int, pad: int, btn: int) -> bool:
	var now: bool = Input.is_joy_button_pressed(pad, btn)
	var was: bool = _pad_btn_prev[i].get(btn, false)
	_pad_btn_prev[i][btn] = now
	return now and not was


## Free platformer control of the ghost, metered by stamina. Time only advances
## while the player is actually driving (or is airborne and committed to the
## arc), and never while a shot is being charged.
func _poll_pilot(i: int, delta: float) -> void:
	var map: Dictionary = _input_map_for(i)
	var pad: int = _pads[i]

	var dir := 0
	var touch_player := _touch_player()
	if _held(map["left"]) or _pad_left(pad) or (i == touch_player and gm._touch_controls.left_held):
		dir -= 1
	if _held(map["right"]) or _pad_right(pad) or (i == touch_player and gm._touch_controls.right_held):
		dir += 1
	# On touch, walking establishes the natural default facing. A deliberate
	# right-side aim gesture latches the bow, so walking the other way afterwards
	# cannot flip the shot.
	if i == touch_player and gm._touch_controls.enabled and dir != 0 \
			and not gm._touch_controls.aim_latched:
		gm.players[i].plan.set_aim_side(dir)

	var jump_now: bool = _jump_input_held(i)
	var jump_edge: bool = jump_now and not _jump_prev[i]
	_jump_prev[i] = jump_now

	var wait_held: bool = _held(map["wait"]) or _pad_down(pad) \
		or (i == touch_player and gm._touch_controls.wait_held)

	if gm.charging[i] or gm.stamina[i] <= 0.0:
		_pilot_accum[i] = 0.0
		return

	# Down + jump goes DOWN. Checked before the jump so the two verbs sharing one
	# button never both fire, and only from the ground, because dropping through
	# a ledge you are not standing on is not a move anyone means to make.
	if jump_edge and wait_held and gm.ghost_ground[i]:
		gm._pilot_step(i, dir, false, false, true)
		_pilot_accum[i] = 0.0
		return

	# A jump press must land on a tick even if nothing else is being held.
	if jump_edge and (gm.ghost_ground[i] or gm.ghost_air_jumps[i] > 0):
		gm._pilot_step(i, dir, true, true)
		_pilot_accum[i] = 0.0
		return

	# ONE time rule, on the ground and in the air alike: the ghost advances only
	# while you are holding a pilot input. Airborne used to advance on its own,
	# which meant the controls silently changed the moment you left the ground,
	# and since a full jump outlasts the window, that was every jump.
	var advancing: bool = dir != 0 or jump_now or wait_held
	if not advancing:
		_pilot_accum[i] = 0.0
		return

	_pilot_accum[i] += delta * gm.pilot_time_scale
	while _pilot_accum[i] >= gm.tick_dt():
		_pilot_accum[i] -= gm.tick_dt()
		if not gm._pilot_step(i, dir, false, jump_now):
			_pilot_accum[i] = 0.0
			break


func _jump_input_held(i: int) -> bool:
	var map: Dictionary = _input_map_for(i)
	var pad: int = _pads[i]
	var touch_jump: bool = gm._touch_controls != null and i == _touch_player() \
		and gm._touch_controls.jump_held
	return _held(map["jump"]) \
		or (pad >= 0 and Input.is_joy_button_pressed(pad, JOY_BUTTON_A)) \
		or touch_jump


func _held(codes: Array) -> bool:
	for c in codes:
		if Input.is_key_pressed(c):
			return true
	return false


func _pad_left(pad: int) -> bool:
	if pad < 0:
		return false
	return Input.get_joy_axis(pad, JOY_AXIS_LEFT_X) < -0.4 \
		or Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_LEFT)


func _pad_right(pad: int) -> bool:
	if pad < 0:
		return false
	return Input.get_joy_axis(pad, JOY_AXIS_LEFT_X) > 0.4 \
		or Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_RIGHT)


## "Let time run without steering": hold to walk the ghost forward through a
## fall, or to line a shot up at a precise moment.
func _pad_down(pad: int) -> bool:
	if pad < 0:
		return false
	return Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y) > 0.4 \
		or Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_DOWN)


func _poll_aim(i: int, delta: float, mouse_moved: bool) -> void:
	if i == _keyboard_player() and gm._ui.pointer_on_action(gm.get_viewport().get_mouse_position()): return
	var p: Player = gm.players[i]
	var map: Dictionary = _input_map_for(i)
	var pad: int = _pads[i]
	var touch_driven: bool = i == _touch_player() and gm._touch_controls.enabled
	# Browsers emulate a mouse cursor from the most recent finger. Without this
	# arbitration, dragging the left joystick can replace a rightward touch aim
	# with the joystick's screen position and silently flip the shot left.
	if touch_driven and aim_source[i] == AimSrc.MOUSE:
		aim_source[i] = AimSrc.TOUCH

	# --- pick the active aim source from whatever the player touched last ---
	var stick := Vector2.ZERO
	if pad >= 0:
		stick = Vector2(Input.get_joy_axis(pad, JOY_AXIS_RIGHT_X), Input.get_joy_axis(pad, JOY_AXIS_RIGHT_Y))
		if stick.length() > gm.stick_deadzone:
			aim_source[i] = AimSrc.PAD
	var key_dir := 0.0
	if _held(map["aim_up"]):
		key_dir += 1.0
	if _held(map["aim_down"]):
		key_dir -= 1.0
	if key_dir != 0.0:
		aim_source[i] = AimSrc.KEYS
	elif i == _touch_player() and gm._touch_controls.aim_active:
		aim_source[i] = AimSrc.TOUCH
	elif i == _keyboard_player() \
			and mouse_moved and not gm._touch_controls.enabled:
		aim_source[i] = AimSrc.MOUSE

	# --- apply it ---
	match aim_source[i]:
		AimSrc.PAD:
			if stick.length() > gm.stick_deadzone:
				p.plan.set_aim_from_vector(stick, gm.aim_min_angle, gm.aim_max_angle)
		AimSrc.MOUSE:
			if not gm._touch_controls.enabled:
				# Measured from the ghost, because that is where the shot leaves from.
				p.plan.set_aim_from_vector(gm.get_global_mouse_position() \
					- Player.shoulder_at(gm.shot_origin(i)),
					gm.aim_min_angle, gm.aim_max_angle)
		AimSrc.TOUCH:
			if gm._touch_controls.aim_active:
				p.plan.set_aim_from_vector(gm._touch_controls.aim_position \
					- Player.shoulder_at(gm.shot_origin(i)),
					gm.aim_min_angle, gm.aim_max_angle)
		AimSrc.KEYS:
			if key_dir != 0.0:
				p.plan.set_elevation(p.plan.elevation() + key_dir * gm.aim_rate * delta,
					gm.aim_min_angle, gm.aim_max_angle)


func _poll_charge(i: int, delta: float) -> void:
	if i == _keyboard_player() and gm._ui.pointer_on_action(gm.get_viewport().get_mouse_position()): return
	var p: Player = gm.players[i]
	var map: Dictionary = _input_map_for(i)
	var pad: int = _pads[i]

	var primary_held: bool = _held(map["charge"]) \
		or (i == _touch_player() and gm._touch_controls.charge_held)
	if i == _keyboard_player() \
			and not gm._touch_controls.has_active_touches() \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		primary_held = true
	if pad >= 0 and Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_RIGHT) > gm.trigger_threshold:
		primary_held = true

	if primary_held:
		if not gm.charging[i]:
			gm.charging[i] = true
			_charge_t[i] = 0.0
		else:
			_charge_t[i] = minf(_charge_t[i] + delta, gm.charge_time)
		p.plan.power = _charge_t[i] / gm.charge_time
	elif gm.charging[i]:
		gm._release_charge(i)
