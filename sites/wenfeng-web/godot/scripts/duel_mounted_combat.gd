extends RefCounted

# Duel cavalry: rein input changes a persistent gait target. Actual collision
# travel is fed back by the actor, so a blocked horse has no imaginary speed.
const TOP_SPEED = 8.2
const REVERSE_SPEED = 2.0
const ACCELERATION = 3.8
const BRAKING = 7.5
const TURN_ACCELERATION = 2.6
var speed = 0.0
var target_speed = 0.0
var turn_rate = 0.0
var throttle = 0.0
var steering = 0.0
var braking = false

func reset() -> void:
	speed = 0.0
	target_speed = 0.0
	turn_rate = 0.0
	throttle = 0.0
	steering = 0.0
	braking = false

func set_input(rein_throttle: float, rein_steer: float, hard_brake = false) -> void:
	throttle = clampf(rein_throttle, -1.0, 1.0)
	steering = clampf(rein_steer, -1.0, 1.0)
	braking = hard_brake

func maximum_turn_rate() -> float:
	return minf(lerpf(1.9, 0.62, clampf(absf(speed) / TOP_SPEED, 0.0, 1.0)), 4.8 / maxf(absf(speed), 1.0))

func steer(delta: float, incapacitated: bool) -> float:
	var desired = 0.0 if incapacitated else steering * maximum_turn_rate()
	turn_rate = move_toward(turn_rate, desired, delta * TURN_ACCELERATION)
	return turn_rate

func advance(delta: float, boost: bool, incapacitated: bool, action_target = INF) -> float:
	if braking or incapacitated:
		target_speed = move_toward(target_speed, 0.0, delta * BRAKING)
	elif boost:
		target_speed = TOP_SPEED
	elif throttle > 0.01:
		target_speed = minf(TOP_SPEED, target_speed + throttle * delta * 3.2)
	elif throttle < -0.01:
		# Opposite rein input first brakes a gallop, then backs up slowly.
		target_speed = maxf(-REVERSE_SPEED, target_speed + throttle * delta * (5.8 if target_speed > 0.0 else 1.5))
	var wanted = target_speed
	if is_finite(action_target): wanted = clampf(action_target, -REVERSE_SPEED, TOP_SPEED)
	var slowing = speed * wanted < 0.0 or absf(wanted) < absf(speed)
	var acceleration = BRAKING if slowing or braking or incapacitated else (7.5 if boost else ACCELERATION)
	speed = move_toward(speed, wanted, delta * acceleration)
	return speed

func reconcile(actual_forward_speed: float, intended_forward_speed: float) -> void:
	speed = actual_forward_speed
	if absf(intended_forward_speed) > 0.35 and absf(actual_forward_speed) < absf(intended_forward_speed) * 0.30:
		# A real wall/body stop also drops the retained gait target.
		target_speed = actual_forward_speed

static func profile(_character: String, _id: String, fallback: Dictionary) -> Dictionary:
	var result = fallback.duplicate(true)
	result["cavalry"] = true
	return result

static func normal_clip(character: String, clip: String, side: int) -> String:
	# The original diagonal cut crosses the rider's right side. The authored
	# low sweep supplies the opposite-side pass without mirroring wrists.
	if character == "guanyu" and side < 0 and clip == "Attack1": return "CrescentLow"
	return clip

static func attack_yaw(side: int, two_handed: bool) -> float:
	# A single right arm already reaches outboard; twisting the whole rider by
	# the two-hand angle carries that knife's arc past its intended pass lane.
	return deg_to_rad(45.0 if side > 0 and not two_handed else 60.0) * float(side)

static func contact_time(data: Dictionary, two_handed: bool) -> float:
	var window: Vector2 = data.active
	# The short one-hand cut crosses outboard at release; a long polearm's
	# useful pass lies later in its longer physical sweep/thrust interval.
	return (window.x + window.y) * 0.5 if two_handed else minf(window.y, window.x + 0.02)
