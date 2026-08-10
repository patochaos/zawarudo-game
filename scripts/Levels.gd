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
	return 2


static func build(index: int) -> Dictionary:
	var lv: Dictionary
	match posmod(index, count()):
		0: lv = _watchtowers()
		_: lv = _flight()

	var plats: Array = []
	if not lv.get("skip_ground", false):
		plats.append(GROUND.duplicate())
	if not lv.get("wrap_x", false):
		plats.append(WALL_L.duplicate())
		plats.append(WALL_R.duplicate())
	plats.append_array(lv["platforms"])
	for pf in plats:
		pf["max_hp"] = pf["hp"]
	lv["platforms"] = plats
	lv["wrap_x"] = lv.get("wrap_x", false)
	lv["wrap_y"] = lv.get("wrap_y", false)
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

## TowerFall Sacred Ground 00, compressed for two players. The side architecture
## creates climbable rooms, but the entire central flight volume remains open so
## persistent knives can accumulate instead of burying themselves immediately.
static func _watchtowers() -> Dictionary:
	return {
		"name": "SACRED DUEL",
		"spawns": [Vector2(250.0, 596.0), Vector2(1030.0, 596.0)],
		"core_spawns": [Vector2(435.0, 470.0), Vector2(640.0, 255.0), Vector2(845.0, 470.0)],
		"platforms": [
			{"rect": Rect2(0, 500, 150, 120), "hp": -1},    # visible side bases
			{"rect": Rect2(1130, 500, 150, 120), "hp": -1},
			{"rect": Rect2(0, 380, 300, 18), "hp": -1},     # upper side rooms
			{"rect": Rect2(980, 380, 300, 18), "hp": -1},
			{"rect": Rect2(270, 380, 30, 120), "hp": 3},    # breakable inner lips
			{"rect": Rect2(980, 380, 30, 120), "hp": 3},
			{"rect": Rect2(350, 500, 170, 16), "hp": 2},    # approach ledges
			{"rect": Rect2(760, 500, 170, 16), "hp": 2},
			# Keep a comfortable margin below the 211px jump ceiling. At y=285
			# this was 215px above the approach ledges and could not be reached.
			{"rect": Rect2(520, 305, 240, 16), "hp": 3},    # moon bridge
		],
	}


## After TowerFall's Flight: islands over a hole in the world. Wraps both ways.
## The ceiling is solid except a wide gap in the middle, and the floor gap sits
## inside it, so anything falling through re-enters in clear space.
static func _flight() -> Dictionary:
	return {
		"name": "FLIGHT",
		"wrap_x": true,
		"wrap_y": true,
		"skip_ground": true,
		# On the solid parts of the floor, either side of the hole.
		"spawns": [Vector2(280.0, 596.0), Vector2(1000.0, 596.0)],
		"core_spawns": [Vector2(290.0, 440.0), Vector2(640.0, 510.0), Vector2(990.0, 440.0)],
		"platforms": [
			{"rect": Rect2(0, 216, 360, 16), "hp": -1},      # ceiling, gap 360..920
			{"rect": Rect2(920, 216, 360, 16), "hp": -1},
			{"rect": Rect2(0, 620, 430, 70), "hp": -1},      # floor, gap 430..850
			{"rect": Rect2(850, 620, 430, 70), "hp": -1},
			{"rect": Rect2(0, 330, 70, 170), "hp": -1},      # horizontal portal frames
			{"rect": Rect2(1210, 330, 70, 170), "hp": -1},
			{"rect": Rect2(180, 470, 220, 16), "hp": 2},     # islands
			{"rect": Rect2(880, 470, 220, 16), "hp": 2},
			{"rect": Rect2(540, 335, 200, 16), "hp": 3},
			{"rect": Rect2(575, 545, 130, 14), "hp": 2},     # the tempting perch
		],
	}
