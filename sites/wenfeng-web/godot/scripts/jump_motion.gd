extends RefCounted

## Orthogonal vertical motion: attack/skill state remains owned by Fighter.
## No animation, position correction, stamina or damage is performed here.
const GRAVITY = 20.0
var active = false
var airborne = false
var phase = "grounded"
var phase_time = 0.0
var flight_time = 0.0
var elapsed = 0.0
var vertical_speed = 0.0
var launch_speed = 6.8
var anticipation = 0.10
var landing_duration = 0.26
var origin_y = 0.0
var interrupted = false
var mounted = false

func begin(on_mount: bool, start_y: float) -> void:
	reset()
	mounted = on_mount
	launch_speed = 7.2 if mounted else 6.8
	anticipation = 0.14 if mounted else 0.10
	landing_duration = 0.28 if mounted else 0.26
	origin_y = start_y
	active = true
	phase = "anticipation"

func reset() -> void:
	active = false
	airborne = false
	phase = "grounded"
	phase_time = 0.0
	flight_time = 0.0
	elapsed = 0.0
	vertical_speed = 0.0
	interrupted = false

func advance(delta: float, defeated: bool) -> bool:
	if not active:
		return false
	if defeated:
		interrupted = true
		if not airborne:
			reset()
			return false
	elapsed += delta
	phase_time += delta
	if phase == "anticipation" and phase_time >= anticipation:
		airborne = true
		phase = "rising"
		phase_time = 0.0
		flight_time = 0.0
		vertical_speed = launch_speed
		return true
	if airborne:
		flight_time += delta
		vertical_speed -= GRAVITY * delta
		phase = "rising" if vertical_speed > 0.0 else "falling"
	elif phase == "landing" and phase_time >= landing_duration:
		reset()
	return false

func land(at_y: float) -> void:
	airborne = false
	phase = "landing"
	phase_time = 0.0
	vertical_speed = 0.0
	origin_y = at_y

func status(actual_y: float, can_start: bool) -> Dictionary:
	var progress = clampf(flight_time / maxf(2.0 * launch_speed / GRAVITY, 0.01), 0.0, 1.0)
	return {"active": active, "airborne": airborne, "can_jump": can_start,
		"phase": phase, "phase_time": phase_time, "flight_time": flight_time,
		"elapsed": elapsed, "flight_progress": progress, "mounted": mounted,
		"anticipation": anticipation, "landing_duration": landing_duration,
		"vertical_speed": vertical_speed, "height": maxf(0.0, actual_y - origin_y) if active else 0.0,
		"cooldown": maxf(0.0, landing_duration - phase_time) if phase == "landing" else 0.0,
		"interrupted": interrupted}
