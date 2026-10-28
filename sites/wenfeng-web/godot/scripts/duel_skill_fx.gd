extends "res://scripts/skill_fx.gd"

## Duel presentation adds readable physical motion cues to normal combat.
## Real projected weapons/cavalry/fronts belong to duel_specials.gd; their
## preparation is deliberately smaller than the released moving geometry.
var _duel_events: Dictionary = {}
var _step_clock: Dictionary = {}
const DUEL_PALETTES = {
	"zhaoyun": [Color("85c4d0"), Color("e4f0e8"), Color("406774")],
	"machao": [Color("dbac67"), Color("fff0ce"), Color("8b5636")],
	"guanyu": [Color("89b8a2"), Color("e5ebd4"), Color("426b59")],
	"zhangfei": [Color("ab9ab5"), Color("e5dfeb"), Color("65546c")],
	"lubu": [Color("cd8991"), Color("f2d7b0"), Color("824351")],
	"xuchu": [Color("c8a878"), Color("eee0c4"), Color("766047")],
}

func _palette(character: String) -> Array:
	return DUEL_PALETTES.get(character, DUEL_PALETTES.zhaoyun)

func _get_mesh(shape: String, character: String, palette: Array) -> ArrayMesh:
	# Cache the same batched geometry with Duel's restrained mineral/metal
	# palette. The shared RPG effects retain their own original colours.
	return super._get_mesh(shape, character, DUEL_PALETTES.get(character, palette))

func _take_material(shape: String) -> ShaderMaterial:
	var material = super._take_material(shape)
	if TextureLayers.supports(shape):
		material.set_shader_parameter("ribbon_width", 0.62 if TextureLayers.is_thrust(shape) else 0.70)
		material.set_shader_parameter("particle_scale", 0.68 if shape.ends_with("_prepare") else (0.72 if shape == "rpg_impact_sparks" else 0.88))
	return material

func _spawn(fighter: DuelFighter, shape: String, palette: Array, lifetime: float, hold: float,
		start_scale: Vector3, end_scale: Vector3, follow = false) -> void:
	super._spawn(fighter, shape, palette, lifetime, hold, start_scale, end_scale, follow)
	var id: int = active_effects.keys().back()
	var effect: Dictionary = active_effects[id]
	# Preparation is quiet, release has a crisp leading edge, the contact
	# layer supplies the brightness. Dust never masks the fighter's torso.
	effect["duel_opacity"] = 0.58 if shape.ends_with("_prepare") else (0.70 if TextureLayers.is_smoke(shape) else 0.85)
	if TextureLayers.ground_smoke(shape):
		effect.mesh.scale.y = 0.55

func _event(key: String) -> void:
	_duel_events[key] = int(_duel_events.get(key, 0)) + 1

func action(fighter: DuelFighter, name: String) -> void:
	if not is_instance_valid(fighter) or not fighter.is_inside_tree(): return
	var palette: Array = _palette(fighter.character_id)
	if name in ["jump", "land"]:
		_jump_feedback(fighter, name)
		_event(name)
		return
	if name in ["swing_light", "swing_heavy"]:
		var heavy = name == "swing_heavy"
		var shape = "tex_lance" if fighter.is_thrust_weapon() else "tex_blade"
		var data = fighter.attack.duplicate(true)
		data["fx_style"] = "duel_normal_heavy" if heavy else "duel_normal_light"
		var window: Vector2 = data.get("active", Vector2(0.0, 0.10))
		var remaining = maxf(0.08, window.y - fighter.action_time)
		# One narrow edge echoes the actual blade; the ordinary attack never
		# makes a fake full-radius shockwave or contact explosion on a whiff.
		_role_layer(fighter, data, "normal_release", palette, shape, clampf(remaining + 0.07, 0.14, 0.40))
		var id: int = active_effects.keys().back()
		active_effects[id]["weapon_track_until"] = remaining + 0.025
		active_effects[id]["duel_activation_delay"] = maxf(0.0, window.x - fighter.action_time - 0.015)
		active_effects[id].material.set_shader_parameter("ribbon_power", 0.66 if heavy else 0.28)
		active_effects[id].material.set_shader_parameter("effect_alpha", 0.0 if active_effects[id].duel_activation_delay > 0.0 else (0.56 if heavy else 0.28))
		active_effects[id]["duel_opacity"] = 0.56 if heavy else 0.28
		_event(name)
	elif name in ["step", "hoof", "dodge", "charge"]:
		if name in ["step", "hoof"] and fighter.has_method("is_jumping") and fighter.call("is_jumping"): return
		var owner = fighter.get_instance_id()
		var now = Time.get_ticks_msec()
		if name in ["step", "hoof"] and now - int(_step_clock.get(owner, -1000)) < 140: return
		_step_clock[owner] = now
		_spawn(fighter, "tex_step_dust", palette, 0.34 if name in ["step", "hoof"] else 0.48, 0.0,
			Vector3.ONE * (0.36 if name == "step" else 0.65), Vector3.ONE * (0.60 if name == "step" else 0.95))
		_event("ground:" + name)

func _jump_feedback(fighter: DuelFighter, name: String) -> void:
	var landing = name == "land"
	var palette: Array = _palette(fighter.character_id)
	_spawn(fighter, "tex_step_dust", palette, 0.48 if landing else 0.28, 0.0,
		Vector3.ONE * (0.62 if fighter.mounted else 0.38), Vector3.ONE * (1.10 if landing and fighter.mounted else 0.70))
	if landing and fighter.mounted:
		_spawn(fighter, "charge_pebbles", palette, 0.34, 0.0, Vector3.ONE * 0.32, Vector3.ONE * 0.42)
	# Reuse the scene's existing sound pool and mute preference. Standalone FX
	# fixtures have no audio host, so presentation tests remain self-contained.
	var host = get_parent()
	if not is_instance_valid(host): return
	for property in host.get_property_list():
		if property.name != "fx": continue
		var audio = host.get("fx")
		if is_instance_valid(audio) and audio.has_method("sound"):
			audio.call("sound", "step" if landing else "dodge", -22.0 if landing else -27.0, 0.72 if fighter.mounted else 1.05)
		break

func play_skill(fighter: DuelFighter, skill: String, stage: String) -> void:
	var profile: Dictionary = fighter.skill_profile(skill)
	var special: Variant = profile.get("special", {})
	if special is String: special = {"type": special}
	if not special is Dictionary or special.is_empty():
		super.play_skill(fighter, skill, stage)
		return
	if stage in ["cancel", "complete"]:
		super.play_skill(fighter, skill, stage)
		return
	var palette: Array = _palette(fighter.character_id)
	var type: String = special.get("type", "")
	var formation: String = special.get("formation", "")
	if stage == "start":
		_remove_followers(fighter.get_instance_id())
		# Small blade-attached motes announce preparation. The actual special
		# arrives later through a visible flight/front, never this cue's timing.
		var shape = "tex_crescent_prepare" if type == "shockwave" else ("tex_brute_prepare" if type == "returning_blade" else ("tex_tiger_prepare" if type == "cavalry" else "tex_dragon_prepare"))
		if type == "weapon_array":
			shape = {"spear_volley": "tex_dragon_prepare", "diagonal_cleave": "tex_crescent_prepare", "ground_pincer": "tex_serpent_prepare", "halberd_encircle": "tex_halberd_prepare", "returning_fan": "tex_brute_prepare"}.get(formation, "tex_dragon_prepare")
		var data = profile.duplicate(true)
		var life = clampf(float(profile.get("windup", profile.get("active", Vector2(0.4, 0.6)).x)) + 0.10, 0.20, 2.0)
		_role_layer(fighter, data, "special_prepare", palette, shape, life, Vector3.ONE * 0.75, Vector3.ONE * 0.75, true)
		_spawn(fighter, "stance_scuff", palette, 0.46, 0.0, Vector3.ONE * 0.7, Vector3.ONE)
		_event(type + ":prepare")
	elif stage == String(special.get("trigger", "release")):
		_remove_followers(fighter.get_instance_id())
		if type in ["air_slam", "roar"]:
			_spawn(fighter, "tex_step_dust", palette, 0.64, 0.0, Vector3.ONE * 0.8, Vector3.ONE * 1.5)
			_spawn(fighter, "slam_debris", palette, 0.60, 0.0, Vector3.ONE * 0.40, Vector3.ONE * 0.65)
		elif type == "cavalry":
			_spawn(fighter, "tex_step_dust", palette, 0.70, 0.0, Vector3.ONE, Vector3.ONE * 1.40)
			_spawn(fighter, "tex_step_dust", palette, 0.62, 0.14, Vector3.ONE * 0.80, Vector3.ONE * 1.25)
		elif type == "weapon_array":
			if formation in ["ground_pincer", "diagonal_cleave"]:
				_spawn(fighter, "tex_step_dust", palette, 0.58, 0.0, Vector3.ONE * 0.65, Vector3.ONE)
			elif formation == "returning_fan":
				# The thrown, current weapon supplies the spectacle; this is only
				# the feet bracing for three delayed heavy releases.
				_spawn(fighter, "stance_scuff", palette, 0.42, 0.0, Vector3.ONE * 0.65, Vector3.ONE * 0.85)
			_event("formation:" + formation)
		_event(type + ":release")

func impact(at: Vector3, outcome: String, direction = Vector3.FORWARD, strength = 1.0) -> void:
	if not is_inside_tree() or outcome in ["evade", "dead"]: return
	var precision = outcome in ["parry", "counter"]
	var heavy = outcome in ["heavy_hit", "break", "counter"]
	var tint = Color("a6d3ca") if precision else Color("e4ba7b")
	var palette: Array = [tint, Color("fff2d6"), Color("463a2c")]
	var size = clampf(strength, 0.55, 1.40)
	# The high-contrast cut is local and brief; a warm flying metal shower
	# continues after its hot core has disappeared, so impact has a clear beat.
	_world_effect(at, direction, "tex_contact_cut", palette, 0.085, Vector3.ONE * size * 0.85)
	_world_effect(at, direction, "rpg_impact_sparks", palette, 0.30 if precision else 0.22, Vector3.ONE * size * (0.88 if precision else 0.66))
	if precision or heavy:
		_world_effect(at, direction, "rpg_impact_flash", palette, 0.050, Vector3.ONE * size * 0.54)
	if heavy:
		# Metal flecks come from the blade contact. Dust belongs on the floor
		# below it; an airborne clash must not spawn a cloud in mid-air.
		_world_effect(at, direction, "contact_chips", palette, 0.34, Vector3.ONE * size * 0.55)
		if at.y < 2.4:
			_world_effect(Vector3(at.x, 0.055, at.z), direction, "tex_contact_dust", palette, 0.43, Vector3(size * 0.72, size * 0.32, size * 0.72))
	_event("impact:" + outcome)

func _process(delta: float) -> void:
	super._process(delta)
	# Ground-shaped preparation follows the actor's current launch height,
	# including mounted jumps; it is never snapped to the world's Y=0 plane.
	for effect in active_effects.values():
		if effect.follow == null or not (TextureLayers.ground_smoke(effect.shape) or effect.shape == "stance_scuff"): continue
		var owner = effect.follow.get_ref()
		if is_instance_valid(owner): effect.node.global_position.y = owner.global_position.y + 0.045

func _set_alpha(alpha: float, id: int) -> void:
	if active_effects.has(id):
		var effect: Dictionary = active_effects[id]
		var delay = float(effect.get("duel_activation_delay", -1.0))
		var activation = smoothstep(delay, delay + 0.020, float(effect.age)) if delay >= 0.0 else 1.0
		effect.material.set_shader_parameter("effect_alpha", alpha * float(effect.get("duel_opacity", 1.0)) * activation)

func clear() -> void:
	super.clear()
	_duel_events.clear()
	_step_clock.clear()

func debug_state() -> Dictionary:
	var records: Array = []
	for effect in active_effects.values():
		records.append({"shape": effect.shape, "age": effect.age, "owner": effect.owner, "stage": effect.get("emitted_stage", ""), "weapon_clip": effect.get("weapon_clip", "")})
	return {"active": active_effect_count(), "groups": records, "events": _duel_events.duplicate(), "max_layers": MAX_EFFECTS}
