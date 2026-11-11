extends RefCounted
class_name Roster

## The playable cast, in one place. Both the local roster screen and the online
## lobby read their names, portraits and kit copy from here, so a fighter can
## never be described two different ways in two different screens.
##
## Weapon ids are append-only and are not presentation order. Ids 1 to 4 are
## retired (Grenadier, Rook, Eclipse, Pulse) and must never be reused: old
## telemetry, captures and the deployed room server still know them.

const DUELIST := 0

## Active playable roster, in presentation order.
const ORDER := [DUELIST]

const DUELIST_PORTRAIT := preload("res://assets/art/portraits/duelist-portrait-v1.png")

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
}


static func entry(weapon: int) -> Dictionary:
	return FIGHTERS.get(weapon, FIGHTERS[DUELIST])


static func full_name(weapon: int) -> String:
	return str(entry(weapon)["name"])


static func short_name(weapon: int) -> String:
	return str(entry(weapon)["short"])


static func portrait(_weapon: int) -> Texture2D:
	return DUELIST_PORTRAIT


## Presentation index of a weapon, clamped into the roster so an unknown id
## lands on the default fighter rather than off the end of the grid.
static func index_of(weapon: int) -> int:
	return maxi(ORDER.find(weapon), 0)


static func step(weapon: int, direction: int) -> int:
	return ORDER[posmod(index_of(weapon) + direction, ORDER.size())]
