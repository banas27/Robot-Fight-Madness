extends RigidBody3D
## Compound chassis with a low centre of mass and free tilt after wheel loss.
const SawArt = preload("res://scripts/art/riptide_visual.gd")
const DrumArt = preload("res://scripts/art/bulldozer_visual.gd")
const RobotArt = preload("res://scripts/art/robot_visual.gd")
const Fit = preload("res://scripts/combat/collision_fit.gd")

var kind: String
var team_color: Color
var cfg: Dictionary
var tune: Dictionary
var hp: float
var max_hp: float
var drive_speed: float
var drive_drag: float
var deck_drag: float
var opponent: RigidBody3D
var active := false
var preparing := true
var art: RobotArt
var visual_override: Script
var shape_roles: Dictionary = {}
var rotor_owner: int
var weapon_pivot: Vector3
var weapon_axis: Vector3
var hit_count := 0
var recovery_count := 0
var cooldown := 0.0
var rotor_angle := 0.0
var collision_angle := 0.0
var rotor_speed := 0.0
var flash := 0.0
var contacts: Array[Dictionary] = []
var supported_wheels := 0
var deck_contact_roles: Dictionary = {}
enum Maneuver { LINE_UP, ATTACK, RECOVER, REPOSITION, GUARD, PRESS, HOLD, EVADE, RAM_PRESS, BRAKE }
enum Capability { ARMED, UNARMED, OPEN_TARGET, NO_DRIVE }
enum Wheel { INTACT, WORN, SEVERE, DRIVE_FAILED, DETACHED }
const WHEEL_WORN := 8.0
const WHEEL_SEVERE := 19.0
const WHEEL_FAILED := 39.0
const WHEEL_MOUNT_BROKEN := 72.0
var maneuver := Maneuver.LINE_UP
var maneuver_age := 0.0
var transition_reason := ""
var trace_orders := false
var last_order := Vector2.ZERO
var audit_local_shape := -1
var audit_other_shape := -1
var audit_witnesses: Array[Dictionary] = []
var maneuver_counts := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
var capability := Capability.ARMED
var press_wide := false
var flank_reverse := false
var turn_side := 1.0
var charge_heading := Vector3.ZERO
var charge_id := 0
var contact_lost := 0.0
var evaded_charge := -1
var dodge_heading := Vector3.ZERO
var dodge_reverse := false
var route_gate := false
var route_rear := false
var route_wait := 0.0
var route_right := Vector3.RIGHT
var route_back := Vector3.BACK
var pass_time := 0.0
var pass_started := false
var recovery_direction := Vector3.ZERO
var recovery_reverse := false
var recovery_wall := false
var recovery_origin := Vector3.ZERO
var recovery_gap := 0.0
var recovery_clear := 0.0
var recovery_replanned := false
var failed_escape := Vector3.ZERO
var escape_requested := false
var flank_goal := Vector3.ZERO
var exchange_hit := false
var pressure_time := 0.0
var stalled := 0.0
var wall_contact := false
var opponent_contact := false
var armor_damage := 0.0
var wheel_damage := [0.0, 0.0, 0.0, 0.0]
var wheel_state := [0, 0, 0, 0]
var failed_wheel_count := 0
var detached_wheel_count := 0
var traction := 1.0
var impact_unload := 0.0
var weapon_damage := 0.0
var weapon_disabled := false
var strike_latched := false
var clear_contact_time := 0.0
var settle_time := 0.0
var settle_origin: Vector3
var settle_direction := Vector3.ZERO

func configure(weapon_kind: String, settings: Dictionary, phase: float, show_art: bool) -> void:
	kind = weapon_kind
	cfg = settings
	tune = cfg[kind]
	max_hp = float(tune.max_hp)
	hp = max_hp
	drive_speed = float(tune.speed_rating) * float(cfg.speed_per_rating)
	name = String(tune.name)
	turn_side = 1.0 if phase < 3.0 else -1.0
	team_color = Color(String(tune.color))
	mass = float(tune.mass)
	center_of_mass_mode = CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.17, 0.015)
	inertia = Vector3(mass * 0.29, mass * (0.39 if kind == "drum" else 0.34), mass * 0.26)
	linear_damp = 0.30
	drive_drag = linear_damp + float(ProjectSettings.get_setting("physics/3d/default_linear_damp", 0.1))
	deck_drag = float(cfg.floor_friction) * float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	angular_damp = 0.85
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	# Native CCD sweeps body translation, not the tooth owner's rotation.
	# The fitted rotor runs at the combat tick rate instead.
	continuous_cd = false
	can_sleep = false
	collision_layer = Fit.BODY
	collision_mask = Fit.BODY | Fit.WALL | Fit.DECK
	max_contacts_reported = 48
	var physics := PhysicsMaterial.new()
	physics.friction = float(cfg.floor_friction)
	physics.bounce = 0.06
	physics_material_override = physics
	Fit.install(self)
	if show_art:
		art = make_visual()
		add_child(art)

func make_visual() -> RobotArt:
	if visual_override != null:
		return visual_override.new()
	return SawArt.new() if kind == "saw" else DrumArt.new()

func add_solid(shape: Shape3D, local: Transform3D, role: String) -> void:
	var owner := create_shape_owner(self)
	shape_owner_add_shape(owner, shape)
	shape_owner_set_transform(owner, local)
	shape_roles[owner] = role

func sync_weapon_shapes() -> void:
	# Each complete tooth pitch leaves the collider union unchanged. Keep
	# an equivalent phase nearest the previous one so a solver manifold
	# can stay on the same spatial tooth as the saw spins past one pitch.
	var pitch := TAU / (24.0 if kind == "saw" else 3.0)
	collision_angle = fposmod(collision_angle + fposmod(rotor_angle - collision_angle + pitch * 0.5, pitch) - pitch * 0.5, TAU)
	shape_owner_set_transform(rotor_owner, Transform3D(Basis(weapon_axis, collision_angle), weapon_pivot))

func role_for_shape(index: int) -> String:
	return shape_roles.get(shape_find_owner(index), "chassis")

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	contacts.clear()
	if audit_local_shape >= 0:
		audit_witnesses.clear()
	supported_wheels = 0
	deck_contact_roles.clear()
	wall_contact = false
	opponent_contact = false
	for i in range(state.get_contact_count()):
		var other := state.get_contact_collider_object(i) as CollisionObject3D
		if other == null:
			continue
		if other.collision_layer == Fit.DECK:
			if state.get_contact_local_normal(i).y > 0.5:
				var index := state.get_contact_local_shape(i)
				var role := role_for_shape(index)
				deck_contact_roles[role] = true
				if role == "wheel":
					supported_wheels |= 1 << wheel_for_shape(index)
			continue
		var here := state.get_contact_local_position(i)
		var there := state.get_contact_collider_position(i)
		var point := (here + there) * 0.5
		var normal := state.get_contact_local_normal(i).normalized()
		var relative := state.get_contact_local_velocity_at_position(i) - state.get_contact_collider_velocity_at_position(i)
		var impulse := state.get_contact_impulse(i).length() / mass
		var local_shape := state.get_contact_local_shape(i)
		var other_shape := state.get_contact_collider_shape(i)
		if local_shape == audit_local_shape and other_shape == audit_other_shape and other == opponent:
			audit_witnesses.append({"engine_frame": Engine.get_physics_frames(),
				"own_point": here, "other_point": there, "normal": normal,
				"own_point_velocity": state.get_contact_local_velocity_at_position(i),
				"other_point_velocity": state.get_contact_collider_velocity_at_position(i),
				"reported_impulse": state.get_contact_impulse(i)})
		var is_wall := other.collision_layer == Fit.WALL
		wall_contact = wall_contact or is_wall
		opponent_contact = opponent_contact or other == opponent
		var other_role: String = other.role_for_shape(other_shape) if other.has_method("role_for_shape") else "wall"
		# This is the native contact witnesses' projection from the solve
		# input pose. A query at the published pose is a separate measurement.
		contacts.append({"point": point, "normal": normal, "strength": maxf(impulse, -relative.dot(normal) * 0.75),
			"slide": (relative - normal * relative.dot(normal)).length(), "wall": is_wall,
			"local_role": role_for_shape(local_shape), "other_role": other_role, "local_shape": local_shape, "other_shape": other_shape,
			"other_id": other.get_instance_id(), "relative": relative, "depth": maxf(0.0, (there - here).dot(normal))})

static func deck_forward(orientation: Basis) -> Vector3:
	var planar := -orientation.z.slide(Vector3.UP)
	if planar.length_squared() < 0.0001:
		planar = Vector3.UP.cross(orientation.x)
	return planar.normalized()

func step(delta: float, radius: Vector2) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	flash = maxf(0.0, flash - delta * 4.5)
	var target_spin := float(tune.weapon_speed) * weapon_output() if active and hp > 0.0 else (float(tune.weapon_speed) * 0.61 if preparing else 0.0)
	rotor_speed = move_toward(rotor_speed, target_spin, float(tune.spin_up) * delta)
	if rotor_speed > 0.0:
		rotor_angle = fposmod(rotor_angle + rotor_speed * delta, TAU)
		sync_weapon_shapes()
	var forward := deck_forward(global_basis)
	var right := forward.cross(Vector3.UP)
	var desired_speed := 0.0
	var desired_yaw := 0.0
	var braking := true
	if active and hp > 0 and is_instance_valid(opponent):
		var order := _drive_order(delta, radius, forward)
		if trace_orders:
			last_order = order
		desired_speed = order.x
		desired_yaw = order.y
		braking = absf(desired_speed) < absf(linear_velocity.dot(forward)) or maneuver == Maneuver.RECOVER
	elif preparing and kind == "saw" and is_instance_valid(opponent):
		# Set the opening angle on the spot while the saw spools up.
		var opening: Vector3 = (opponent.position - position).slide(Vector3.UP).normalized().rotated(Vector3.UP, -turn_side * 0.83)
		desired_yaw = _steer(forward.signed_angle_to(opening, Vector3.UP), 0.0).y
	elif settle_time > 0.0 and hp > 0.0:
		settle_time -= delta
		if position.distance_to(settle_origin) < 0.87 and position.distance_to(opponent.position) < 3.18:
			var reverse := forward.dot(settle_direction) < 0.0
			var heading := -settle_direction if reverse else settle_direction
			var angle := forward.signed_angle_to(heading, Vector3.UP)
			desired_yaw = clampf(angle * 4.6, -2.4, 2.4)
			desired_speed = (-1.65 if reverse else 1.65) * clampf(1.0 - absf(angle) * 1.45, 0.0, 1.0)
	# Briefly unload the motors after a hard strike so they don't immediately
	# cancel the velocity and yaw the solver and rotor transfer just produced.
	var control := 1.0 - 0.66 * clampf(impact_unload / 0.12, 0.0, 1.0)
	impact_unload = maxf(0.0, impact_unload - delta)
	var grip := supported_drive_grip() * control
	var limit := float(cfg.brake_acceleration) if braking else float(tune.acceleration)
	# Feed forward the nominal deck resistance at cruising speed. Damage,
	# impacts and traction still scale this force through the same grip.
	var cruise := smoothstep(0.70, 1.0, absf(desired_speed) / drive_speed)
	var drag := (signf(desired_speed) * deck_drag + desired_speed * drive_drag) * cruise
	var longitudinal := clampf((desired_speed - linear_velocity.dot(forward)) * 5.0 + drag, -limit, limit)
	var sideways := clampf(-linear_velocity.dot(right) * float(cfg.lateral_grip), -11.0, 11.0)
	var drive := forward * longitudinal + right * sideways
	if active and not is_zero_approx(desired_speed):
		# Ease the motor into a surface it is already touching, without
		# cutting the lateral force that lets it turn or peel away.
		for contact in contacts:
			var outward := Vector3(contact.normal.x, 0, contact.normal.z).normalized()
			var push := drive.dot(outward)
			var push_limit := 3.2 if kind == "drum" and (maneuver == Maneuver.ATTACK or maneuver == Maneuver.RAM_PRESS) and desired_speed > 0.0 and not contact.wall else 1.8
			if push < -push_limit:
				drive += outward * (-push_limit - push)
	apply_central_force(drive * mass * grip)
	var yaw_accel := clampf((desired_yaw - angular_velocity.y) * float(tune.turn_response), -23.0, 23.0)
	apply_torque(Vector3.UP * inertia.y * yaw_accel * grip)
	if art != null:
		art.update_visual(delta, rotor_angle, linear_velocity.dot(forward), angular_velocity.y, flash * 0.42, hp <= 0.0)

func _drive_order(delta: float, radius: Vector2, forward: Vector3) -> Vector2:
	maneuver_age += delta
	var to_opponent: Vector3 = (opponent.position - position).slide(Vector3.UP)
	var distance := to_opponent.length()
	var toward := to_opponent.normalized()
	var angle := forward.signed_angle_to(toward, Vector3.UP)
	var planar_speed := linear_velocity.slide(Vector3.UP).length()
	var inward := _wall_inward(radius)
	var wall_trap := not inward.is_zero_approx() and forward.dot(inward) < -0.40 and (wall_contact or planar_speed < 0.65)
	var available := _capability()
	if available != capability:
		capability = available
		_resume_tactics(radius, toward)
	if capability == Capability.NO_DRIVE:
		return Vector2.ZERO
	if maneuver == Maneuver.RECOVER:
		return _recover_order(delta, radius, forward, toward, distance)
	pressure_time = pressure_time + delta if opponent_contact else maxf(0.0, pressure_time - delta * 2.4)
	stalled = stalled + delta if opponent_contact and planar_speed < 0.52 else maxf(0.0, stalled - delta * 2.0)
	if wall_trap or (wall_contact and pressure_time > 0.30):
		_recover(forward, toward, radius, "nose toward rail" if wall_trap else "rail under pressure")
		return Vector2.ZERO
	if capability == Capability.UNARMED:
		if stalled > 0.92 and maneuver_age > 0.70:
			_recover(forward, toward, radius)
			return Vector2.ZERO
		return _guard_order(forward, toward, inward, distance)
	if capability == Capability.OPEN_TARGET:
		return _press_order(radius, forward, toward, distance, planar_speed)
	if kind == "drum":
		return _drum_order(delta, radius, forward, toward, distance, angle)
	return _saw_order(delta, radius, forward, toward, distance)

func _drum_order(delta: float, radius: Vector2, forward: Vector3, toward: Vector3, distance: float, angle: float) -> Vector2:
	var aim := (toward * distance + _lead(0.23, 0.66)).normalized()
	if maneuver == Maneuver.ATTACK:
		if opponent_contact and absf(angle) < 0.65:
			_enter(Maneuver.RAM_PRESS)
			contact_lost = 0.0
		elif maneuver_age > 1.40 or (maneuver_age > 0.40 and absf(angle) > 0.95):
			_enter(Maneuver.BRAKE)
			return Vector2.ZERO
		else:
			var correction := clampf(charge_heading.signed_angle_to(aim, Vector3.UP), -0.11, 0.11)
			return _steer(forward.signed_angle_to(charge_heading.rotated(Vector3.UP, correction), Vector3.UP), drive_speed)
	if maneuver == Maneuver.RAM_PRESS:
		contact_lost = 0.0 if opponent_contact else contact_lost + delta
		if contact_lost > 0.20 or absf(angle) > 1.02:
			_enter(Maneuver.BRAKE)
			return Vector2.ZERO
		if stalled > 0.96 or maneuver_age > 2.05:
			_recover(forward, toward, radius)
			return Vector2.ZERO
		var correction := clampf(charge_heading.signed_angle_to(toward, Vector3.UP), -0.21, 0.21)
		return _steer(forward.signed_angle_to(charge_heading.rotated(Vector3.UP, correction), Vector3.UP), drive_speed)
	if maneuver == Maneuver.BRAKE:
		if maneuver_age < 0.24:
			return Vector2.ZERO
		_enter(Maneuver.LINE_UP)
	# Line up using the target lead, but don't charge across a nearby rail.
	var alignment := forward.signed_angle_to(aim, Vector3.UP)
	var room := _rail_overflow(position + forward * 1.2, radius - Vector2.ONE * 1.18) < 0.30
	if maneuver_age > 0.19 and absf(alignment) < 0.27 and distance < 4.40 and room:
		charge_heading = aim
		charge_id += 1
		_enter(Maneuver.ATTACK)
		return _steer(alignment, drive_speed)
	if stalled > 0.72:
		_recover(forward, toward, radius)
		return Vector2.ZERO
	var approach := clampf(1.0 - absf(alignment) * 1.26, 0.0, 1.0)
	return _steer(alignment, drive_speed * (0.72 if room else 0.22) * approach)

func _saw_order(delta: float, radius: Vector2, forward: Vector3, toward: Vector3, distance: float) -> Vector2:
	if maneuver == Maneuver.EVADE:
		if maneuver_age >= 0.57:
			_begin_flank(radius)
		else:
			return _heading_order(forward, dodge_heading, drive_speed, dodge_reverse)
	if escape_requested or stalled > float(cfg.stuck_seconds) + 0.02 or (maneuver == Maneuver.REPOSITION and pressure_time > 0.48):
		_recover(forward, toward, radius, "incoming strike" if escape_requested else "blocked approach")
		return Vector2.ZERO
	if _try_dodge(radius, forward, distance):
		return _heading_order(forward, dodge_heading, drive_speed, dodge_reverse)
	if maneuver == Maneuver.LINE_UP:
		_begin_flank(radius)
	var front := -deck_forward(opponent.global_basis).dot(toward)
	if maneuver == Maneuver.REPOSITION:
		route_wait -= delta
		if route_wait <= 0.0:
			_update_saw_waypoint(radius)
		var lane := (flank_goal - position).slide(Vector3.UP)
		var ready := rotor_speed >= float(tune.weapon_speed) * weapon_output() * 0.86
		var opening := front < 0.82 and distance < 3.82
		var wide: bool = (position - opponent.position).dot(route_right) * turn_side > 1.63
		var shoulder := wide and distance < 3.43 and lane.length() < 1.18
		if ready and maneuver_age >= 0.24 and (opening or shoulder):
			_enter(Maneuver.ATTACK, "open approach" if opening else "outside shoulder")
		elif maneuver_age > 2.05 + (1.0 - drive_grip()):
			if front < 0.86 and distance < 3.90:
				_enter(Maneuver.ATTACK, "approach time limit with opening")
			else:
				_recover(forward, toward, radius, "approach time limit")
				return Vector2.ZERO
		else:
			# Turn the saw in as the lane opens, then go through that opening.
			var heading := lane.normalized()
			if opening or (wide and lane.length() < 1.72 and distance < 3.7):
				heading = (heading * 0.34 + toward * 0.78).normalized()
			var approach_speed := drive_speed * clampf(lane.length() / 1.7, 0.38, 0.96)
			return _heading_order(forward, heading, approach_speed, flank_reverse and not opening)
	if (maneuver_age >= 0.23 and exchange_hit) or pass_time >= 0.82 or maneuver_age >= 1.58:
		_recover(forward, toward, radius, "scored hit" if exchange_hit else "pass time limit")
		return Vector2.ZERO
	var side: float = signf(deck_forward(opponent.global_basis).cross(Vector3.UP).dot(-toward))
	if is_zero_approx(side):
		side = turn_side
	var shoulder_offset := lerpf(0.20, 0.80, clampf((front - 0.38) / 0.50, 0.0, 1.0))
	var aim: Vector3 = toward * distance + _lead(0.18, 0.54) + deck_forward(opponent.global_basis).cross(Vector3.UP) * side * shoulder_offset
	var cut := forward.signed_angle_to(aim.normalized(), Vector3.UP)
	if absf(cut) < 0.65 or opponent_contact:
		pass_started = true
	if pass_started:
		pass_time += delta
	return _steer(cut, drive_speed * clampf(1.0 - absf(cut) * 0.82, 0.0, 1.0))

func _try_dodge(radius: Vector2, forward: Vector3, distance: float) -> bool:
	if opponent.maneuver != Maneuver.ATTACK or opponent.charge_id == evaded_charge or distance < 2.93 or distance > 4.65:
		return false
	var run: Vector3 = opponent.charge_heading
	var from_drum: Vector3 = (position - opponent.position).slide(Vector3.UP)
	var cross := run.cross(Vector3.UP)
	if from_drum.dot(run) < 2.65 or absf(from_drum.dot(cross)) > 1.12 or opponent.linear_velocity.dot(run) < 0.82:
		return false
	var limit := radius - Vector2.ONE * 1.42
	var best := -INF
	var chosen := Vector3.ZERO
	for side: float in [-1.0, 1.0]:
		var lane := (cross * side + run * 0.24).normalized()
		var endpoint := position + lane * 1.38
		if _rail_overflow(endpoint, limit) > 0.10:
			continue
		var score := absf((endpoint - opponent.position).dot(cross)) + 0.78 * absf(forward.dot(lane))
		if score > best:
			best = score
			chosen = lane
	if chosen.is_zero_approx():
		return false
	dodge_heading = chosen
	dodge_reverse = forward.dot(chosen) < -0.36
	evaded_charge = opponent.charge_id
	_enter(Maneuver.EVADE, "avoid charge lane")
	return true

func _lead(seconds: float, limit: float) -> Vector3:
	return (opponent.linear_velocity.slide(Vector3.UP) * seconds).limit_length(limit)

func _plan_saw_lane(radius: Vector2) -> void:
	var origin: Vector3 = opponent.position + _lead(0.27, 0.80)
	var right: Vector3 = deck_forward(opponent.global_basis).cross(Vector3.UP)
	var back := -deck_forward(opponent.global_basis)
	# Commit to this flank relative to the chassis pose at the planning tick.
	# Lead translation as it moves without letting its yaw drag us in a loop.
	route_right = right
	route_back = back
	var local := position - origin
	var front_distance := -local.dot(back)
	var limit := radius - Vector2.ONE * 1.34
	var best := INF
	var preferred := turn_side
	for side: float in [-1.0, 1.0]:
		var via_front := front_distance > 0.70 and local.dot(right) * side < 2.18
		var gate: Vector3 = origin + right * (side * 2.65) - back * 1.58
		for rear in [false, true]:
			var target: Vector3 = origin + right * (side * (1.62 if rear else 2.57)) + back * (2.28 if rear else 0.47)
			if rear and front_distance > 0.55:
				continue
			var entry := gate if via_front else target
			var heading := (entry - position).slide(Vector3.UP).normalized()
			var route_cost := position.distance_to(entry) + (0.58 * gate.distance_to(target) if via_front else 0.0)
			route_cost += 5.4 * (_rail_overflow(entry, limit) + _rail_overflow(target, limit))
			route_cost += (1.0 + (1.0 - drive_grip()) * 2.0) * (1.0 - deck_forward(global_basis).dot(heading))
			route_cost += 0.18 if side != preferred else 0.0
			if route_cost < best:
				best = route_cost
				turn_side = side
				route_gate = via_front
				route_rear = rear
	_update_saw_waypoint(radius)

func _update_saw_waypoint(radius: Vector2) -> void:
	var origin: Vector3 = opponent.position + _lead(0.27, 0.80)
	var right := route_right
	var back := route_back
	var local := position - origin
	if route_gate and (local.dot(right) * turn_side > 2.17 or -local.dot(back) < 0.55):
		route_gate = false
	var target: Vector3
	if route_gate:
		target = origin + right * (turn_side * 2.65) - back * 1.58
	elif route_rear:
		target = origin + right * (turn_side * 1.62) + back * 2.28
	else:
		target = origin + right * (turn_side * 2.57) + back * 0.47
	var limit := radius - Vector2.ONE * 1.34
	flank_goal = Vector3(clampf(target.x, -limit.x, limit.x), position.y, clampf(target.z, -limit.y, limit.y))
	flank_reverse = failed_wheel_count > 0 and deck_forward(global_basis).dot(flank_goal - position) < -0.70
	route_wait = 0.15

func _steer(angle: float, speed: float) -> Vector2:
	var limit := float(tune.turn_speed)
	if failed_wheel_count > 0:
		# Give the remaining drive time to align before asking it to translate.
		limit *= lerpf(0.65, 1.0, drive_grip())
		speed *= clampf(1.5 - absf(angle), 0.0, 1.0)
	var gain := float(cfg.turn_gain) * (1.0 if maneuver == Maneuver.RECOVER else float(tune.steering_gain))
	return Vector2(speed, clampf(angle * gain, -limit, limit))

func _enter(next: Maneuver, reason := "") -> void:
	maneuver = next
	transition_reason = reason
	maneuver_age = 0.0
	maneuver_counts[next] += 1
	exchange_hit = false
	if next == Maneuver.ATTACK and kind == "saw":
		pass_started = false
		pass_time = 0.0

func _capability() -> Capability:
	if traction <= 0.0:
		return Capability.NO_DRIVE
	if weapon_disabled:
		return Capability.UNARMED
	if opponent.weapon_disabled:
		return Capability.OPEN_TARGET
	return Capability.ARMED

func _resume_tactics(radius: Vector2, toward: Vector3) -> void:
	escape_requested = false
	pressure_time = 0.0
	stalled = 0.0
	match capability:
		Capability.NO_DRIVE:
			_enter(Maneuver.HOLD)
		Capability.UNARMED:
			_enter(Maneuver.GUARD)
		Capability.OPEN_TARGET:
			_enter(Maneuver.PRESS)
			press_wide = -deck_forward(opponent.global_basis).dot(toward) > 0.38
			if press_wide:
				_pick_flank(radius, 2.46)
		_:
			_enter(Maneuver.LINE_UP)

func _guard_order(forward: Vector3, toward: Vector3, inward: Vector3, distance: float) -> Vector2:
	var angle := forward.signed_angle_to(toward, Vector3.UP)
	var speed := drive_speed
	if kind == "drum" or opponent.weapon_disabled:
		# Keep the solid front between the opponent and the wheels. A short
		# shove uses the ordinary motor and chassis contact, even with no drum.
		return _steer(angle, speed * 0.44 * clampf(1.0 - absf(angle) * 1.85, 0.0, 1.0))
	if distance > 3.7 and inward.is_zero_approx():
		return _steer(angle, 0.0)
	var lateral := toward.cross(Vector3.UP) * turn_side
	if not inward.is_zero_approx() and lateral.dot(inward) < 0.0:
		lateral = -lateral
	var lane := (lateral - toward * 0.32 + inward * 0.52).normalized()
	return _steer(forward.signed_angle_to(lane, Vector3.UP), speed * 0.50)

func _press_order(radius: Vector2, forward: Vector3, toward: Vector3, distance: float, planar_speed: float) -> Vector2:
	var front := -deck_forward(opponent.global_basis).dot(toward)
	var lane := (flank_goal - position).slide(Vector3.UP)
	if press_wide:
		if (maneuver_age >= 0.30 and (front < 0.22 or lane.length() < 0.62)) or maneuver_age > 1.06 + (1.0 - drive_grip()):
			press_wide = false
			maneuver_age = 0.0
			pressure_time = 0.0
		else:
			return _heading_order(forward, lane, drive_speed * 0.79, flank_reverse)
	if (front > 0.56 and distance < 3.25 and maneuver_age >= 0.38) or (pressure_time > 0.48 and planar_speed < 0.65):
		# A stationary weapon still blocks its owner's front. Go around the
		# obstruction or shift the contact, rather than backing out to charge.
		_pick_flank(radius, 2.46)
		press_wide = true
		maneuver_age = 0.0
		pressure_time = 0.0
		return _heading_order(forward, (flank_goal - position).slide(Vector3.UP), drive_speed * 0.79, flank_reverse)
	var aim: Vector3 = (opponent.position - deck_forward(opponent.global_basis) * 0.30 - position).slide(Vector3.UP)
	var angle := forward.signed_angle_to(aim.normalized(), Vector3.UP)
	return _steer(angle, drive_speed * 0.78 * clampf(1.0 - absf(angle) * 0.81, 0.0, 1.0))

func _heading_order(forward: Vector3, lane: Vector3, speed: float, reverse: bool) -> Vector2:
	var heading := -lane if reverse else lane
	var angle := forward.signed_angle_to(heading.normalized(), Vector3.UP)
	var throttle := clampf(1.0 - absf(angle) * 0.65, 0.0, 0.90)
	return _steer(angle, (-minf(speed, float(cfg.reverse_speed)) if reverse else speed) * throttle)

func _recover(forward: Vector3, toward: Vector3, radius: Vector2, reason := "") -> void:
	_enter(Maneuver.RECOVER, reason)
	recovery_count += 1
	escape_requested = false
	pressure_time = 0.0
	stalled = 0.0
	recovery_origin = position
	recovery_gap = (opponent.position - position).slide(Vector3.UP).length()
	recovery_clear = 0.0
	recovery_replanned = false
	recovery_wall = not _wall_inward(radius).is_zero_approx()
	_choose_escape(forward, toward, radius)

func _choose_escape(forward: Vector3, toward: Vector3, radius: Vector2) -> void:
	var away := -toward if not toward.is_zero_approx() else -forward
	var opponent_front: Vector3 = deck_forward(opponent.global_basis)
	var threat: Vector3 = opponent.position + opponent.linear_velocity.slide(Vector3.UP) * 0.19
	var limit := radius - Vector2.ONE * 1.51
	var best := -INF
	for degrees in [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 120.0, -120.0]:
		var route := away.rotated(Vector3.UP, deg_to_rad(degrees))
		var endpoint := position + route * (1.66 if kind == "saw" else 1.34)
		var exposed := (endpoint - threat).slide(Vector3.UP)
		var wall_cost := _rail_overflow(endpoint, limit)
		var nose_risk := 0.0 if opponent.weapon_disabled else maxf(0.0, opponent_front.dot(exposed.normalized()))
		var alignment := forward.dot(route)
		var score := exposed.length() - nose_risk * (1.65 if kind == "saw" else 0.85) - wall_cost * 4.8
		score += 0.82 * absf(alignment) + (0.22 * alignment if kind == "saw" else -0.16 * alignment)
		if failed_wheel_count > 0:
			score += absf(alignment) * (1.0 - drive_grip()) * 2.0
		score -= 1.8 * maxf(0.0, (route.dot(failed_escape) - 0.62) / 0.38)
		score += turn_side * signf(degrees) * 0.012
		if score > best:
			best = score
			recovery_direction = route
	recovery_reverse = forward.dot(recovery_direction) < 0.0

func _recover_order(delta: float, radius: Vector2, forward: Vector3, toward: Vector3, distance: float) -> Vector2:
	recovery_clear = 0.0 if opponent_contact else recovery_clear + delta
	var progress := (position - recovery_origin).slide(Vector3.UP).dot(recovery_direction)
	var room := distance >= maxf(3.12, recovery_gap + 0.46)
	var separated := recovery_clear >= 0.16 and room and progress > 0.58
	var limit := (1.36 if kind == "saw" else 1.04) + (0.19 if recovery_wall else 0.0) + (1.0 - drive_grip()) * 0.9
	if (separated and maneuver_age >= 0.52) or maneuver_age >= limit:
		failed_escape = Vector3.ZERO if separated else recovery_direction
		if capability != Capability.ARMED:
			_resume_tactics(radius, toward)
		elif kind == "saw":
			_begin_flank(radius)
			transition_reason = "clear of opponent" if separated else "recovery time limit"
		else:
			_enter(Maneuver.LINE_UP)
		return Vector2.ZERO
	if not recovery_replanned and maneuver_age > 0.54 and progress < 0.22 and (wall_contact or opponent_contact):
		failed_escape = recovery_direction
		recovery_replanned = true
		_choose_escape(forward, toward, radius)
	var heading := -recovery_direction if recovery_reverse else recovery_direction
	var angle := forward.signed_angle_to(heading, Vector3.UP)
	var throttle := clampf(1.0 - absf(angle) * 0.63, 0.0, 1.0)
	var speed := -minf(float(cfg.reverse_speed), drive_speed * 0.80) if recovery_reverse else drive_speed * 0.88
	return _steer(angle, speed * throttle)

func _begin_flank(radius: Vector2) -> void:
	_enter(Maneuver.REPOSITION, "start flank approach")
	_plan_saw_lane(radius)

func _pick_flank(radius: Vector2, width: float) -> void:
	var limit := radius - Vector2.ONE * 1.42
	var axis: Vector3 = deck_forward(opponent.global_basis).cross(Vector3.UP)
	var base: Vector3 = opponent.position - deck_forward(opponent.global_basis) * 0.38
	var best := -INF
	for side in [-1.0, 1.0]:
		var outside: Vector3 = base + axis * side * width
		var score := -position.distance_to(outside) - 4.2 * _rail_overflow(outside, limit)
		score += 0.35 * recovery_direction.dot((outside - position).slide(Vector3.UP).normalized())
		if score > best:
			best = score
			flank_goal = Vector3(clampf(outside.x, -limit.x, limit.x), position.y, clampf(outside.z, -limit.y, limit.y))
			turn_side = side
	flank_reverse = failed_wheel_count > 0 and deck_forward(global_basis).dot(flank_goal - position) < -0.42

static func _rail_overflow(point: Vector3, limit: Vector2) -> float:
	return maxf(0.0, absf(point.x) - limit.x) + maxf(0.0, absf(point.z) - limit.y)

func _wall_inward(radius: Vector2) -> Vector3:
	var inward := Vector3.ZERO
	# Include the rail thickness and the furthest weapon tip.
	if absf(position.x) > radius.x - 1.66:
		inward.x = -signf(position.x)
	if absf(position.z) > radius.y - 1.66:
		inward.z = -signf(position.z)
	return inward.normalized()

func weapon_output() -> float:
	return 0.0 if weapon_disabled else lerpf(1.0, 0.54, clampf((weapon_damage - 11.0) / 40.0, 0.0, 1.0))

func drive_grip() -> float:
	return traction

func supported_drive_grip() -> float:
	var drives := wheel_state.size() - failed_wheel_count
	if drives == 0:
		return 0.0
	var on_deck := 0
	for wheel in range(wheel_state.size()):
		if wheel_state[wheel] < Wheel.DRIVE_FAILED and (supported_wheels & (1 << wheel)) != 0:
			on_deck += 1
	return drive_grip() * float(on_deck) / drives

func _update_traction() -> void:
	var loss := 0.0
	failed_wheel_count = 0
	for wear: float in wheel_damage:
		if wear >= WHEEL_FAILED:
			loss += 0.24
			failed_wheel_count += 1
		elif wear >= WHEEL_SEVERE:
			loss += lerpf(0.12, 0.19, inverse_lerp(WHEEL_SEVERE, WHEEL_FAILED, wear))
		elif wear >= WHEEL_WORN:
			loss += lerpf(0.045, 0.075, inverse_lerp(WHEEL_WORN, WHEEL_SEVERE, wear))
	traction = 0.0 if failed_wheel_count == 4 else 1.0 - minf(loss, maxf(0.52, failed_wheel_count * 0.24))

func wheel_for_shape(shape_index: int) -> int:
	var axle := shape_owner_get_transform(shape_find_owner(shape_index)).origin
	return _wheel_at(axle)

static func _wheel_at(axle: Vector3) -> int:
	return int(axle.x > 0.0) + 2 * int(axle.z > 0.0)

func damage_component(damage: float, part: String, shape_index: int, impulse := Vector3.ZERO) -> Array[String]:
	var changes: Array[String] = []
	if part == "chassis" or part == "support":
		var prior := armor_damage
		armor_damage += damage
		if prior < 18.0 and armor_damage >= 18.0:
			changes.append("armor_damaged")
	if part == "support":
		weapon_damage += damage * 0.78
		if not weapon_disabled and weapon_damage >= 49.0:
			weapon_disabled = true
			changes.append("weapon_disabled")
	elif part == "wheel" and shape_index >= 0:
		var wheel := wheel_for_shape(shape_index)
		wheel_damage[wheel] += damage
		var wear: float = wheel_damage[wheel]
		var stage := Wheel.INTACT
		if wear >= WHEEL_MOUNT_BROKEN:
			stage = Wheel.DETACHED
		elif wear >= WHEEL_FAILED:
			stage = Wheel.DRIVE_FAILED
		elif wear >= WHEEL_SEVERE:
			stage = Wheel.SEVERE
		elif wear >= WHEEL_WORN:
			stage = Wheel.WORN
		if stage != wheel_state[wheel]:
			wheel_state[wheel] = stage
			changes.append(["", "wheel_damaged", "wheel_severe", "wheel_drive_failed", "wheel_detached"][stage])
			if stage == Wheel.DETACHED:
				_detach_wheel(wheel, impulse)
		_update_traction()
	if art != null:
		art.show_damage(armor_damage, wheel_state, weapon_damage, weapon_disabled)
	return changes

func _detach_wheel(wheel: int, impulse: Vector3) -> void:
	detached_wheel_count += 1
	# The intact controller runs yaw-only. Once the support polygon changes,
	# gravity and the surviving tread, skids and mounts determine the tilt.
	axis_lock_angular_x = false
	axis_lock_angular_z = false
	supported_wheels &= ~(1 << wheel)
	var axle := Vector3.ZERO
	var owners: Array[int] = []
	for owner in get_shape_owners():
		if shape_roles[owner] != "wheel":
			continue
		var local := shape_owner_get_transform(owner).origin
		if _wheel_at(local) == wheel:
			owners.append(owner)
			if is_zero_approx(axle.x) or absf(local.x) < absf(axle.x):
				axle = local
	var loose := RigidBody3D.new()
	loose.name = "%sLooseWheel%d" % [name, wheel]
	loose.mass = 1.6
	# The loose wheel rolls on the deck and rails. It cannot block or score
	# against either combatant. The original tire and hub leave the chassis.
	loose.collision_layer = 0
	loose.collision_mask = Fit.WALL | Fit.DECK
	var debris_material := PhysicsMaterial.new()
	debris_material.friction = 0.12
	loose.physics_material_override = debris_material
	loose.linear_damp = 0.36
	loose.angular_damp = 0.55
	for owner in owners:
		var part := CollisionShape3D.new()
		part.shape = shape_owner_get_shape(owner, 0)
		part.transform = shape_owner_get_transform(owner)
		part.position -= axle
		loose.add_child(part)
		shape_owner_set_disabled(owner, true)
	get_parent().add_child(loose)
	var center := to_global(axle)
	loose.global_transform = Transform3D(global_basis, center)
	var outward := global_basis.x * signf(axle.x)
	# Clear the broken shaft with a small release along the axle.
	var release := clampf(impulse.length() / 27.0, 0.50, 0.68)
	var axle_motion := linear_velocity + angular_velocity.cross(center - to_global(center_of_mass))
	loose.linear_velocity = axle_motion + outward * release
	var roll := axle_motion.dot(-global_basis.z)
	loose.angular_velocity = angular_velocity - global_basis.x * (roll / (0.320 if kind == "saw" else 0.294))
	if art != null:
		art.wheel_pivots[wheel].reparent(loose, true)

func stop_fighting() -> void:
	active = false
	preparing = false
	maneuver = Maneuver.HOLD
	escape_requested = false

func begin_settle(radius: Vector2) -> void:
	var away: Vector3 = position - opponent.position
	away.y = 0.0
	away = away.normalized()
	var limit := radius - Vector2.ONE * 0.96
	var best_score := -INF
	for angle in [0.0, 45.0, -45.0, 90.0, -90.0, 120.0, -120.0]:
		var direction := away.rotated(Vector3.UP, deg_to_rad(angle))
		var next := position + direction * 1.0
		var overflow := maxf(0.0, absf(next.x) - limit.x) + maxf(0.0, absf(next.z) - limit.y)
		var score := direction.dot(away) + 0.32 * absf(direction.dot(deck_forward(global_basis))) - 4.0 * overflow
		if score > best_score:
			settle_direction = direction
			best_score = score
	settle_origin = position
	settle_time = 1.75

func struck(damage: float, point: Vector3, impulse: Vector3, strength: float, major: bool) -> void:
	hp = maxf(0.0, hp - damage)
	flash = 1.0 if major else 0.25 + strength * 0.32
	if major:
		impact_unload = 0.14
	if kind == "saw" and strength >= 0.55 and maneuver in [Maneuver.LINE_UP, Maneuver.ATTACK]:
		escape_requested = true
	apply_impulse(impulse, point - global_position)
	if hp <= 0.0:
		active = false
