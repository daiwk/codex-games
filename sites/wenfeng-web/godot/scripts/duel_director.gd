extends RefCounted

# Readable pressure phrases: approach/circle, a short committed sequence, then
# reposition. The actor still owns every cost, active window and collision.
var think = 0.0
var recovery = 0.0
var circle = 1.0
var phrase_left = 0
var phrase_combo = -1
var last_state = ""
var phase = 1
var decision = "approach"
var reaction = 0.0

func reset() -> void:
	think = 0.0
	recovery = 0.0
	circle = 1.0
	phrase_left = 0
	phrase_combo = -1
	last_state = ""
	phase = 1
	reaction = 0.0
	decision = "approach"

func update(game: Node, delta: float) -> void:
	var boss: DuelFighter = game.enemy
	var player: DuelFighter = game.player
	if not is_instance_valid(boss) or not is_instance_valid(player): return
	recovery = maxf(0.0, recovery - delta)
	think -= delta
	reaction = maxf(0.0, reaction - delta)
	var next_phase = 2 if boss.hp <= 60.0 else 1
	if next_phase != phase:
		phase = next_phase
		game.toast = "对手变招 · 留意蓄势与收招空隙"
		game.toast_time = 1.8
	var offset = (player.position - boss.position).slide(Vector3.UP)
	var gap = offset.length()
	var toward = offset.normalized() if gap > 0.01 else boss.forward()
	var side = toward.cross(Vector3.UP) * circle
	boss.wants_block = false
	if boss.state in ["dead", "hit", "stagger", "dodge", "skill", "ultimate"]:
		last_state = boss.state
		return
	if last_state == "attack" and boss.state != "attack":
		recovery = game.rng.randf_range(0.20, 0.40) * (0.82 if phase == 2 else 1.0)
		phrase_left = 0
		phrase_combo = -1
	last_state = boss.state
	var incoming = player.state in ["attack", "skill", "ultimate"]
	var ranged_threat = _incoming_special(game, boss)
	if incoming and gap < 4.8:
		var aerial = player.has_method("duel_is_airborne") and bool(player.call("duel_is_airborne"))
		var can_react = player.action_time > [0.25, 0.18, 0.13][game.difficulty]
		if can_react and reaction <= 0.0 and (ranged_threat or aerial or bool(player.attack.get("heavy", false))):
			reaction = game.rng.randf_range(0.6, 0.95)
			if game.rng.randf() < [0.35, 0.65, 0.82][game.difficulty] and boss.request_dodge((side - toward * 0.25).normalized()):
				decision = "evade_pattern"
				return
		if ranged_threat or aerial:
			boss.input_move = (side - toward * 0.4).normalized()
			decision = "leave_impact_lane"
			return
	if boss.state == "attack":
		# One queued follow-up per actual contact phrase; no per-frame spam.
		if phrase_left > 0 and boss.combo != phrase_combo and boss.action_time >= float(boss.attack.active.y) + 0.025:
			if boss.request_light():
				phrase_combo = boss.combo
				phrase_left -= 1
		decision = "committed_phrase"
		return
	var preferred = 2.10 if boss.is_thrust_weapon() else (1.70 if boss.character_id == "xuchu" else 2.05)
	if boss.stamina < 24.0:
		boss.input_move = (side * 0.7 - toward * (0.8 if gap < 3.6 else 0.15)).limit_length()
		decision = "recover_spacing"
		return
	if recovery > 0.0:
		boss.input_move = (side * 0.65 - toward * (0.55 if gap < preferred - 0.25 else 0.1)).limit_length()
		decision = "reposition"
		return
	if gap > preferred + 0.2:
		boss.input_move = (toward + side * 0.2).normalized()
	else:
		boss.input_move = (side * 0.55 - toward * (0.45 if gap < preferred - 0.35 else 0.0)).limit_length()
	decision = "approach" if gap > preferred + 0.2 else "circle"
	if think > 0.0: return
	think = [0.24, 0.17, 0.12][game.difficulty]
	if game.rng.randf() < 0.07: circle *= -1.0
	if incoming and player.action_time > 0.12 and gap < 2.8 and reaction <= 0.0 and game.rng.randf() < 0.28:
		boss.wants_block = true
		reaction = 0.3
		decision = "read_guard"
		return
	if boss.skill_ready("ultimate") and gap < 9.0 and gap > 1.3:
		if boss.request_ultimate():
			decision = "signature_ultimate"
			return
	var q = boss.skill_profile("rush")
	var e = boss.skill_profile("counter")
	var special_q = q.get("special", {})
	var special_e = e.get("special", {})
	if boss.skill_ready("rush") and ((not special_q.is_empty() and gap > 2.4 and gap < 9.0) or (gap > 2.6 and gap < 4.6)) and game.rng.randf() < 0.4:
		if boss.request_skill("rush"):
			decision = "signature_pressure"
			return
	if boss.skill_ready("counter") and gap < (4.0 if not special_e.is_empty() else 2.5) and game.rng.randf() < 0.23:
		if boss.request_skill("counter"):
			decision = "signature_answer"
			return
	if gap <= (2.7 if boss.is_thrust_weapon() else boss.basic_reach()) and gap > 0.8:
		if boss.stamina > 48.0 and (player.state == "block" or game.rng.randf() < 0.18):
			if boss.request_heavy():
				decision = "heavy_commit"
				return
		if boss.request_light():
			phrase_left = 2 if phase == 2 else 1
			phrase_combo = -1
			decision = "start_phrase"

func _incoming_special(game: Node, actor: DuelFighter) -> bool:
	if not is_instance_valid(game.specials): return false
	for group in game.specials.groups.values():
		if group.target.get_ref() == actor:
			return true
	return false
