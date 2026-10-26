extends RefCounted

## Bounded world-space recoil, added to the controller's independent camera
## base. Collision checks and the view target remain owned by the controller.
const MAX_RECOIL = 0.10
const MAX_VELOCITY = 3.6
const SPRING = 400.0
const DAMPING = 40.0
const MAX_SUBSTEP = 1.0 / 120.0

var recoil = Vector3.ZERO
var velocity = Vector3.ZERO

func kick(direction: Vector3, heavy: bool) -> void:
	if not direction.is_finite() or direction.length_squared() < 0.000001:
		return
	velocity = (velocity + direction.normalized() * (2.6 if heavy else 1.1)).limit_length(MAX_VELOCITY)

func update(delta: float) -> Vector3:
	if not is_finite(delta) or delta <= 0.0:
		return recoil
	# Small integration steps remain stable after a delayed browser frame.
	# One second already settles this critically damped spring to zero.
	var remaining = minf(delta, 1.0)
	while remaining > 0.000001:
		var step = minf(remaining, MAX_SUBSTEP)
		velocity += (-recoil * SPRING - velocity * DAMPING) * step
		recoil += velocity * step
		if recoil.length_squared() > MAX_RECOIL * MAX_RECOIL:
			recoil = recoil.limit_length(MAX_RECOIL)
			var outward = recoil.normalized()
			velocity -= outward * maxf(0.0, velocity.dot(outward))
		remaining -= step
	if recoil.length_squared() < 0.00000001 and velocity.length_squared() < 0.00000001:
		recoil = Vector3.ZERO
		velocity = Vector3.ZERO
	return recoil

func reset() -> void:
	recoil = Vector3.ZERO
	velocity = Vector3.ZERO

static func anticipation(actor: Node) -> float:
	if not is_instance_valid(actor) or actor.hp <= 0.0:
		return 0.0
	var maximum = 0.0
	var windup = 0.0
	match String(actor.state):
		"attack":
			maximum = 1.1 if bool(actor.attack.get("heavy", false)) else 0.35
			windup = float(actor.attack.get("active", Vector2.ZERO).x)
		"skill":
			maximum = 1.1
			windup = float(actor.attack.get("active", actor.skill_profile(actor.skill_id).get("active", Vector2.ZERO)).x)
		"ultimate":
			maximum = 2.6
			windup = actor.ultimate_windup()
		_:
			return 0.0
	var time = maxf(0.0, float(actor.action_time))
	if windup <= 0.0 or time >= windup:
		return 0.0
	return maximum * smoothstep(0.0, windup, time)
