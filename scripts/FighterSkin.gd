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
@export var sprite_texture_filter: CanvasItem.TextureFilter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
@export var ghost_texture: Texture2D
@export var ghost_atlases: Dictionary = {}
@export var portrait: Texture2D
@export var palette: Dictionary = {}
@export var visual_bounds := Rect2(-32.0, -68.0, 64.0, 92.0)
@export var attachments: Dictionary = {
	&"shoulder": Vector2(0.0, -6.0),
	&"muzzle_distance": 22.0,
}
@export var silhouette: Dictionary = {}
@export_range(1, 60, 1) var ticks_per_frame: int = 5
@export var state_ticks_per_frame: Dictionary = {}
## Authored wind-up frames precede the simulation launch. Other skins start at 0.
@export var shot_release_frame: int = 0
@export var procedural_aim_arm_enabled: bool = true
## Positive values select authored launch/apex and descent/brace poses by speed.
## Zero keeps the existing looping animation for other skins.
@export var air_pose_speed_threshold: float = 0.0


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

const ANIMATED_EXECUTOR_PATHS := {
	&"IDLE": "res://assets/art/fighters/duelist-polished-v2/idle.png",
	&"WALK": "res://assets/art/fighters/duelist-polished-v2/walk.png",
	&"RUN": "res://assets/art/fighters/duelist-polished-v2/run.png",
	&"RISE": "res://assets/art/fighters/duelist-polished-v2/rise.png",
	&"FALL": "res://assets/art/fighters/duelist-polished-v2/fall.png",
	&"SHOT": "res://assets/art/fighters/duelist-polished-v2/shoot.png",
	&"LOCK": "res://assets/art/fighters/duelist-polished-v2/lock.png",
	&"DEFEAT": "res://assets/art/fighters/duelist-polished-v2/defeat.png",
}

const ANIMATED_COUNTS := {
	&"IDLE": 4,
	&"WALK": 6,
	&"RUN": 6,
	&"RISE": 2,
	&"FALL": 2,
	&"SHOT": 4,
	&"LOCK": 2,
	&"DEFEAT": 4,
}

const ANIMATED_EXECUTOR_GHOST_PATHS := {
	&"IDLE": "res://assets/art/fighters/duelist-polished-v2/ghost-idle.png",
	&"WALK": "res://assets/art/fighters/duelist-polished-v2/ghost-walk.png",
	&"RUN": "res://assets/art/fighters/duelist-polished-v2/ghost-run.png",
	&"RISE": "res://assets/art/fighters/duelist-polished-v2/ghost-rise.png",
	&"FALL": "res://assets/art/fighters/duelist-polished-v2/ghost-fall.png",
	&"SHOT": "res://assets/art/fighters/duelist-polished-v2/ghost-shoot.png",
	&"LOCK": "res://assets/art/fighters/duelist-polished-v2/ghost-lock.png",
	&"DEFEAT": "res://assets/art/fighters/duelist-polished-v2/ghost-defeat.png",
}

const ROOK_ATLAS_PATHS := {
	&"IDLE": "res://assets/art/fighters/rook-animated-v2/idle.png",
	&"WALK": "res://assets/art/fighters/rook-animated-v2/walk.png",
	&"RUN": "res://assets/art/fighters/rook-animated-v2/run.png",
	&"RISE": "res://assets/art/fighters/rook-animated-v2/rise.png",
	&"FALL": "res://assets/art/fighters/rook-animated-v2/fall.png",
	&"SHOT": "res://assets/art/fighters/rook-animated-v2/shot.png",
	&"LOCK": "res://assets/art/fighters/rook-animated-v2/lock.png",
	&"DEFEAT": "res://assets/art/fighters/rook-animated-v2/defeat.png",
}

const ROOK_GHOST_PATHS := {
	&"IDLE": "res://assets/art/fighters/rook-animated-v2/ghost-idle.png",
	&"WALK": "res://assets/art/fighters/rook-animated-v2/ghost-walk.png",
	&"RUN": "res://assets/art/fighters/rook-animated-v2/ghost-run.png",
	&"RISE": "res://assets/art/fighters/rook-animated-v2/ghost-rise.png",
	&"FALL": "res://assets/art/fighters/rook-animated-v2/ghost-fall.png",
	&"SHOT": "res://assets/art/fighters/rook-animated-v2/ghost-shot.png",
	&"LOCK": "res://assets/art/fighters/rook-animated-v2/ghost-lock.png",
	&"DEFEAT": "res://assets/art/fighters/rook-animated-v2/ghost-defeat.png",
}

const PULSE_ATLAS_PATHS := {
	&"IDLE": "res://assets/art/fighters/pulse-animated-v2/idle.png",
	&"WALK": "res://assets/art/fighters/pulse-animated-v2/walk.png",
	&"RUN": "res://assets/art/fighters/pulse-animated-v2/run.png",
	&"RISE": "res://assets/art/fighters/pulse-animated-v2/rise.png",
	&"FALL": "res://assets/art/fighters/pulse-animated-v2/fall.png",
	&"SHOT": "res://assets/art/fighters/pulse-animated-v2/shot.png",
	&"LOCK": "res://assets/art/fighters/pulse-animated-v2/lock.png",
	&"DEFEAT": "res://assets/art/fighters/pulse-animated-v2/defeat.png",
}

const PULSE_GHOST_PATHS := {
	&"IDLE": "res://assets/art/fighters/pulse-animated-v2/ghost-idle.png",
	&"WALK": "res://assets/art/fighters/pulse-animated-v2/ghost-walk.png",
	&"RUN": "res://assets/art/fighters/pulse-animated-v2/ghost-run.png",
	&"RISE": "res://assets/art/fighters/pulse-animated-v2/ghost-rise.png",
	&"FALL": "res://assets/art/fighters/pulse-animated-v2/ghost-fall.png",
	&"SHOT": "res://assets/art/fighters/pulse-animated-v2/ghost-shot.png",
	&"LOCK": "res://assets/art/fighters/pulse-animated-v2/ghost-lock.png",
	&"DEFEAT": "res://assets/art/fighters/pulse-animated-v2/ghost-defeat.png",
}

const ECLIPSE_ATLAS_PATHS := {
	&"IDLE": "res://assets/art/fighters/eclipse-animated-v1/idle.png",
	&"WALK": "res://assets/art/fighters/eclipse-animated-v1/walk.png",
	&"RUN": "res://assets/art/fighters/eclipse-animated-v1/run.png",
	&"RISE": "res://assets/art/fighters/eclipse-animated-v1/rise.png",
	&"FALL": "res://assets/art/fighters/eclipse-animated-v1/fall.png",
	&"SHOT": "res://assets/art/fighters/eclipse-animated-v1/shot.png",
	&"LOCK": "res://assets/art/fighters/eclipse-animated-v1/lock.png",
	&"DEFEAT": "res://assets/art/fighters/eclipse-animated-v1/defeat.png",
}

const ECLIPSE_GHOST_PATHS := {
	&"IDLE": "res://assets/art/fighters/eclipse-animated-v1/ghost-idle.png",
	&"WALK": "res://assets/art/fighters/eclipse-animated-v1/ghost-walk.png",
	&"RUN": "res://assets/art/fighters/eclipse-animated-v1/ghost-run.png",
	&"RISE": "res://assets/art/fighters/eclipse-animated-v1/ghost-rise.png",
	&"FALL": "res://assets/art/fighters/eclipse-animated-v1/ghost-fall.png",
	&"SHOT": "res://assets/art/fighters/eclipse-animated-v1/ghost-shot.png",
	&"LOCK": "res://assets/art/fighters/eclipse-animated-v1/ghost-lock.png",
	&"DEFEAT": "res://assets/art/fighters/eclipse-animated-v1/ghost-defeat.png",
}


const ANIMATED_FIGHTERS := {
	&"rook_animated_v2": {
		"name": "The Rook — simplified animated arena fighter",
		"atlases": ROOK_ATLAS_PATHS,
		"ghosts": ROOK_GHOST_PATHS,
		"ghost": "res://assets/art/fighters/rook-animated-v2/ghost.png",
		"palette": {
			&"body": Color("101b3d"),
			&"secondary": Color("c45128"),
			&"ink": Color("111117"),
			&"defeat": Color(0.18, 0.19, 0.26, 0.82),
		},
	},
	&"pulse_animated_v2": {
		"name": "The Pulse — simplified animated arena fighter",
		"atlases": PULSE_ATLAS_PATHS,
		"ghosts": PULSE_GHOST_PATHS,
		"ghost": "res://assets/art/fighters/pulse-animated-v2/ghost.png",
		"palette": {
			&"body": Color("c6f25b"),
			&"secondary": Color("6d3e99"),
			&"ink": Color("211426"),
			&"defeat": Color(0.13, 0.08, 0.15, 0.82),
		},
	},
	&"eclipse_animated_v1": {
		"name": "The Eclipse — simplified animated arena fighter",
		"atlases": ECLIPSE_ATLAS_PATHS,
		"ghosts": ECLIPSE_GHOST_PATHS,
		"ghost": "res://assets/art/fighters/eclipse-animated-v1/ghost.png",
		"palette": {
			&"body": Color("551d35"),
			&"secondary": Color("e8e1d4"),
			&"ink": Color("111016"),
			&"defeat": Color(0.12, 0.07, 0.10, 0.82),
		},
	},
}


static func animated_fighter(id: StringName, player_color: Color) -> FighterSkin:
	var data: Dictionary = ANIMATED_FIGHTERS[id]
	var skin := FighterSkin.new()
	skin.skin_id = id
	skin.display_name = data["name"]
	for state: StringName in data["atlases"]:
		var texture := load(data["atlases"][state]) as Texture2D
		if texture != null:
			skin.sprite_atlases[state] = texture
	skin.sprite_counts = ANIMATED_COUNTS.duplicate()
	skin.sprite_cell_size = Vector2i(384, 256)
	skin.sprite_draw_rect = Rect2(-43.5, -29.921875, 87.0, 58.0)
	skin.visual_bounds = Rect2(-43.5, -30.0, 87.0, 54.0)
	skin.ghost_texture = load(data["ghost"]) as Texture2D
	for state: StringName in data["ghosts"]:
		var texture := load(data["ghosts"][state]) as Texture2D
		if texture != null:
			skin.ghost_atlases[state] = texture
	skin.palette = data["palette"].duplicate()
	apply_player_identity(skin, player_color)
	skin.ticks_per_frame = 5
	skin.state_ticks_per_frame = {
		&"IDLE": 12, &"WALK": 6, &"RUN": 4, &"RISE": 6,
		&"FALL": 6, &"SHOT": 3, &"LOCK": 8, &"DEFEAT": 5,
	}
	skin.procedural_aim_arm_enabled = false
	return skin


func frame_count(state: StringName) -> int:
	if sprite_counts.has(state):
		return int(sprite_counts[state])
	var authored: Array = frames.get(state, [])
	return authored.size()


func has_sprite(state: StringName) -> bool:
	return sprite_atlases.has(state) and sprite_atlases[state] is Texture2D \
		and frame_count(state) > 0


func ticks_for_state(state: StringName) -> int:
	return maxi(1, int(state_ticks_per_frame.get(state, ticks_per_frame)))


func motion_frame(state: StringName, tick: int, velocity: Vector2) -> int:
	var count := frame_count(state)
	if count <= 0:
		return 0
	if air_pose_speed_threshold > 0.0:
		if state == &"RISE":
			return mini(1, count - 1) if absf(velocity.y) < air_pose_speed_threshold else 0
		if state == &"FALL":
			return mini(1, count - 1) if velocity.y >= air_pose_speed_threshold else 0
	return posmod(tick / ticks_for_state(state), count)


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


## Pre-rendered art carries one authored colour, so two players who picked the
## same fighter would be the same figure. A light wash toward the player's own
## accent separates them without repainting the art: `sprite_tint` multiplies, so
## near-white stays near-white and only the authored hues shift.
##
## The wash alone is deliberately weak — the readable signal is the label, ground
## shadow, invulnerability ring and SUPER arc, which all read `palette.body`.
const IDENTITY_WASH := 0.34


static func apply_player_identity(skin: FighterSkin, player_color: Color) -> void:
	skin.sprite_tint = Color.WHITE.lerp(player_color, IDENTITY_WASH)
	skin.palette[&"body"] = player_color


static func animated_executor_proof(player_color: Color) -> FighterSkin:
	var skin := greybox(0)
	skin.shot_release_frame = 1
	skin.air_pose_speed_threshold = 300.0
	skin.sprite_texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	skin.skin_id = &"duelist_polished_v2"
	skin.display_name = "The Duelist — polished cel animation"
	skin.sprite_atlases = {}
	for state: StringName in ANIMATED_EXECUTOR_PATHS:
		var texture := load(ANIMATED_EXECUTOR_PATHS[state]) as Texture2D
		if texture != null:
			skin.sprite_atlases[state] = texture
	skin.sprite_counts = ANIMATED_COUNTS.duplicate()
	skin.sprite_cell_size = Vector2i(384, 256)
	# The 224 px authored body height maps to the same ~51 px perceived height
	# as the accepted single-pose proof. The wider cell preserves cape and limbs.
	skin.sprite_draw_rect = Rect2(-43.5, -29.921875, 87.0, 58.0)
	skin.visual_bounds = Rect2(-43.5, -30.0, 87.0, 54.0)
	apply_player_identity(skin, player_color)
	skin.ghost_texture = load(
		"res://assets/art/fighters/duelist-polished-v2/ghost.png"
	) as Texture2D
	skin.ghost_atlases = {}
	for state: StringName in ANIMATED_EXECUTOR_GHOST_PATHS:
		var texture := load(ANIMATED_EXECUTOR_GHOST_PATHS[state]) as Texture2D
		if texture != null:
			skin.ghost_atlases[state] = texture
	skin.ticks_per_frame = 5
	skin.state_ticks_per_frame = {
		&"IDLE": 12,
		&"WALK": 6,
		&"RUN": 4,
		&"RISE": 6,
		&"FALL": 6,
		&"SHOT": 3,
		&"LOCK": 8,
		&"DEFEAT": 5,
	}
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
