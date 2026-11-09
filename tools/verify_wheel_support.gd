extends SceneTree
## Controlled input and forced component damage on production chassis and colliders.
const Robot = preload("res://scripts/combat/robot.gd")
const Fit = preload("res://scripts/combat/collision_fit.gd")
const Shapes = preload("res://scripts/shapes.gd")
const Arena = preload("res://scenes/arena_combat.tscn")
const EpisodeView = preload("res://scripts/presentation/episode_view.gd")
const CASES := {
	"intact": [], "FL": [0], "FR": [1], "RL": [2], "RR": [3],
	"left": [0, 2], "right": [1, 3], "front": [0, 1], "rear": [2, 3], "failed_FL": [0]
}
const ARENA := Vector2(16, 16)
var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/combat.json"))
var dt: float
var stage: Node3D
var bot: FixtureBot
var debris: Array[RigidBody3D]
var failures: Array[String] = []
var test_name: String
var review_camera: Camera3D
const REVIEW_ANGLE := Vector3(-4.8, 1.85, -2.7)

class FixtureBot extends Robot:
	var command := Vector2.ZERO

	func _drive_order(_delta: float, _radius: Vector2, _forward: Vector3) -> Vector2:
		return command

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	Engine.physics_ticks_per_second = int(config.physics_hz)
	dt = 1.0 / Engine.physics_ticks_per_second
	var output := "res://qa/wheel-support/fixtures.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture-report="):
			output = arg.trim_prefix("--fixture-report=")
		elif arg.begins_with("--wheel-review="):
			await review(arg.trim_prefix("--wheel-review="))
			quit()
			return
	var rows: Array[Dictionary] = []
	for kind in ["saw", "drum"]:
		for scenario: String in CASES:
			test_name = "%s/%s" % [kind, scenario]
			rows.append(await exercise(kind, scenario))
		test_name = kind + "/controls"
		await verify_transfer_and_airborne(kind)
		await verify_showcase(kind)
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Could not write wheel support fixture report.")
		quit(1)
		return
	file.store_string(JSON.stringify({"physics_hz": Engine.physics_ticks_per_second,
		"cases": rows, "controls": ["airborne", "moving transfer", "damaged winner showcase"],
		"failures": failures}, "\t") + "\n")
	print("RFS_WHEEL_SUPPORT_FIXTURES ", rows.size(), " cases, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

func spawn(kind: String) -> void:
	stage = Node3D.new()
	root.add_child(stage)
	debris = []
	var deck := StaticBody3D.new()
	deck.collision_layer = Fit.DECK
	deck.collision_mask = Fit.BODY
	var surface := PhysicsMaterial.new()
	surface.friction = config.floor_friction
	deck.physics_material_override = surface
	var slab := CollisionShape3D.new()
	var bounds := BoxShape3D.new()
	bounds.size = Vector3(34, 0.35, 34)
	slab.shape = bounds
	slab.position.y = -0.175
	deck.add_child(slab)
	stage.add_child(deck)
	bot = FixtureBot.new()
	bot.configure(kind, config, 0.0, true)
	bot.position.y = 0.40
	bot.preparing = false
	stage.add_child(bot)
	# Only the fixture controller is overridden. The production step still
	# expects an opponent node before it requests a drive command.
	bot.opponent = RigidBody3D.new()
	bot.opponent.freeze = true
	bot.opponent.collision_layer = 0
	bot.opponent.collision_mask = 0
	stage.add_child(bot.opponent)
	check(bot.wheel_state.count(Robot.Wheel.INTACT) == 4 and bot.drive_grip() == 1.0
		and bot.axis_lock_angular_x and bot.axis_lock_angular_z and stage.get_child_count() == 3, "fresh support and debris reset")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(test_name + ": " + message)
		push_error(failures.back())

func wheel_owners(chassis: Robot, wheel: int) -> Array[int]:
	var owners: Array[int] = []
	for owner in chassis.get_shape_owners():
		if chassis.shape_roles[owner] != "wheel":
			continue
		var index := chassis.shape_owner_get_shape_index(owner, 0)
		if chassis.wheel_for_shape(index) == wheel:
			owners.append(owner)
	return owners

func damage(wheel: int, failed_only := false) -> void:
	var owners := wheel_owners(bot, wheel)
	var shape := bot.shape_owner_get_shape_index(owners[0], 0)
	var pivot := bot.art.wheel_pivots[wheel]
	var prior := pivot.global_transform
	var wear := Robot.WHEEL_FAILED if failed_only else Robot.WHEEL_MOUNT_BROKEN
	var notice := bot.damage_component(wear, "wheel", shape, Vector3.RIGHT * 17.0)
	if failed_only:
		check(notice == ["wheel_drive_failed"] and bot.art.model.is_ancestor_of(pivot)
			and not bot.is_shape_owner_disabled(owners[0]) and not bot.is_shape_owner_disabled(owners[1]), "failed drive retains both solids")
		return
	var loose := pivot.get_parent() as RigidBody3D
	check(notice == ["wheel_detached"] and loose != null and loose.get_parent() == stage, "one detached wheel assembly")
	if loose == null:
		return
	check(prior.is_equal_approx(pivot.global_transform), "no pose jump during transfer")
	check(loose.get_shape_owners().size() == 2 and bot.is_shape_owner_disabled(owners[0])
		and bot.is_shape_owner_disabled(owners[1]), "tread and hub move to debris")
	check(bot.damage_component(1.0, "wheel", shape).is_empty() and pivot.get_parent() == loose,
		"repeated damage cannot duplicate debris")
	debris.append(loose)

func advance(seconds: float) -> Dictionary:
	var minimum := INF
	var maximum := 0.0
	for i in range(roundi(seconds / dt)):
		await physics_frame
		bot.step(dt, ARENA)
		if review_camera != null:
			var anchor := bot.position.slide(Vector3.UP)
			review_camera.position = anchor + REVIEW_ANGLE
			review_camera.look_at(anchor + Vector3(-0.28, 0.20, -0.06))
		minimum = minf(minimum, clearance())
		maximum = maxf(maximum, bot.position.y)
	return {"min_clearance_m": minimum, "max_root_y_m": maximum}

func clearance() -> float:
	return bot.position.y + Fit.lowest_surface_y(bot, bot.global_basis)

func sample() -> Dictionary:
	var up := bot.global_basis.y
	var debris_speed := 0.0
	var debris_spin := 0.0
	for loose in debris:
		debris_speed = maxf(debris_speed, loose.linear_velocity.length())
		debris_spin = maxf(debris_spin, loose.angular_velocity.length())
	return {"wheel_support_bits": bot.supported_wheels, "deck_roles": bot.deck_contact_roles.keys(),
		"pitch_deg": rad_to_deg(asin(clampf(-bot.global_basis.z.y, -1.0, 1.0))),
		"roll_deg": rad_to_deg(asin(clampf(bot.global_basis.x.y, -1.0, 1.0))),
		"tilt_deg": rad_to_deg(Vector3.UP.angle_to(up)), "clearance_m": clearance(),
		"drive_grip": bot.drive_grip(), "supported_grip": bot.supported_drive_grip(),
		"speed_m_s": bot.linear_velocity.length(), "angular_rad_s": bot.angular_velocity.length(),
		"max_debris_speed_m_s": debris_speed, "max_debris_angular_rad_s": debris_spin}

func exercise(kind: String, scenario: String) -> Dictionary:
	spawn(kind)
	await advance(0.30)
	check(bot.supported_wheels == 15, "all four wheels support the intact chassis")
	for wheel: int in CASES[scenario]:
		damage(wheel, scenario == "failed_FL")
	var settling := await advance(5.0)
	var rest := sample()
	check(stage.get_child_count() == 3 + debris.size(), "exact debris count")
	check(absf(rest.clearance_m) < 0.012 and rest.speed_m_s < 0.10 and rest.angular_rad_s < 0.32, "stationary supported rest")
	check(rest.max_debris_speed_m_s < 0.10 and rest.max_debris_angular_rad_s < 0.30, "debris settles")
	check(bot.art.weapon_pivot.global_position.is_equal_approx(bot.to_global(bot.weapon_pivot)),
		"weapon mesh and collider follow the tilted chassis")
	for wheel: int in CASES[scenario]:
		var present := (int(rest.wheel_support_bits) & (1 << wheel)) != 0
		check(present == (scenario == "failed_FL"), "missing or passive wheel support")
	if scenario == "intact" or scenario == "failed_FL":
		check(rest.tilt_deg < 0.1 and rest.wheel_support_bits == 15, "attached wheels hold the level stance")
	if scenario == "failed_FL":
		check(is_equal_approx(rest.supported_grip, 0.76), "passive wheel adds no motor traction")
	if scenario in ["left", "right"]:
		check(rest.roll_deg * (1.0 if scenario == "left" else -1.0) > 4.0
			and "chassis" in rest.deck_roles, "lowered side rests on a chassis skid or mount")
	if scenario in ["front", "rear"]:
		check(rest.pitch_deg * (-1.0 if scenario == "front" else 1.0) > 2.0, "correct end drops")
	# Keep the first mobility probe independent of rotor contact. The
	# following phase then checks the same controller with a live weapon.
	bot.weapon_disabled = true
	var origin := bot.position
	bot.active = true
	bot.command = Vector2(2.0, 0.0)
	var straight := await advance(1.1)
	straight["travel_m"] = bot.position.distance_to(origin)
	straight["end_support"] = sample()
	var forward := Robot.deck_forward(bot.global_basis)
	bot.command = Vector2(1.0, 1.8)
	var turn := await advance(0.85)
	turn["yaw_deg"] = rad_to_deg(forward.signed_angle_to(Robot.deck_forward(bot.global_basis), Vector3.UP))
	turn["end_support"] = sample()
	check(straight.travel_m > 0.20 and turn.yaw_deg > 5.0, "surviving drive can advance and turn")
	bot.weapon_disabled = false
	origin = bot.position
	forward = Robot.deck_forward(bot.global_basis)
	var live_rotor := await advance(1.8)
	live_rotor["travel_m"] = bot.position.distance_to(origin)
	live_rotor["yaw_deg"] = rad_to_deg(forward.signed_angle_to(Robot.deck_forward(bot.global_basis), Vector3.UP))
	live_rotor["end_support"] = sample()
	bot.active = false
	bot.struck(0.0, bot.to_global(Vector3(0.35, 0.18, -0.45)), Vector3(18, 22, 7), 0.8, true)
	var impact := await advance(3.2)
	impact["rest"] = sample()
	check(absf(impact.rest.clearance_m) < 0.012 and impact.rest.speed_m_s < 0.10 and impact.rest.angular_rad_s < 0.32,
		"settles again after an off-centre impulse")
	for phase in [settling, straight, turn, live_rotor, impact]:
		check(phase.min_clearance_m > -0.025 and phase.max_root_y_m < 0.75, "bounded deck penetration and lift")
	var row := {"robot": kind, "scenario": scenario, "settling": settling, "rest": rest,
		"straight": straight, "turn": turn, "live_rotor": live_rotor, "impact": impact}
	stage.queue_free()
	await physics_frame
	check(not is_instance_valid(bot), "fixture teardown removes the old chassis")
	for loose in debris:
		check(not is_instance_valid(loose), "fixture teardown removes debris")
	return row

func verify_transfer_and_airborne(kind: String) -> void:
	spawn(kind)
	bot.position.y = 2.0
	bot.active = true
	bot.command = Vector2(2.0, 1.8)
	await advance(0.12)
	check(bot.supported_drive_grip() == 0.0 and bot.linear_velocity.slide(Vector3.UP).length() < 0.001
		and absf(bot.angular_velocity.y) < 0.001, "airborne commands supply no drive or steering")
	await advance(1.4)
	var before := bot.art.wheel_pivots[0].global_position
	var at_axle := bot.linear_velocity + bot.angular_velocity.cross(before - bot.to_global(bot.center_of_mass))
	var forward := Robot.deck_forward(bot.global_basis)
	var expected_roll := at_axle.dot(forward) / bot.art.wheel_radius
	damage(0)
	var loose := debris[0]
	check(expected_roll > 0.5 and absf(loose.linear_velocity.dot(forward) - at_axle.dot(forward)) < 0.001
		and absf(loose.angular_velocity.dot(-bot.global_basis.x) - expected_roll) < 0.02,
		"moving debris inherits axle-point motion and rolling spin")
	stage.queue_free()
	await physics_frame

func verify_showcase(kind: String) -> void:
	var match_node := Arena.instantiate()
	root.add_child(match_node)
	match_node.set_physics_process(false)
	match_node.phase = "fight"
	var index := 0 if kind == "saw" else 1
	var damaged := match_node.bots[index] as Robot
	for i in range(2):
		var chassis := match_node.bots[i] as Robot
		chassis.freeze = false
		chassis.position = Vector3(-2.4 if i == 0 else 2.4, 0.40, 0)
		chassis.rotation.y = 0.0
		if i != index:
			chassis.hp *= 0.5
	for i in range(roundi(0.3 / dt)):
		await physics_frame
	for wheel in [0, 2]:
		var owner := wheel_owners(damaged, wheel)[0]
		damaged.damage_component(Robot.WHEEL_MOUNT_BROKEN, "wheel", damaged.shape_owner_get_shape_index(owner, 0))
	for i in range(roundi(2.3 / dt)):
		await physics_frame
	match_node._finish("time limit / health decision")
	var snapshot: Dictionary = match_node.result_snapshot
	var state: Dictionary = snapshot.robots[index]
	var display := EpisodeView.new()
	display.match_node = match_node
	match_node.add_child(display)
	var visual := display.models[index]
	var rest_error := absf(visual.position.y + Fit.lowest_surface_y(damaged, visual.basis))
	check(snapshot.winner_index == index and snapshot.is_read_only() and state.is_read_only()
		and state.wheel_states.is_read_only(), "immutable damaged winner record")
	check(not visual.wheel_pivots[0].visible and not visual.wheel_pivots[2].visible
		and visual.wheel_pivots[1].visible and visual.wheel_pivots[3].visible, "showcase hides the two lost wheels")
	check(rest_error < 0.001 and visual.basis.y.y < 0.999 and is_equal_approx(visual.basis.y.y, damaged.basis.y.y),
		"showcase preserves physical lean and seats its support on the pedestal")
	check(visual.find_children("*LooseWheel*", "RigidBody3D").is_empty(), "showcase owns no arena debris")
	match_node.queue_free()
	await physics_frame

func review(kind: String) -> void:
	spawn(kind)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("202b38")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("ddeaff")
	environment.ambient_light_energy = 0.58
	world.environment = environment
	stage.add_child(world)
	Shapes.box(stage, Vector3(34, 0.1, 34), Vector3(0, -0.05, 0), Shapes.material(Color("344554"), 0.82))
	var key := DirectionalLight3D.new()
	stage.add_child(key)
	key.position = Vector3(-3, 5, -4)
	key.look_at(Vector3.ZERO)
	key.shadow_enabled = true
	key.light_energy = 0.82
	key.directional_shadow_max_distance = 10.0
	var fill := OmniLight3D.new()
	stage.add_child(fill)
	fill.position = Vector3(-3.6, 1.15, -2.2)
	fill.omni_range = 10.0
	fill.light_energy = 0.90
	review_camera = Camera3D.new()
	stage.add_child(review_camera)
	review_camera.position = REVIEW_ANGLE
	review_camera.look_at(Vector3(-0.28, 0.20, -0.06))
	review_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	review_camera.keep_aspect = Camera3D.KEEP_WIDTH
	review_camera.size = 3.65
	review_camera.current = true
	var overlay := CanvasLayer.new()
	stage.add_child(overlay)
	var title := Label.new()
	overlay.add_child(title)
	title.position = Vector2(34, 238)
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_outline_color", Color("19212c"))
	title.add_theme_constant_override("outline_size", 8)
	var caption := Label.new()
	overlay.add_child(caption)
	caption.position = Vector2(35, 293)
	caption.add_theme_font_size_override("font_size", 25)
	caption.add_theme_color_override("font_outline_color", Color("19212c"))
	caption.add_theme_constant_override("outline_size", 7)
	title.text = "%s  |  FORCED DAMAGE FIXTURE" % bot.name.to_upper()
	caption.text = "Intact • all four treads on deck"
	await advance(2.0)
	bot.weapon_disabled = true
	await review_release(0, caption, "Front-left wheel removed • three treads remain", 3.55)
	await review_release(2, caption, "Both left wheels removed • chassis settles on skid", 4.55)

func review_release(wheel: int, caption: Label, message: String, hold: float) -> void:
	bot.active = true
	bot.command = Vector2(2.35, 0.0)
	await advance(0.62)
	damage(wheel)
	caption.text = message
	bot.command = Vector2.ZERO
	await advance(0.65)
	bot.active = false
	await advance(hold)
