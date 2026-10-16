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
##   wrap_x: leaving one side re-enters the other. Side walls are omitted.
##   wrap_y: leaving the actual top or bottom of the screen re-enters at the
##            opposite edge. A wrap-y level MUST have a solid gate below the
##            HUD everywhere except a gap in the middle third, and its floor gap
##            must sit inside that top gap. Then re-entry always reaches open,
##            un-occluded space instead of teleporting at an interior seam.
##            A level without wrap_y gets an invisible ceiling whose underside
##            is STAGE_TOP, so no jump or dash leaves the visible stage.
##
## MOVING GEOMETRY
##   A platform may carry a `motion` dictionary (see Mover.gd). It then sweeps
##   between its authored position and `home + axis * travel`, driven purely by
##   the absolute simulation tick, so it is frozen during planning and moves
##   only while time is running. Everything that reads geometry (collision, the
##   ghost preview, the AI, the lockstep digest) projects it from the same
##   function, so a moving ledge is a thing the player can plan around rather
##   than an ambush.
##
##   A moving piece must remain legal at BOTH ends of its sweep. The layout
##   test checks every constraint at each extreme.
##
## HAZARDS
##   `hazards` lists pulse orbs (see Hazard.gd). An orb drifts on its own rail
##   and, when a knife strikes it, pushes fighters and relaunches knives radially
##   at full throw speed before going dark for a couple of windows. Place them where being pushed is
##   interesting (over a gap, beside a seam, under the crown), not where a push
##   simply ends the round.
##
## Player counts: every arena is authored for four fighters. Pieces tagged
## `min_players` leave when fewer play, so a duel is the four-player board cut
## down, never a separate map. Spawn and respawn sockets stay on permanent
## geometry in every count.
##
## Design constraints for a new level:
##   * playable band is roughly y 120..620 on non-wrapping levels
##   * a jump clears 211px (Pulse about 176px), so keep climbs near 140px and
##     stack surfaces at least 140px apart so a climb does not bonk
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
## Invisible lid for non-wrapping levels. Its bottom edge is STAGE_TOP and it
## starts left of the arena so Arena skips it like the side walls.
const CEILING := {"rect": Rect2(-60, STAGE_TOP - 100.0, 1400, 100), "hp": -1}

static func count() -> int:
	return 5

static func build(index: int, player_count: int = 4) -> Dictionary:
	return _finish(_layout(index), clampi(player_count, 2, 4))

## A compact crossing for the Interception experiment, outside the arena rotation.
## The central shelf gives the core a low approach with limited jumping room;
## its exposed upper landing remains reachable with one ordinary ground jump.
static func build_interception() -> Dictionary:
	return _finish({
		"name": "INTERCEPTION COURT",
		"feature": "INTERCEPTION // threaten the crossing or catch the upper landing.",
		"spawns": [
			Vector2(370.0, 596.0), Vector2(910.0, 596.0),
			Vector2(260.0, 466.0), Vector2(1020.0, 466.0),
		],
		"respawn_points": [
			Vector2(350.0, 596.0), Vector2(430.0, 596.0),
			Vector2(850.0, 596.0), Vector2(930.0, 596.0),
			Vector2(260.0, 466.0), Vector2(1020.0, 466.0),
		],
		"core_spawns": [Vector2(640.0, 584.0)],
		"hazards": [],
		"platforms": [
			# Visible side walls keep this encounter inside an 864px chamber.
			{"rect": Rect2(0, STAGE_TOP, 208, 562), "hp": -1},
			{"rect": Rect2(1072, STAGE_TOP, 208, 562), "hp": -1},
			# Rear steps offer raised firing positions without roofing the spawns.
			{"rect": Rect2(208, 490, 102, 130), "hp": -1},
			{"rect": Rect2(970, 490, 102, 130), "hp": -1},
			# 100px below, 120px up: a tight low route and a single-jump landing.
			{"rect": Rect2(500, 500, 280, 20), "hp": -1},
		],
	}, 2)

## The compact arena authored for Close Camera. It is deliberately outside the
## normal seven-arena rotation: only the dedicated mode can load it.
static func build_close_camera() -> Dictionary:
	return _finish({
		"name": "KNIFE COURT",
		"feature": "CLOSE CAMERA // intimate planning, full-arena execution.",
		"wrap_x": true,
		"spawns": [
			Vector2(400.0, 596.0), Vector2(880.0, 596.0),
			Vector2(380.0, 371.0), Vector2(900.0, 371.0),
		],
		"respawn_points": [
			Vector2(160.0, 596.0), Vector2(400.0, 596.0), Vector2(640.0, 596.0),
			Vector2(880.0, 596.0), Vector2(1120.0, 596.0),
			Vector2(180.0, 481.0), Vector2(1100.0, 481.0),
		],
		"core_spawns": [
			Vector2(220.0, 460.0), Vector2(640.0, 445.0), Vector2(1060.0, 460.0),
		],
		"hazards": [],
		"platforms": [
			{"rect": Rect2(0, 540, 56, 80), "hp": -1},
			{"rect": Rect2(1224, 540, 56, 80), "hp": -1},
			{"rect": Rect2(100, 505, 260, 18), "hp": -1},
			{"rect": Rect2(920, 505, 260, 18), "hp": -1},
			{"rect": Rect2(260, 395, 240, 18), "hp": 3},
			{"rect": Rect2(780, 395, 240, 18), "hp": 3},
			{
				"rect": Rect2(460, 285, 160, 16), "hp": -1,
				"motion": {
					"axis": Vector2.RIGHT, "travel": 200.0, "period": 240, "phase": 0.0,
				},
			},
			{"rect": Rect2(604, 500, 72, 120), "hp": -1},
		],
	}, 2)

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

## The first single-player prototype is deliberately authored as a situation,
## not a fair versus arena. A hostile echo stands to the right while one of its
## earlier knives is already entering from the left. The player therefore reads
## two known futures from the first freeze instead of waiting for a bot to invent
## an interesting position.
static func build_fate_trial_crossfire() -> Dictionary:
	return _finish({
		"name": "THE CROSSFIRE",
		"feature": "FATE TRIAL // survive three revealed volleys.",
		"spawns": [
			Vector2(300.0, 596.0), Vector2(1050.0, 596.0),
			Vector2(180.0, 406.0), Vector2(1100.0, 406.0),
		],
		"respawn_points": [
			Vector2(300.0, 596.0), Vector2(1050.0, 596.0),
		],
		"core_spawns": [],
		"hazards": [],
		"platforms": [
			# Side balconies offer vertical escape routes without blocking the
			# hostile ground-level firing lane.
			{"rect": Rect2(90, 470, 250, 16), "hp": -1},
			{"rect": Rect2(940, 470, 250, 16), "hp": -1},
			{"rect": Rect2(420, 370, 180, 16), "hp": -1},
			{"rect": Rect2(680, 370, 180, 16), "hp": -1},
			# Fragile low cover can catch one trajectory, but relying on it changes
			# the board inherited by the later windows.
			{"rect": Rect2(565, 535, 150, 16), "hp": 1},
		],
	}, 2)

## The rotation. One rule per arena, in the order the opponent ladder visits
## them: the readable baseline first, the wrap finale last.
static func _layout(index: int) -> Dictionary:
	match posmod(index, count()):
		0: return _crosshair_court()
		1: return _clockwork_gallery()
		2: return _stilled_hall()
		3: return _pulse_chamber()
		_: return _endless_descent()


## A moving-platform fixture outside the rotation, kept for the kinetic
## contract tests (ghost/execution parity on a lift, riders, pulse orbs).
static func build_kinetic_proof(player_count: int = 2) -> Dictionary:
	return _finish(_pendulum(), clampi(player_count, 2, 4))

static func _finish(lv: Dictionary, player_count: int) -> Dictionary:
	var plats: Array = []
	if not lv.get("skip_ground", false):
		plats.append(GROUND.duplicate())
	if not lv.get("wrap_x", false):
		plats.append(WALL_L.duplicate())
		plats.append(WALL_R.duplicate())
	if not lv.get("wrap_y", false) and not lv.get("skip_ceiling", false):
		plats.append(CEILING.duplicate())
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
	# A respawn socket may sit on a crowd-only perch: {"at": point, "min_players": 3}.
	var sockets: Array = []
	for entry in lv.get("respawn_points", lv["spawns"]):
		if entry is Dictionary:
			if int(entry.get("min_players", 2)) > player_count:
				continue
			sockets.append(entry["at"])
		else:
			sockets.append(entry)
	lv["respawn_points"] = sockets
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
	var active_zones: Array = []
	for authored: Dictionary in lv.get("zones", []):
		if int(authored.get("min_players", 2)) > player_count:
			continue
		var field: Dictionary = authored.duplicate(true)
		field.erase("min_players")
		active_zones.append(field)
	lv["zones"] = active_zones
	lv["player_count"] = player_count
	return lv

static func wrap_label(lv: Dictionary) -> String:
	if lv.get("upper_side_passages", false):
		return "WRAP ↕ · UPPER ↔"
	if lv["wrap_x"] and lv["wrap_y"]:
		return "WRAP ↔ ↕"
	if lv["wrap_x"]:
		return "WRAP ↔"
	if lv["wrap_y"]:
		return "WRAP ↕"
	return "WALLED"

# ----------------------------------------------------------- the rotation --
##
## Spacing contract (playtest, Oct 2026): stacked surfaces sit 140px apart, so
## a standing fighter keeps about 76px of headroom and a climb never starts
## under the ledge it is aiming for. Each arena offers ground plus three raised
## tiers near 480 / 340 / 200, and climbs are offset sideways so the next step
## is beside the fighter rather than above it.

## Every surface is permanent and every important firing lane has a simple,
## visible answer: shoot flat through the middle, arc over the centre mast, or
## use a side stair to change height. Extra fighters add small staging ledges,
## but never new rules, so this is the control case for the whole level set.
static func _crosshair_court() -> Dictionary:
	return {
		"name": "CROSSHAIR COURT",
		"feature": "START HERE // catch a landing with a slow fan, or bank a fast throw off hard cover.",
		"spawns": [
			Vector2(290.0, 596.0), Vector2(990.0, 596.0),
			Vector2(140.0, 176.0), Vector2(1140.0, 176.0),
		],
		"respawn_points": [
			Vector2(290.0, 596.0), Vector2(400.0, 596.0), Vector2(880.0, 596.0),
			Vector2(990.0, 596.0),
			Vector2(150.0, 456.0), Vector2(1130.0, 456.0),
			Vector2(560.0, 456.0), Vector2(720.0, 456.0),
			Vector2(400.0, 316.0), Vector2(880.0, 316.0),
			Vector2(560.0, 236.0), Vector2(720.0, 236.0),
			Vector2(140.0, 176.0), Vector2(1140.0, 176.0),
			{"at": Vector2(400.0, 176.0), "min_players": 3},
			{"at": Vector2(880.0, 176.0), "min_players": 4},
		],
		"core_spawns": [Vector2(285.0, 440.0), Vector2(640.0, 560.0), Vector2(995.0, 440.0)],
		"platforms": [
			# A three-step stair on each side: low wing, inner landing, high wing.
			{"rect": Rect2(40, 480, 220, 16), "hp": -1},
			{"rect": Rect2(1020, 480, 220, 16), "hp": -1},
			{"rect": Rect2(310, 340, 180, 16), "hp": -1},
			{"rect": Rect2(790, 340, 180, 16), "hp": -1},
			{"rect": Rect2(40, 200, 200, 16), "hp": -1},
			{"rect": Rect2(1040, 200, 200, 16), "hp": -1},
			# The mast blocks the free middle volley but leaves high arcs open.
			{"rect": Rect2(520, 480, 240, 16), "hp": -1},
			{"rect": Rect2(616, 276, 48, 204), "hp": -1},
			{"rect": Rect2(500, 260, 280, 16), "hp": -1},
			# Crowd-only perches above the inner landings.
			{"rect": Rect2(330, 200, 140, 16), "hp": -1, "min_players": 3},
			{"rect": Rect2(810, 200, 140, 16), "hp": -1, "min_players": 4},
		],
		"hazards": [],
	}

## Thesis: nothing here is safe for long. Three bridge gates and two low gates
## open and close on staggered clocks, so every plan has to include where the
## floor will be when time stops again. Side towers stay permanent.
## Authored for four: the breakable top shelves are crowd landings; a duel
## cuts them so the gates are the only middle ground.
## Walled on purpose: a side wrap let fighters trade flat throws through the
## borders and skip the gates.
static func _clockwork_gallery() -> Dictionary:
	return {
		"name": "CLOCKWORK GALLERY",
		"feature": "SHUTTERS // every gate opens on a clock. Stand on one when it does and you fall.",
		"spawns": [
			Vector2(90.0, 596.0), Vector2(1190.0, 596.0),
			Vector2(90.0, 316.0), Vector2(1190.0, 316.0),
		],
		"respawn_points": [
			Vector2(90.0, 596.0), Vector2(480.0, 596.0), Vector2(640.0, 596.0),
			Vector2(800.0, 596.0), Vector2(1190.0, 596.0),
			Vector2(240.0, 456.0), Vector2(1040.0, 456.0),
			Vector2(90.0, 316.0), Vector2(1190.0, 316.0),
			Vector2(240.0, 176.0), Vector2(1040.0, 176.0),
			Vector2(640.0, 166.0),
		],
		"core_spawns": [Vector2(640.0, 290.0), Vector2(200.0, 440.0), Vector2(1080.0, 440.0)],
		"platforms": [
			# Permanent towers: low wing, outer ledge, high wing.
			{"rect": Rect2(150, 480, 180, 16), "hp": -1},
			{"rect": Rect2(950, 480, 180, 16), "hp": -1},
			{"rect": Rect2(0, 340, 190, 16), "hp": -1},
			{"rect": Rect2(1090, 340, 190, 16), "hp": -1},
			{"rect": Rect2(150, 200, 180, 16), "hp": -1},
			{"rect": Rect2(950, 200, 180, 16), "hp": -1},
			{"rect": Rect2(560, 190, 160, 16), "hp": -1},
			# The bridge: three gates on one clock, a third of a period apart.
			{"rect": Rect2(400, 330, 150, 16), "hp": -1,
				"cycle": {"period": 210, "solid": 105, "phase": 0}},
			{"rect": Rect2(565, 330, 150, 16), "hp": -1,
				"cycle": {"period": 210, "solid": 105, "phase": 70}},
			{"rect": Rect2(730, 330, 150, 16), "hp": -1,
				"cycle": {"period": 210, "solid": 105, "phase": 140}},
			# Low gates beside the towers: a landing that will not keep you.
			{"rect": Rect2(370, 470, 110, 16), "hp": -1,
				"cycle": {"period": 210, "solid": 105, "phase": 105}},
			{"rect": Rect2(800, 470, 110, 16), "hp": -1,
				"cycle": {"period": 210, "solid": 105, "phase": 35}},
			{"rect": Rect2(370, 200, 120, 14), "hp": 2, "min_players": 3},
			{"rect": Rect2(790, 200, 120, 14), "hp": 2, "min_players": 4},
		],
		"hazards": [],
	}

## Thesis: a knife is a trap if it takes long enough to arrive. Two stasis
## columns flank the centre pillar; every arc across the hall passes through
## one, and anything thrown into a field lingers there for several turns.
## Authored for four: small high shelves seat the crowd; a duel cuts them.
static func _stilled_hall() -> Dictionary:
	return {
		"name": "STILLED HALL",
		"feature": "STASIS // time crawls inside the fields. A knife thrown in stays a threat for turns.",
		"spawns": [
			Vector2(60.0, 596.0), Vector2(1220.0, 596.0),
			Vector2(250.0, 176.0), Vector2(1030.0, 176.0),
		],
		"respawn_points": [
			Vector2(60.0, 596.0), Vector2(400.0, 596.0), Vector2(880.0, 596.0),
			Vector2(1220.0, 596.0),
			Vector2(200.0, 456.0), Vector2(1080.0, 456.0),
			Vector2(75.0, 316.0), Vector2(1205.0, 316.0),
			Vector2(580.0, 226.0), Vector2(700.0, 226.0),
			Vector2(250.0, 176.0), Vector2(1030.0, 176.0),
		],
		"core_spawns": [Vector2(640.0, 330.0), Vector2(250.0, 440.0), Vector2(1030.0, 440.0)],
		"platforms": [
			# Side towers: low wing, outer ledge, high wing.
			{"rect": Rect2(100, 480, 200, 16), "hp": -1},
			{"rect": Rect2(980, 480, 200, 16), "hp": -1},
			{"rect": Rect2(0, 340, 150, 16), "hp": -1},
			{"rect": Rect2(1130, 340, 150, 16), "hp": -1},
			{"rect": Rect2(180, 200, 150, 16), "hp": -1},
			{"rect": Rect2(950, 200, 150, 16), "hp": -1},
			# The pillar closes the flat lane, so throws arc through the fields.
			{"rect": Rect2(624, 380, 32, 240), "hp": -1},
			{"rect": Rect2(530, 250, 220, 16), "hp": -1},
			{"rect": Rect2(340, 340, 150, 16), "hp": 2},
			{"rect": Rect2(790, 340, 150, 16), "hp": 2},
			{"rect": Rect2(380, 200, 100, 14), "hp": -1, "min_players": 3},
			{"rect": Rect2(800, 200, 100, 14), "hp": -1, "min_players": 4},
		],
		"zones": [
			{"rect": Rect2(440, 250, 170, 330), "time_scale": 0.35},
			{"rect": Rect2(670, 250, 170, 330), "time_scale": 0.35},
		],
		"hazards": [],
	}

## A fair opening with two contested pulse orbs. Both fighters have permanent
## stairs, an exposed inner perch and fragile cover in the middle column.
## The ground lane offers a quiet approach; taking height brings the orbs into play.
## Lower bulkheads close the ground seam: a spawn-level throw or an orb push no
## longer leaves the stage at once. The wrap is open from the side ledges up.
static func _pulse_chamber() -> Dictionary:
	return {
		"name": "PULSE CHAMBER",
		"feature": "1v1 HAZARDS // hit an orb with a knife to push fighters and redirect knives. Dark = recharging.",
		"wrap_x": true,
		"spawns": [
			Vector2(150.0, 456.0), Vector2(1130.0, 456.0),
			Vector2(100.0, 176.0), Vector2(1180.0, 176.0),
		],
		"respawn_points": [
			Vector2(330.0, 596.0), Vector2(520.0, 596.0),
			Vector2(760.0, 596.0), Vector2(950.0, 596.0),
			Vector2(150.0, 456.0), Vector2(1130.0, 456.0), Vector2(640.0, 446.0),
			Vector2(420.0, 316.0), Vector2(860.0, 316.0),
			Vector2(100.0, 176.0), Vector2(1180.0, 176.0),
		],
		"core_spawns": [Vector2(220.0, 440.0), Vector2(640.0, 405.0), Vector2(1060.0, 440.0)],
		"platforms": [
			# Lower bulkheads, flush with the side ledges: the ground lane is
			# walled while the seam stays open at ledge height and above.
			{"rect": Rect2(0, 480, 80, 240), "hp": -1},
			{"rect": Rect2(1200, 480, 80, 240), "hp": -1},
			{"rect": Rect2(80, 480, 220, 16), "hp": -1},
			{"rect": Rect2(980, 480, 220, 16), "hp": -1},
			{"rect": Rect2(340, 340, 160, 16), "hp": -1},
			{"rect": Rect2(780, 340, 160, 16), "hp": -1},
			# High side perches straddle the seam above the orbs.
			{"rect": Rect2(0, 200, 250, 16), "hp": -1},
			{"rect": Rect2(1030, 200, 250, 16), "hp": -1},
			# Central high ground is exposed to either player's loaded orb.
			{"rect": Rect2(550, 470, 180, 16), "hp": -1},
			{"rect": Rect2(580, 330, 120, 16), "hp": 2},
			{"rect": Rect2(300, 200, 100, 14), "hp": 2, "min_players": 3},
			{"rect": Rect2(880, 200, 100, 14), "hp": 2, "min_players": 4},
		],
		"hazards": [
			{
				"home": Vector2(430.0, 425.0),
				"blast_radius": 180.0,
				"recharge_windows": 2,
			},
			{
				"home": Vector2(850.0, 425.0),
				"blast_radius": 180.0,
				"recharge_windows": 2,
			},
			{
				"home": Vector2(640.0, 150.0),
				"motion": {"axis": Vector2.DOWN, "travel": 90.0, "period": 300, "phase": 0.0},
				"blast_radius": 140.0,
				"min_players": 4,
			},
		],
	}

## A four-corner vertical loop over a hole in the world. P1/P2 start on the
## split floor and P3/P4 on the upper side walkways.
## Offset side stairs make the full climb indestructible; inner breakable steps
## offer faster diagonals. Duels leave the upper firing lane open; a hanging
## centre pillar separates the extra high spawns in three/four-player matches.
static func _endless_descent() -> Dictionary:
	return {
		"name": "ENDLESS DESCENT",
		"upper_side_passages": true,
		"feature": "1v1 // drop through the shaft to return above; cross the side passages upstairs.",
		"wrap_x": true,
		"wrap_y": true,
		"skip_ground": true,
		# On the solid parts of the floor, either side of the hole.
		"spawns": [
			Vector2(340.0, 596.0), Vector2(940.0, 596.0),
			Vector2(150.0, 316.0), Vector2(1130.0, 316.0),
		],
		"respawn_points": [
			Vector2(100.0, 596.0), Vector2(340.0, 596.0),
			Vector2(940.0, 596.0), Vector2(1180.0, 596.0),
			Vector2(150.0, 316.0), Vector2(1130.0, 316.0),
			Vector2(210.0, 456.0), Vector2(1070.0, 456.0),
			Vector2(330.0, 176.0), Vector2(950.0, 176.0),
		],
		"core_spawns": [Vector2(470.0, 440.0), Vector2(640.0, 560.0), Vector2(810.0, 440.0)],
		"platforms": [
			# The gate sits directly below the HUD, but its opening continues to the
			# real top edge. Bodies and knives wrap only once they leave the screen.
			{"rect": Rect2(0, STAGE_TOP, 360, 16), "hp": -1}, # top gate, gap 360..920
			{"rect": Rect2(920, STAGE_TOP, 360, 16), "hp": -1},
			{"rect": Rect2(0, 620, 430, 70), "hp": -1},      # floor, gap 430..850
			{"rect": Rect2(850, 620, 430, 70), "hp": -1},
			# Lower bulkheads close the ground shortcut. The only side passages
			# are above these walls, along the walkways flush with their tops.
			{"rect": Rect2(0, 340, 70, 380), "hp": -1},
			{"rect": Rect2(1210, 340, 70, 380), "hp": -1},
			{"rect": Rect2(70, 340, 160, 16), "hp": -1},
			{"rect": Rect2(1050, 340, 160, 16), "hp": -1},
			# Offset from the starting bodies: a held outward jump lands here
			# instead of hitting a ceiling directly above the spawn.
			{"rect": Rect2(120, 480, 180, 16), "hp": -1},
			{"rect": Rect2(980, 480, 180, 16), "hp": -1},
			{"rect": Rect2(260, 200, 140, 16), "hp": -1},
			{"rect": Rect2(880, 200, 140, 16), "hp": -1},
			# Faster inner stairs can be destroyed to reopen diagonal knife lanes.
			{"rect": Rect2(380, 340, 120, 16), "hp": 2},
			{"rect": Rect2(780, 340, 120, 16), "hp": 2},
			# Anchored to the top gate and touching the centre beam: it blocks the
			# P3/P4 opening line but leaves a vertical portal on either side.
			{"rect": Rect2(620, STAGE_TOP, 40, 212), "hp": -1, "min_players": 3},
			{"rect": Rect2(540, 270, 200, 16), "hp": 3},
			{"rect": Rect2(575, 480, 130, 14), "hp": 2},     # the tempting perch
			{"rect": Rect2(440, 480, 90, 14), "hp": 2, "min_players": 3},
			{"rect": Rect2(750, 480, 90, 14), "hp": 2, "min_players": 4},
		],
	}

# -------------------------------------------------------------- fixtures --

## Former rotation arena, now only the kinetic test fixture: a single lift
## joining a vertical-only loop. See `build_kinetic_proof`.
static func _pendulum() -> Dictionary:
	return {
		"name": "PENDULUM",
		"feature": "TIMING PRACTICE // intercept a landing after the lift or the top/bottom portal.",
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
