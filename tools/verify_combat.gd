extends SceneTree
## Tests the installed compound colliders with real physics steps.
const Arena = preload("res://scenes/arena_combat.tscn")
const Robot = preload("res://scripts/combat/robot.gd")
const Match = preload("res://scripts/combat/match.gd")
const Contact = preload("res://scripts/combat/weapon_contact.gd")
const EpisodeView = preload("res://scripts/presentation/episode_view.gd")
var passed := 0

class StraightBot extends Robot:
	func _drive_order(_delta: float, _radius: Vector2, _forward: Vector3) -> Vector2:
		return Vector2(drive_speed, 0.0)

func _initialize() -> void:
	run.call_deferred()

func stage(start_in_fight := true) -> Match:
	var m := Arena.instantiate() as Match
	root.add_child(m)
	m.set_physics_process(false)
	if start_in_fight:
		m.phase = "fight"
		for bot: Robot in m.bots:
			bot.freeze = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rate="):
			Engine.physics_ticks_per_second = int(arg.trim_prefix("--rate="))
		elif arg == "--ccd":
			for bot: Robot in m.bots:
				bot.continuous_cd = true
	return m

func place(bot: Robot, at: Vector3, yaw: float, velocity: Vector3, powered: bool) -> void:
	bot.position = at
	bot.rotation.y = yaw
	bot.linear_velocity = velocity
	bot.active = powered
	bot.preparing = false
	bot.rotor_speed = float(bot.tune.weapon_speed) if powered else 0.0

func spin(m: Match, dt: float) -> void:
	for bot: Robot in m.bots:
		bot.rotor_angle = fposmod(bot.rotor_angle + bot.rotor_speed * dt, TAU)
		bot.sync_weapon_shapes()
		bot.cooldown = maxf(0.0, bot.cooldown - dt)

func count(seconds: float) -> int:
	return roundi(seconds * Engine.physics_ticks_per_second)

func passed_case(m: Match, message: String) -> void:
	passed += 1
	print("PASS ", message)
	m.queue_free()

func test_head_on() -> void:
	var m := stage()
	var saw := m.bots[0] as Robot
	var drum := m.bots[1] as Robot
	place(saw, Vector3(0,.41,1.62), 0, Vector3.ZERO, true)
	place(drum, Vector3(0,.40,-1.62), PI, Vector3.ZERO, true)
	saw.axis_lock_angular_y = true
	drum.axis_lock_angular_y = true
	var dt := 1.0 / Engine.physics_ticks_per_second
	for i in range(count(.16)):
		await physics_frame
		spin(m, dt)
		var sample := Contact.read_pair(m.bots, dt)
		assert(sample.clash.is_empty() and sample.hits[0].is_empty() and sample.hits[1].is_empty(), "Air gap caused a hit")
	saw.linear_velocity = Vector3(0,0,-3.3)
	drum.linear_velocity = Vector3(0,0,3.3)
	var closest := INF
	var peak := 0.0
	var duration := 0.0
	var peak_duration := 0.0
	var clashes := 0
	for i in range(count(.68)):
		await physics_frame
		var sample := Contact.read_pair(m.bots, dt)
		closest = minf(closest, saw.position.distance_to(drum.position))
		peak = maxf(peak, sample.weapon_depth)
		duration = duration + dt if sample.weapon_depth > .025 else 0.0
		peak_duration = maxf(peak_duration, duration)
		clashes += int(not sample.clash.is_empty())
		assert(sample.hits[0].is_empty() and sample.hits[1].is_empty(), "A weapon-to-weapon clash awarded damage")
		spin(m, dt)
	assert(clashes > 0 and closest > 2.57 and peak < .12, "Head-on passed too far through the weapon: gap %.3f depth %.3f contacts %d" % [closest, peak, clashes])
	passed_case(m, "head-on and near miss: %.3fm minimum centre gap, %.3fm peak depth, %.3fs above 25mm" % [closest, peak, peak_duration])

func test_strike(drum_attacks: bool) -> void:
	var m := stage()
	var attacker := m.bots[int(drum_attacks)] as Robot
	var defender := m.bots[1 - int(drum_attacks)] as Robot
	place(defender, Vector3(0,.41,0), 0, Vector3.ZERO, false)
	place(attacker, Vector3(-2.56,.41,-.40 if drum_attacks else .41), -PI/2 + (.11 if drum_attacks else 0.0), Vector3(3.7,0,.32 if drum_attacks else 0.0), true)
	var dt := 1.0 / Engine.physics_ticks_per_second
	var yaw_response := 0.0
	for i in range(count(.47)):
		await physics_frame
		var sample := Contact.read_pair(m.bots, dt)
		m.fight_elapsed += dt
		m.resolve_strikes(sample.hits[0], sample.hits[1])
		yaw_response = maxf(yaw_response, absf(defender.angular_velocity.y))
		spin(m, dt)
	assert(m.events.size() == 1 and defender.hp < defender.max_hp, "Expected one real tooth strike: %s" % str(m.events))
	assert(yaw_response > .10, "Off-centre contact failed to turn the target")
	assert(m.events[0].target_part in ["chassis", "wheel", "support"], "Damage must come from tooth vs solid")
	if drum_attacks:
		assert(m.events[0].target_part == "wheel" and defender.drive_grip() < 1.0, "Wheel strike did not reduce traction")
		assert(defender.wheel_damage.count(0.0) == 3 and m.component_events.size() == 1, "Wheel damage must affect the contacted axle only")
	passed_case(m, "%s strike: %s, %.2f rad/s target yaw" % ["glancing drum" if drum_attacks else "side saw", m.events[0].target_part, yaw_response])

func test_sustained() -> void:
	var m := stage()
	var saw := m.bots[0] as Robot
	var drum := m.bots[1] as Robot
	drum.freeze = true # Holds the target in a fixture, as a rail would.
	place(drum, Vector3(0,.40,0), 0, Vector3.ZERO, false)
	place(saw, Vector3(-2.53,.41,.43), -PI/2, Vector3(3,0,0), true)
	saw.axis_lock_angular_y = true
	saw.axis_lock_linear_z = true
	var dt := 1.0 / Engine.physics_ticks_per_second
	var touching_ticks := 0
	var eligible_after_cooldown := false
	for i in range(count(2.3)):
		await physics_frame
		var sample := Contact.read_pair(m.bots, dt)
		m.fight_elapsed += dt
		m.resolve_strikes(sample.hits[0], sample.hits[1])
		if saw.clear_contact_time == 0.0:
			touching_ticks += 1
			eligible_after_cooldown = eligible_after_cooldown or (saw.strike_latched and saw.cooldown <= 0.0)
		saw.apply_central_force(Vector3.RIGHT * saw.mass * 6.0)
		spin(m, dt)
	assert(m.events.size() == 1 and eligible_after_cooldown and touching_ticks * dt > 1.0,
		"Sustained press must deal one hit past cooldown: %d events, %.3fs contact, expired=%s" % [m.events.size(), touching_ticks * dt, eligible_after_cooldown])
	passed_case(m, "sustained contact: one hit across %.2fs of solver contacts" % (touching_ticks * dt))

func test_wall() -> void:
	var m := stage()
	var saw := m.bots[0] as Robot
	var drum := m.bots[1] as Robot
	place(saw, Vector3(2.78,.41,4.0), -PI*.75, Vector3(4,0,4), true)
	place(drum, Vector3(-1.6,.40,-2.9), 0, Vector3.ZERO, false)
	m.set_physics_process(true)
	for i in range(count(1.45)):
		await physics_frame
	assert(m.wall_bumps > 0 and saw.position.distance_to(Vector3(2.78,.41,4.0)) > 0.85 and not saw.wall_contact,
		"Wall fixture: %d bumps, pos %s" % [m.wall_bumps, saw.position])
	assert(m.max_extent < 1.0 and m.peak_lift < .2 and m.lowest_root > .33, "Corner escaped the arena or lost grounding")
	passed_case(m, "corner: real wall contact, bounded reverse and turn")

func test_wall_pin(damaged: bool = false) -> void:
	var m := stage()
	var saw := m.bots[0] as Robot
	var drum := m.bots[1] as Robot
	if damaged:
		var axle_shape := -1
		for owner in saw.get_shape_owners():
			if saw.shape_roles[owner] == "wheel" and saw.shape_owner_get_transform(owner).origin.x > 0.0:
				axle_shape = saw.shape_owner_get_shape_index(owner, 0)
				break
		assert(axle_shape >= 0)
		saw.art = Robot.SawArt.new()
		saw.add_child(saw.art)
		assert(saw.damage_component(15.0, "wheel", axle_shape) == ["wheel_damaged"])
		var worn_grip := saw.drive_grip()
		assert(worn_grip > 0.90 and worn_grip < 1.0)
		assert(saw.damage_component(10.0, "wheel", axle_shape) == ["wheel_severe"] and saw.drive_grip() < worn_grip)
		var severe_grip := saw.drive_grip()
		var owners := saw.get_shape_owners().size()
		assert(saw.damage_component(16.0, "wheel", axle_shape) == ["wheel_drive_failed"] and saw.drive_grip() < severe_grip)
		var failed_grip := saw.drive_grip()
		assert(saw.damage_component(19.0, "wheel", axle_shape).is_empty() and saw.drive_grip() == failed_grip)
		assert(saw.art.wheel_wear.count(3) == 1 and saw.get_shape_owners().size() == owners)
	place(saw, Vector3(2.43,.41,1.10), -PI/2, Vector3(2,0,0), true)
	place(drum, Vector3(.08,.40,1.05), -PI/2, Vector3(4.1,0,0), true)
	m.set_physics_process(true)
	var dt := 1.0 / Engine.physics_ticks_per_second
	var wall_since := INF
	var peer_since := INF
	var pinned := false
	var pin_gap := INF
	var clear_gain := 0.0
	for i in range(count(4.0)):
		await physics_frame
		wall_since += dt
		peer_since += dt
		for contact in saw.contacts:
			if contact.wall:
				wall_since = 0.0
			elif contact.other_id == drum.get_instance_id():
				peer_since = 0.0
		var gap := saw.position.distance_to(drum.position)
		if wall_since < .085 and peer_since < .085:
			pinned = true
			pin_gap = minf(pin_gap, gap)
		if pinned and wall_since > .20 and peer_since > .13:
			clear_gain = maxf(clear_gain, gap - pin_gap)
	assert(pinned and m.max_extent < 1.0 and clear_gain > .45,
		"Expected physical escape: pinned=%s pos=%s wall=%.2fs ago cleared gain=%.2fm" % [pinned, saw.position, wall_since, clear_gain])
	passed_case(m, "wall pin: cleared by %.2fm%s" % [clear_gain, " after wheel drive failure" if damaged else ""])

func test_knockout() -> void:
	var m := stage()
	var saw := m.bots[0] as Robot
	var drum := m.bots[1] as Robot
	place(saw, Vector3(-2.46,.41,3.84), -PI/2, Vector3(3.7,0,0), true)
	place(drum, Vector3(0,.40,3.43), 0, Vector3.ZERO, false)
	drum.rotor_speed = 12.0
	drum.hp = 1.0
	var dt := 1.0 / Engine.physics_ticks_per_second
	for i in range(count(.40)):
		await physics_frame
		m._physics_process(dt)
		if m.phase == "result":
			break
	assert(m.phase == "result" and m.winner_name == "RIPTIDE", "Expected real side contact to cause a knockout")
	var saw_at_ko := saw.transform
	var drum_at_ko := drum.transform
	var fight_at_ko := m.fight_elapsed
	var owners := drum.get_shape_owners().size()
	var event_count := m.events.size()
	for i in range(count(.25)):
		await physics_frame
		m._physics_process(dt)
	assert(m.events.size() == event_count and m.fight_elapsed == fight_at_ko and not saw.active and not drum.active,
		"Combat continued after knockout")
	assert(is_zero_approx(drum.rotor_speed) and is_zero_approx(saw.rotor_speed) and drum.hp == 0, "Weapons must stop")
	assert(drum.freeze and drum.get_shape_owners().size() == owners and drum.collision_mask == 7 and drum.collision_layer == 1,
		"Defeated robot lost solidity")
	assert(saw.freeze and saw.transform.is_equal_approx(saw_at_ko) and drum.transform.is_equal_approx(drum_at_ko),
		"Arena motion continued under the showcase")
	for i in range(count(4.75)):
		m._physics_process(dt)
	assert(m.finished and m.result_elapsed == 5.0 and is_equal_approx(m.elapsed, 15.0 + fight_at_ko))
	# Move only the winner in this fixture to probe the stopped loser's shapes.
	saw.freeze = false
	saw.linear_velocity = Vector3.ZERO
	var blocked := false
	for i in range(count(1.15)):
		await physics_frame
		for bot: Robot in m.bots:
			for contact in bot.contacts:
				blocked = blocked or contact.other_id == bot.opponent.get_instance_id()
		if blocked:
			break
		var toward := drum.position - saw.position
		toward.y = 0.0
		saw.apply_central_force(toward.normalized() * saw.mass * 7.0)
	assert(blocked and m.events.size() == event_count, "Stopped loser did not block a subsequent push")
	passed_case(m, "near-wall knockout cuts immediately, holds arena poses, shows five seconds and keeps loser solid")

func test_component_state() -> void:
	var m := stage()
	var saw := m.bots[0] as Robot
	var drum := m.bots[1] as Robot
	drum.art = Robot.DrumArt.new()
	drum.add_child(drum.art)
	var support_hit := {"target_part": "support", "strength": 0.9, "point": drum.to_global(Vector3(.72,.12,-1.1)),
		"tangent": Vector3.ZERO, "normal": Vector3.RIGHT, "closing": 1.0}
	for i in range(2):
		m.resolve_strikes(support_hit.duplicate(), {})
	assert(drum.weapon_output() < 1.0 and not drum.weapon_disabled and drum.art.armor_wear > 0.0)
	m.resolve_strikes(support_hit.duplicate(), {})
	assert(drum.hp > 0.0 and drum.weapon_disabled and drum.weapon_output() == 0.0 and drum.art.rotor_broken)
	assert(m.component_events.size() == 2 and m.notice_queue.size() == 2, "Only the two component transitions should notify")
	m._update_notice(.01)
	assert(m.current_notice.kind == "armor_damaged")
	m._update_notice(.60)
	assert(m.current_notice.kind == "armor_damaged")
	m._update_notice(.66)
	assert(m.current_notice.kind == "weapon_disabled" and m.notice_queue.is_empty())

	# Replay the glancing strike with residual spin after disablement.
	place(saw, Vector3(0,.41,0), 0, Vector3.ZERO, false)
	place(drum, Vector3(-2.56,.41,-.40), -PI/2 + .11, Vector3(3.7,0,.32), true)
	var dt := 1.0 / Engine.physics_ticks_per_second
	var teeth_touched := false
	for i in range(count(.47)):
		await physics_frame
		var sample := Contact.read_pair(m.bots, dt)
		assert(sample.hits[1].is_empty(), "Disabled weapon dealt damage during spin-down")
		for contact in drum.contacts:
			teeth_touched = teeth_touched or (contact.local_role == "tooth" and contact.other_role == "wheel")
		spin(m, dt)
	assert(teeth_touched, "Disabled tooth should still block the wheel")
	for i in range(count(.94)):
		await physics_frame
		drum.step(dt, Vector2(4.1, 5.3))
	assert(is_zero_approx(drum.rotor_speed), "Disabled weapon did not stop")
	assert(drum.capability == Robot.Capability.UNARMED and drum.maneuver_counts[Robot.Maneuver.ATTACK] == 0)
	saw.active = true
	saw.step(dt, Vector2(4.1, 5.3))
	assert(saw.capability == Robot.Capability.OPEN_TARGET and saw.maneuver == Robot.Maneuver.PRESS)
	m._finish("time limit / health decision")
	assert(m.current_notice.is_empty() and m.component_events.back().kind == "weapon_disabled")
	passed_case(m, "component wear slows and disables the rotor; real contacts stay solid and notices serialize")
	await physics_frame
	var fresh := stage()
	var new_drum := fresh.bots[1] as Robot
	new_drum.art = Robot.DrumArt.new()
	new_drum.add_child(new_drum.art)
	assert(fresh.bots[0].hp == 150.0 and new_drum.hp == 200.0 and new_drum.drive_grip() == 1.0 and new_drum.weapon_output() == 1.0)
	assert(not new_drum.art.rotor_broken and new_drum.art.armor_wear == 0.0 and new_drum.art.wheel_wear.count(0) == 4)
	assert(fresh.current_notice.is_empty() and fresh.notice_queue.is_empty() and fresh.notice_seen.is_empty())
	assert(fresh.final_hp.is_empty() and fresh.final_ratio.is_empty() and new_drum.capability == Robot.Capability.ARMED)
	passed_case(fresh, "fresh match resets component state, materials, traction and notifications")

func test_wheel_separation() -> void:
	var m := stage()
	var saw := m.bots[0] as Robot
	var drum := m.bots[1] as Robot
	place(saw, Vector3(0, .40, 1.2), 0.0, Vector3.ZERO, false)
	place(drum, Vector3(-2.3, .40, -2.8), 0.0, Vector3.ZERO, false)
	saw.art = Robot.SawArt.new()
	saw.add_child(saw.art)
	var owner_ids: Array[int] = []
	for owner in saw.get_shape_owners():
		var local := saw.shape_owner_get_transform(owner).origin
		if saw.shape_roles[owner] == "wheel" and local.x > 0.0 and local.z < 0.0:
			owner_ids.append(owner)
	assert(owner_ids.size() == 2)
	var shape := saw.shape_owner_get_shape_index(owner_ids[0], 0)
	var pivot := saw.art.wheel_pivots[1]
	assert(saw.damage_component(41.0, "wheel", shape) == ["wheel_drive_failed"])
	assert(saw.art.model.is_ancestor_of(pivot) and not saw.is_shape_owner_disabled(owner_ids[0]))
	assert(saw.art.wheel_marks[1].get_child_count() == 2)
	var grip := saw.drive_grip()
	assert(saw.damage_component(31.0, "wheel", shape, Vector3.RIGHT * 18.0) == ["wheel_detached"])
	var loose := pivot.get_parent() as RigidBody3D
	assert(loose != null and loose.get_parent() == m and loose.collision_layer == 0)
	assert(saw.is_shape_owner_disabled(owner_ids[0]) and saw.is_shape_owner_disabled(owner_ids[1]))
	assert(saw.drive_grip() == grip and saw.art.wheel_wear[1] == Robot.Wheel.DETACHED)
	var origin := loose.position
	for i in range(count(.65)):
		await physics_frame
	assert(loose.position.x > origin.x + .12 and loose.position.y > .07 and loose.position.y < .45,
		"Loose wheel must move independently on the deck, from %s to %s" % [origin, loose.position])
	assert(pivot.global_position.is_equal_approx(loose.global_position))
	for owner in saw.get_shape_owners():
		if saw.shape_roles[owner] == "wheel" and not saw.is_shape_owner_disabled(owner):
			saw.damage_component(39.0, "wheel", saw.shape_owner_get_shape_index(owner, 0))
			if saw.failed_wheel_count == 4:
				break
	saw.active = true
	saw.step(1.0 / Engine.physics_ticks_per_second, Vector2(4.1, 5.3))
	assert(saw.drive_grip() == 0.0 and saw.maneuver == Robot.Maneuver.HOLD)
	passed_case(m, "wheel detachment transfers support and mesh, and total drive failure enters hold")

func test_results() -> void:
	var m := stage()
	var dt := 1.0 / Engine.physics_ticks_per_second
	m.bots[0].hp = 90.0
	m.bots[1].hp = 110.0
	m.fight_elapsed = float(m.cfg.fight_seconds) - dt * 0.5
	m._physics_process(dt)
	assert(m.phase == "result" and m.winner_name == "RIPTIDE" and m.result_reason == "time limit / health decision")
	assert(m.final_hp == [90.0, 110.0] and m.final_ratio == [0.6, 0.55])
	var hit := {"target_part": "chassis", "strength": 1.0, "point": Vector3.ZERO,
		"tangent": Vector3.ZERO, "normal": Vector3.RIGHT, "closing": 4.0}
	m.resolve_strikes(hit.duplicate(), hit.duplicate())
	assert(m.events.is_empty() and m.bots[1].hp == 110.0 and m.bots[0].maneuver == Robot.Maneuver.HOLD)
	m.bots[1].hp = 190.0
	m._finish("knockout")
	var snapshot := m.result_snapshot
	assert(snapshot.is_read_only() and snapshot.robots.is_read_only() and snapshot.robots[1].is_read_only())
	assert(snapshot.robots[1].wheel_states.is_read_only() and snapshot.robots[1].wheel_bases.is_read_only())
	m.bots[1].wheel_state[0] = Robot.Wheel.DRIVE_FAILED
	assert(snapshot.robots[1].hp == 110.0 and snapshot.robots[1].wheel_states[0] == Robot.Wheel.INTACT)
	assert(snapshot.winner_index == 0 and snapshot.reason == "time limit / health decision")
	m.queue_free()
	await physics_frame
	m = stage()
	m.bots[0].hp = 90.0
	m.bots[1].hp = 120.0
	m.fight_elapsed = float(m.cfg.fight_seconds) - dt * 0.5
	m._physics_process(dt)
	assert(m.winner_name == "DRAW" and m.result_reason == "time limit / health decision" and m.final_ratio == [0.6, 0.6])
	assert(m.result_snapshot.winner_index == -1 and m.result_snapshot.robots.size() == 2)
	m.queue_free()
	await physics_frame
	m = stage()
	m.bots[0].hp = 90.0006
	m.bots[1].hp = 120.0
	m.fight_elapsed = float(m.cfg.fight_seconds) - dt * 0.5
	m._physics_process(dt)
	var hud: Control = EpisodeView.new()
	var display: Array[String] = hud.result_percentages(m.final_ratio, false)
	hud.free()
	assert(m.winner_name == "RIPTIDE" and float(display[0].trim_suffix("%")) > float(display[1].trim_suffix("%")))
	m.queue_free()
	await physics_frame
	m = stage()
	m.bots[0].hp = 1.0
	m.bots[1].hp = 1.0
	m.fight_elapsed = float(m.cfg.fight_seconds) - dt * 0.5
	# Deliver both already-selected strikes of the last tick, then expire it.
	m.resolve_strikes(hit.duplicate(), hit.duplicate())
	m._physics_process(dt)
	assert(m.events.size() == 2 and m.winner_name == "DRAW" and m.result_reason == "knockout")
	assert(m.final_hp == [0.0, 0.0] and not m.bots[0].active and not m.bots[1].active)
	passed_case(m, "percentage win and tie, close-result precision, last-tick double knockout and locked result")

func test_episode() -> void:
	var m := stage(false)
	var dt := 1.0 / Engine.physics_ticks_per_second
	var start_poses: Array[Transform3D] = [m.bots[0].transform, m.bots[1].transform]
	for at in [0.5, 1.0, 1.5, 2.0]:
		assert(EpisodeView.reveal(at - 1.0 / 30.0, at) == 0.0)
		assert(EpisodeView.reveal(at, at) > 0.0 and EpisodeView.reveal(at + 0.27, at) == 1.0)
	for i in range(count(10.0) - 1):
		m._physics_process(dt)
		if i == count(5.0) - 1:
			assert(m.phase == "intro" and m.intro_shot_seconds == 5.0 and is_equal_approx(m.elapsed, 5.0))
	assert(m.phase == "intro" and m.fight_elapsed == 0.0 and m.events.is_empty() and m.result_snapshot.is_empty())
	for i in range(2):
		var bot := m.bots[i] as Robot
		assert(bot.transform == start_poses[i] and bot.freeze and not bot.active)
		assert(bot.hp == bot.max_hp and bot.rotor_angle == 0.0 and bot.rotor_speed == 0.0)
	m._physics_process(dt)
	assert(m.phase == "fight" and m.elapsed == 10.0 and m.fight_elapsed == 0.0 and m.cfg.fight_seconds == 25.0)
	for bot: Robot in m.bots:
		assert(bot.active and not bot.freeze)
	m._physics_process(dt)
	assert(is_equal_approx(m.fight_elapsed, dt))
	passed_case(m, "fresh episode resets state, reveals stats in sequence and starts 25-second combat at 10.0")

func test_drive_ratings() -> void:
	var m := stage()
	var deck := StaticBody3D.new()
	deck.position = Vector3(0, -0.5, 60)
	deck.collision_layer = 4
	deck.collision_mask = 1
	var surface := PhysicsMaterial.new()
	surface.friction = float(m.combat.floor_friction)
	deck.physics_material_override = surface
	var floor_shape := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(18, 1, 40)
	floor_shape.shape = slab
	deck.add_child(floor_shape)
	m.add_child(deck)
	var pair: Array[StraightBot] = []
	for kind in ["saw", "drum"]:
		var bot := StraightBot.new()
		bot.configure(kind, m.combat, 0.0, false)
		bot.position = Vector3(4.0 * pair.size(), 0.4, 72.0)
		m.add_child(bot)
		bot.preparing = false
		bot.active = true
		pair.append(bot)
	pair[0].opponent = pair[1]
	pair[1].opponent = pair[0]
	var dt := 1.0 / Engine.physics_ticks_per_second
	for i in range(count(3.5)):
		await physics_frame
		for bot in pair:
			bot.step(dt, Vector2(20.0, 100.0))
	var saw_speed := -pair[0].linear_velocity.z
	var drum_speed := -pair[1].linear_velocity.z
	assert(absf(saw_speed - pair[0].drive_speed) < 0.03 and absf(drum_speed - pair[1].drive_speed) < 0.03)
	assert(absf(saw_speed / drum_speed - 2.0) < 0.025)
	passed_case(m, "undamaged straight drive %.2f / %.2f world units per second" % [saw_speed, drum_speed])

func test_charge_miss() -> void:
	var m := stage()
	var saw := m.bots[0] as Robot
	var drum := m.bots[1] as Robot
	place(saw, Vector3(0,.40,1.8), 0.0, Vector3.ZERO, false)
	place(drum, Vector3(0,.40,-1.8), PI, Vector3.ZERO, true)
	var dt := 1.0 / Engine.physics_ticks_per_second
	var radius := Vector2(4.1, 5.3)
	for i in range(count(.48)):
		await physics_frame
		drum.step(dt, radius)
	assert(drum.maneuver == Robot.Maneuver.ATTACK and drum.linear_velocity.z > 1.25)
	var lane := drum.charge_heading
	# A test-only lateral departure supplies a clear miss for the driver.
	saw.linear_velocity = Vector3(5.3, 0, 0)
	var braked := false
	var reset := false
	var contact := false
	var entry_speed := 0.0
	for i in range(count(1.26)):
		await physics_frame
		drum.step(dt, radius)
		if not braked:
			contact = contact or drum.opponent_contact
			if drum.maneuver == Robot.Maneuver.ATTACK:
				assert(drum.charge_heading.is_equal_approx(lane))
		if not braked and drum.maneuver == Robot.Maneuver.BRAKE:
			braked = true
			entry_speed = drum.linear_velocity.length()
		if braked and drum.maneuver == Robot.Maneuver.LINE_UP:
			reset = drum.linear_velocity.length() < entry_speed - 0.30
			break
	assert(braked and reset and not contact, "Miss must brake and line up again without faking a hit")
	passed_case(m, "missed charge holds its heading, brakes and realigns")

func run() -> void:
	await test_head_on()
	await physics_frame
	await test_strike(false)
	await physics_frame
	await test_strike(true)
	await physics_frame
	await test_sustained()
	await physics_frame
	await test_wall()
	await physics_frame
	await test_wall_pin()
	await physics_frame
	await test_wall_pin(true)
	await physics_frame
	await test_knockout()
	await physics_frame
	await test_component_state()
	await physics_frame
	await test_wheel_separation()
	await physics_frame
	await test_results()
	await physics_frame
	test_episode()
	await physics_frame
	await test_drive_ratings()
	await physics_frame
	await test_charge_miss()
	if passed != 15:
		quit(1)
		return
	print("RFS_FOCUSED_CHECKS_COMPLETE")
	quit()
