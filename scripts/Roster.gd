extends RefCounted
class_name Roster

## The playable cast, in one place. Both the local roster screen and the online
## lobby read their names, portraits and kit copy from here, so a fighter can
## never be described two different ways in two different screens.
##
## Weapon ids are append-only and are not presentation order: id 1 is the
## vacancy the retired Grenadier left, and the Chakram keeps id 3 while sitting
## fourth on the roster.

const DUELIST := 0
const DASHBLADE := 2
const CHAKRAM := 3
const SHOCK := 4

## Presentation order.
const ORDER := [DUELIST, DASHBLADE, SHOCK, CHAKRAM]

const DUELIST_PORTRAIT := preload("res://assets/art/portraits/duelist-portrait-v1.png")
const ROOK_PORTRAIT := preload("res://assets/art/portraits/rook-portrait-v1.png")
const ECLIPSE_PORTRAIT := preload("res://assets/art/portraits/eclipse-portrait-v1.png")
const PULSE_PORTRAIT := preload("res://assets/art/portraits/pulse-portrait-v1.png")

## Movement is the line that decides how a kit feels; the three abilities are
## what it does. The short kit line is what fits under a portrait.
const FIGHTERS := {
	DUELIST: {
		"name": "THE DUELIST",
		"short": "DUELIST",
		"kit": "CLASH · HARD RICOCHET",
		"movement": "BALANCED WALK · DOUBLE JUMP",
		"abilities": [
			["TWIN DAGGERS", "Reliable direct volleys."],
			["FAN THROW", "Pressure several routes at once."],
			["HARD RICOCHET", "Bank steel off arena cover."],
		],
	},
	DASHBLADE: {
		"name": "THE ROOK",
		"short": "ROOK",
		"kit": "CUT TO END · FRONT GUARD",
		"movement": "NO JUMP · 90% WALK · FAST FALL",
		"abilities": [
			["CUT TO END", "Dash through the planned line."],
			["LOST FRAMES", "Slow movement banks dash distance."],
			["FRONT GUARD", "Parry shots during the dash."],
		],
	},
	SHOCK: {
		"name": "THE PULSE",
		"short": "PULSE",
		"kit": "BACKBEAT · FEEDBACK",
		"movement": "FLOATY SINGLE JUMP · 90% WALK",
		"abilities": [
			["NEEDLE NOTE", "Fast, direct pressure."],
			["BACKBEAT", "Place persistent field traps."],
			["FEEDBACK", "Plasma and orb redirect weapons."],
		],
	},
	CHAKRAM: {
		"name": "THE ECLIPSE",
		"short": "ECLIPSE",
		"kit": "CONSECRATE · THIRD-TURN RETURN",
		"movement": "HIGH + DOUBLE JUMP · 105% WALK",
		"abilities": [
			["DECREE", "One corona follows the exact aim."],
			["CONSECRATION", "Walls hold it; a midair cast waits."],
			["ABSOLUTION", "It returns on its third turn."],
		],
	},
}


static func entry(weapon: int) -> Dictionary:
	return FIGHTERS.get(weapon, FIGHTERS[DUELIST])


static func full_name(weapon: int) -> String:
	return str(entry(weapon)["name"])


static func short_name(weapon: int) -> String:
	return str(entry(weapon)["short"])


static func portrait(weapon: int) -> Texture2D:
	match weapon:
		DASHBLADE: return ROOK_PORTRAIT
		CHAKRAM: return ECLIPSE_PORTRAIT
		SHOCK: return PULSE_PORTRAIT
		_: return DUELIST_PORTRAIT


## Presentation index of a weapon, clamped into the roster so an unknown id
## lands on the default fighter rather than off the end of the grid.
static func index_of(weapon: int) -> int:
	return maxi(ORDER.find(weapon), 0)


static func step(weapon: int, direction: int) -> int:
	return ORDER[posmod(index_of(weapon) + direction, ORDER.size())]
