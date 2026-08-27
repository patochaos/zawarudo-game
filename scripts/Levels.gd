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
##   wrap_y — leaving the actual top or bottom of the screen re-enters at the
##            opposite edge. A wrap-y level MUST have a solid gate below the
##            HUD everywhere except a gap in the middle third, and its floor gap
##            must sit inside that top gap. Then re-entry always reaches open,
##            un-occluded space instead of teleporting at an interior seam.
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
## Wrapping is a screen-edge rule. STAGE_TOP is separately the lower edge of the
## compact HUD rail and is where visible arena architecture begins.
const WRAP_TOP := 0.0
const STAGE_TOP := 58.0

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

## Two vertical wrap chutes flank a bridge that can be dismantled piece by
## piece. Early turns happen across the bridge; later turns spill through the
## holes it leaves and return from the opposite screen edge.
static func _shattered_sanctum() -> Dictionary:
	return {
		"name": "SHATTERED SANCTUM",
		"feature": "COLLAPSE // break the middle bridge to open two vertical wrap chutes.",
		"wrap_x": true,
		"wrap_y": true,
		"skip_ground": true,
		"spawns": [
			Vector2(140.0, 596.0), Vector2(1140.0, 596.0),
			Vector2(390.0, 296.0), Vector2(890.0, 296.0),
		],
		"respawn_points": [
			Vector2(120.0, 596.0), Vector2(640.0, 596.0), Vector2(1160.0, 596.0),
			Vector2(390.0, 296.0), Vector2(890.0, 296.0),
			Vector2(120.0, 430.0), Vector2(1160.0, 390.0), Vector2(640.0, 476.0),
		],
		"core_spawns": [Vector2(390.0, 250.0), Vector2(640.0, 450.0), Vector2(1100.0, 350.0)],
		"platforms": [
			# Two paired top/floor apertures make separate vertical circuits.
			{"rect": Rect2(0, STAGE_TOP, 250, 16), "hp": -1},
			{"rect": Rect2(530, STAGE_TOP, 220, 16), "hp": -1},
			{"rect": Rect2(1030, STAGE_TOP, 250, 16), "hp": -1},
			{"rect": Rect2(0, 620, 300, 70), "hp": -1},
			{"rect": Rect2(500, 620, 280, 70), "hp": -1},
			{"rect": Rect2(980, 620, 300, 70), "hp": -1},
			# Permanent islands remain after every destructible piece is gone.
			{"rect": Rect2(280, 320, 220, 16), "hp": -1},
			{"rect": Rect2(780, 320, 220, 16), "hp": -1},
			{"rect": Rect2(0, 454, 240, 16), "hp": -1},
			{"rect": Rect2(1040, 414, 240, 16), "hp": -1},
			{"rect": Rect2(560, 500, 160, 16), "hp": -1},
			# The bridge is the arena's temporary starting state, not its final one.
			{"rect": Rect2(380, 400, 160, 16), "hp": 2},
			{"rect": Rect2(560, 400, 160, 16), "hp": 3},
			{"rect": Rect2(740, 400, 160, 16), "hp": 2},
			{"rect": Rect2(250, 510, 110, 16), "hp": 2},
			{"rect": Rect2(920, 470, 110, 16), "hp": 2},
			{"rect": Rect2(380, 535, 110, 14), "hp": 2, "min_players": 3},
			{"rect": Rect2(790, 535, 110, 14), "hp": 2, "min_players": 4},
		],
		"hazards": [],
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
			# The gate sits directly below the HUD, but its opening continues to the
			# real top edge. Bodies and knives wrap only once they leave the screen.
			{"rect": Rect2(0, STAGE_TOP, 360, 16), "hp": -1}, # top gate, gap 360..920
			{"rect": Rect2(920, STAGE_TOP, 360, 16), "hp": -1},
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
			# Anchored to the top gate and touching the centre beam: it blocks the
			# P3/P4 opening line but leaves a vertical portal on either side.
			{"rect": Rect2(620, STAGE_TOP, 40, 277), "hp": -1},
			{"rect": Rect2(540, 335, 200, 16), "hp": 3},
			{"rect": Rect2(575, 545, 130, 14), "hp": 2},     # the tempting perch
			{"rect": Rect2(445, 485, 110, 14), "hp": 2, "min_players": 3},
			{"rect": Rect2(725, 485, 110, 14), "hp": 2, "min_players": 4},
		],
	}


# ----------------------------------------------------------- kinetic arenas --

## A single lift joins a vertical-only loop. It is useful, but never mandatory:
## the fastest route may be to jump through the bottom and return from above.
static func _pendulum() -> Dictionary:
	return {
		"name": "PENDULUM",
		"feature": "VERTICAL LOOP // ride the lift or beat it through the top/bottom portal.",
		"wrap_y": true,
		"skip_ground": true,
		"spawns": [
			Vector2(180.0, 596.0), Vector2(1100.0, 596.0),
			Vector2(420.0, 326.0), Vector2(860.0, 236.0),
		],
		"respawn_points": [
			Vector2(120.0, 596.0), Vector2(360.0, 596.0),
			Vector2(940.0, 596.0), Vector2(1160.0, 596.0),
			Vector2(170.0, 456.0), Vector2(420.0, 326.0),
			Vector2(860.0, 236.0), Vector2(1120.0, 406.0),
		],
		"core_spawns": [Vector2(220.0, 410.0), Vector2(640.0, 125.0), Vector2(1060.0, 360.0)],
		"platforms": [
			{"rect": Rect2(0, STAGE_TOP, 500, 16), "hp": -1},
			{"rect": Rect2(780, STAGE_TOP, 500, 16), "hp": -1},
			{"rect": Rect2(0, 620, 500, 70), "hp": -1},
			{"rect": Rect2(780, 620, 500, 70), "hp": -1},
			# Static landings form one rising zig-zag around the central shaft.
			{"rect": Rect2(70, 480, 200, 16), "hp": -1},
			{"rect": Rect2(320, 350, 200, 16), "hp": -1},
			{"rect": Rect2(760, 260, 200, 16), "hp": -1},
			{"rect": Rect2(1010, 430, 220, 16), "hp": -1},
			# One lift owns the open shaft; its entire sweep stays readable.
			{
				"rect": Rect2(565, 470, 150, 16), "hp": -1,
				"motion": {"axis": Vector2.UP, "travel": 220.0, "period": 300, "phase": 0.0},
			},
			{"rect": Rect2(390, 550, 110, 14), "hp": 2, "min_players": 3},
			{"rect": Rect2(780, 535, 110, 14), "hp": 2, "min_players": 4},
		],
		"hazards": [],
	}


## An asymmetric horizontal loop with two loaded pulse orbs. The terrain aims
## movement toward them, so a deliberate detonation can slingshot a whole fight
## across the seam instead of merely disturbing a symmetric firing lane.
static func _pulse_chamber() -> Dictionary:
	return {
		"name": "PULSE CHAMBER",
		"feature": "SLINGSHOT // paired pulse orbs turn the wrap route into a pinball table.",
		"wrap_x": true,
		"spawns": [
			Vector2(170.0, 596.0), Vector2(1110.0, 596.0),
			Vector2(330.0, 336.0), Vector2(900.0, 246.0),
		],
		"respawn_points": [
			Vector2(100.0, 596.0), Vector2(500.0, 596.0),
			Vector2(760.0, 596.0), Vector2(1180.0, 596.0),
			Vector2(90.0, 446.0), Vector2(330.0, 336.0), Vector2(610.0, 416.0),
			Vector2(900.0, 246.0), Vector2(930.0, 496.0), Vector2(1190.0, 306.0),
		],
		"core_spawns": [Vector2(110.0, 400.0), Vector2(640.0, 350.0), Vector2(1050.0, 270.0)],
		"platforms": [
			# Staggered islands create a loop with no mirrored firing row.
			{"rect": Rect2(0, 470, 180, 16), "hp": -1},
			{"rect": Rect2(1100, 330, 180, 16), "hp": -1},
			{"rect": Rect2(220, 360, 220, 16), "hp": -1},
			{"rect": Rect2(520, 440, 180, 16), "hp": -1},
			{"rect": Rect2(800, 270, 200, 16), "hp": -1},
			{"rect": Rect2(820, 520, 220, 16), "hp": -1},
			{"rect": Rect2(50, 290, 120, 14), "hp": 2, "min_players": 3},
			{"rect": Rect2(1030, 450, 120, 14), "hp": 2, "min_players": 4},
		],
		"hazards": [
			{
				"home": Vector2(430.0, 420.0),
				"blast_radius": 165.0,
				"recharge_windows": 2,
			},
			{
				"home": Vector2(850.0, 360.0),
				"blast_radius": 165.0,
				"recharge_windows": 2,
			},
			{
				"home": Vector2(640.0, 255.0),
				"motion": {"axis": Vector2.DOWN, "travel": 90.0, "period": 300, "phase": 0.0},
				"blast_radius": 140.0,
				"min_players": 4,
			},
		],
	}


## A full-height shutter patrols the open middle. It creates two honest routes—
## over and under—and horizontal wrap adds a third route around the outside.
static func _foundry() -> Dictionary:
	return {
		"name": "FOUNDRY",
		"feature": "GUILLOTINE // route above, below or around one roaming wall.",
		"wrap_x": true,
		"spawns": [
			Vector2(160.0, 596.0), Vector2(1120.0, 596.0),
			Vector2(150.0, 296.0), Vector2(1130.0, 296.0),
		],
		"respawn_points": [
			Vector2(100.0, 596.0), Vector2(420.0, 596.0), Vector2(640.0, 596.0),
			Vector2(860.0, 596.0), Vector2(1180.0, 596.0),
			Vector2(150.0, 296.0), Vector2(1130.0, 296.0),
			Vector2(130.0, 476.0), Vector2(1150.0, 476.0),
		],
		"core_spawns": [Vector2(160.0, 370.0), Vector2(640.0, 570.0), Vector2(1120.0, 370.0)],
		"platforms": [
			# Deep side rooms remain useful as the middle changes allegiance.
			{"rect": Rect2(0, 320, 300, 16), "hp": -1},
			{"rect": Rect2(980, 320, 300, 16), "hp": -1},
			{"rect": Rect2(0, 500, 260, 16), "hp": -1},
			{"rect": Rect2(1020, 500, 260, 16), "hp": -1},
			{"rect": Rect2(0, 190, 260, 16), "hp": -1},
			{"rect": Rect2(1020, 190, 260, 16), "hp": -1},
			# THE GUILLOTINE. Its 90px lower clearance is a real body route.
			{
				"rect": Rect2(360, 230, 48, 300), "hp": -1,
				"motion": {"axis": Vector2.RIGHT, "travel": 512.0, "period": 420, "phase": 0.0},
			},
			{"rect": Rect2(40, 410, 190, 16), "hp": 2},
			{"rect": Rect2(1050, 410, 190, 16), "hp": 2},
			{"rect": Rect2(270, 560, 100, 14), "hp": 2, "min_players": 3},
			{"rect": Rect2(910, 560, 100, 14), "hp": 2, "min_players": 4},
		],
		"hazards": [],
	}


## The final arena keeps Level 2's four-way freedom and removes most of its safe
## architecture. Two ferries cross the void at different heights; a low pulse
## orb can eject bodies or knives straight through the bottom portal.
static func _collision_course() -> Dictionary:
	return {
		"name": "COLLISION COURSE",
		"feature": "ZERO-G CROSSING // ferries and a pulse launcher feed a four-way void.",
		"wrap_x": true,
		"wrap_y": true,
		"skip_ground": true,
		"spawns": [
			Vector2(150.0, 596.0), Vector2(1130.0, 596.0),
			Vector2(210.0, 296.0), Vector2(1090.0, 236.0),
		],
		"respawn_points": [
			Vector2(140.0, 596.0), Vector2(1140.0, 596.0),
			Vector2(210.0, 296.0), Vector2(1090.0, 236.0),
			Vector2(190.0, 476.0), Vector2(1070.0, 406.0), Vector2(640.0, 366.0),
		],
		"core_spawns": [Vector2(250.0, 420.0), Vector2(640.0, 330.0), Vector2(1030.0, 350.0)],
		"platforms": [
			{"rect": Rect2(0, STAGE_TOP, 300, 16), "hp": -1},
			{"rect": Rect2(980, STAGE_TOP, 300, 16), "hp": -1},
			{"rect": Rect2(0, 620, 340, 70), "hp": -1},
			{"rect": Rect2(940, 620, 340, 70), "hp": -1},
			# Sparse fixed islands leave the portals as first-class routes.
			{"rect": Rect2(80, 320, 260, 16), "hp": -1},
			{"rect": Rect2(980, 260, 220, 16), "hp": -1},
			{"rect": Rect2(80, 500, 220, 16), "hp": -1},
			{"rect": Rect2(940, 430, 260, 16), "hp": -1},
			{"rect": Rect2(570, 390, 140, 16), "hp": -1},
			# Ferries cross at different heights, never forming a safe mirrored row.
			{
				"rect": Rect2(340, 520, 180, 16), "hp": -1,
				"motion": {"axis": Vector2.RIGHT, "travel": 400.0, "period": 360, "phase": 0.0},
			},
			{
				"rect": Rect2(760, 250, 180, 16), "hp": -1,
				"motion": {"axis": Vector2.LEFT, "travel": 400.0, "period": 360, "phase": 0.5},
			},
			{"rect": Rect2(400, 450, 110, 14), "hp": 2, "min_players": 3},
			{"rect": Rect2(770, 450, 110, 14), "hp": 2, "min_players": 4},
		],
		"hazards": [
			{
				"home": Vector2(640.0, 570.0),
				"motion": {"axis": Vector2.UP, "travel": 120.0, "period": 240, "phase": 0.0},
				"blast_radius": 165.0,
				"recharge_windows": 3,
			},
			{
				"home": Vector2(420.0, 175.0),
				"motion": {"axis": Vector2.RIGHT, "travel": 440.0, "period": 360, "phase": 0.5},
				"blast_radius": 145.0,
				"min_players": 3,
			},
		],
	}
