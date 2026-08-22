extends Resource
class_name FighterSkin

## Cosmetic fighter data. Nothing in this resource is read by simulation,
## prediction, collision, replay capture or the online digest.

@export var skin_id: StringName = &"greybox"
@export var display_name: String = "Greybox"
@export var frames: Dictionary = {}
@export var pivots: Dictionary = {}
@export var sprite_atlases: Dictionary = {}
@export var sprite_counts: Dictionary = {}
@export var sprite_cell_size := Vector2i(256, 256)
@export var sprite_draw_rect := Rect2(-64.0, -97.0, 128.0, 128.0)
@export var sprite_tint := Color.WHITE
@export var portrait: Texture2D
@export var palette: Dictionary = {}
@export var visual_bounds := Rect2(-32.0, -68.0, 64.0, 92.0)
@export var attachments: Dictionary = {
	&"shoulder": Vector2(0.0, -6.0),
	&"muzzle_distance": 22.0,
}
@export var silhouette: Dictionary = {}
@export_range(1, 60, 1) var ticks_per_frame: int = 5
@export var procedural_aim_arm_enabled: bool = true


const EXECUTOR_ATLAS_PATHS := {
	&"IDLE": "res://assets/art/fighters/gilded-executor-prototype-v1/idle.png",
	&"RUN": "res://assets/art/fighters/gilded-executor-prototype-v1/run.png",
	&"RISE": "res://assets/art/fighters/gilded-executor-prototype-v1/rise.png",
	&"FALL": "res://assets/art/fighters/gilded-executor-prototype-v1/fall.png",
	&"SHOT": "res://assets/art/fighters/gilded-executor-prototype-v1/shoot.png",
	&"LOCK": "res://assets/art/fighters/gilded-executor-prototype-v1/lock.png",
}

const EXECUTOR_COUNTS := {
	&"IDLE": 6,
	&"RUN": 8,
	&"RISE": 4,
	&"FALL": 4,
	&"SHOT": 6,
	&"LOCK": 2,
}

const SIMPLIFIED_EXECUTOR_PATHS := {
	&"IDLE": "res://assets/art/fighters/gilded-executor-simplified-proof-v1/idle.png",
	&"RUN": "res://assets/art/fighters/gilded-executor-simplified-proof-v1/run.png",
	&"RISE": "res://assets/art/fighters/gilded-executor-simplified-proof-v1/rise.png",
	&"FALL": "res://assets/art/fighters/gilded-executor-simplified-proof-v1/rise.png",
	&"SHOT": "res://assets/art/fighters/gilded-executor-simplified-proof-v1/lock.png",
	&"LOCK": "res://assets/art/fighters/gilded-executor-simplified-proof-v1/lock.png",
}


func frame_count(state: StringName) -> int:
	if sprite_counts.has(state):
		return int(sprite_counts[state])
	var authored: Array = frames.get(state, [])
	return authored.size()


func has_sprite(state: StringName) -> bool:
	return sprite_atlases.has(state) and sprite_atlases[state] is Texture2D \
		and frame_count(state) > 0


static func executor_prototype(player_index: int) -> FighterSkin:
	var skin := greybox(player_index)
	skin.skin_id = &"gilded_executor_prototype_v1"
	skin.display_name = "The Gilded Executor — rigged prototype"
	skin.sprite_atlases = {}
	for state: StringName in EXECUTOR_ATLAS_PATHS:
		var texture := load(EXECUTOR_ATLAS_PATHS[state]) as Texture2D
		if texture != null:
			skin.sprite_atlases[state] = texture
	skin.sprite_counts = EXECUTOR_COUNTS.duplicate()
	skin.sprite_cell_size = Vector2i(256, 256)
	skin.sprite_draw_rect = Rect2(-64.0, -97.0, 128.0, 128.0)
	skin.sprite_tint = Color.WHITE if player_index % 2 == 0 else Color(0.82, 0.74, 1.0)
	skin.visual_bounds = Rect2(-64.0, -97.0, 128.0, 128.0)
	skin.ticks_per_frame = 5
	return skin


static func simplified_executor_proof() -> FighterSkin:
	var skin := greybox(0)
	skin.skin_id = &"gilded_executor_simplified_proof_v1"
	skin.display_name = "The Gilded Executor — simplified arena proof"
	skin.sprite_atlases = {}
	for state: StringName in SIMPLIFIED_EXECUTOR_PATHS:
		var texture := load(SIMPLIFIED_EXECUTOR_PATHS[state]) as Texture2D
		if texture != null:
			skin.sprite_atlases[state] = texture
	skin.sprite_counts = {
		&"IDLE": 1, &"RUN": 1, &"RISE": 1,
		&"FALL": 1, &"SHOT": 1, &"LOCK": 1,
	}
	skin.sprite_cell_size = Vector2i(256, 256)
	skin.sprite_draw_rect = Rect2(-64.0, -104.0, 128.0, 128.0)
	skin.sprite_tint = Color.WHITE
	skin.visual_bounds = Rect2(-64.0, -104.0, 128.0, 128.0)
	skin.ticks_per_frame = 5
	# The proof sprites still contain both arms. A layered aim arm belongs to the
	# eventual production atlas; drawing the technical overlay now makes three.
	skin.procedural_aim_arm_enabled = false
	return skin


## Gate 1 keeps the proof self-contained and cheap. These dictionaries are the
## temporary authored "frames"; replacing them with imported sprite metadata
## later does not require changing FighterVisual's observer contract.
static func greybox(player_index: int) -> FighterSkin:
	var skin := FighterSkin.new()
	var executor := player_index % 2 == 0
	skin.skin_id = &"greybox_executor" if executor else &"greybox_witness"
	skin.display_name = "The Gilded Executor — greybox" if executor \
		else "The Violet Witness — greybox"
	skin.palette = {
		&"body": Color(0.92, 0.72, 0.24) if executor else Color(0.62, 0.38, 0.94),
		&"secondary": Color(0.52, 0.30, 0.08) if executor else Color(0.18, 0.80, 0.88),
		&"ink": Color(0.025, 0.025, 0.04),
		&"defeat": Color(0.30, 0.30, 0.34, 0.78),
	}
	skin.silhouette = {
		&"profile": &"EXECUTOR" if executor else &"WITNESS",
		&"shoulder_width": 25.0 if executor else 17.0,
		&"waist_width": 9.0 if executor else 7.0,
		&"head_radius": 8.5 if executor else 7.5,
	}
	skin.pivots = {
		&"IDLE": Vector2(0.0, 24.0),
		&"RUN": Vector2(0.0, 24.0),
		&"RISE": Vector2(0.0, 24.0),
		&"FALL": Vector2(0.0, 24.0),
		&"LOCK": Vector2(0.0, 24.0),
		&"DEFEAT": Vector2(0.0, 24.0),
	}
	skin.frames = {
		&"IDLE": [
			{&"bob": 0.0, &"lean": -1.0, &"stride": 0.0, &"coat": -1.0},
			{&"bob": 1.0, &"lean": 0.0, &"stride": 0.0, &"coat": 1.0},
		],
		&"RUN": [
			{&"bob": 0.0, &"lean": 4.0, &"stride": -13.0, &"coat": -5.0},
			{&"bob": 2.0, &"lean": 5.0, &"stride": -5.0, &"coat": -2.0},
			{&"bob": 0.0, &"lean": 4.0, &"stride": 13.0, &"coat": 5.0},
			{&"bob": 2.0, &"lean": 5.0, &"stride": 5.0, &"coat": 2.0},
		],
		&"RISE": [
			{&"bob": -2.0, &"lean": 2.0, &"stride": 7.0, &"coat": -7.0},
		],
		&"FALL": [
			{&"bob": 1.0, &"lean": -2.0, &"stride": -8.0, &"coat": 7.0},
		],
		&"LOCK": [
			{&"bob": -2.0, &"lean": -6.0, &"stride": 8.0, &"coat": 9.0},
		],
		&"DEFEAT": [
			{&"bob": 15.0, &"lean": -18.0, &"stride": 18.0, &"coat": 4.0},
		],
	}
	return skin
