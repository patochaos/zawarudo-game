extends RefCounted
class_name Levels

## Arena layouts. Each returns a fresh copy so a restart always gets undamaged
## platforms.
##
## `hp = -1` is indestructible (ground, walls, ceilings); everything else chips
## away as arrows strike it. Breakable cover is deliberately kept OUT of the
## lobbing corridor between the spawns, so destroying a platform opens new
## firing lines rather than closing the match down.
##
## WRAPPING (TowerFall style)
##   wrap_x — leaving one side re-enters the other. Side walls are omitted.
##   wrap_y — falling off the bottom re-enters at the top, inside the band
##            [WRAP_TOP, ARENA_H]. The HUD owns the screen above WRAP_TOP, so a
##            wrap-y level MUST have a solid ceiling everywhere except a gap in
##            the middle third, and its floor gap must sit inside that ceiling
##            gap. Then re-entry always lands in open, un-occluded space.
##
## MOVING GEOMETRY
##   A platform may carry a `motion` dictionary (see Mover.gd). It then sweeps
##   between its authored position and `home + axis * travel`, driven purely by
##   the absolute simulation tick — so it is frozen during planning and moves
##   only while time is running. Everything that reads geometry (collision, the
##   ghost preview, the AI, the lockstep digest) projects it from the same
##   function, so a moving ledge is a thing the player can plan around rather
##   than an ambush.
##
##   A moving piece must remain legal at BOTH ends of its sweep — the layout
##   test checks every constraint at each extreme.
##
## HAZARDS
##   `hazards` lists pulse orbs (see Hazard.gd). An orb drifts on its own rail
##   and, when a knife strikes it, pushes fighters and relaunches knives radially
##   at full throw speed before going dark for a couple of windows. Place them where being pushed is
##   interesting — over a gap, beside a seam, under the crown — not where a push
##   simply ends the round.
##
## Design constraints for a new level:
##   * playable band is roughly y 262..620 on non-wrapping levels
##   * a jump clears 211px, so a step is reachable from a surface 211px below
##   * leave an arc that clears mid-field cover, or there is no direct shot

const ARENA_W := 1280.0
const ARENA_H := 720.0
## Vertical wrapping happens inside this band. Chosen so a body re-entering at
## the top has its head at y=192, clear of the lowest HUD text at y=186.
const WRAP_TOP := 216.0

const GROUND := {"rect": Rect2(0, 620, 1280, 100), "hp": -1}
const WALL_L := {"rect": Rect2(-60, -1400, 60, 2100), "hp": -1}
const WALL_R := {"rect": Rect2(1280, -1400, 60, 2100), "hp": -1}


static func count() -> int:
	return 7


static func build(index: int, player_count: int = 4) -> Dictionary:
	return _finish(_layout(index), clampi(player_count, 2, 4))


## A quiet room for learning the three basic verbs. The open horizontal seam
## lets the player test wrapping in either direction without enemies, hazards,
## moving pieces, or breakable geometry competing for attention.
static func build_tutorial() -> Dictionary:
	return _finish({
		"name": "TRAINING TUNNEL",
		"wrap_x": true,
		"spawns": [
			Vector2(220.0, 596.0), Vector2(1060.0, 596.0),
			Vector2(400.0, 446.0), Vector2(880.0, 446.0),
		],
		"respawn_points": [
			Vector2(140.0, 596.0), Vector2(420.0, 596.0),
			Vector2(860.0, 596.0), Vector2(1140.0, 596.0),
			Vector2(180.0, 476.0), Vector2(640.0, 396.0), Vector2(1100.0, 476.0),
		],
		"core_spawns": [],
		"hazards": [],
		"platforms": [
			{"rect": Rect2(80, 500, 250, 16), "hp": -1},
			{"rect": Rect2(510, 420, 260, 16), "hp": -1},
			{"rect": Rect2(950, 500, 250, 16), "hp": -1},
		],
	}, 2)


static func _layout(index: int) -> Dictionary:
	match posmod(index, count()):
		0: return _crosshair_court()
		1: return _endless_descent()
		2: return _pendulum()
		3: return _pulse_chamber()
		4: return _shattered_sanctum()
		5: return _foundry()
		_: return _collision_course()


static func _finish(lv: Dictionary, player_count: int) -> Dictionary:
	var plats: Array = []
	if not lv.get("skip_ground", false):
		plats.append(GROUND.duplicate())
	if not lv.get("wrap_x", false):
		plats.append(WALL_L.duplicate())
		plats.append(WALL_R.duplicate())
	for authored: Dictionary in lv["platforms"]:
		if int(authored.get("min_players", 2)) > player_count:
			continue
		var pf: Dictionary = authored.duplicate(true)
		pf.erase("min_players")
		plats.append(pf)
	for pf in plats:
		pf["max_hp"] = pf["hp"]
		# A mover is defined relative to where it was authored, so the home point
		# survives every later reposition.
		if pf.has("motion"):
			pf["home"] = pf["rect"].position
	lv["platforms"] = plats
	lv["wrap_x"] = lv.get("wrap_x", false)
	lv["wrap_y"] = lv.get("wrap_y", false)
	var active_hazards: Array = []
	for authored: Dictionary in lv.get("hazards", []):
		if int(authored.get("min_players", 2)) > player_count:
			continue
		var hazard: Dictionary = authored.duplicate(true)
		hazard.erase("min_players")
		active_hazards.append(hazard)
	lv["hazards"] = active_hazards
	lv["player_count"] = player_count
	return lv


static func wrap_label(lv: Dictionary) -> String:
	if lv["wrap_x"] and lv["wrap_y"]:
		return "WRAP ↔ ↕"
	if lv["wrap_x"]:
		return "WRAP ↔"
	if lv["wrap_y"]:
		return "WRAP ↕"
	return "WALLED"


# ------------------------------------------------------------ walled arenas --

## Thesis: learn the collision game before the arena starts moving.
##
## Every surface is permanent and every important firing lane has a simple,
## visible answer: shoot flat through the middle, arc over the centre mast, or
## use a side stair to change height. Extra fighters add small staging ledges,
## but never new rules, so this is the control case for the whole level set.
static func _crosshair_court() -> Dictionary:
	return {
		"name": "CROSSHAIR COURT",
		"feature": "BASIC // static cover makes knife collisions and future danger easy to read.",
		"spawns": [
			Vector2(220.0, 596.0), Vector2(1060.0, 596.0),
			Vector2(140.0, 296.0), Vector2(1140.0, 296.0),
		],
		"respawn_points": [
			Vector2(120.0, 596.0), Vector2(400.0, 596.0), Vector2(640.0, 596.0),
			Vector2(880.0, 596.0), Vector2(1160.0, 596.0),
			Vector2(120.0, 296.0), Vector2(1160.0, 296.0),
			Vector2(180.0, 476.0), Vector2(1100.0, 476.0),
			Vector2(360.0, 386.0), Vector2(920.0, 386.0),
			Vector2(550.0, 226.0), Vector2(730.0, 226.0),
		],
		"core_spawns": [Vector2(300.0, 460.0), Vector2(640.0, 555.0), Vector2(980.0, 460.0)],
		"platforms": [
			# Visible side architecture doubles as permanent P3/P4 spawn support.
			{"rect": Rect2(0, 320, 240, 16), "hp": -1},
			{"rect": Rect2(1040, 320, 240, 16), "hp": -1},
			# Simple two-step climbs keep every height reachable without a mover.
			{"rect": Rect2(70, 500, 230, 16), "hp": -1},
			{"rect": Rect2(980, 500, 230, 16), "hp": -1},
			{"rect": Rect2(280, 410, 190, 16), "hp": -1},
			{"rect": Rect2(810, 410, 190, 16), "hp": -1},
			# The mast blocks the free upper-corner volley but leaves high arcs open.
			{"rect": Rect2(616, 250, 48, 180), "hp": -1},
			{"rect": Rect2(500, 250, 280, 16), "hp": -1},
			{"rect": Rect2(520, 515, 240, 16), "hp": -1},
			# Crowd-only shelves add landing choices as the number of threats grows.
			{"rect": Rect2(345, 550, 130, 14), "hp": -1, "min_players": 3},
			{"rect": Rect2(805, 550, 130, 14), "hp": -1, "min_players": 4},
		],
		"hazards": [],
	}

## A four-corner sanctum built around forced vertical circulation. P1/P2 enter
## from the floor while P3/P4 own permanent upper balconies. Three short side
## tiers connect those openings; the warm middle steps are destructible, but a
## permanent route always survives through each outer gallery.
static func _shattered_sanctum() -> Dictionary:
	return {
		"name": "SHATTERED SANCTUM",
		"feature": "BREAKABLE // destroy cover now to author the firing lanes of later turns.",
		"wrap_x": true,
		"spawns": [
			Vector2(210.0, 596.0), Vector2(1070.0, 596.0),
			Vector2(135.0, 296.0), Vector2(1145.0, 296.0),
		],
		"respawn_points": [
			Vector2(180.0, 596.0), Vector2(400.0, 596.0),
			Vector2(880.0, 596.0), Vector2(1100.0, 596.0),
			Vector2(100.0, 446.0), Vector2(1180.0, 446.0),
			Vector2(120.0, 296.0), Vector2(1160.0, 296.0),
			Vector2(370.0, 396.0), Vector2(910.0, 396.0),
			Vector2(580.0, 261.0), Vector2(700.0, 261.0),
		],
		"core_spawns": [Vector2(125.0, 420.0), Vector2(640.0, 345.0), Vector2(1155.0, 420.0)],
		"platforms": [
			# Hard lower gates close the seam near the ground. Above y=370 the
			# horizontal seam is open to both fighters and knives.
			{"rect": Rect2(0, 370, 54, 250), "hp": -1},
			{"rect": Rect2(1226, 370, 54, 250), "hp": -1},
			# Permanent side galleries make both former dead-end alcoves useful.
			{"rect": Rect2(0, 470, 180, 18), "hp": -1},
			{"rect": Rect2(1100, 470, 180, 18), "hp": -1},
			# P3/P4 spawn here. Spawn support is permanent; the crown across the
			# middle blocks a free opening shot between the upper corners.
			{"rect": Rect2(40, 320, 190, 16), "hp": -1},
			{"rect": Rect2(1050, 320, 190, 16), "hp": -1},
			# Breakable middle stairs add a second route between the upper spawn
			# balconies and the permanent inner terraces.
			{"rect": Rect2(220, 370, 90, 14), "hp": 2},
			{"rect": Rect2(970, 370, 90, 14), "hp": 2},
			# A permanent inner pair keeps a route alive after every breakable falls.
			{"rect": Rect2(290, 420, 160, 16), "hp": -1},
			{"rect": Rect2(830, 420, 160, 16), "hp": -1},
			# Low sacrificial steps reward breaking the floor under an opponent.
			{"rect": Rect2(270, 540, 150, 16), "hp": 2},
			{"rect": Rect2(860, 540, 150, 16), "hp": 2},
			# The shrine blocks the direct spawn-to-spawn firing line permanently.
			{"rect": Rect2(610, 390, 60, 230), "hp": -1},
			# Breakable shoulders create close-range positions around the shrine.
			{"rect": Rect2(475, 500, 80, 16), "hp": 3},
			{"rect": Rect2(725, 500, 80, 16), "hp": 3},
			# The solid crown is the stable high objective; its satellites are not.
			{"rect": Rect2(535, 285, 210, 16), "hp": -1},
			{"rect": Rect2(290, 270, 160, 16), "hp": 2},
			{"rect": Rect2(830, 270, 160, 16), "hp": 2},
			{"rect": Rect2(70, 550, 110, 14), "hp": 2, "min_players": 3},
			{"rect": Rect2(1100, 550, 110, 14), "hp": 2, "min_players": 4},
		],
	}

## A four-corner vertical loop over a hole in the world. P1/P2 start on the
## split floor and P3/P4 on high permanent perches.
## Side islands make the full climb indestructible; inner breakable steps offer
## faster diagonals. A hanging centre pillar splits the upper firing lane while
## leaving two broad vertical portals around it.
static func _endless_descent() -> Dictionary:
	return {
		"name": "ENDLESS DESCENT",
		"feature": "TUNNELS // threats can arrive from left, right, above or below through four-way wrap.",
		"wrap_x": true,
		"wrap_y": true,
		"skip_ground": true,
		# On the solid parts of the floor, either side of the hole.
		"spawns": [
			Vector2(280.0, 596.0), Vector2(1000.0, 596.0),
			Vector2(160.0, 276.0), Vector2(1120.0, 276.0),
		],
		"respawn_points": [
			Vector2(120.0, 596.0), Vector2(340.0, 596.0),
			Vector2(940.0, 596.0), Vector2(1160.0, 596.0),
			Vector2(130.0, 276.0), Vector2(1150.0, 276.0),
			Vector2(240.0, 446.0), Vector2(360.0, 446.0),
			Vector2(920.0, 446.0), Vector2(1040.0, 446.0),
		],
		"core_spawns": [Vector2(290.0, 440.0), Vector2(640.0, 510.0), Vector2(990.0, 440.0)],
		"platforms": [
			{"rect": Rect2(0, 216, 360, 16), "hp": -1},      # ceiling, gap 360..920
			{"rect": Rect2(920, 216, 360, 16), "hp": -1},
			# Safe high-corner spawn perches, with enough headroom below the ceiling.
			{"rect": Rect2(70, 300, 210, 16), "hp": -1},
			{"rect": Rect2(1000, 300, 210, 16), "hp": -1},
			{"rect": Rect2(0, 620, 430, 70), "hp": -1},      # floor, gap 430..850
			{"rect": Rect2(850, 620, 430, 70), "hp": -1},
			{"rect": Rect2(0, 330, 70, 170), "hp": -1},      # horizontal portal frames
			{"rect": Rect2(1210, 330, 70, 170), "hp": -1},
			# Permanent side islands are the guaranteed lower-to-upper route.
			{"rect": Rect2(180, 470, 220, 16), "hp": -1},
			{"rect": Rect2(880, 470, 220, 16), "hp": -1},
			# Faster inner stairs can be destroyed to reopen diagonal knife lanes.
			{"rect": Rect2(300, 385, 170, 16), "hp": 2},
			{"rect": Rect2(810, 385, 170, 16), "hp": 2},
			# Anchored to the ceiling and touching the centre beam: it blocks the
			# P3/P4 opening line but leaves a vertical portal on either side.
			{"rect": Rect2(620, 216, 40, 119), "hp": -1},
			{"rect": Rect2(540, 335, 200, 16), "hp": 3},
			{"rect": Rect2(575, 545, 130, 14), "hp": 2},     # the tempting perch
			{"rect": Rect2(445, 485, 110, 14), "hp": 2, "min_players": 3},
			{"rect": Rect2(725, 485, 110, 14), "hp": 2, "min_players": 4},
		],
	}


# ----------------------------------------------------------- kinetic arenas --

## Thesis: the ledge you are aiming at is not where it will be.
##
## Two wide lifts rise and fall in opposite phase on either side of a permanent
## spine, so the mid-field alternates between one high floor and one low one
## every two and a half seconds. Everything else is static and permanent enough
## to plan from: the lifts change what a route COSTS, not whether one exists.
##
## No hazards compete for attention here. The level teaches one timing read:
## where each lift will be when a player or persistent knife reaches it.
static func _pendulum() -> Dictionary:
	return {
		"name": "PENDULUM",
		"feature": "MOVING PLATFORMS // plan against two readable lifts that trade high ground.",
		"spawns": [
			Vector2(250.0, 596.0), Vector2(1030.0, 596.0),
			Vector2(150.0, 296.0), Vector2(1130.0, 296.0),
		],
		"respawn_points": [
			Vector2(160.0, 596.0), Vector2(420.0, 596.0), Vector2(640.0, 596.0),
			Vector2(860.0, 596.0), Vector2(1120.0, 596.0),
			Vector2(110.0, 296.0), Vector2(1170.0, 296.0),
			Vector2(120.0, 446.0), Vector2(1160.0, 446.0),
			Vector2(600.0, 476.0), Vector2(680.0, 476.0),
		],
		"core_spawns": [Vector2(390.0, 250.0), Vector2(640.0, 568.0), Vector2(890.0, 250.0)],
		"platforms": [
			# Upper balconies: P3/P4 spawn support and the arena's side facade.
			{"rect": Rect2(0, 320, 220, 16), "hp": -1},
			{"rect": Rect2(1060, 320, 220, 16), "hp": -1},
			# The spine denies a free upper-corner exchange and gives the lifts
			# something fixed to be read against.
			{"rect": Rect2(616, 232, 48, 200), "hp": -1},
			# THE LIFTS. Opposite phase, so the field is never symmetric and the
			# two halves are never equally reachable at the same moment.
			{
				"rect": Rect2(250, 300, 180, 16), "hp": -1,
				"motion": {"axis": Vector2.DOWN, "travel": 190.0, "period": 300, "phase": 0.0},
			},
			{
				"rect": Rect2(850, 300, 180, 16), "hp": -1,
				"motion": {"axis": Vector2.DOWN, "travel": 190.0, "period": 300, "phase": 0.5},
			},
			# Permanent galleries: the climb that works no matter where a lift is.
			{"rect": Rect2(45, 470, 175, 16), "hp": -1},
			{"rect": Rect2(1060, 470, 175, 16), "hp": -1},
			# A permanent centre landing keeps the low middle worth contesting.
			{"rect": Rect2(545, 500, 190, 16), "hp": -1},
			# Breakable shoulders tight against the spine — destroying one opens a
			# lane the lifts cannot close again.
			{"rect": Rect2(480, 380, 110, 14), "hp": 2},
			{"rect": Rect2(690, 380, 110, 14), "hp": 2},
			# Low sacrificial steps, out of the lift corridors.
			{"rect": Rect2(330, 545, 150, 14), "hp": 2},
			{"rect": Rect2(800, 545, 150, 14), "hp": 2},
			{"rect": Rect2(485, 565, 105, 14), "hp": 2, "min_players": 3},
			{"rect": Rect2(690, 565, 105, 14), "hp": 2, "min_players": 4},
		],
		"hazards": [],
	}


## Thesis: a hazard is a temporary promise, not ambient random damage.
##
## The three pulse orbs advertise their exact blast radius. A knife can spend a
## charged orb to bend fighters and persistent knives away from their expected
## futures; the dark recharge pips then guarantee a quiet interval. More crowded
## matches add flank landings and a matching flank orb so available safe space
## grows with the number of simultaneous plans.
static func _pulse_chamber() -> Dictionary:
	return {
		"name": "PULSE CHAMBER",
		"feature": "TEMPORARY HAZARDS // shoot charged orbs to bend danger, then exploit their visible cooldown.",
		"wrap_x": true,
		"spawns": [
			Vector2(230.0, 596.0), Vector2(1050.0, 596.0),
			Vector2(150.0, 286.0), Vector2(1130.0, 286.0),
		],
		"respawn_points": [
			Vector2(160.0, 596.0), Vector2(420.0, 596.0), Vector2(640.0, 596.0),
			Vector2(860.0, 596.0), Vector2(1120.0, 596.0),
			Vector2(110.0, 286.0), Vector2(1170.0, 286.0),
			Vector2(100.0, 456.0), Vector2(1180.0, 456.0),
			Vector2(330.0, 376.0), Vector2(950.0, 376.0),
			Vector2(580.0, 496.0), Vector2(700.0, 496.0),
		],
		"core_spawns": [Vector2(260.0, 450.0), Vector2(640.0, 575.0), Vector2(1020.0, 450.0)],
		"platforms": [
			{"rect": Rect2(0, 310, 230, 16), "hp": -1},
			{"rect": Rect2(1050, 310, 230, 16), "hp": -1},
			{"rect": Rect2(0, 480, 210, 16), "hp": -1},
			{"rect": Rect2(1070, 480, 210, 16), "hp": -1},
			{"rect": Rect2(250, 400, 190, 16), "hp": -1},
			{"rect": Rect2(840, 400, 190, 16), "hp": -1},
			# A thin centre baffle blocks the opening upper volley without hiding an orb.
			{"rect": Rect2(620, 230, 40, 130), "hp": -1},
			{"rect": Rect2(530, 350, 220, 16), "hp": -1},
			{"rect": Rect2(500, 520, 280, 16), "hp": -1},
			{"rect": Rect2(330, 545, 130, 14), "hp": 2, "min_players": 3},
			{"rect": Rect2(820, 545, 130, 14), "hp": 2, "min_players": 4},
		],
		"hazards": [
			{
				"home": Vector2(640.0, 455.0),
				"blast_radius": 175.0,
				"recharge_windows": 2,
			},
			{
				"home": Vector2(300.0, 335.0),
				"motion": {"axis": Vector2.RIGHT, "travel": 100.0, "period": 300, "phase": 0.0},
				"blast_radius": 155.0,
				"min_players": 3,
			},
			{
				"home": Vector2(980.0, 335.0),
				"motion": {"axis": Vector2.LEFT, "travel": 100.0, "period": 300, "phase": 0.0},
				"blast_radius": 155.0,
				"min_players": 4,
			},
		],
	}


## Thesis: the direct lane exists, but only half the time and only on one side.
##
## A single wide shutter slides the whole width of the mid-field, sealing the
## left half and then the right. A knife thrown across the open half arrives; a
## knife thrown at the shutter feeds the wall. Because the shutter is permanent
## it cannot be destroyed — it can only be waited out or gone around.
##
## Unlike the final arena, no pulse orb can rewrite the timing. The shutter's
## visible rail is the single clock both players are solving.
static func _foundry() -> Dictionary:
	return {
		"name": "FOUNDRY",
		"feature": "SHUTTER // one side of the direct shot opens while the other side closes.",
		"wrap_x": true,
		"spawns": [
			Vector2(240.0, 596.0), Vector2(1040.0, 596.0),
			Vector2(140.0, 276.0), Vector2(1140.0, 276.0),
		],
		"respawn_points": [
			Vector2(120.0, 596.0), Vector2(360.0, 596.0), Vector2(640.0, 596.0),
			Vector2(920.0, 596.0), Vector2(1160.0, 596.0),
			Vector2(100.0, 276.0), Vector2(1180.0, 276.0),
			Vector2(100.0, 446.0), Vector2(1180.0, 446.0),
		],
		"core_spawns": [Vector2(150.0, 350.0), Vector2(640.0, 560.0), Vector2(1130.0, 350.0)],
		"platforms": [
			# Upper perches, permanent, doubling as the seam-side architecture.
			{"rect": Rect2(0, 300, 210, 16), "hp": -1},
			{"rect": Rect2(1070, 300, 210, 16), "hp": -1},
			# The chimney blocks the upper-corner opening line and splits the top.
			{"rect": Rect2(600, 232, 56, 140), "hp": -1},
			# THE SHUTTER. One long horizontal sweep; whichever half it is over is
			# closed to a flat shot and open to an arc.
			{
				"rect": Rect2(240, 400, 300, 18), "hp": -1,
				"motion": {"axis": Vector2.RIGHT, "travel": 500.0, "period": 420, "phase": 0.0},
			},
			# Permanent galleries reach the perches without ever using the shutter.
			{"rect": Rect2(0, 470, 200, 16), "hp": -1},
			{"rect": Rect2(1080, 470, 200, 16), "hp": -1},
			# Breakable counterweights sit at either end of the shutter's run, just
			# clear of it. The shutter seals against one of them at each extreme,
			# so destroying one leaves that half of the mid lane open for good —
			# the only permanent answer to a barrier that cannot be broken.
			{"rect": Rect2(20, 400, 190, 16), "hp": 2},
			{"rect": Rect2(1070, 400, 190, 16), "hp": 2},
			# Breakable upper shoulders either side of the chimney.
			{"rect": Rect2(400, 330, 150, 14), "hp": 2},
			{"rect": Rect2(706, 330, 150, 14), "hp": 2},
			# Low terraces, clear of the orb columns.
			{"rect": Rect2(300, 540, 170, 14), "hp": 2},
			{"rect": Rect2(810, 540, 170, 14), "hp": 2},
			{"rect": Rect2(500, 545, 100, 14), "hp": 2, "min_players": 3},
			{"rect": Rect2(680, 545, 100, 14), "hp": 2, "min_players": 4},
		],
		"hazards": [],
	}


## Thesis: mastery means reading where several deterministic systems intersect.
##
## Two horizontal ferries squeeze the firing lane toward a permanent mast while
## a pulse orb patrols vertically through the remaining gap. Nothing is random:
## the rails, current positions and blast footprint expose the entire puzzle.
## The safest plan is often to collide a knife early so its falling future misses
## the next crossing rather than merely aiming at a fighter's current position.
static func _collision_course() -> Dictionary:
	return {
		"name": "COLLISION COURSE",
		"feature": "MASTERY // moving cover and a pulsing crossing make future knife collisions the real target.",
		"spawns": [
			Vector2(240.0, 596.0), Vector2(1040.0, 596.0),
			Vector2(150.0, 296.0), Vector2(1130.0, 296.0),
		],
		"respawn_points": [
			Vector2(120.0, 596.0), Vector2(360.0, 596.0), Vector2(640.0, 596.0),
			Vector2(920.0, 596.0), Vector2(1160.0, 596.0),
			Vector2(110.0, 296.0), Vector2(1170.0, 296.0),
			Vector2(120.0, 456.0), Vector2(1160.0, 456.0),
			Vector2(600.0, 486.0), Vector2(680.0, 486.0),
		],
		"core_spawns": [Vector2(360.0, 455.0), Vector2(640.0, 555.0), Vector2(920.0, 455.0)],
		"platforms": [
			{"rect": Rect2(0, 320, 220, 16), "hp": -1},
			{"rect": Rect2(1060, 320, 220, 16), "hp": -1},
			{"rect": Rect2(45, 480, 175, 16), "hp": -1},
			{"rect": Rect2(1060, 480, 175, 16), "hp": -1},
			{"rect": Rect2(616, 232, 48, 158), "hp": -1},
			# Ferries converge on the mast but preserve a readable 16px air seam.
			{
				"rect": Rect2(260, 380, 160, 16), "hp": -1,
				"motion": {"axis": Vector2.RIGHT, "travel": 180.0, "period": 360, "phase": 0.0},
			},
			{
				"rect": Rect2(860, 380, 160, 16), "hp": -1,
				"motion": {"axis": Vector2.LEFT, "travel": 180.0, "period": 360, "phase": 0.0},
			},
			{"rect": Rect2(545, 510, 190, 16), "hp": -1},
			{"rect": Rect2(300, 550, 150, 14), "hp": 2},
			{"rect": Rect2(830, 550, 150, 14), "hp": 2},
			{"rect": Rect2(455, 445, 105, 14), "hp": 2, "min_players": 3},
			{"rect": Rect2(720, 445, 105, 14), "hp": 2, "min_players": 4},
		],
		"hazards": [
			{
				"home": Vector2(640.0, 420.0),
				"motion": {"axis": Vector2.DOWN, "travel": 115.0, "period": 240, "phase": 0.0},
				"blast_radius": 165.0,
				"recharge_windows": 3,
			},
			{
				"home": Vector2(300.0, 270.0),
				"motion": {"axis": Vector2.RIGHT, "travel": 150.0, "period": 360, "phase": 0.5},
				"blast_radius": 145.0,
				"min_players": 3,
			},
			{
				"home": Vector2(980.0, 270.0),
				"motion": {"axis": Vector2.LEFT, "travel": 150.0, "period": 360, "phase": 0.5},
				"blast_radius": 145.0,
				"min_players": 4,
			},
		],
	}
