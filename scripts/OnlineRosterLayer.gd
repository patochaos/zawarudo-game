extends RosterLayer
class_name OnlineRosterLayer

## The custom-match lineup screen, played over the network. Every seat belongs
## to a connected player; this machine steers only its own column and sees the
## others' picks arrive live. Confirming moves on to the arena and length vote.

signal pick_changed(weapon: int)

var local_slot: int = 0
var seat_count: int = 2
var seat_names: Array = []
var seat_connected: Array = []
## Who has readied up on the rules screen; shown here so a player who stepped
## back to change fighter can see the table is waiting.
var seat_ready: Array = []


func _ready() -> void:
	super._ready()
	layer = 21


## `weapons` is the room's view of every seat. The local seat keeps its own pick
## unless `take_local` asks for the room's copy (first open, reconnects).
func configure_room(local: int, seats: int, names: Array, connected: Array, room_weapons: Array,
		ready_seats: Array, take_local: bool = false) -> void:
	local_slot = clampi(local, 0, MAX_SLOTS - 1)
	seat_count = clampi(seats, MIN_FIGHTERS, MAX_SLOTS)
	seat_names = names.duplicate()
	seat_connected = connected.duplicate()
	seat_ready = ready_seats.duplicate()
	for i in MAX_SLOTS:
		if i < room_weapons.size() and (i != local_slot or take_local):
			weapons[i] = int(room_weapons[i])
	_normalize()
	if is_node_ready():
		_refresh()


func open() -> void:
	visible = true
	cursor_slot = local_slot
	row = ROW_FIGHTER
	_normalize()
	_refresh()


func local_weapon() -> int:
	return weapons[local_slot]


func handle_joy_button(_device: int, button: int) -> void:
	match button:
		JOY_BUTTON_DPAD_LEFT:
			_cycle_fighter(local_slot, -1)
		JOY_BUTTON_DPAD_RIGHT:
			_cycle_fighter(local_slot, 1)
		JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN:
			_step_row(1)
		JOY_BUTTON_A, JOY_BUTTON_START:
			_confirm()
		JOY_BUTTON_B:
			cancel()


func _normalize() -> void:
	for i in MAX_SLOTS:
		if weapons[i] not in ROSTER:
			weapons[i] = ROSTER[0]
		kinds[i] = SlotKind.PLAYER if i < seat_count else SlotKind.OPEN
		devices[i] = NO_DEVICE
		ready_slots[i] = i < seat_ready.size() and bool(seat_ready[i])
	cursor_slot = local_slot
	if row == ROW_ROLE:
		row = ROW_FIGHTER


func _cycle_fighter(slot: int, direction: int) -> void:
	if slot != local_slot or direction == 0:
		return
	weapons[slot] = Roster.step(weapons[slot], direction)
	ui_navigated.emit()
	_refresh()
	pick_changed.emit(weapons[slot])


# Seats are fixed by the room: nobody can add a CPU, free a seat or join a pad.
func _cycle_role(_slot: int, _direction: int) -> void:
	pass


func _set_role(_slot: int, _index: int) -> void:
	pass


func _release(_slot: int) -> void:
	pass


func _join(_device: int) -> void:
	pass


func _set_ready(_slot: int, _value: bool) -> void:
	pass


func _can_advance() -> bool:
	return true


func _focus(slot: int, next_row: int) -> void:
	if slot != local_slot or next_row == ROW_ROLE:
		return
	super._focus(slot, next_row)


func _step_row(_direction: int) -> void:
	row = ROW_NEXT if row == ROW_FIGHTER else ROW_FIGHTER
	ui_navigated.emit()
	_refresh()


func _step_slot(_direction: int) -> void:
	pass


func _activate() -> void:
	_confirm()


func _click_card(slot: int) -> void:
	if slot == local_slot:
		_confirm()


func _click_arrow(slot: int, target_row: int, direction: int) -> void:
	if slot == local_slot and target_row == ROW_FIGHTER:
		_cycle_fighter(slot, direction)


func _seat_tag(slot: int) -> String:
	return OnlineLobby.seat_tag(slot, seat_names)


func _role_label(slot: int) -> String:
	if slot >= seat_count:
		return "NOT IN THIS ROOM"
	if slot == local_slot:
		return "YOU"
	if slot < seat_connected.size() and not bool(seat_connected[slot]):
		return "DISCONNECTED"
	return "ONLINE"


func _ready_label(slot: int) -> String:
	if slot >= seat_count:
		return "—"
	if ready_slots[slot]:
		return "READY"
	return "PICKING" if slot != local_slot else "ENTER TO CONTINUE"


func _refresh() -> void:
	super._refresh()
	_write("breadcrumb", "// ONLINE  ·  PICK YOUR FIGHTER")
	_write("tally", "%d-PLAYER ROOM" % seat_count)
	for i in MAX_SLOTS:
		if i < seat_count:
			_write("head_tag_%d" % i, _seat_tag(i) if i != local_slot else "%s · YOU" % _seat_tag(i))
		else:
			_write("card_name_%d" % i, "—")
			_write("card_kit_%d" % i, "%d-PLAYER ROOM" % seat_count)
		_write("role_label_%d" % i, "PLAYER")
	_write("next", "ARENA VOTE  ›")
	_tint("next", HOT)
	_write("hint", "← / →  CHANGE FIGHTER   ·   ENTER  ARENA VOTE   ·   ESC  LEAVE ROOM\n" \
		+ "PAD  ·   D-PAD  CHANGE FIGHTER   ·   A  ARENA VOTE   ·   B  LEAVE ROOM")
	# Only this machine's column is live; the rest are a read-out of the room.
	var columns: Array = _art.model.get("columns", [])
	for i in columns.size():
		var column: Dictionary = columns[i]
		column["arrows"] = i == local_slot
		column["role_focused"] = false
		column["ready"] = ready_slots[i]
	_art.queue_redraw()
