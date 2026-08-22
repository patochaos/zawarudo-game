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
## `start_tick` is the absolute world tick the tail begins at, so a coasting body
## meets moving geometry where it will actually be. -1 freezes the world.
## `drop_ticks` carries an in-progress drop-through into the tail, so a ghost
## that steps off a ledge on its last piloted tick keeps falling through it
## instead of landing back on top a frame later.
static func coast(pos: Vector2, vel: Vector2, on_ground: bool, steps: int, cfg,
		start_tick: int = -1, drop_ticks: int = 0, drop_from_y: float = 0.0) -> Dictionary:
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	var path := PackedVector2Array()
	for i in steps:
		# no input at all, jump key included — this is the uncontrolled tail
		var drop_result := Player.apply_drop(pos.y, vel, on_ground, drop_ticks, drop_from_y, false)
		vel = drop_result[0]
		on_ground = drop_result[1]
		drop_ticks = drop_result[2]
		var st := Player.step_state(pos, vel, on_ground, 0, false, dt, cfg,
			-1 if start_tick < 0 else start_tick + i, drop_ticks, drop_from_y)
		pos = st[0]
		vel = st[1]
		on_ground = st[2]
		path.append(pos)
	return {"path": path, "end": pos}


## Predicts The Pulse's lance, which is ballistic and also expires at a
## charge-dependent distance. Stops on terrain, on that distance, or at the world
## edge. Returns { "path": PackedVector2Array, "blocked": bool }.
static func predict_plasma(start_pos: Vector2, start_vel: Vector2, cfg,
		max_distance: float, start_tick: int = -1) -> Dictionary:
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	var pos: Vector2 = start_pos
	var vel: Vector2 = start_vel
	var travelled: float = 0.0
	var path := PackedVector2Array()
	path.append(pos)

	for i in ShockPlasma.MAX_PREDICT_TICKS:
		if travelled >= max_distance:
			return {"path": path, "blocked": false}
		var st := ShockPlasma.step_state(pos, vel, dt, cfg)
		var raw: Vector2 = st[0]
		vel = st[1]
		var step := pos.distance_to(raw)
		# The bolt dies mid-step when its budget runs out, exactly as it does live.
		if travelled + step > max_distance:
			path.append(pos.lerp(raw, (max_distance - travelled) / maxf(step, 0.000001)))
			return {"path": path, "blocked": false}
		var at_tick: int = -1 if start_tick < 0 else start_tick + i + 1
		for platform: Dictionary in cfg.platform_colliders_at(at_tick):
			var impact := Arrow.segment_rect_impact(pos, raw,
				platform["rect"].grow(ShockPlasma.COLLISION_RADIUS))
			if not impact.is_empty():
				path.append(pos.lerp(raw, float(impact[0])))
				return {"path": path, "blocked": true}
		travelled += step
		pos = cfg.wrap_point(raw)
		path.append(pos)
		if not cfg.world_bounds.has_point(pos):
			return {"path": path, "blocked": false}
	return {"path": path, "blocked": false}


## Predicts a projectile path, stopping early on terrain / world bounds.
## Returns { "path": PackedVector2Array, "blocked": bool }
## `clashed` selects the heavier debris gravity, so the previewed path of an
## already-deflected knife matches the one it will actually fall along.
static func predict_arrow(start_pos: Vector2, start_vel: Vector2, cfg, duration: float,
		start_tick: int = -1, clashed: bool = false) -> Dictionary:
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	var steps: int = int(round(duration / dt))
	var pos: Vector2 = start_pos
	var vel: Vector2 = start_vel
	var path := PackedVector2Array()
	var ricochets := 0
	path.append(pos)

	for i in steps:
		var st := Arrow.step_state(pos, vel, dt, cfg, clashed)
		var next: Vector2 = st[0]
		vel = st[1]
		var raw: Vector2 = st[2]
		# Tested unwrapped — colliders carry seam copies. Material is retained so
		# the preview banks from HARD exactly where runtime does, while breakable
		# cover remains a terminal impact.
		var at_tick: int = -1 if start_tick < 0 else start_tick + i + 1
		var first_hit: Array = []
		var first_platform: Dictionary = {}
		for platform: Dictionary in cfg.platform_colliders_at(at_tick):
			var impact := Arrow.segment_rect_impact(pos, raw, platform["rect"])
			if not impact.is_empty() and (first_hit.is_empty() or impact[0] < first_hit[0]):
				first_hit = impact
				first_platform = platform
		if not first_hit.is_empty():
			var normal: Vector2 = first_hit[1]
			var impact_at: Vector2 = pos.lerp(raw, first_hit[0])
			path.append(impact_at)
			if Arrow.can_ricochet_velocity(vel, normal, first_platform, cfg, ricochets):
				vel = vel.bounce(normal) * cfg.knife_ricochet_retention
				ricochets += 1
				pos = impact_at + normal * 2.0
				path.append(pos)
				continue
			return {"path": path, "blocked": true}
		pos = next
		path.append(pos)
		if not cfg.world_bounds.has_point(pos):
			return {"path": path, "blocked": false}

	return {"path": path, "blocked": false}
