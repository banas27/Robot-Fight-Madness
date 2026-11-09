extends "res://scripts/match.gd"
## Combat and presentation consume the same fixed-tick solver contacts.
const CombatRobot = preload("res://scripts/combat/robot.gd")
const RiptideFlank = preload("res://scripts/combat/riptide_flank.gd")
const RiptideRailExit = preload("res://scripts/combat/riptide_rail_exit.gd")
const RiptideRecoveryControl = preload("res://scripts/combat/riptide_recovery_control.gd")
const RiptideTrackedRoutes = preload("res://scripts/combat/riptide_tracked_routes.gd")
const RiptideTrackedFlank = preload("res://scripts/combat/riptide_tracked_flank.gd")
const BulldozerTrackedIntercept = preload("res://scripts/combat/bulldozer_tracked_intercept.gd")
const WeaponContact = preload("res://scripts/combat/weapon_contact.gd")
const ImpactFX = preload("res://scripts/combat/impacts.gd")
const DebugOverlay = preload("res://scripts/combat/debug_overlay.gd")
const Fit = preload("res://scripts/combat/collision_fit.gd")
const EpisodeView = preload("res://scripts/presentation/episode_view.gd")
const ContactAudit = preload("res://scripts/combat/contact_audit.gd")
const TIME_EPSILON := 0.000001

@export var bulldozer_visual_override: Script
@export var bulldozer_uses_tracks := false
var combat: Dictionary
var presentation: Dictionary
var impact_fx: ImpactFX
var overlay: DebugOverlay
var headless: bool
var camera_focus := Vector3.ZERO
var smoke_wait := [0.0, 0.0]
var bump_wait := 0.0
var clash_wait := 0.0
var debug_close := false
var previous_physics_hz := 0
var peak_weapon_depth := 0.0
var last_weapon_depth := 0.0
var deep_overlap_time := 0.0
var longest_deep_overlap := 0.0
var wall_wait := [0.0, 0.0]
var scrape_wait := [0.0, 0.0]
var world_impacts := {"bump": 0, "scrape": 0, "clash": 0, "shutdown": 0}
var peak_lift := 0.0
var lowest_root := INF
var min_detached_clearance := INF
var max_detached_tilt := 0.0
var deep_deck_run := [0, 0]
var max_deep_deck_ticks := 0
var unsupported_stall := [0.0, 0.0]
var close_run := 0.0
var longest_close_run := 0.0
var wall_bumps := 0
var perf_path := ""
var trace_path := ""
var trace
var contact_audit: ContactAudit
var frame_times: Array[float] = []
var last_frame_us := 0
const COMPONENT_NOTICES := {
	"armor_damaged": "ARMOUR DAMAGED", "wheel_damaged": "WHEEL DAMAGED", "wheel_severe": "WHEEL BADLY DAMAGED",
	"wheel_drive_failed": "WHEEL DRIVE FAILED", "wheel_detached": "WHEEL DETACHED", "weapon_disabled": "WEAPON DISABLED",
	"track_damaged": "TRACK DAMAGED", "track_severe": "TRACK BADLY DAMAGED", "track_drive_failed": "TRACK DRIVE FAILED",
	"track_detached": "TRACK THROWN", "road_wheel_damaged": "ROAD WHEEL DAMAGED",
	"road_wheel_severe": "ROAD WHEEL BADLY DAMAGED", "road_wheel_detached": "ROAD WHEEL LOST",
}
var component_events: Array[Dictionary] = []
var notice_queue: Array[Dictionary] = []
var notice_seen: Dictionary = {}
var current_notice: Dictionary = {}
var notice_time := 0.0
var final_hp: Array[float] = []
var final_ratio: Array[float] = []
var result_snapshot: Dictionary = {}
var episode_view: EpisodeView
var intro_shot_seconds: float
var combat_only := false
var swapped_start := false
var riptide_ai := "baseline"
var bulldozer_ai := "baseline"
var start_poses: Array[Array] = []
const RESULT_RATIO_TOLERANCE := 0.000001

func _ready() -> void:
	var combat_data = JSON.parse_string(FileAccess.get_file_as_string("res://config/combat.json"))
	var presentation_data = JSON.parse_string(FileAccess.get_file_as_string("res://config/presentation.json"))
	if not combat_data is Dictionary or not presentation_data is Dictionary:
		push_error("Invalid combat or presentation configuration.")
		get_tree().quit(2)
		return
	combat = combat_data
	riptide_ai = String(combat.get("riptide_ai", "baseline"))
	presentation = presentation_data
	var episode: Dictionary = presentation.episode
	intro_shot_seconds = float(episode.intro_shot_seconds)
	previous_physics_hz = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = clampi(int(combat.get("physics_hz", 180)), 60, 240)
	headless = DisplayServer.get_name() == "headless"
	combat_only = headless and "--combat-only" in OS.get_cmdline_user_args()
	swapped_start = "--swap-start" in OS.get_cmdline_user_args()
	debug_close = "--debug-close" in OS.get_cmdline_user_args()
	var audit_options := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--perf="):
			perf_path = arg.trim_prefix("--perf=")
		elif arg.begins_with("--trace="):
			trace_path = arg.trim_prefix("--trace=")
			trace = preload("res://scripts/combat/trace.gd").new()
			trace.detailed = "--contact-trace" in OS.get_cmdline_user_args()
			trace.tracked_ai = bulldozer_uses_tracks
		elif arg.begins_with("--riptide-ai="):
			riptide_ai = arg.trim_prefix("--riptide-ai=")
		elif arg.begins_with("--bulldozer-ai="):
			bulldozer_ai = arg.trim_prefix("--bulldozer-ai=")
		elif arg.begins_with("--wheel-drum-audit="):
			audit_options = arg.trim_prefix("--wheel-drum-audit=")
	if not audit_options.is_empty():
		contact_audit = ContactAudit.new()
		if trace == null or not contact_audit.configure(audit_options):
			push_error("Wheel/drum audit requires --trace and a tick,wheel-shape,drum-shape specification.")
			get_tree().quit(2)
			return
	if riptide_ai not in ["baseline", "candidate", "rail-exit", "tracked-flank", "tracked-routes", "recovery-control"]:
		push_error("Unknown Riptide AI: " + riptide_ai)
		get_tree().quit(2)
		return
	if bulldozer_ai not in ["baseline", "tracked-intercept"]:
		push_error("Unknown Bulldozer AI: " + bulldozer_ai)
		get_tree().quit(2)
		return
	if not bulldozer_uses_tracks and (riptide_ai in ["tracked-flank", "tracked-routes", "recovery-control"] or bulldozer_ai != "baseline"):
		push_error("Tracked AI policies require the functional tracked arena.")
		get_tree().quit(2)
		return
	super._ready()
	autostop = autostop or combat_only
	cfg.intro_seconds = intro_shot_seconds * 2.0
	cfg.fight_seconds = float(episode.fight_seconds)
	cfg.result_seconds = float(episode.showcase_seconds)
	for node in get_children():
		if node is CanvasLayer:
			node.get_child(0).combat_style = true
	if overlay != null and "--debug-combat" in OS.get_cmdline_user_args():
		overlay.toggle()
	if not headless:
		var studio_layer := CanvasLayer.new()
		studio_layer.layer = 3
		add_child(studio_layer)
		episode_view = EpisodeView.new()
		episode_view.match_node = self
		studio_layer.add_child(episode_view)
		episode_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _exit_tree() -> void:
	if previous_physics_hz > 0:
		Engine.physics_ticks_per_second = previous_physics_hz
	super._exit_tree()

func _build_arena() -> void:
	super._build_arena()
	var floor_material := Shapes.material(Color("455360"), 0.13)
	floor_material.roughness = 0.83
	var wall_material := Shapes.material(Color("263541"), 0.22)
	wall_material.roughness = 0.65
	var rails := Shapes.material(Color("d1a256"), 0.19)
	rails.roughness = 0.52
	var seam := Shapes.material(Color("505d69"), 0.11)
	for node in get_children():
		if node is StaticBody3D:
			node.collision_mask = Fit.BODY
			var mesh := node.get_child(0) as MeshInstance3D
			var contact_material := PhysicsMaterial.new()
			if node.position.y < 0.0:
				# Set the solver surface to the visible deck at Y = 0.
				node.position.y = -0.175
				node.collision_layer = Fit.DECK
				mesh.position.y = -0.002
				contact_material.friction = float(combat.floor_friction)
			else:
				node.collision_layer = Fit.WALL
				mesh.material_override = wall_material
				contact_material.friction = 0.22
			node.physics_material_override = contact_material
		elif node is MeshInstance3D and node.mesh is BoxMesh:
			var dims: Vector3 = node.mesh.size
			if is_equal_approx(dims.y, 0.08):
				node.material_override = floor_material
			elif is_equal_approx(dims.y, 0.008):
				node.material_override = seam
			elif is_equal_approx(dims.y, 0.045):
				node.material_override = rails
		elif node is WorldEnvironment:
			node.environment.ambient_light_color = Color("d8e3ef")
			node.environment.ambient_light_energy = 0.44
			node.environment.background_color = Color("111b28")
		elif node is DirectionalLight3D:
			if node.shadow_enabled:
				node.rotation_degrees = Vector3(-56, -31, 0)
				node.light_color = Color("fff4e7")
				node.light_energy = 0.75
				node.directional_shadow_max_distance = 36.0
			else:
				node.light_color = Color("b9d9ff")
				node.light_energy = 0.31
	camera_home = Vector3(7.2, 9.5, 16.4) if debug_close else Vector3(7.2, 13.4, 16.4)
	camera.position = camera_home
	camera.look_at(Vector3.ZERO)
	camera.size = float(presentation.camera_max_width)

func _build_bots() -> void:
	if not headless:
		overlay = DebugOverlay.new()
		add_child(overlay)
	for i in range(2):
		var bot: CombatRobot
		if i == 0 and riptide_ai == "candidate":
			bot = RiptideFlank.new()
		elif i == 0 and riptide_ai == "rail-exit":
			bot = RiptideRailExit.new()
		elif i == 0 and riptide_ai == "tracked-flank":
			bot = RiptideTrackedFlank.new()
		elif i == 0 and riptide_ai == "tracked-routes":
			bot = RiptideTrackedRoutes.new()
		elif i == 0 and riptide_ai == "recovery-control":
			bot = RiptideRecoveryControl.new()
		elif i == 1 and bulldozer_ai == "tracked-intercept":
			bot = BulldozerTrackedIntercept.new()
		else:
			bot = CombatRobot.new()
		var kind := "saw" if i == 0 else "drum"
		if kind == "drum":
			bot.visual_override = bulldozer_visual_override
			bot.tracked_drive = bulldozer_uses_tracks
		bot.configure(kind, combat, rng.randf_range(0, 6), not headless)
		bot.trace_orders = trace != null and (trace.detailed or trace.tracked_ai)
		if contact_audit != null:
			bot.audit_local_shape = contact_audit.indices[i]
			bot.audit_other_shape = contact_audit.indices[1 - i]
		add_child(bot)
		bot.position = Vector3(rng.randf_range(-0.4, 0.4), 0.4, 3.4 if i == 0 else -3.4)
		bot.rotation.y = 0.0 if i == 0 else PI
		if swapped_start:
			# Rotate both seeded poses together. Preserve the offsets, facing,
			# fighter identity and insertion order.
			bot.position = Vector3(-bot.position.x, bot.position.y, -bot.position.z)
			bot.rotate_y(PI)
		bot.freeze = true
		bot.preparing = false
		bots.append(bot)
		if overlay != null:
			overlay.add_robot(bot)
	(bots[0] as CombatRobot).opponent = bots[1]
	(bots[1] as CombatRobot).opponent = bots[0]

func _build_sound() -> void:
	if not headless:
		impact_fx = ImpactFX.new()
		add_child(impact_fx)
		impact_fx.setup(presentation, match_seed)

func _physics_process(delta: float) -> void:
	if bots.size() != 2 or finished:
		return
	elapsed += delta
	if phase == "intro":
		# Keep the same frozen tick offset in QA. Starting at the first tick
		# changes some later solver contacts even with identical spawn poses.
		if elapsed + TIME_EPSILON >= float(cfg.intro_seconds):
			elapsed = 0.0 if combat_only else float(cfg.intro_seconds)
			_start_fight()
		return
	if phase == "result":
		result_elapsed += delta
		if result_elapsed + TIME_EPSILON >= float(cfg.result_seconds):
			result_elapsed = float(cfg.result_seconds)
			elapsed = float(cfg.intro_seconds) + fight_elapsed + result_elapsed
			finished = true
			_write_report()
			if autostop:
				get_tree().quit()
		return
	_update_notice(delta)
	shake = move_toward(shake, 0.0, delta * 3.9)
	fight_elapsed = minf(fight_elapsed + delta, float(cfg.fight_seconds))
	if contact_audit != null:
		contact_audit.publish(bots, fight_elapsed)
	close_run = close_run + delta if bots[0].position.distance_to(bots[1].position) < 2.20 else 0.0
	longest_close_run = maxf(longest_close_run, close_run)
	var radius := _arena_radius()
	var probe = trace if trace != null and trace.detailed else null
	if probe != null:
		probe.contact_time = fight_elapsed
	var pair := WeaponContact.read_pair(bots, delta, probe)
	last_weapon_depth = float(pair.weapon_depth)
	if trace != null and trace.tracked_ai:
		trace.observe_tick(bots, delta, fight_elapsed, pair)
	peak_weapon_depth = maxf(peak_weapon_depth, last_weapon_depth)
	deep_overlap_time = deep_overlap_time + delta if last_weapon_depth > 0.025 else 0.0
	longest_deep_overlap = maxf(longest_deep_overlap, deep_overlap_time)
	var hits: Array[Dictionary] = pair.hits
	# Both directions are selected from the same solved step before KO.
	resolve_strikes(hits[0], hits[1])
	var weapon_hit := not hits[0].is_empty() or not hits[1].is_empty()
	clash_wait = maxf(0.0, clash_wait - delta)
	var clashed: bool = not weapon_hit and clash_wait <= 0.0 and not pair.clash.is_empty()
	if clashed:
		_weapon_clash(pair.clash)
	_solver_impacts(delta, weapon_hit or clashed)
	if bots[0].hp <= 0.0 or bots[1].hp <= 0.0:
		for bot: CombatRobot in bots:
			if bot.hp <= 0.0:
				_present({"kind": "shutdown", "point": bot.position - bot.basis.z * 0.22,
					"normal": Vector3.UP, "strength": 1.0})
		_finish("knockout")
		return
	if fight_elapsed + TIME_EPSILON >= float(cfg.fight_seconds):
		fight_elapsed = float(cfg.fight_seconds)
		_finish("time limit / health decision")
		return
	for i in range(2):
		var bot := bots[i] as CombatRobot
		peak_speed = maxf(peak_speed, bot.linear_velocity.length())
		peak_lift = maxf(peak_lift, bot.position.y - 0.40)
		lowest_root = minf(lowest_root, bot.position.y)
		if bot.detached_wheel_count > 0 or bot.track_state.has(CombatRobot.Wheel.DETACHED):
			var clearance := bot.position.y + Fit.lowest_surface_y(bot, bot.global_basis)
			min_detached_clearance = minf(min_detached_clearance, clearance)
			max_detached_tilt = maxf(max_detached_tilt, rad_to_deg(Vector3.UP.angle_to(bot.global_basis.y)))
			deep_deck_run[i] = int(deep_deck_run[i]) + 1 if clearance < -0.025 else 0
			max_deep_deck_ticks = maxi(max_deep_deck_ticks, deep_deck_run[i])
			if bot.supported_drive_grip() == 0.0 and bot.linear_velocity.slide(Vector3.UP).length() < 0.25:
				unsupported_stall[i] += delta
		max_extent = maxf(max_extent, maxf(absf(bot.position.x) / radius.x, absf(bot.position.z) / radius.y))
		bot.step(delta, radius)
		if impact_fx != null and bot.hp < bot.max_hp * 0.24:
			smoke_wait[i] = float(smoke_wait[i]) - delta
			if float(smoke_wait[i]) <= 0.0:
				impact_fx.puff(bot.to_global(Vector3(0.14, 0.29, 0.30)))
				smoke_wait[i] = 0.92 if bot.hp <= 0.0 else 0.82
	if trace != null:
		trace.tick(bots, delta, fight_elapsed, radius, true)
	if contact_audit != null:
		contact_audit.submit(bots, fight_elapsed + delta)
	if not screenshot_taken and screenshot_path != "" and fight_elapsed > 3.4 and not headless:
		screenshot_taken = true
		_save_screenshot.call_deferred()

func _arena_radius() -> Vector2:
	return Vector2(float(cfg.arena_half_width), float(cfg.arena_half_length))

func _start_fight() -> void:
	phase = "fight"
	for bot: CombatRobot in bots:
		start_poses.append([bot.position.x, bot.position.z, bot.rotation.y, bot.hp, bot.rotor_speed])
		bot.freeze = false
		bot.active = true

func _finish(reason: String) -> void:
	if phase == "result" or finished:
		return
	final_hp.assign([bots[0].hp, bots[1].hp])
	final_ratio.assign([final_hp[0] / bots[0].max_hp, final_hp[1] / bots[1].max_hp])
	super._finish(reason)
	if reason != "knockout":
		if absf(final_ratio[0] - final_ratio[1]) <= RESULT_RATIO_TOLERANCE:
			winner_name = "DRAW"
			winner_color = Color.WHITE
		else:
			var winner := bots[0] if final_ratio[0] > final_ratio[1] else bots[1]
			winner_name = String(winner.name).to_upper()
			winner_color = winner.team_color
	_capture_result()
	if trace != null:
		trace.tick(bots, 0.0, fight_elapsed, _arena_radius(), false)
	for bot: CombatRobot in bots:
		bot.stop_fighting()
		bot.rotor_speed = 0.0
	for child in get_children():
		if child is RigidBody3D:
			child.freeze = true
	current_notice = {}
	notice_queue.clear()
	notice_time = 0.0
	if combat_only:
		elapsed = fight_elapsed
		finished = true
		_write_report()
		get_tree().quit()

func _capture_result() -> void:
	var records: Array[Dictionary] = []
	var winner_index := -1
	for i in range(bots.size()):
		var bot := bots[i] as CombatRobot
		if String(bot.name).to_upper() == winner_name:
			winner_index = i
		var wheel_states := bot.wheel_state.duplicate()
		wheel_states.make_read_only()
		var wheel_bases: Array[Basis] = []
		for j in range(wheel_states.size()):
			wheel_bases.append(bot.art.wheel_pivots[j].basis if bot.art != null and wheel_states[j] != CombatRobot.Wheel.DETACHED else Basis.IDENTITY)
		wheel_bases.make_read_only()
		var weapon := "Disabled" if bot.weapon_disabled else ("Damaged" if bot.weapon_output() < 1.0 else "Operational")
		var drive := "Operational"
		var failed_tracks := bot.track_state.count(CombatRobot.Wheel.DRIVE_FAILED)
		if bot.track_state.count(CombatRobot.Wheel.DETACHED) == 2:
			drive = "Both tracks thrown"
		elif bot.track_state.has(CombatRobot.Wheel.DETACHED):
			drive = "Left track thrown" if bot.track_state[0] == CombatRobot.Wheel.DETACHED else "Right track thrown"
		elif bot.drive_grip() <= 0.0:
			drive = "Failed"
		elif failed_tracks > 0:
			drive = "Left track drive failed" if bot.track_state[0] == CombatRobot.Wheel.DRIVE_FAILED else "Right track drive failed"
		elif bot.failed_wheel_count > 0:
			drive = "Partial failure · %d/4 drives" % bot.failed_wheel_count
		elif bot.drive_grip() < 1.0:
			drive = "Damaged"
		var yaw := Vector3.FORWARD.signed_angle_to(CombatRobot.deck_forward(bot.global_basis), Vector3.UP)
		var tilt := (Basis(Vector3.UP, -yaw) * bot.global_basis).orthonormalized()
		var condition := {"name": String(bot.name), "color": bot.team_color,
			"hp": final_hp[i], "max_hp": bot.max_hp, "ratio": final_ratio[i],
			"armor_damage": bot.armor_damage, "wheel_states": wheel_states, "wheel_bases": wheel_bases,
			"weapon_damage": bot.weapon_damage, "weapon_disabled": bot.weapon_disabled, "rotor_angle": bot.rotor_angle,
			"weapon": weapon, "drive": drive, "tilt": tilt, "pedestal_height": -Fit.lowest_surface_y(bot, tilt)}
		if bot.tracked_drive:
			var track_states := bot.track_state.duplicate()
			var road_wheel_states := bot.road_wheel_state.duplicate()
			track_states.make_read_only()
			road_wheel_states.make_read_only()
			condition.track_states = track_states
			condition.road_wheel_states = road_wheel_states
		condition.make_read_only()
		records.append(condition)
	records.make_read_only()
	result_snapshot = {"winner_index": winner_index, "reason": result_reason, "robots": records}
	result_snapshot.make_read_only()

func resolve_strikes(a: Dictionary, b: Dictionary) -> void:
	if phase != "fight" or finished:
		return
	if not a.is_empty():
		_apply_strike(bots[0], bots[1], a)
	if not b.is_empty():
		_apply_strike(bots[1], bots[0], b)

func _weapon_clash(contact: Dictionary) -> void:
	clash_wait = 0.46
	_present(contact)

func _apply_strike(attacker: CombatRobot, defender: CombatRobot, hit: Dictionary) -> void:
	var strength: float = hit.strength
	var point: Vector3 = hit.point
	# The solver already supplies the normal impulse. Transfer a bounded
	# portion of the rotating surface motion at the exact same point.
	var tangent: Vector3 = hit.tangent
	var impulse := tangent.limit_length(8.0) * attacker.mass * 0.062 * float(attacker.tune.hit_kick) * strength
	impulse.y = clampf(impulse.y, -defender.mass * 0.14, defender.mass * 0.54)
	var damage := roundi(float(attacker.tune.base_attack) * lerpf(0.51, 1.0, strength))
	var major := strength >= 0.76 and float(hit.closing) >= 3.8
	hit.major = major
	attacker.cooldown = float(attacker.tune.hit_cooldown)
	attacker.strike_latched = true
	attacker.hit_count += 1
	attacker.exchange_hit = true
	if attacker.kind == "saw":
		attacker.rotor_speed *= lerpf(0.84, 0.73, strength)
	attacker.pressure_time = 0.0
	attacker.stalled = 0.0
	var trace_hit: Dictionary
	if trace != null:
		trace_hit = trace.hit(attacker, defender, hit, damage, impulse, fight_elapsed)
	attacker.apply_impulse(-impulse, point - attacker.global_position)
	defender.struck(damage, point, impulse, strength, major)
	var shape_index := int(hit.get("target_shape", -1))
	var wheel := defender.wheel_for_shape(shape_index) if hit.target_part == "wheel" and shape_index >= 0 else -1
	var track := defender.track_for_shape(shape_index) if hit.target_part == "track" and shape_index >= 0 else -1
	var road := defender.road_wheel_for_shape(shape_index) if hit.target_part == "road_wheel" and shape_index >= 0 else -1
	for change in defender.damage_component(damage, hit.target_part, shape_index, impulse):
		if change == "track_detached" and road >= 0:
			_component_changed(defender, change, -1, int(road >= 3))
		else:
			_component_changed(defender, change, wheel, track, road)
	if trace != null:
		trace_hit.grip_after = defender.drive_grip()
		trace_hit.wheel_damage = defender.wheel_damage.duplicate()
		trace_hit.wheel_state = defender.wheel_state.duplicate()
		if defender.tracked_drive:
			trace_hit.track_damage = defender.track_damage.duplicate()
			trace_hit.track_state = defender.track_state.duplicate()
			trace_hit.road_wheel_state = defender.road_wheel_state.duplicate()
	hit.kind = attacker.kind
	_present(hit)
	events.append({"time": snappedf(fight_elapsed, 0.001), "attacker": String(attacker.name), "damage": damage,
		"target_hp": defender.hp, "weapon": attacker.kind, "point": [point.x, point.y, point.z],
		"strength": strength, "closing_speed": snappedf(float(hit.closing), 0.001),
		"target_part": hit.target_part, "major": major, "source": "solver_tooth"})

func _component_changed(bot: CombatRobot, change: String, wheel := -1, track := -1, road := -1) -> void:
	var item := {"time": snappedf(fight_elapsed, 0.001), "robot": String(bot.name), "kind": change}
	if wheel >= 0:
		item.wheel = wheel
	if track >= 0:
		item.track = track
	if road >= 0:
		item.road_wheel = road
	component_events.append(item)
	var key := "%s/%s/%d" % [bot.name, change, maxi(wheel, maxi(track, road))]
	if phase == "fight" and bot.hp > 0.0 and not notice_seen.has(key):
		notice_seen[key] = true
		notice_queue.append(item)

func _update_notice(delta: float) -> void:
	if current_notice.is_empty() and notice_queue.is_empty():
		return
	notice_time = maxf(0.0, notice_time - delta)
	if notice_time > 0.0:
		return
	current_notice = {}
	if not notice_queue.is_empty():
		current_notice = notice_queue.pop_front()
		notice_time = 1.22

func _solver_impacts(delta: float, weapon_hit: bool) -> void:
	bump_wait = maxf(0.0, bump_wait - delta)
	var strongest_pair: Dictionary = {}
	for i in range(2):
		var bot := bots[i] as CombatRobot
		wall_wait[i] = maxf(0.0, float(wall_wait[i]) - delta)
		scrape_wait[i] = maxf(0.0, float(scrape_wait[i]) - delta)
		var strongest_wall: Dictionary = {}
		for contact: Dictionary in bot.contacts:
			if contact.wall:
				if float(contact.strength) > float(strongest_wall.get("strength", 0.0)):
					strongest_wall = contact
				if float(contact.slide) > 1.35 and float(scrape_wait[i]) <= 0.0 and float(contact.strength) < 1.2:
					_present({"kind": "scrape", "point": contact.point, "normal": contact.normal, "strength": 0.26})
					scrape_wait[i] = 0.32
			elif not WeaponContact.is_weapon(contact.local_role) and not WeaponContact.is_weapon(contact.other_role) and float(contact.strength) > float(strongest_pair.get("strength", 0.0)):
				strongest_pair = contact
		if float(wall_wait[i]) <= 0.0 and float(strongest_wall.get("strength", 0.0)) > 1.02:
			_bump(strongest_wall, bot)
			wall_wait[i] = 0.30
	if not weapon_hit and bump_wait <= 0.0 and float(strongest_pair.get("strength", 0.0)) > 1.12:
		_bump(strongest_pair, null)
		bump_wait = 0.26

func _bump(contact: Dictionary, bot: CombatRobot) -> void:
	var power := clampf(float(contact.strength) / 5.5, 0.16, 0.72)
	_present({"kind": "bump", "point": contact.point, "normal": contact.normal, "strength": power})
	if bot != null:
		wall_bumps += 1

func _present(event: Dictionary) -> void:
	if world_impacts.has(event.kind):
		world_impacts[event.kind] += 1
	if float(event.strength) > 0.48 and event.kind != "scrape":
		shake = maxf(shake, float(event.strength) * (0.55 if event.kind == "bump" else 1.0))
	if impact_fx != null:
		impact_fx.impact(event)
	if overlay != null and event.kind != "shutdown":
		overlay.impact(event.point, event.normal)

func _process(delta: float) -> void:
	if headless or bots.size() != 2:
		return
	var midpoint := (bots[0].position + bots[1].position) * 0.5
	midpoint.y = 0.07
	var distance := bots[0].position.distance_to(bots[1].position)
	var amount := 1.0 - exp(-delta * 3.6)
	camera_focus = camera_focus.lerp(midpoint * 0.93, amount)
	camera.position = camera_home + camera_focus
	var target_size := clampf(5.8 + distance * 0.98, float(presentation.camera_min_width), float(presentation.camera_max_width))
	if debug_close:
		target_size = clampf(2.35 + distance * 1.16, 4.9, float(presentation.camera_max_width))
	camera.size = lerpf(camera.size, target_size, amount)
	var amplitude := shake * float(presentation.camera_max_shake)
	camera.h_offset = sin(elapsed * 103.0) * amplitude
	camera.v_offset = sin(elapsed * 81.0) * amplitude * 0.52
	if perf_path != "":
		var now := Time.get_ticks_usec()
		if last_frame_us > 0 and phase == "fight" and fight_elapsed > 0.4 and frame_times.size() < 12000:
			frame_times.append(float(now - last_frame_us) / 1000.0)
		last_frame_us = now

func _write_report() -> void:
	var conditions := []
	for state in result_snapshot.robots:
		var condition := {"weapon": state.weapon, "drive": state.drive, "wheels": state.wheel_states}
		if state.has("track_states"):
			condition.erase("wheels")
			condition.tracks = state.track_states
			condition.road_wheels = state.road_wheel_states
		conditions.append(condition)
	var report := {"version": "R08", "seed": match_seed, "winner": winner_name, "reason": result_reason,
		"riptide_ai": riptide_ai, "start": "swapped" if swapped_start else "standard", "start_poses": start_poses,
		"duration": elapsed, "intro_duration": 0.0 if combat_only else cfg.intro_seconds,
		"fight_duration": fight_elapsed, "showcase_duration": result_elapsed,
		"final_conditions": conditions, "hp": final_hp,
		"max_hp": [bots[0].max_hp, bots[1].max_hp], "remaining_ratio": final_ratio,
		"hits": [bots[0].hit_count, bots[1].hit_count], "recoveries": [bots[0].recovery_count, bots[1].recovery_count],
		"peak_speed": peak_speed, "max_arena_extent_ratio": max_extent, "peak_lift": peak_lift, "lowest_root": lowest_root,
		"min_detached_deck_clearance": min_detached_clearance if is_finite(min_detached_clearance) else null,
		"max_detached_tilt_deg": max_detached_tilt, "unsupported_stall_seconds": unsupported_stall,
		"max_deep_deck_ticks": max_deep_deck_ticks,
		"events": events, "other_impacts": world_impacts, "wall_bumps": wall_bumps,
		"longest_close_run": longest_close_run, "peak_particles": 0, "peak_voices": 0,
		"physics_hz": Engine.physics_ticks_per_second, "peak_weapon_contact_depth": peak_weapon_depth,
		"longest_weapon_depth_over_25mm": longest_deep_overlap, "end_weapon_contact_depth": last_weapon_depth,
		"end_center_gap": bots[0].position.distance_to(bots[1].position), "component_events": component_events,
		"maneuvers": [bots[0].maneuver_counts, bots[1].maneuver_counts]}
	if bulldozer_uses_tracks:
		report.bulldozer_drive = "tracks"
		report.bulldozer_ai = bulldozer_ai
	if impact_fx != null:
		report.peak_particles = impact_fx.peak_particles
		report.peak_voices = impact_fx.peak_voices
	print("RFS_RESULT " + JSON.stringify(report))
	_write_json(report_path, report)
	if trace != null:
		var details := {"seed": match_seed, "robots": trace.entries, "strikes": trace.strikes,
			"contact_runs": trace.contact_runs, "deep_contacts": trace.deep_contacts}
		if trace.tracked_ai:
			details.tracked_metrics = trace.tracked_metrics
		if contact_audit != null:
			details.wheel_drum = contact_audit.evidence()
		_write_json(trace_path, details)
	if perf_path != "" and not frame_times.is_empty():
		var total := 0.0
		for sample in frame_times:
			total += sample
		frame_times.sort()
		var viewport := get_viewport().get_texture().get_size()
		_write_json(perf_path, {"frames": frame_times.size(), "fight_window_seconds": total / 1000.0,
			"mean_fps": frame_times.size() * 1000.0 / total, "p95_frame_ms": frame_times[floori((frame_times.size()-1) * 0.95)],
			"p99_frame_ms": frame_times[floori((frame_times.size()-1) * 0.99)], "worst_frame_ms": frame_times.back(),
			"viewport": [viewport.x, viewport.y], "renderer": RenderingServer.get_current_rendering_method(),
			"gpu": RenderingServer.get_video_adapter_name(), "engine": Engine.get_version_info().string})

func _write_json(path: String, data: Dictionary) -> void:
	if path.is_empty():
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write " + path)
		get_tree().quit(3)
		return
	file.store_string(JSON.stringify(data, "\t") + "\n")

func _unhandled_key_input(event: InputEvent) -> void:
	if overlay != null and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_D:
		overlay.toggle()
	else:
		super._unhandled_key_input(event)
