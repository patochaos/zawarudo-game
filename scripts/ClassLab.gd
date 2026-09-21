extends RefCounted
class_name ClassLab

const ORDER := [Roster.DUELIST, Roster.DASHBLADE, Roster.SHOCK, Roster.CHAKRAM]
const COPY := ["TWIN DAGGERS / charge narrows spread", "LANCE / charge increases speed / pierces one fragile cover",
	"DELAYED SPLIT / charge sets fuse / carrier is harmless", "CORONA / charge sets range / fixed return / one active"]

static func start(gm, live: bool = false, first: int = Roster.CHAKRAM, second: int = Roster.DUELIST) -> void:
	if live:
		gm.start_real_time()
	else:
		gm._start_local_match(0, 2, [0, 0], {
			"roles": ["HUMAN", "AI"], "devices": [gm.KEYBOARD_DEVICE, gm.NO_DEVICE]})
	gm.class_lab = true
	gm.player_weapons[0] = first
	gm.player_weapons[1] = second
	configure_arena(gm)
	# A fresh mode already has empty projectile arrays and plans.
	for i in gm.players.size():
		gm.players[i].fighter_style = gm.player_weapons[i]
		gm.players[i].air_jumps_left = gm.air_jumps_for(i)
		gm._sync_fighter_visual(gm.players[i], i)
	gm._transition.visible = false
	gm._tuning.visible = false

static func handle_key(gm, key: int) -> bool:
	if key == KEY_ESCAPE:
		gm._open_menu()
		return true
	var first: int = gm.player_weapons[0]
	var second: int = gm.player_weapons[1]
	var live: bool = gm.real_time_mode
	if key >= KEY_1 and key <= KEY_4:
		first = ORDER[key - KEY_1]
	elif key >= KEY_5 and key <= KEY_8:
		second = ORDER[key - KEY_5]
	elif key == KEY_T:
		live = not live
	else:
		return false
	start(gm, live, first, second)
	return true

static func make_projectile(gm, weapon: int, origin: Vector2, direction: Vector2, power: float):
	var projectile := InterceptProjectile.new()
	projectile.cfg = gm
	projectile.setup(weapon, origin, direction, power)
	return projectile

static func spawn(gm, p) -> void:
	var weapon: int = gm.player_weapons[p.index]
	if weapon == Roster.DUELIST:
		gm._spawn_arrow(p)
		return
	if weapon == Roster.CHAKRAM:
		for old in gm.arrows:
			if old is InterceptProjectile and old.shooter == p.index and old.kind == weapon:
				return
	var projectile = make_projectile(gm, weapon, p.shoulder() + p.aim_dir() * 22, p.aim_dir(), p.plan.power)
	projectile.shooter = p.index
	projectile.color = p.color
	projectile.volley = gm._next_volley
	gm._next_volley += 1
	projectile.network_id = gm._next_arrow_id
	gm._next_arrow_id += 1
	gm._arrow_layer.add_child(projectile)
	gm.arrows.append(projectile)
	gm._sfx.play("knife_throw")

static func split(gm, carrier, survivors: Array) -> void:
	for angle in [-9.0, 9.0]:
		var dart := Arrow.new()
		dart.cfg = gm
		dart.shooter = carrier.shooter
		dart.color = carrier.color
		dart.volley = carrier.volley
		dart.network_id = gm._next_arrow_id
		gm._next_arrow_id += 1
		dart.position = carrier.position
		dart.prev_pos = carrier.position
		dart.vel = carrier.direction.rotated(deg_to_rad(angle)) * 540.0
		dart.rotation = dart.vel.angle()
		gm._arrow_layer.add_child(dart)
		survivors.append(dart)

## Shared preview/CPU forecast. The lab uses static Crosshair Court geometry.
static func forecast(projectile, ticks: int) -> Array:
	var copy = projectile.copy_for_prediction()
	var path := PackedVector2Array([copy.position])
	var paths: Array = []
	for tick in ticks:
		var result: Dictionary = copy.sim_step(copy.cfg.tick_dt(), [])
		path.append(copy.position)
		if result.burst:
			for angle in [-9.0, 9.0]:
				var prediction := PredictionSystem.predict_arrow(copy.position,
					copy.direction.rotated(deg_to_rad(angle)) * 540.0,
					copy.cfg, (ticks - tick - 1) * copy.cfg.tick_dt())
				paths.append({"path": prediction.path, "offset": tick + 1, "lethal": true})
		if not result.alive:
			break
	paths.push_front({"path": path, "offset": 0, "lethal": copy.kind != Roster.SHOCK})
	copy.free()
	return paths


static func configure_arena(gm) -> void:
	# One fragile pillar provides a repeatable lance/cover comparison.
	for platform in gm.platforms:
		var rect: Rect2 = platform["rect"]
		if rect.has_point(Vector2(640, 350)):
			platform["hp"] = 1
	gm._rebuild_solids()
	gm._arena.setup(gm.platforms)
