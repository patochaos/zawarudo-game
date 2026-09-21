extends SceneTree

const MAIN_SCENE := preload("res://scenes/Main.tscn")
var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await process_frame
	game._sfx.muted = true
	game.set_process(false)
	game.set_physics_process(false)
	for arena in Levels.count():
		game.online_mode = false
		game._on_roster_confirmed({
			"mode": MatchSetupLayer.BattleMode.VS,
			"player_count": 4,
			"roles": ["HUMAN", "HUMAN", "HUMAN", "HUMAN"],
			"devices": [-2, -1, -1, -1],
			"teams": [-1, -1, -1, -1],
			"weapons": [0, 0, 0, 0],
			"level": arena,
			"match_lives": 5,
		})
		var label: String = game.level_name
		_check(game.players.size() == 4, label + ": four active fighters")
		_check(game.platforms.size() == Levels.build(arena, 4)["platforms"].size(),
			label + ": live game loads crowd geometry")
		_check(not game._camera.enabled, label + ": complete arena stays visible")
		# Respawn selection can run at any simulation tick, so every candidate
		# must stay clear throughout moving-platform cycles, not only at tick 0.
		for tick in range(0, 2520, 12):
			for socket in game.respawn_points:
				var body := Rect2(socket - Player.HALF, Player.SIZE)
				for platform in game.platforms:
					if not platform.has("motion"):
						continue
					var posed: Rect2 = platform["rect"]
					posed.position = platform["home"] + Mover.offset(platform["motion"], tick)
					_check(not body.intersects(posed),
						label + ": moving geometry never sweeps through a respawn")
		# A simultaneous wipe must recover four different, collision-free sockets,
		# even after all destructible cover has disappeared.
		for platform in game.platforms:
			if int(platform["hp"]) > 0:
				platform["hp"] = 0
		for player in game.players:
			player.alive = false
		var occupied := {}
		for slot in 4:
			game._respawn(slot)
			var player = game.players[slot]
			_check(not occupied.has(player.position), label + ": respawns do not overlap")
			occupied[player.position] = true
			var body := Rect2(player.position - Player.HALF, Player.SIZE)
			for platform in game.platforms:
				if int(platform["hp"]) != 0:
					_check(not body.intersects(platform["rect"]), label + ": clear respawn body")
		# Every online seat gets its own instructions and sees every rival; all
		# four score rows remain available regardless of who owns this client.
		game.online_mode = true
		game.online_room = "AUDIT"
		for slot in 4:
			game.online_player = slot
			game._ui.refresh()
			_check("YOU P%d" % (slot + 1) in game._ui._hint_p1.text,
				label + ": local online seat is identified")
			for rival in 4:
				if rival != slot:
					_check("P%d" % (rival + 1) in game._ui._hint_p2.text,
						label + ": every remote rival is listed")
				_check(game._ui._pips[rival][0].visible, label + ": every score is visible")
		game.online_peer_lost = true
		game._ui.refresh()
		_check("RECONNECT" in game._ui._hint_p2.text and not "CLAIM" in game._ui._hint_p2.text,
			label + ": one missing player cannot award a four-player match")
		game.online_peer_lost = false
		game.online_mode = false
		# Every seat can score and finish the match, including P3/P4.
		for shooter in 4:
			game.score.fill(0)
			game.score[shooter] = game.hits_to_win - 1
			game.state = Phase.EXECUTING
			var victim := (shooter + 1) % 4
			game.players[victim].alive = true
			game._on_player_hit(victim, game.players[victim].position, shooter)
			_check(game.state == Phase.GAME_OVER and game.winner == shooter,
				label + ": every seat can win through scoring")
	game.queue_free()
	await process_frame
	if _failures == 0:
		print("Four-player arenas and online HUD: all tests passed")
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
