extends RefCounted
class_name Mover

## Tick-indexed motion for arena geometry and hazards.
##
## A mover's position is a pure FUNCTION of the absolute simulation tick, never
## an accumulated velocity. That is what makes planning honest: the ghost path
## can be resolved against where every platform WILL be on each tick of the
## coming window instead of against the frozen snapshot, so a plan that walks
## onto a rising ledge is a plan the player actually authored.
##
## The wave is a triangle, not a sine. Integer arithmetic only, so two browsers
## in a lockstep room cannot drift apart on a transcendental; and a constant
## speed with a hard turnaround is far easier to read out of a single stopped
## frame than an easing curve — the player can see the rail, the two ends and
## the current point, and estimate the rest.
##
## Motion dictionary:
##   axis    unit direction of travel          (Vector2)
##   travel  peak-to-peak distance in pixels   (float)
##   period  ticks for one there-and-back      (int, 60 = 1 second)
##   phase   0..1 head start along the cycle   (float)

const DEFAULT_PERIOD := 240


## Displacement from the authored home position at `abs_tick`.
static func offset(motion: Dictionary, abs_tick: int) -> Vector2:
	var period: int = maxi(2, int(motion.get("period", DEFAULT_PERIOD)))
	var lead: int = int(round(float(motion.get("phase", 0.0)) * float(period)))
	var t: int = posmod(abs_tick + lead, period)
	var half: int = period / 2
	var u: float
	if t < half:
		u = float(t) / float(half)
	else:
		u = 1.0 - float(t - half) / float(period - half)
	var axis: Vector2 = motion.get("axis", Vector2.DOWN)
	return axis * (float(motion.get("travel", 0.0)) * u)


## Both ends of the sweep, relative to home. Layout tests validate an arena at
## each of these, and the preview draws the rail between them.
static func travel_ends(motion: Dictionary) -> Array:
	var axis: Vector2 = motion.get("axis", Vector2.DOWN)
	return [Vector2.ZERO, axis * float(motion.get("travel", 0.0))]


## Fraction of the sweep covered at `abs_tick`, for HUD-free readouts like the
## rail marker. Same wave as offset(), expressed as 0..1.
static func phase_at(motion: Dictionary, abs_tick: int) -> float:
	var travel: float = float(motion.get("travel", 0.0))
	if is_zero_approx(travel):
		return 0.0
	return offset(motion, abs_tick).length() / travel
