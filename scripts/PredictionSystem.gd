extends RefCounted
class_name PredictionSystem

## Produces previews from KNOWN information only:
##   - current world state
##   - existing projectile trajectories
##   - the asking player's own plan
##
## It never simulates the opponent's plan, and it never simulates player-vs-player
## or arrow-vs-player interaction. Previews answer "what will MY action probably
## do?", not "what will happen".


## Continues a player state forward with NO input, for `steps` ticks. This is
## the uncontrolled tail of the execution window: whatever happens after the
## stamina runs out. Returns { "path": PackedVector2Array, "end": Vector2 }.
static func coast(pos: Vector2, vel: Vector2, on_ground: bool, steps: int, cfg) -> Dictionary:
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	var path := PackedVector2Array()
	for i in steps:
		# no input at all, jump key included — this is the uncontrolled tail
		var st := Player.step_state(pos, vel, on_ground, 0, false, dt, cfg)
		pos = st[0]
		vel = st[1]
		on_ground = st[2]
		path.append(pos)
	return {"path": path, "end": pos}


## Predicts a projectile path, stopping early on terrain / world bounds.
## Returns { "path": PackedVector2Array, "blocked": bool }
static func predict_arrow(start_pos: Vector2, start_vel: Vector2, cfg, duration: float) -> Dictionary:
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	var steps: int = int(round(duration / dt))
	var pos: Vector2 = start_pos
	var vel: Vector2 = start_vel
	var path := PackedVector2Array()
	path.append(pos)

	for i in steps:
		var st := Arrow.step_state(pos, vel, dt, cfg)
		var next: Vector2 = st[0]
		vel = st[1]
		var raw: Vector2 = st[2]
		var blocked := false
		# tested unwrapped — the solid set carries seam copies for exactly this
		for r in cfg.solid_rects:
			if Arrow.seg_hits_rect(pos, raw, r):
				blocked = true
				break
		if blocked:
			return {"path": path, "blocked": true}
		pos = next
		path.append(pos)
		if not cfg.world_bounds.has_point(pos):
			return {"path": path, "blocked": false}

	return {"path": path, "blocked": false}
