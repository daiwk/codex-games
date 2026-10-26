extends RefCounted

## Presentation-only wall-clock hit stop. Contacts and combat timers remain
## authoritative in the controller/fighter; this helper never causes damage.
const MAX_STOP_MS = 90
const REARM_MS = 160

var deadline = 0
var started = 0
var cooldown_until = 0
var _slow_scale = 1.0

func request(duration_ms: int, slow_scale: float) -> int:
	tick()
	if duration_ms <= 0 or not is_finite(slow_scale):
		return deadline
	var now = Time.get_ticks_msec()
	var requested_scale = clampf(slow_scale, 0.01, 1.0)
	if deadline > now:
		# A later light contact cannot shorten a heavy contact. A crowd cannot
		# extend one freeze indefinitely either: all merges share one start.
		deadline = mini(maxi(deadline, now + duration_ms), started + MAX_STOP_MS)
		_slow_scale = minf(_slow_scale, requested_scale)
		Engine.time_scale = _slow_scale
		return deadline
	if now < cooldown_until:
		return 0
	started = now
	cooldown_until = now + REARM_MS
	deadline = now + mini(duration_ms, MAX_STOP_MS)
	_slow_scale = requested_scale
	Engine.time_scale = _slow_scale
	return deadline

func tick() -> int:
	if deadline > 0 and Time.get_ticks_msec() >= deadline:
		deadline = 0
		_slow_scale = 1.0
		Engine.time_scale = 1.0
	return deadline

func reset() -> void:
	deadline = 0
	started = 0
	cooldown_until = 0
	_slow_scale = 1.0
	Engine.time_scale = 1.0
