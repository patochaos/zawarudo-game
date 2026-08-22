extends RefCounted
class_name PlayerPlan

## The plan is a RECORDING, not a set of toggles. During planning the player
## pilots their ghost with free platformer controls and every tick of input is
## captured here; execution replays it verbatim.
##
## Movement is bounded by stamina, so the recording is normally shorter than the
## execution window — the remaining ticks run with no input (momentum, gravity).

var dirs: PackedByteArray = PackedByteArray()    # per tick: 0 = left, 1 = neutral, 2 = right
var jumps: PackedByteArray = PackedByteArray()   # per tick: 1 = jump impulse on this tick
## Per tick: 1 = the jump key was still down. Releasing it while still rising
## snips the climb, which is what gives a tap a short hop and a hold a full one.
var holds: PackedByteArray = PackedByteArray()
## Per tick: 1 = down+jump was pressed, dropping the body through the thin ledge
## it is standing on. A separate channel from `jumps` because it is the opposite
## verb sharing one button, and both have to replay exactly as recorded.
var drops: PackedByteArray = PackedByteArray()

var shot_tick: int = -1     # tick the arrow is loosed on; -1 = no shot this turn
var aim_angle: float = 0.0  # WORLD degrees: 0 = right, +90 = straight up
var power: float = 0.5      # 0..1, maps to arrow speed
## Grenadier-only planning choice. It persists between turns just like aim and
## power; the fuse itself advances only while GameManager simulates execution.
var grenade_fuse_seconds: int = 2
## Attack captured when the charge starts. The Shock user maps LMB/0 to the
## straight plasma lance and RMB/1 to the persistent lobbed orb. Other kits
## ignore it, which keeps their normal verb singular and immediately readable.
var attack_mode: int = 0
## A full meter plus the player's explicit SUPER toggle upgrades this shot. The
## flag is stored on the plan so rollback can change it without spending meter.
var super_shot: bool = false
## All waves in one super share a volley id, preventing the burst from striking
## itself as the staggered waves leave the player.
var super_volley: int = -1
var confirmed: bool = false


func recorded_ticks() -> int:
	return dirs.size()


func dir_at(t: int) -> int:
	return int(dirs[t]) - 1 if t >= 0 and t < dirs.size() else 0


func jump_at(t: int) -> bool:
	return t >= 0 and t < jumps.size() and jumps[t] == 1


func hold_at(t: int) -> bool:
	return t >= 0 and t < holds.size() and holds[t] == 1


func drop_at(t: int) -> bool:
	return t >= 0 and t < drops.size() and drops[t] == 1


func record(dir: int, jump: bool, hold: bool, drop: bool = false) -> void:
	dirs.append(dir + 1)
	jumps.append(1 if jump else 0)
	holds.append(1 if hold else 0)
	drops.append(1 if drop else 0)


func clear_path() -> void:
	dirs.clear()
	jumps.clear()
	holds.clear()
	drops.clear()


func has_shot() -> bool:
	return shot_tick >= 0


func aim_vector() -> Vector2:
	var r := deg_to_rad(aim_angle)
	return Vector2(cos(r), -sin(r))


## Which way the shot points horizontally: +1 right, -1 left.
func aim_side() -> int:
	return 1 if cos(deg_to_rad(aim_angle)) >= 0.0 else -1


## Flip the horizontal side without changing how high the bow is aimed.
func set_aim_side(side: int) -> void:
	var elev := elevation()
	aim_angle = elev if side >= 0 else 180.0 - elev


## Angle above the horizon, always in [-90, 90] regardless of side.
func elevation() -> float:
	return rad_to_deg(asin(sin(deg_to_rad(aim_angle))))


func set_elevation(e: float, min_elev: float, max_elev: float) -> void:
	var clamped := clampf(e, min_elev, max_elev)
	aim_angle = clamped if aim_side() > 0 else 180.0 - clamped


## Point the bow along an arbitrary vector (cursor delta, analogue stick),
## keeping the elevation inside the configured limits.
func set_aim_from_vector(v: Vector2, min_elev: float, max_elev: float) -> void:
	if v.length_squared() < 0.0001:
		return
	var side := 1 if v.x >= 0.0 else -1
	var elev := clampf(rad_to_deg(atan2(-v.y, absf(v.x))), min_elev, max_elev)
	aim_angle = elev if side > 0 else 180.0 - elev


## Nothing about the recording survives a turn; aim and power do, so the player
## does not have to rebuild the whole shot every phase.
func start_new_turn() -> void:
	clear_path()
	shot_tick = -1
	super_shot = false
	super_volley = -1
	confirmed = false


## Compact, JSON-safe lockstep payload. The server validates every byte before
## relaying it, and both clients replay exactly this same recording.
func to_network_dict() -> Dictionary:
	return {
		"dirs": Array(dirs),
		"jumps": Array(jumps),
		"holds": Array(holds),
		"drops": Array(drops),
		"shot_tick": shot_tick,
		"aim_angle": aim_angle,
		"power": power,
		"grenade_fuse_seconds": grenade_fuse_seconds,
		"attack_mode": attack_mode,
		"super_shot": super_shot,
	}


func apply_network_dict(data: Dictionary) -> void:
	dirs = PackedByteArray(data.get("dirs", []))
	jumps = PackedByteArray(data.get("jumps", []))
	holds = PackedByteArray(data.get("holds", []))
	# Builds from before ledge drops existed relay only three movement channels.
	# Treat the missing channel as "no drop" so either deployment order remains
	# compatible while the room service and web client roll over.
	if data.has("drops"):
		drops = PackedByteArray(data["drops"])
	else:
		drops = PackedByteArray()
		drops.resize(dirs.size())
		drops.fill(0)
	shot_tick = int(data.get("shot_tick", -1))
	aim_angle = float(data.get("aim_angle", 0.0))
	power = clampf(float(data.get("power", 0.5)), 0.0, 1.0)
	grenade_fuse_seconds = clampi(int(data.get("grenade_fuse_seconds", 2)), 1, 3)
	attack_mode = clampi(int(data.get("attack_mode", 0)), 0, 1)
	super_shot = bool(data.get("super_shot", false))
	super_volley = -1
	confirmed = true
