extends SceneTree
## Exercise the test arena's actual contact, drive and result paths.
const Arena = preload("res://scenes/review/arena_tracked_bulldozer_test.tscn")
const Match = preload("res://scripts/combat/match.gd")
const Robot = preload("res://scripts/combat/robot.gd")
const Contact = preload("res://scripts/combat/weapon_contact.gd")
const EpisodeView = preload("res://scripts/presentation/episode_view.gd")
const TracksArt = preload("res://scripts/art/bulldozer_tracks_visual.gd")
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, description: String) -> void:
	if condition:
		print("PASS ", description)
	else:
		failures += 1
		push_error(description)

func stage() -> Match:
	var arena := Arena.instantiate() as Match
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.phase = "fight"
	var drum := arena.bots[1] as Robot
	drum.art = drum.make_visual()
	drum.add_child(drum.art)
	drum.freeze = false
	drum.position = Vector3(0, 0.4, 0)
	drum.rotation.y = 0.0
	return arena

func drive_for(bot: Robot, thrust: float, yaw_torque: float, ticks: int) -> void:
	var delta := 1.0 / Engine.physics_ticks_per_second
	for _tick in range(ticks):
		await physics_frame
		var forward := Robot.deck_forward(bot.global_basis)
		bot._apply_track_drive(forward, forward.cross(Vector3.UP), forward * thrust, yaw_torque, float(bot.tune.acceleration), 1.0)
		bot.art.update_visual(delta, 0.0, bot.linear_velocity.dot(forward), bot.angular_velocity.y,
			0.0, false, bot.supported_tracks, bot.supported_road_wheels)
	await physics_frame

func shape_on_side(bot: Robot, side: int) -> int:
	for owner in bot.get_shape_owners():
		if bot.shape_roles[owner] != "track":
			continue
		var index := bot.shape_owner_get_shape_index(owner, 0)
		if bot.track_for_shape(index) == side:
			return index
	return -1

func road_hub(bot: Robot, wheel: int) -> int:
	for owner in bot.get_shape_owners():
		if bot.shape_roles[owner] != "road_wheel" or owner in bot.road_tread_owners:
			continue
		var index := bot.shape_owner_get_shape_index(owner, 0)
		if bot.road_wheel_for_shape(index) == wheel:
			return index
	return -1

func belt_travel(art: TracksArt, before: Array) -> Vector2:
	var span := art.loop_length
	return Vector2(wrapf(art.travel[0] - before[0], -span * 0.5, span * 0.5),
		wrapf(art.travel[1] - before[1], -span * 0.5, span * 0.5))

func test_strike() -> void:
	var arena := stage()
	var saw := arena.bots[0] as Robot
	var drum := arena.bots[1] as Robot
	saw.freeze = false
	saw.position = Vector3(-2.56, 0.41, 0.34)
	saw.rotation.y = -PI * 0.5
	saw.linear_velocity = Vector3(3.7, 0.0, 0.0)
	saw.active = true
	saw.rotor_speed = float(saw.tune.weapon_speed)
	var delta := 1.0 / Engine.physics_ticks_per_second
	var peak_yaw := 0.0
	for _tick in range(90):
		await physics_frame
		var pair := Contact.read_pair(arena.bots, delta)
		arena.fight_elapsed += delta
		arena.resolve_strikes(pair.hits[0], pair.hits[1])
		peak_yaw = maxf(peak_yaw, absf(drum.angular_velocity.y))
		saw.rotor_angle = fposmod(saw.rotor_angle + saw.rotor_speed * delta, TAU)
		saw.sync_weapon_shapes()
	check(arena.events.size() == 1 and arena.events[0].target_part == "track"
		and drum.hp < drum.max_hp and peak_yaw > 0.05, "real side strike scores once and physically turns Bulldozer")
	check(drum.track_damage[0] > 0.0 and drum.track_damage[1] == 0.0 and not arena.component_events.is_empty()
		and arena.component_events[0].get("track") == 0,
		"the solver contact damages only the left belt")
	saw.freeze = true
	drum.linear_velocity = Vector3.ZERO
	drum.angular_velocity = Vector3.ZERO
	var left := shape_on_side(drum, 0)
	var thrown := drum.damage_component(Robot.WHEEL_MOUNT_BROKEN, "track", left)
	await drive_for(drum, 0.0, 0.0, 100)
	check(thrown == ["track_detached"] and drum.is_shape_owner_disabled(drum.shape_find_owner(left))
		and drum.supported_tracks == 2 and (drum.supported_road_wheels & 7) != 0
		and is_equal_approx(drum.supported_drive_grip(), 0.5), "a thrown belt exposes passive road wheels without leaving traction")
	arena.queue_free()
	await physics_frame

func test_road_hub_strike() -> void:
	var arena := stage()
	var saw := arena.bots[0] as Robot
	var drum := arena.bots[1] as Robot
	# Raise the target in this fixture so the saw meets the exposed rear
	# hub at its center height, independent of the combat approach AI.
	drum.position.y = 0.607
	drum.freeze = true
	saw.freeze = false
	saw.position = Vector3(-2.56, 0.40, 0.433)
	saw.rotation.y = -PI * 0.5
	saw.linear_velocity = Vector3(3.7, 0.0, 0.0)
	saw.active = true
	saw.rotor_speed = float(saw.tune.weapon_speed)
	var delta := 1.0 / Engine.physics_ticks_per_second
	for _tick in range(90):
		await physics_frame
		var pair := Contact.read_pair(arena.bots, delta)
		arena.fight_elapsed += delta
		arena.resolve_strikes(pair.hits[0], pair.hits[1])
		saw.rotor_angle = fposmod(saw.rotor_angle + saw.rotor_speed * delta, TAU)
		saw.sync_weapon_shapes()
	check(arena.events.size() == 1 and arena.events[0].target_part == "road_wheel"
		and drum.road_wheel_damage[2] > 0.0 and drum.track_damage == [0.0, 0.0],
		"a saw strike on the exposed rear hub damages its road wheel separately")
	arena.queue_free()
	await physics_frame

func test_drive() -> void:
	var arena := stage()
	var drum := arena.bots[1] as Robot
	var left := shape_on_side(drum, 0)
	var right := shape_on_side(drum, 1)
	var art := drum.art as TracksArt
	check(left >= 0 and right >= 0 and left != right and not drum.shape_roles.values().has("wheel"),
		"two independent belt hulls replace the wheel colliders")
	drum.position.y = 1.0
	await drive_for(drum, 8.0, 110.0, 12)
	check(drum.supported_tracks == 0 and drum.linear_velocity.slide(Vector3.UP).length() < 0.01
		and absf(drum.angular_velocity.y) < 0.01, "airborne belts generate no traction or steering torque")
	drum.position.y = 0.4
	drum.linear_velocity = Vector3.ZERO
	await drive_for(drum, 0.0, 0.0, 18)
	check(drum.supported_tracks == 3, "both belt hulls support the chassis on the deck")
	var before := art.travel.duplicate()
	await drive_for(drum, 8.0, 0.0, 45)
	var travel := belt_travel(art, before)
	check(-drum.linear_velocity.z > 0.5 and absf(drum.angular_velocity.y) < 0.12 and travel.x < -0.03 and travel.y < -0.03,
		"equal grounded belt forces and animation drive forward")
	drum.linear_velocity = Vector3.ZERO
	before = art.travel.duplicate()
	await drive_for(drum, -8.0, 0.0, 45)
	travel = belt_travel(art, before)
	check(drum.linear_velocity.z > 0.5 and absf(drum.angular_velocity.y) < 0.12 and travel.x > 0.03 and travel.y > 0.03,
		"both belts reverse with the chassis")
	drum.linear_velocity = Vector3.ZERO
	drum.angular_velocity = Vector3.ZERO
	before = art.travel.duplicate()
	await drive_for(drum, 0.0, 180.0, 40)
	travel = belt_travel(art, before)
	check(drum.angular_velocity.y > 0.2 and drum.linear_velocity.slide(Vector3.UP).length() < 0.15
		and travel.x > 0.02 and travel.y < -0.02, "opposite belt forces and animation turn in place")
	drum.linear_velocity = Vector3.ZERO
	drum.angular_velocity = Vector3.ZERO
	var worn := drum.damage_component(Robot.WHEEL_WORN, "track", left)
	var reduced_grip := drum.drive_grip()
	var failed := drum.damage_component(Robot.WHEEL_FAILED - Robot.WHEEL_WORN, "track", left)
	check(worn == ["track_damaged"] and reduced_grip < 1.0 and reduced_grip > 0.5
		and failed == ["track_drive_failed"] and drum.drive_grip() == 0.5, "wear reduces traction and a failed belt loses motor force")
	await drive_for(drum, 10.0, 0.0, 40)
	check(drum.angular_velocity.y > 0.15 and drum.supported_tracks == 3,
		"the remaining right drive turns the chassis while the disabled side still supports it")
	drum.damage_component(Robot.WHEEL_FAILED, "track", right)
	drum.linear_velocity = Vector3.ZERO
	drum.angular_velocity = Vector3.ZERO
	await drive_for(drum, 10.0, 100.0, 30)
	check(drum.drive_grip() == 0.0 and drum.supported_tracks == 3
		and drum.linear_velocity.slide(Vector3.UP).length() < 0.01 and absf(drum.angular_velocity.y) < 0.01,
		"both disabled drives stop propulsion without removing collision support")
	var idler := road_hub(drum, 1)
	var wheel_hit := drum.damage_component(Robot.WHEEL_SEVERE, "road_wheel", idler)
	check(wheel_hit == ["road_wheel_severe"] and drum.road_wheel_state[1] == Robot.Wheel.SEVERE
		and drum.track_state[0] == Robot.Wheel.DRIVE_FAILED and not art.road_finishes[1].is_empty(),
		"road wheel damage has its own state and finish")
	var end_hub := road_hub(drum, 3)
	var end_lost := drum.damage_component(Robot.WHEEL_MOUNT_BROKEN, "road_wheel", end_hub)
	await drive_for(drum, 10.0, 100.0, 120)
	var debris := 0
	var visible_attached_shoes := 0
	for shoe: Node3D in art.links[1]:
		if shoe.get_parent() is RigidBody3D:
			debris += 1
		elif shoe.visible:
			visible_attached_shoes += 1
	check(end_lost == ["road_wheel_detached", "track_detached"] and drum.supported_tracks == 1
		and (drum.supported_road_wheels & 8) == 0 and (drum.supported_road_wheels & 48) != 0
		and drum.is_shape_owner_disabled(drum.road_tread_owners[3]) and drum.supported_drive_grip() == 0.0,
		"losing an end wheel throws its belt and leaves only the surviving wheels as passive support")
	check(debris > 0 and visible_attached_shoes == 0 and art.road_wheels[3].get_parent() is RigidBody3D,
		"belt strip and lost wheel become debris with no attached floating geometry")
	arena.bots[0].hp = 0
	arena._finish("knockout")
	var view := EpisodeView.new()
	view.match_node = arena
	arena.add_child(view)
	var winner := view.models[1] as TracksArt
	check(arena.result_snapshot.robots[1].track_states.is_read_only() and winner.track_wear == drum.track_state
		and winner.road_wear == drum.road_wheel_state and not winner.belt_finishes[0].is_empty()
		and not winner.links[1][0].visible and not winner.road_wheels[3].visible and winner.road_wheels[4].visible,
		"showcase preserves the failed belt, thrown belt and missing road wheel")
	arena.queue_free()
	await physics_frame

func run() -> void:
	await test_strike()
	await test_road_hub_strike()
	await test_drive()
	print("RFS_TRACK_FIXTURES ", failures, " failures")
	quit(0 if failures == 0 else 1)
