extends SceneTree

## Independent acceptance of the real role/action -> physical hit -> FX chain.
## Import assets first, then run:
## Godot --headless --path . --script res://tools/role_fx_test.gd -- --rpg-test
## --rpg-test prevents the RPG scene from reading or writing a player's save.
## This fixture never calls play_skill(), an FX emitter, an action update, an
## animation seek, or a SkeletonModifier callback to manufacture a passing hit.

const ROLES = ["zhaoyun", "machao", "guanyu", "zhangfei", "lubu", "xuchu"]
const SKILLS = ["rush", "counter", "ultimate"]
const Roster = preload("res://scripts/roster.gd")
const MAX_LAYERS = 24
const TIP_TOLERANCE_M = 0.02
const OUTPUT = "res://qa/role-fx-results.json"

# Authored acceptance criteria are deliberately independent of presentation_profile
# and its shape classifier. A regression in either cannot change this expectation.
const EXPECTED = {
	"zhaoyun": {
		"rush": [["dragon_double", "line", "DragonNeedle"], ["dragon_double", "line", "DragonLow"]],
		"counter": [["dragon_slip", "line", "DragonHigh"]],
		"ultimate": [["dragon_flurry", "line", "DragonNeedle"], ["dragon_flurry", "line", "DragonLow"], ["dragon_flurry", "line", "DragonHigh"], ["dragon_flurry", "line", "DragonNeedle"], ["dragon_flurry", "line", "DragonLow"]]},
	"machao": {
		"rush": [["tiger_couch", "line", "TigerCouch"]],
		"counter": [["tiger_charge", "line", "TigerDrive"]],
		"ultimate": [["tiger_breakthrough", "line", "TigerCommit"]]},
	"guanyu": {
		"rush": [["crescent_low", "sector", "CrescentLow"]],
		"counter": [["crescent_draw", "sector", "CrescentReturn"]],
		"ultimate": [["crescent_split", "sector", "CrescentSplit"], ["crescent_orbit", "radial", "CrescentOrbit"]]},
	"zhangfei": {
		"rush": [["serpent_brace", "line", "SerpentRoot"]],
		"counter": [["serpent_roar", "radial", "SerpentVoice"]],
		"ultimate": [["serpent_shock", "radial", "SerpentVoice"], ["serpent_anchor", "line", "SerpentLong"]]},
	"lubu": {
		"rush": [["halberd_rise", "sector", "HalberdRise"]],
		"counter": [["halberd_orbit", "sector", "HalberdWheel"]],
		"ultimate": [["halberd_lift", "sector", "HalberdRise"], ["halberd_spin", "radial", "HalberdWheel"], ["halberd_drop", "sector", "HalberdDrop"]]},
	"xuchu": {
		"rush": [["brute_close", "sector", "BruteShoulder"]],
		"counter": [["brute_rebuke", "sector", "BruteRebuke"]],
		"ultimate": [["brute_impact", "radial", "BruteExecution"]]}}

class FinalSampler:
	extends Node
	signal sample_finished
	var observe: Callable
	func _process(_delta: float) -> void:
		# Ask the real rendering server to run its pre-draw synchronisation. In
		# headless mode there is no screenshot or viewport readback requirement.
		# This is also the production FX's normal final-pose refresh, not a call
		# to an FX helper from this test.
		RenderingServer.force_draw(false, 0.0)
		observe.call("post_process")
		sample_finished.emit()

var game: Node3D
var sampler: FinalSampler
var current: Dictionary = {}
var cases: Array = []
var checks: Array = []
var failures: Array[String] = []
var seen_effects: Dictionary = {}
var layer_to_hit: Dictionary = {}
var final_bone_events = 0
var frame_pre_draw_events = 0
var last_bone_frame = -1
var last_final_tip = Vector3.ZERO
var last_final_clip = ""
var peak_layers = 0
var peak_material_pool = 0
var budget_valid = true
var endpoint_max_error = 0.0
var started_ms = 0

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, detail: Variant = null) -> void:
	checks.append({"name": label, "passed": passed, "detail": detail})
	if not passed:
		failures.append(label)
		print("FAIL ", label, " ", detail if detail != null else "")

func frames(count: int) -> void:
	for index in count:
		await physics_frame
		await sampler.sample_finished

func vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func own_layers(fighter: Node, following_only = false) -> Array:
	var result: Array = []
	for id in game.skill_fx.active_effects:
		var effect: Dictionary = game.skill_fx.active_effects[id]
		if int(effect.owner) == fighter.get_instance_id() and (not following_only or effect.follow != null):
			result.append(id)
	return result

func observe_budget() -> void:
	if not is_instance_valid(game) or not is_instance_valid(game.skill_fx):
		return
	var count: int = game.skill_fx.active_effects.size()
	peak_layers = maxi(peak_layers, count)
	budget_valid = budget_valid and count <= MAX_LAYERS
	for pool in [game.skill_fx._material_pool, game.skill_fx._dust_material_pool, game.skill_fx._texture_material_pool]:
		peak_material_pool = maxi(peak_material_pool, pool.size())
		budget_valid = budget_valid and pool.size() <= MAX_LAYERS
	if not current.is_empty():
		current["peak_layers"] = maxi(int(current.peak_layers), count)

func final_skeleton() -> void:
	if current.is_empty() or not is_instance_valid(game.player):
		return
	# This signal is emitted after the actual SkeletonModifier stack. Read the
	# weapon attached to that pose, rather than trusting FX's cached blade_tip.
	final_bone_events += 1
	last_bone_frame = int(Engine.get_process_frames())
	last_final_tip = game.player.blade_tip()
	last_final_clip = game.player.current_clip
	current["bone_events"] = int(current.bone_events) + 1
	if game.player.skill_hit_index >= 0 and current.hits.has(game.player.skill_hit_index):
		var hit: Dictionary = current.hits[game.player.skill_hit_index]
		hit["final_bone_events"] = int(hit.final_bone_events) + 1
		hit["final_bone_tip"] = vector(last_final_tip)
		hit["final_bone_clip"] = last_final_clip

func pre_draw() -> void:
	frame_pre_draw_events += 1
	# Connected after the scene's own FX pre-draw listener, so the production
	# refresh has already consumed the final animation/modifier result.
	sample_live_endpoints("frame_pre_draw")

func sample_live_endpoints(source: String) -> void:
	observe_budget()
	if current.is_empty() or not is_instance_valid(game.player) or paused:
		return
	for id in game.skill_fx.active_effects:
		var effect: Dictionary = game.skill_fx.active_effects[id]
		if not effect.has("weapon_track") or not layer_to_hit.has(id) or float(effect.age) > float(effect.get("weapon_track_until", 0.08)):
			continue
		if game.player.current_clip != effect.get("weapon_clip", "") or game.player.skill_hit_index != int(effect.get("weapon_hit_index", -1)):
			continue
		var hit: Dictionary = layer_to_hit[id]
		if int(hit.final_bone_events) <= 0 or not is_instance_valid(effect.node):
			continue
		# Re-read the actual weapon world point after the final skeleton event;
		# comparing visual_blade_tip only with effect.blade_tip would be tautological.
		var physical_tip: Vector3 = game.player.blade_tip()
		var presented_tip: Vector3 = effect.get("visual_blade_tip", Vector3(INF, INF, INF))
		var error = physical_tip.distance_to(presented_tip)
		hit["endpoint_samples"] = int(hit.endpoint_samples) + 1
		hit["max_tip_error_m"] = maxf(float(hit.max_tip_error_m), error)
		endpoint_max_error = maxf(endpoint_max_error, error)
		hit["last_anchor_sample"] = {"source": source, "clip": game.player.current_clip,
			"action_time": game.player.action_time, "effect_age": effect.age, "track_until": effect.get("weapon_track_until", 0.08),
			"bone_frame": last_bone_frame, "sample_frame": Engine.get_process_frames(),
			"physical_tip": vector(physical_tip), "visual_tip": vector(presented_tip),
			"final_bone_tip": vector(last_final_tip)}

func current_expected() -> Array:
	return EXPECTED[String(current.identity)][String(current.skill)]

func on_skill(fighter: Node3D, id: String, stage: String) -> void:
	if current.is_empty() or fighter != game.player or id != current.skill:
		return
	current.stages.append({"stage": stage, "time": fighter.action_time, "clip": fighter.current_clip})
	observe_budget()
	if stage == "complete":
		current["complete_count"] = int(current.complete_count) + 1
		current["complete_followers"] = own_layers(fighter, true).size()
		return
	if stage == "cancel":
		current["cancel_count"] = int(current.cancel_count) + 1
		current["cancel_owned"] = own_layers(fighter).size()
		return
	var fresh: Array = []
	for effect_id in game.skill_fx.active_effects:
		var effect: Dictionary = game.skill_fx.active_effects[effect_id]
		if int(effect.owner) == fighter.get_instance_id() and not seen_effects.has(effect_id):
			fresh.append(effect_id)
			seen_effects[effect_id] = true
	if stage not in ["release", "strike", "finish"] or (id == "ultimate" and stage == "release"):
		return
	var index: int = fighter.skill_hit_index
	if current.hits.has(index):
		current.duplicate_hit_events.append(index)
		return
	var row = {"index": index, "stage": stage, "time": fighter.action_time,
		"clip": fighter.current_clip, "layers": [], "stroke_ids": [],
		"physical_callbacks": 0, "physical_payload": {}, "final_bone_events": 0,
		"endpoint_samples": 0, "max_tip_error_m": 0.0, "texture_layers": 0}
	for effect_id in fresh:
		var effect: Dictionary = game.skill_fx.active_effects[effect_id]
		var material: ShaderMaterial = effect.material
		var layer = {"shape": effect.shape, "style": effect.get("fx_style", ""),
			"contact_shape": effect.get("contact_shape", ""), "stage": effect.get("emitted_stage", ""),
			"ribbon_kind": material.get_shader_parameter("ribbon_kind")}
		row.layers.append(layer)
		if material.get_shader_parameter("sprite_texture") is Texture2D:
			row["texture_layers"] = int(row.texture_layers) + 1
		if effect.has("weapon_track"):
			row.stroke_ids.append(effect_id)
			layer_to_hit[effect_id] = row
	current.hits[index] = row

func on_strike(fighter: Node3D, payload: Dictionary) -> void:
	if current.is_empty() or fighter != game.player or fighter.skill_id != current.skill:
		return
	var index: int = fighter.skill_hit_index
	if not current.hits.has(index):
		current.unannounced_physical_hits.append({"index": index, "time": fighter.action_time})
		return
	var hit: Dictionary = current.hits[index]
	hit["physical_callbacks"] = int(hit.physical_callbacks) + 1
	if hit.physical_payload.is_empty():
		var window: Vector2 = payload.get("active", Vector2.ZERO)
		hit["physical_payload"] = {"shape": payload.get("shape", ""), "style": payload.get("fx_style", ""),
			"reach": payload.get("reach", 0.0), "active": [window.x, window.y],
			"time": fighter.action_time, "clip": fighter.current_clip,
			"blade_tip": vector(fighter.blade_tip())}

func connect_observers() -> void:
	game.player.skill_triggered.connect(on_skill)
	game.player.strike_requested.connect(on_strike)
	game.player.skeleton.skeleton_updated.connect(final_skeleton)

func begin_case(label: String, identity: String, skill: String, lifecycle: String) -> void:
	current = {"label": label, "identity": identity, "skill": skill, "lifecycle": lifecycle,
		"mounted": game.player.mounted, "weapon": game.player.weapon_id,
		"hits": {}, "stages": [], "duplicate_hit_events": [], "unannounced_physical_hits": [],
		"peak_layers": 0, "complete_count": 0, "cancel_count": 0,
		"complete_followers": -1, "cancel_owned": -1, "bone_events": 0}
	seen_effects.clear()
	layer_to_hit.clear()
	last_bone_frame = -1

func reset_actor() -> void:
	current = {}
	game.player.reset_fighter()
	game.player.enabled = true
	game.player.set_physics_process(true)
	game.player.input_move = Vector3.ZERO
	game.player.energy = 100.0
	game.player.stamina = 100.0
	if game.has_method("return_to_menu"):
		game.player.position = Vector3(0, 0.015, 0)
		game.player.rotation.y = 0.0
		game.enemy.position = Vector3(0, 0.015, 7.3)
		game.enemy.rotation.y = PI
		game.enemy.enabled = false
		game.enemy.set_physics_process(false)
	else:
		game.player.position = Vector3(58, 0.06, -70)
		game.player.rotation.y = 0.0
		game.player.opponent = null

func setup_duel(role: String, mode: String) -> void:
	current = {}
	game.return_to_menu()
	game.select_combat_mode(mode)
	game.select_character(role)
	game.select_opponent("machao" if role == "zhaoyun" else "zhaoyun")
	game.select_weapon(String(Roster.weapon_choices(role)[0]))
	game.testing = true
	game.ai_enabled = false
	game.phase = "fight"
	game.round_time = 900.0
	game.set_physics_process(false)
	game.set_process(false)
	# Keep one normal game step per physics tick while shortening a full suite.
	Engine.physics_ticks_per_second = 120
	Engine.time_scale = 2.0
	reset_actor()
	connect_observers()
	await frames(4)

func request_action(id: String) -> bool:
	return game.player.request_ultimate() if id == "ultimate" else game.player.request_skill(id)

func pause_live_action(label: String) -> void:
	var ages: Dictionary = {}
	var transforms: Dictionary = {}
	var shader_times: Dictionary = {}
	for id in game.skill_fx.active_effects:
		var effect: Dictionary = game.skill_fx.active_effects[id]
		ages[id] = effect.age
		transforms[id] = effect.node.global_transform
		shader_times[id] = effect.material.get_shader_parameter("effect_time")
	var action_time: float = game.player.action_time
	var clip: String = game.player.current_clip
	var tip: Vector3 = game.player.blade_tip()
	paused = true
	for index in 8:
		await sampler.sample_finished
	var frozen = ages.size() == game.skill_fx.active_effects.size()
	for id in ages:
		if not game.skill_fx.active_effects.has(id):
			frozen = false
			continue
		var effect: Dictionary = game.skill_fx.active_effects[id]
		frozen = frozen and is_equal_approx(float(effect.age), float(ages[id]))
		frozen = frozen and Transform3D(transforms[id]).is_equal_approx(effect.node.global_transform)
		frozen = frozen and effect.material.get_shader_parameter("effect_time") == shader_times[id]
	check(label + " pause freezes live layers/shader time/transforms", not ages.is_empty() and frozen, ages.size())
	check(label + " pause freezes actual action and final weapon pose",
		is_equal_approx(game.player.action_time, action_time) and game.player.current_clip == clip and
		game.player.blade_tip().distance_to(tip) < 0.0001)
	paused = false
	current["pause_tested"] = true

func validate_hits(expected_count: int) -> void:
	var label: String = current.label
	var expected: Array = current_expected()
	check(label + " emits exactly one visual event per actual hit", current.hits.size() == expected_count and current.duplicate_hit_events.is_empty(), current.hits.keys())
	check(label + " physical hit callbacks have visual-stage partners", current.unannounced_physical_hits.is_empty(), current.unannounced_physical_hits)
	for index in expected_count:
		var prefix = label + "/hit" + str(index + 1)
		if not current.hits.has(index) or index >= expected.size():
			check(prefix + " exists", false)
			continue
		var hit: Dictionary = current.hits[index]
		var spec: Array = expected[index]
		var shape: String = spec[1]
		var expected_stage = "finish" if index == expected.size() - 1 else "strike"
		if current.skill != "ultimate" and index == 0:
			expected_stage = "release"
		check(prefix + " emits only its actual release/strike/finish beat", hit.stage == expected_stage, hit.stage)
		check(prefix + " uses actual authored clip", hit.clip == spec[2], hit.clip)
		check(prefix + " has real physical contact window", int(hit.physical_callbacks) > 0 and not hit.physical_payload.is_empty(), hit.physical_callbacks)
		if not hit.physical_payload.is_empty():
			check(prefix + " physical geometry matches role design", hit.physical_payload.shape == shape, hit.physical_payload)
			var window: Array = hit.physical_payload.active
			check(prefix + " stage occurs inside real physical active window", float(hit.time) >= float(window[0]) - 0.0001 and float(hit.time) <= float(window[1]) + 0.0001, hit.time)
		var metadata_matches = not hit.layers.is_empty()
		for layer in hit.layers:
			metadata_matches = metadata_matches and layer.style == spec[0] and layer.contact_shape == shape and layer.stage == hit.stage
		check(prefix + " emitted style/shape/stage match current physical hit", metadata_matches, hit.layers)
		check(prefix + " binds a real texture", int(hit.texture_layers) > 0, hit.texture_layers)
		check(prefix + " samples real final skeleton events", int(hit.final_bone_events) > 0, hit.final_bone_events)
		var is_voice = String(spec[0]) in ["serpent_roar", "serpent_shock"]
		var strokes_match = true
		var voice_seen = false
		for layer in hit.layers:
			voice_seen = voice_seen or layer.shape == "tex_serpent_roar"
			if layer.shape == "rpg_lance" or layer.shape == "forward_thrust":
				strokes_match = false
		for id in hit.stroke_ids:
			for layer in hit.layers:
				if layer.ribbon_kind != null and String(layer.shape).begins_with("tex_") and not String(layer.shape).ends_with("pressure") and not String(layer.shape).ends_with("dust") and not String(layer.shape).ends_with("mist"):
					strokes_match = strokes_match and int(layer.ribbon_kind) == (1 if shape == "line" else 0)
		check(prefix + " cut/line/voice presentation follows actual geometry", strokes_match and (voice_seen if is_voice else not hit.stroke_ids.is_empty()), hit.stroke_ids.size())
		if is_voice:
			check(prefix + " voice does not fabricate a blade stroke", hit.stroke_ids.is_empty())
		else:
			check(prefix + " final-pose blade endpoint stays within 2cm", int(hit.endpoint_samples) > 0 and float(hit.max_tip_error_m) <= TIP_TOLERANCE_M,
				{"samples": hit.endpoint_samples, "max_error_m": hit.max_tip_error_m, "last": hit.get("last_anchor_sample", {})})

func action_case(identity: String, skill: String, prefix: String) -> void:
	reset_actor()
	await frames(3)
	var label = prefix + "/" + skill
	begin_case(label, identity, skill, "complete")
	var accepted = request_action(skill)
	check(label + " accepts a real input request", accepted)
	if not accepted:
		cases.append(current.duplicate(true))
		return
	var pause_done = false
	var settled = false
	for index in 360:
		await frames(1)
		if not pause_done and not current.hits.is_empty():
			await pause_live_action(label)
			pause_done = true
		if game.player.state not in ["skill", "ultimate"]:
			settled = true
			break
	check(label + " action naturally recovers", settled and game.player.state == "idle", game.player.state)
	validate_hits(current_expected().size())
	check(label + " natural recovery emits complete exactly once", current.complete_count == 1 and current.cancel_count == 0, current.stages)
	check(label + " complete removes attached preparation", current.complete_followers == 0, current.complete_followers)
	check(label + " pause was exercised while actual effects were live", pause_done)
	await frames(90)
	check(label + " released layers naturally expire without clear", game.skill_fx.active_effects.is_empty(), game.skill_fx.active_effects.size())
	cases.append(current.duplicate(true))
	print("ROLE_FX ", label, " hits=", current.hits.size(), " layers<=", current.peak_layers)
	current = {}

func cancellation_case(identity: String, skill: String, prefix: String) -> void:
	reset_actor()
	await frames(3)
	var label = prefix + "/" + skill + "/reset-interrupt"
	begin_case(label, identity, skill, "cancel")
	check(label + " accepts real action before interruption", request_action(skill))
	for index in 300:
		await frames(1)
		if not current.hits.is_empty():
			break
	var released = own_layers(game.player).size()
	check(label + " has genuinely released owner layers", released > 0 and not current.hits.is_empty(), released)
	# This is the production reset/interruption entry point. Its genuine
	# skill_triggered(cancel) must reclaim released as well as following layers.
	game.player.reset_fighter()
	check(label + " emits real cancel and reclaims every owned layer", current.cancel_count == 1 and current.cancel_owned == 0 and own_layers(game.player).is_empty(), current.stages)
	check(label + " does not mislabel interruption as complete", current.complete_count == 0)
	await frames(20)
	check(label + " cancelled layers cannot reappear", own_layers(game.player).is_empty())
	cases.append(current.duplicate(true))
	current = {}

func dispose_game() -> void:
	current = {}
	layer_to_hit.clear()
	if is_instance_valid(game):
		game.queue_free()
	game = null
	current_scene = null
	await frames(3)

func rpg_cases() -> void:
	await dispose_game()
	game = load("res://rpg.tscn").instantiate()
	root.add_child(game)
	# The replacement scene has just registered its own pre-draw callback.
	# Preserve production-refresh-before-observer ordering in this scene too.
	RenderingServer.frame_pre_draw.disconnect(pre_draw)
	RenderingServer.frame_pre_draw.connect(pre_draw)
	game.testing = true
	game.set_physics_process(false)
	game.set_process(false)
	game.phase = "explore"
	game.dialogue.clear()
	game.fx.muted = true
	for actor in game.enemies.values():
		actor.enabled = false
		actor.set_physics_process(false)
	connect_observers()
	for weapon in ["guandao", "halberd"]:
		reset_actor()
		check("RPG equips actual " + weapon + " model", game.player.equip_weapon(weapon) and game.player.weapon_id == weapon)
		var identity = "guanyu" if weapon == "guandao" else "lubu"
		await action_case(identity, "ultimate", "rpg/mounted/zhaoyun/" + weapon)
		await cancellation_case(identity, "ultimate", "rpg/mounted/zhaoyun/" + weapon)
	check("RPG equipment ultimates retain the shared 24-layer limit", budget_valid)

func run() -> void:
	started_ms = Time.get_ticks_msec()
	# Never auto-start main.gd's older integration tests in this standalone suite.
	for flag in ["--test", "--skills-test", "--role-test"]:
		if flag in OS.get_cmdline_user_args():
			push_error("Run role_fx_test without " + flag + "; use only --rpg-test")
			quit(2)
			return
	if "--rpg-test" not in OS.get_cmdline_user_args():
		push_error("Add -- --rpg-test so the real RPG scene cannot read a user's save")
		quit(2)
		return
	Engine.physics_ticks_per_second = 120
	Engine.time_scale = 2.0
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.testing = true
	game.fx.muted = true
	game.set_physics_process(false)
	game.set_process(false)
	sampler = FinalSampler.new()
	sampler.name = "RoleFXFinalObserver"
	sampler.process_priority = 100000
	sampler.process_mode = Node.PROCESS_MODE_ALWAYS
	sampler.observe = sample_live_endpoints
	root.add_child(sampler)
	RenderingServer.frame_pre_draw.connect(pre_draw)
	for role in ROLES:
		for mode in ["foot", "mounted"]:
			await setup_duel(role, mode)
			for skill in SKILLS:
				await action_case(role, skill, "duel/" + mode + "/" + role)
				await cancellation_case(role, skill, "duel/" + mode + "/" + role)
	await rpg_cases()
	check("all real scenarios respect the 24-mesh/material-pool budget", budget_valid and peak_layers > 0, {"peak_layers": peak_layers, "peak_pool": peak_material_pool})
	check("the suite received actual final skeleton events", final_bone_events > 0, final_bone_events)
	var result = {"passed": failures.is_empty(), "checks": checks.size(), "failures": failures,
		"cases": cases, "results": checks, "peak_layers": peak_layers, "peak_material_pool": peak_material_pool,
		"endpoint_max_error_m": endpoint_max_error, "final_skeleton_events": final_bone_events,
		"frame_pre_draw_events": frame_pre_draw_events, "elapsed_seconds": (Time.get_ticks_msec() - started_ms) / 1000.0,
		"method": "real requests, real skill/strike signals, final skeleton events, production pre-draw refresh; no fabricated FX stages"}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://qa"))
	var file = FileAccess.open(OUTPUT, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write " + OUTPUT)
		quit(2)
		return
	file.store_string(JSON.stringify(result, "\t") + "\n")
	file.close()
	print("ROLE_FX_RESULT ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks.size(), " cases=", cases.size(), " peak=", peak_layers,
		" endpoint_m=", endpoint_max_error, " output=", ProjectSettings.globalize_path(OUTPUT))
	await dispose_game()
	RenderingServer.frame_pre_draw.disconnect(pre_draw)
	sampler.observe = Callable()
	sampler.queue_free()
	sampler = null
	for index in 3:
		await process_frame
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	quit(0 if failures.is_empty() else 1)
