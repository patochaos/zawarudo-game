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


## Predicts a projectile path, stopping early on terrain / world bounds.
## Returns { "path": PackedVector2Array, "blocked": bool }
## `clashed` selects the heavier debris gravity, so the previewed path of an
## already-deflected knife matches the one it will actually fall along.
static func predict_arrow(start_pos: Vector2, start_vel: Vector2, cfg, duration: float,
		start_tick: int = -1, clashed: bool = false, initial_ricochets: int = 0) -> Dictionary:
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	var steps: int = int(round(duration / dt))
	var pos: Vector2 = start_pos
	var vel: Vector2 = start_vel
	var path := PackedVector2Array()
	var ricochets := initial_ricochets
	path.append(pos)

	for i in steps:
		var st := Knife.step_state(pos, vel, dt, cfg, clashed)
		var next: Vector2 = st[0]
		vel = st[1]
		var raw: Vector2 = st[2]
		# Tested unwrapped, since colliders carry seam copies. Material is retained so
		# the preview banks from HARD exactly where runtime does, while breakable
		# cover remains a terminal impact.
		var at_tick: int = -1 if start_tick < 0 else start_tick + i + 1
		var first_hit: Array = []
		var first_platform: Dictionary = {}
		for platform: Dictionary in cfg.platform_colliders_at(at_tick):
			var impact := Knife.segment_rect_impact(pos, raw, platform["rect"])
			if not impact.is_empty() and (first_hit.is_empty() or impact[0] < first_hit[0]):
				first_hit = impact
				first_platform = platform
		if not first_hit.is_empty():
			var normal: Vector2 = first_hit[1]
			var impact_at: Vector2 = pos.lerp(raw, first_hit[0])
			if Knife.can_ricochet_velocity(vel, normal, first_platform, cfg, ricochets):
				vel = vel.bounce(normal) * cfg.knife_ricochet_retention
				ricochets += 1
				pos = impact_at + normal * 2.0
				path.append(pos)
				continue
			path.append(impact_at)
			return {"path": path, "blocked": true}
		pos = next
		path.append(pos)
		if not cfg.world_bounds.has_point(pos):
			return {"path": path, "blocked": false}

	return {"path": path, "blocked": false}
