extends RefCounted
class_name MatchReplay

## The end-of-match replay, split out of GameManager: it records one visual
## snapshot per execution tick and plays the retained history back on the
## result screen. GameManager owns one instance as `_replay`; `gm` is that
## GameManager.

var gm

## Visual snapshots of execution ticks. Replaying snapshots instead of running
## the simulation again keeps the online result immutable and includes every
## persistent knife and damaged platform without re-triggering game rules.
var _replay_frames: Array[Dictionary] = []
var _replay_terminal_frame: Dictionary = {}
var _replay_frame_index: int = 0
var _replay_accum: float = 0.0
const REPLAY_COMPACTION_SLACK_SECONDS := 2.0


func _init(owner) -> void:
	gm = owner


## Store the drawn state after each simulation tick. No planning frame reaches
## this method, which is what makes the finished replay one continuous burst.
func _capture_replay_frame() -> void:
	if gm.state != Phase.EXECUTING and gm.state != Phase.GAME_OVER:
		return
	var player_frames: Array[Dictionary] = []
	for p: Player in gm.players:
		player_frames.append({
			"position": p.position,
			"vel": p.vel,
			"on_ground": p.on_ground,
			"air_jumps_left": p.air_jumps_left,
			"drop_ticks": p.drop_ticks,
			"drop_from_y": p.drop_from_y,
			"alive": p.alive,
			"facing": p.facing,
			"invuln_turns": p.invuln_turns,
			"aim_angle": p.plan.aim_angle,
			"power": p.plan.power,
			"anim_time": p._anim_time,
		})

	var arrow_frames: Array[Dictionary] = []
	for a: Knife in gm.arrows:
		arrow_frames.append({
			"network_id": a.network_id,
			"shooter": a.shooter,
			"volley": a.volley,
			"position": a.position,
			"prev_pos": a.prev_pos,
			"vel": a.vel,
			"rotation": a.rotation,
			"color": a.color,
			"age_ticks": a.age_ticks,
			"clashed": a.clashed,
			"spin": a.spin,
			"clash_count": a.clash_count,
			"boost_count": a.boost_count,
			"ricochet_count": a.ricochet_count,
			"trail": a.trail.duplicate(),
		})

	var hazard_frames: Array[Dictionary] = []
	for h: Hazard in gm.hazards:
		hazard_frames.append({
			"position": h.position,
			"charged": h.charged,
			"windows_left": h.windows_left,
			"flash": h.flash,
		})

	_replay_frames.append({
		"turn": gm.turn,
		"score": gm.score.duplicate(),
		"players": player_frames,
		"arrows": arrow_frames,
		"hazards": hazard_frames,
		"world_tick": gm.world_tick,
		"platforms": gm.platforms.duplicate(true),
		"super_meter": gm.super_meter.duplicate(),
		"super_armed": gm.super_armed.duplicate(),
		"core_position": gm.core_position,
		"core_announced": gm.core_announced,
		"core_active": gm.core_active,
		"core_turns_left": gm.core_turns_left,
		"core_time": gm._temporal_core._time if gm._temporal_core != null else 0.0,
		"effects": gm._effects._fx.duplicate(true) if gm._effects != null else [],
	})
	_trim_replay_history()


func replay_frame_capacity() -> int:
	return maxi(1, int(ceil(gm.replay_history_seconds * float(Engine.physics_ticks_per_second))))


## Compact in batches rather than shifting a large Array every simulation tick.
## The small slack is still a hard, predictable upper bound during a match; a
## replay request forces the exact configured limit before playback begins.
func _trim_replay_history(force: bool = false) -> void:
	var capacity := replay_frame_capacity()
	var slack := maxi(1, int(ceil(REPLAY_COMPACTION_SLACK_SECONDS \
		* float(Engine.physics_ticks_per_second))))
	if _replay_frames.size() <= capacity \
			or (not force and _replay_frames.size() <= capacity + slack):
		return
	var compacted: Array[Dictionary] = []
	compacted.assign(_replay_frames.slice(_replay_frames.size() - capacity))
	_replay_frames = compacted


func _start_match_replay() -> void:
	if gm.state != Phase.GAME_OVER or _replay_frames.is_empty():
		return
	_trim_replay_history(true)
	_replay_terminal_frame = _replay_frames.back().duplicate(true)
	_replay_frame_index = 0
	_replay_accum = 0.0
	gm.state = Phase.REPLAY
	if gm._super_freeze != null:
		gm._cancel_super_cutin()
	_apply_replay_frame(_replay_frames[0])
	gm.banner_time = 0.0
	gm._preview.queue_redraw()
	gm._ui.refresh()


func _tick_match_replay(delta: float) -> void:
	_replay_accum += delta * maxf(gm.replay_speed, 0.01)
	var frame_time: float = gm.tick_dt()
	while _replay_accum >= frame_time:
		_replay_accum -= frame_time
		_replay_frame_index += 1
		if _replay_frame_index >= _replay_frames.size():
			_finish_match_replay()
			return
		_apply_replay_frame(_replay_frames[_replay_frame_index])


func _apply_replay_frame(frame: Dictionary) -> void:
	gm.turn = int(frame["turn"])
	var frame_score: Array = frame["score"]
	var frame_meter: Array = frame["super_meter"]
	var frame_armed: Array = frame["super_armed"]
	for i in gm.players.size():
		gm.score[i] = int(frame_score[i])
		gm.super_meter[i] = float(frame_meter[i])
		gm.super_armed[i] = bool(frame_armed[i])
		var p: Player = gm.players[i]
		var data: Dictionary = frame["players"][i]
		p.position = data["position"]
		p.vel = data["vel"]
		p.on_ground = bool(data["on_ground"])
		p.air_jumps_left = int(data.get("air_jumps_left", gm.air_jumps_for(i)))
		p.drop_ticks = int(data.get("drop_ticks", 0))
		p.drop_from_y = float(data.get("drop_from_y", 0.0))
		p.alive = bool(data["alive"])
		p.facing = int(data["facing"])
		p.invuln_turns = int(data["invuln_turns"])
		p.plan.aim_angle = float(data["aim_angle"])
		p.plan.power = float(data["power"])
		p._anim_time = float(data["anim_time"])
		p.queue_redraw()

	var arrow_by_id: Dictionary = {}
	for child in gm._arrow_layer.get_children():
		if child is Knife:
			arrow_by_id[child.network_id] = child
			child.visible = false
	var frame_arrows: Array = []
	for data: Dictionary in frame["arrows"]:
		var id := int(data["network_id"])
		var a: Knife = arrow_by_id.get(id)
		if a == null:
			a = Knife.new()
			a.cfg = gm
			a.network_id = id
			gm._arrow_layer.add_child(a)
			arrow_by_id[id] = a
		a.visible = true
		a.shooter = int(data["shooter"])
		a.volley = int(data["volley"])
		a.position = data["position"]
		a.prev_pos = data["prev_pos"]
		a.vel = data["vel"]
		a.rotation = float(data["rotation"])
		a.color = data["color"]
		a.age_ticks = int(data["age_ticks"])
		a.clashed = bool(data["clashed"])
		a.spin = float(data["spin"])
		a.clash_count = int(data["clash_count"])
		a.boost_count = int(data.get("boost_count", 0))
		a.ricochet_count = int(data.get("ricochet_count", 0))
		a.trail = PackedVector2Array(data["trail"])
		a.queue_redraw()
		frame_arrows.append(a)
	gm.arrows = frame_arrows

	gm.world_tick = int(frame["world_tick"])
	gm.platforms = frame["platforms"].duplicate(true)
	gm._rebuild_solids()
	gm._arena.setup(gm.platforms)
	var hazard_frames: Array = frame["hazards"]
	for i in mini(gm.hazards.size(), hazard_frames.size()):
		var h: Hazard = gm.hazards[i]
		var data: Dictionary = hazard_frames[i]
		h.position = data["position"]
		h.charged = bool(data["charged"])
		h.windows_left = int(data["windows_left"])
		h.flash = float(data["flash"])
		h.queue_redraw()
	gm.core_position = frame["core_position"]
	gm.core_announced = bool(frame["core_announced"])
	gm.core_active = bool(frame["core_active"])
	gm.core_turns_left = int(frame["core_turns_left"])
	gm._sync_temporal_core_visual()
	if gm._temporal_core != null:
		gm._temporal_core._time = float(frame["core_time"])
	if gm._effects != null:
		gm._effects._fx = frame["effects"].duplicate(true)
		gm._effects._remembered.clear()
		gm._effects.queue_redraw()


func _finish_match_replay() -> void:
	if not _replay_terminal_frame.is_empty():
		_apply_replay_frame(_replay_terminal_frame)
	for child in gm._arrow_layer.get_children():
		if child is Knife and not gm.arrows.has(child):
			child.queue_free()
	gm.state = Phase.GAME_OVER
	gm.banner_text = ("FATE DEFIED" if gm.fate_trial_succeeded else "FATE CLAIMED YOU") \
		if gm.fate_trial_mode else ("TEAM %s WINS THE MATCH" % gm.TEAM_NAMES[gm.winning_team] \
		if gm.team_mode and gm.winning_team >= 0 else \
		("%s WINS THE MATCH" % gm.player_title(gm.winner) if gm.winner >= 0 else "MATCH OVER"))
	gm.banner_color = (gm.PLAYER_COLORS[0] if gm.fate_trial_succeeded else gm.PLAYER_COLORS[1]) \
		if gm.fate_trial_mode else (gm.TEAM_COLORS[gm.winning_team] if gm.team_mode and gm.winning_team >= 0 else \
		(gm.PLAYER_COLORS[gm.winner] if gm.winner >= 0 else Color.WHITE)
		)
	gm.banner_time = gm.banner_duration
	_replay_frame_index = 0
	_replay_accum = 0.0
