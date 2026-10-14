class_name Opponents
extends RefCounted

## The named opponent ladder behind Start Duel. Each rung is one CPU: a skill
## preset (how much of the search it spends, how precisely it aims, how long it
## deliberates) and a style, a few weights the shared planner reads when it
## ranks routes and shots. Every rung plans by the same rules and still cannot
## see the player's plan; what differs is what it wants.

## Neutral style. A rung lists only the keys it changes.
const NEUTRAL_STYLE := {
	## Multiplies the penalty for routes that cross a known knife.
	"safety_scale": 1.0,
	## Preferred distance to the rival at the end of the route, in px. Negative
	## means no preference. `range_weight` is the score lost per px away from it.
	"range_target": -1.0,
	"range_weight": 0.0,
	## Score for ending the route above the rival (full value at 120 px higher).
	"height_weight": 0.0,
	## Flat score for any route that jumps.
	"jump_bias": 0.0,
	## Score lost per tick the throw is delayed inside the window.
	"fire_tick_cost": 0.2,
	## Score per unit of draw above a 0.7 power throw; negative prefers quick throws.
	"power_bias": 0.0,
	## On a wrapping arena, score for throwing away from the rival so the knife
	## arrives through the seam.
	"seam_bias": 0.0,
	## A throw must beat this score or the CPU keeps the knife. 0 always throws.
	"withhold_score": 0.0,
}

## Ordered from first to last. `skill` is a GameManager.Difficulty value kept
## for the HUD and the custom match screens; `tuning` is what the planner reads.
const LADDER := [
	{
		"id": "apprentice", "name": "THE APPRENTICE", "tagline": "LEARNS THE KNIFE",
		"skill": 0,
		"tuning": {"aim_jitter": 7.0, "moves_searched": 1, "think_min": 1.4, "think_max": 3.0},
		"style": {},
	},
	{
		"id": "hound", "name": "THE HOUND", "tagline": "CLOSES IN · THROWS EARLY",
		"skill": 0,
		"tuning": {"aim_jitter": 4.5, "moves_searched": 2, "think_min": 1.0, "think_max": 2.2},
		"style": {"range_target": 140.0, "range_weight": 0.35, "fire_tick_cost": 1.2,
			"power_bias": -60.0, "safety_scale": 0.7},
	},
	{
		"id": "warden", "name": "THE WARDEN", "tagline": "KEEPS THE KNIFE UNTIL IT IS SURE",
		"skill": 1,
		"tuning": {"aim_jitter": 2.0, "moves_searched": 2, "think_min": 0.8, "think_max": 2.2},
		"style": {"safety_scale": 1.6, "withhold_score": 900.0,
			"range_target": 420.0, "range_weight": 0.12},
	},
	{
		"id": "spire", "name": "THE SPIRE", "tagline": "TAKES THE HIGH GROUND · FULL DRAW",
		"skill": 1,
		"tuning": {"aim_jitter": 1.4, "moves_searched": 3, "think_min": 0.8, "think_max": 2.0},
		"style": {"height_weight": 90.0, "range_target": 560.0, "range_weight": 0.2,
			"power_bias": 140.0, "fire_tick_cost": 0.05},
	},
	{
		"id": "phantom", "name": "THE PHANTOM", "tagline": "STRIKES THROUGH THE SEAM",
		"skill": 2,
		"tuning": {"aim_jitter": 0.6, "moves_searched": 5, "think_min": 0.5, "think_max": 1.2},
		"style": {"seam_bias": 220.0, "jump_bias": 30.0, "safety_scale": 1.2},
	},
]


static func count() -> int:
	return LADDER.size()


static func valid(rung: int) -> bool:
	return rung >= 0 and rung < LADDER.size()


static func rung(index: int) -> Dictionary:
	return LADDER[clampi(index, 0, LADDER.size() - 1)]


static func display_name(index: int) -> String:
	return str(rung(index)["name"])


static func tagline(index: int) -> String:
	return str(rung(index)["tagline"])


static func skill(index: int) -> int:
	return int(rung(index)["skill"])


static func tuning(index: int) -> Dictionary:
	return rung(index)["tuning"]


## The rung's weights over the neutral defaults, so the planner never has to
## check for a missing key.
static func style(index: int) -> Dictionary:
	var out := NEUTRAL_STYLE.duplicate()
	if valid(index):
		for key in rung(index)["style"]:
			out[key] = rung(index)["style"][key]
	return out


static func neutral_style() -> Dictionary:
	return NEUTRAL_STYLE.duplicate()


## "OPPONENT 2 / 5" for banners and the result screen.
static func position_label(index: int) -> String:
	return "OPPONENT %d / %d" % [clampi(index, 0, LADDER.size() - 1) + 1, LADDER.size()]
