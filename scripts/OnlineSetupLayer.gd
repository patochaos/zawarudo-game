extends MatchSetupLayer
class_name OnlineSetupLayer

## The custom-match rules screen, played over the network. Each player votes for
## an arena and a match length; when everyone is ready the room counts the votes
## and breaks a tie at random. Online matches are always free-for-all VS, so the
## mode row is shown but fixed.

signal vote_changed(level: int, lives: int)
signal ready_changed(now_ready: bool)

var local_slot: int = 0
var is_ready: bool = false
var seat_names: Array = []
var seat_ready: Array = []
var level_votes: Array = []
var lives_votes: Array = []


func _ready() -> void:
	super._ready()
	layer = 21


func configure_room(local: int, names: Array, room_weapons: Array, votes: Array,
		lives: Array, ready_seats: Array) -> void:
	local_slot = local
	seat_names = names.duplicate()
	seat_ready = ready_seats.duplicate()
	level_votes = votes.duplicate()
	lives_votes = lives.duplicate()
	var roles: Array = []
	roles.resize(room_weapons.size())
	roles.fill("HUMAN")
	configure({"player_count": room_weapons.size(), "weapons": room_weapons.duplicate(),
		"roles": roles})


## `vote_level` and `vote_lives` are this machine's current votes.
func open_vote(vote_level: int, vote_lives: int, ready_flag: bool) -> void:
	battle_mode = BattleMode.VS
	level = posmod(vote_level, Levels.count())
	match_lives = vote_lives if vote_lives in MATCH_LIFE_OPTIONS else 5
	is_ready = ready_flag
	visible = true
	row = ROW_START if is_ready else ROW_ARENA
	_refresh()


func cancel() -> void:
	ui_accepted.emit()
	if is_ready:
		is_ready = false
		ready_changed.emit(false)
	close()
	canceled.emit()


func _step_row(direction: int) -> void:
	row = posmod(row + direction, ROW_TOTAL)
	if row == ROW_MODE:
		row = posmod(row + direction, ROW_TOTAL)
	ui_navigated.emit()
	_refresh()


func _focus(next_row: int) -> void:
	if next_row == ROW_MODE:
		return
	super._focus(next_row)


func _adjust(direction: int) -> void:
	if is_ready or row == ROW_MODE:
		return
	var before := [level, match_lives]
	super._adjust(direction)
	if [level, match_lives] != before:
		vote_changed.emit(level, match_lives)


func _activate() -> void:
	if row == ROW_START:
		_start_match()
	elif not is_ready:
		_adjust(1)


func _start_match() -> void:
	ui_accepted.emit()
	is_ready = not is_ready
	if is_ready:
		row = ROW_START
	ready_changed.emit(is_ready)
	_refresh()


## How many seats back `value`. This machine's own vote is read locally because
## the room's echo of it may still be in flight.
func _votes_for(values: Array, value: int, mine: int) -> int:
	var total := 0
	for i in player_count():
		var vote: int = mine if i == local_slot else (int(values[i]) if i < values.size() else -1)
		if vote == value:
			total += 1
	return total


func _owner_text(index: int) -> String:
	var vote_level: int = level if index == local_slot \
		else (int(level_votes[index]) if index < level_votes.size() else -1)
	var vote_lives: int = match_lives if index == local_slot \
		else (int(lives_votes[index]) if index < lives_votes.size() else 5)
	var arena := "—" if vote_level < 0 else str(Levels.build(posmod(vote_level, Levels.count()))["name"])
	var seat_is_ready: bool = is_ready if index == local_slot \
		else (index < seat_ready.size() and bool(seat_ready[index]))
	return "%s · %d%s" % [arena, vote_lives, " · READY" if seat_is_ready else ""]


func _waiting_count() -> int:
	var waiting := 0
	for i in player_count():
		var seat_is_ready: bool = is_ready if i == local_slot else (i < seat_ready.size() and bool(seat_ready[i]))
		if not seat_is_ready:
			waiting += 1
	return waiting


func _refresh() -> void:
	super._refresh()
	var count := player_count()
	_write("breadcrumb", "// ONLINE  ·  VOTE THE RULES")
	_write("tally", "%d PLAYERS VOTING" % count)
	_write("rule_label_1", "ARENA VOTE")
	_write("rule_label_2", "MATCH LENGTH VOTE")
	_write("rule_note_0", "ONLINE MATCHES ARE EVERY FIGHTER FOR THEMSELVES")
	var arena_votes := _votes_for(level_votes, level, level)
	_write("rule_note_1", "%d OF %d  ·  %d OF %d VOTES  ·  TIES PICK AT RANDOM" % [
		level + 1, Levels.count(), arena_votes, count])
	var length_votes := _votes_for(lives_votes, match_lives, match_lives)
	_write("rule_note_2", "%d OF %d VOTES" % [length_votes, count])
	_write("lineup_kicker", "VOTES")
	for i in count:
		_write("lineup_tag_%d" % i, "YOU" if i == local_slot else OnlineLobby.seat_tag(i, seat_names))
	_write("back", "‹  BACK TO FIGHTER")
	var waiting := _waiting_count()
	if not is_ready:
		_write("start", "READY")
	elif waiting > 0:
		_write("start", "READY  ·  WAITING FOR %d" % waiting)
	else:
		_write("start", "STARTING…")
	_write("hint", "↑ / ↓  RULE   ·   ← / →  CHANGE VOTE   ·   ENTER  READY   ·   ESC  BACK")
	_art.model["rule_live_0"] = false
	_art.model["rule_live_1"] = not is_ready
	_art.model["rule_live_2"] = not is_ready
	_art.queue_redraw()
