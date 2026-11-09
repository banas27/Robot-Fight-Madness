extends "res://scripts/combat/robot.gd"
## Alternate saw orders. All motor commands, capability changes and contacts
## still use CombatRobot. Distances are planar world units.

var note := ""
var attack_offset := Vector3.ZERO
var previous_pass_side := 0.0
var escape_leg_origin := Vector3.ZERO
var redirected := false

func decision_note() -> String:
	return note

func attack_intent() -> String:
	if note == "outside shoulder opening":
		return "shoulder"
	return "rear" if route_rear else "side"

func _drive_order(delta: float, radius: Vector2, forward: Vector3) -> Vector2:
	var available := _capability()
	if exchange_hit and maneuver != Maneuver.RECOVER and available in [Capability.ARMED, Capability.OPEN_TARGET]:
		capability = available
		previous_pass_side = turn_side
		var toward := (opponent.position - position).slide(Vector3.UP).normalized()
		return _exit_pass("saw hit: leave contact", radius, forward, toward)
	return super._drive_order(delta, radius, forward)

func _begin_flank(radius: Vector2) -> void:
	_enter(Maneuver.REPOSITION)
	redirected = false
	_plan_saw_lane(radius)

func _plan_saw_lane(radius: Vector2) -> void:
	route_right = opponent.global_basis.x
	route_back = opponent.global_basis.z
	var origin := opponent.position + _lead(0.24, 0.62)
	var local := (position - origin).slide(Vector3.UP)
	var limit := radius - Vector2.ONE * 1.16
	var forward := -global_basis.z
	var best := INF
	for side: float in [-1.0, 1.0]:
		var wide := local.dot(route_right) * side >= 1.9
		var gate := local.dot(route_back) < -0.65 and not wide
		var rear := local.dot(route_back) > 1.25 and absf(local.dot(route_right)) < 1.75
		var target := _flank_point(origin, side, gate, rear)
		var heading := (target - position).slide(Vector3.UP).normalized()
		var facing := forward.dot(heading)
		var cost := position.distance_to(target) + 5.0 * _rail_overflow(target, limit)
		cost += 2.1 * _nose_risk(position.lerp(target, 0.62), origin, route_back, route_right)
		cost += lerpf(2.05, 0.90, drive_grip()) * (1.0 - maxf(facing, -facing * 0.63))
		cost += 0.7 if side == previous_pass_side else 0.0
		if cost < best:
			best = cost
			turn_side = side
			route_gate = gate
			route_rear = rear
	_update_saw_waypoint(radius)

func _flank_point(origin: Vector3, side: float, gate: bool, rear: bool) -> Vector3:
	if gate:
		return origin + route_right * (side * 2.85) - route_back * 2.02
	if rear:
		return origin + route_right * (side * 0.72) + route_back * 2.42
	return origin + route_right * (side * 2.46) + route_back * 0.58

func _update_saw_waypoint(radius: Vector2) -> void:
	var origin := opponent.position + _lead(0.24, 0.62)
	var local := (position - origin).slide(Vector3.UP)
	if route_gate and (local.dot(route_right) * turn_side > 2.05 or local.dot(route_back) > -0.53):
		route_gate = false
	var target := _flank_point(origin, turn_side, route_gate, route_rear)
	var limit := radius - Vector2.ONE * 1.16
	flank_goal = Vector3(clampf(target.x, -limit.x, limit.x), position.y, clampf(target.z, -limit.y, limit.y))
	var lane := (flank_goal - position).slide(Vector3.UP).normalized()
	flank_reverse = (-global_basis.z).dot(lane) < (-0.69 if failed_wheel_count > 0 else -0.88)
	route_wait = 0.16
	note = "front gate" if route_gate else ("rear lane" if route_rear else "side lane")

func _saw_order(delta: float, radius: Vector2, forward: Vector3, toward: Vector3, distance: float) -> Vector2:
	if escape_requested or stalled > 0.39 or (maneuver == Maneuver.REPOSITION and pressure_time > 0.33):
		return _exit_pass("contact blocked approach", radius, forward, toward)
	if maneuver == Maneuver.EVADE:
		if maneuver_age < 0.50:
			return _heading_order(forward, dodge_heading, drive_speed, dodge_reverse)
		_begin_flank(radius)
	if maneuver != Maneuver.ATTACK:
		if _try_dodge(radius, forward, distance):
			note = "clear drum charge lane"
			return _heading_order(forward, dodge_heading, drive_speed, dodge_reverse)
		if maneuver != Maneuver.REPOSITION:
			_begin_flank(radius)
		return _approach(delta, radius, forward, toward, distance)
	var front: float = opponent.global_basis.z.dot(toward)
	var contact_limit := 0.37 if front < 0.61 else 0.20
	if maneuver_age > 1.04 or (maneuver_age > 0.25 and pressure_time > contact_limit):
		return _exit_pass("pass missed or blocked", radius, forward, toward)
	var aim := toward * distance + _lead(0.15, 0.47) + attack_offset
	var cut := forward.signed_angle_to(aim.normalized(), Vector3.UP)
	if maneuver_age > 0.28 and absf(cut) > 1.02:
		return _exit_pass("target passed the saw", radius, forward, toward)
	return _steer(cut, drive_speed * clampf(1.0 - absf(cut) * 0.92, 0.0, 1.0))

func _approach(delta: float, radius: Vector2, forward: Vector3, toward: Vector3, distance: float) -> Vector2:
	route_wait -= delta
	if route_wait <= 0.0:
		_update_saw_waypoint(radius)
	var front: float = opponent.global_basis.z.dot(toward)
	var local_side: float = signf(opponent.global_basis.x.dot(-toward))
	if is_zero_approx(local_side):
		local_side = turn_side
	var offset: Vector3 = opponent.global_basis.x * local_side * 0.60 + opponent.global_basis.z * 0.39
	var attack_heading := (toward * distance + _lead(0.15, 0.47) + offset).normalized()
	var cut := forward.signed_angle_to(attack_heading, Vector3.UP)
	var ready := cooldown < 0.16 and rotor_speed >= float(tune.weapon_speed) * weapon_output() * 0.82
	var flank_open := front < (0.55 if not opponent.weapon_disabled else 0.72)
	# If the drum keeps facing us, a close outside shoulder can still be
	# reachable. Require both lateral clearance and saw alignment.
	var shoulder_open: bool = maneuver_age > 0.92 and front < 0.90 and distance < 3.24 \
		and opponent.maneuver != Maneuver.ATTACK and opponent.maneuver != Maneuver.RAM_PRESS
	if ready and maneuver_age >= 0.19 and distance < 3.64 and absf(cut) < 0.58 and (flank_open or shoulder_open):
		attack_offset = offset
		route_rear = front < -0.62
		previous_pass_side = turn_side
		_enter(Maneuver.ATTACK)
		note = "side/rear opening" if flank_open else "outside shoulder opening"
		return _steer(cut, drive_speed * (1.0 - absf(cut) * 0.65))
	var approach_limit := 2.52 + (1.0 - drive_grip()) * 0.58
	if maneuver_age > approach_limit and not redirected and distance > 2.70 and not opponent_contact and not wall_contact:
		# A closed lane with room to drive calls for another angle, not
		# backing away again. Allow just one bounded correction.
		redirected = true
		previous_pass_side = turn_side
		_plan_saw_lane(radius)
		note = "closed lane; redirect once"
	if maneuver_age > approach_limit + (0.84 if redirected else 0.0):
		previous_pass_side = turn_side
		return _exit_pass("lane closed before alignment", radius, forward, toward)
	var lane := (flank_goal - position).slide(Vector3.UP)
	var heading := lane.normalized()
	var reverse := flank_reverse
	if distance < 4.9 and front > 0.36:
		# Keep translating around the nose. Chasing a point on a turning
		# chassis lets the drum catch up while the saw brakes to turn in.
		var tangent := toward.cross(Vector3.UP) * -turn_side
		var radial := clampf((distance - 2.43) * 0.87, -0.82, 1.25)
		heading = (tangent + toward * radial).normalized()
		var inward := _wall_inward(radius)
		if heading.dot(inward) < -0.10:
			heading = (heading + inward * 0.83).normalized()
		reverse = failed_wheel_count > 0 and forward.dot(heading) < -0.78
	if (flank_open or shoulder_open) and distance < 3.75:
		# Turn the saw in before requesting a full speed pass.
		var blend := 0.81 if ready else 0.36
		heading = (heading * (1.0 - blend) + attack_heading * blend).normalized()
		return _approach_order(forward, heading, false, 0.82)
	return _approach_order(forward, heading, reverse, 1.0)

func _approach_order(forward: Vector3, lane: Vector3, reverse: bool, speed_scale: float) -> Vector2:
	var angle := forward.signed_angle_to(-lane if reverse else lane, Vector3.UP)
	var throttle := clampf(1.0 - absf(angle) * 0.73, 0.0, 1.0)
	var speed := -float(cfg.reverse_speed) if reverse else drive_speed
	return _steer(angle, speed * throttle * speed_scale)

func _try_dodge(radius: Vector2, forward: Vector3, distance: float) -> bool:
	if opponent.maneuver != Maneuver.ATTACK or opponent.charge_id == evaded_charge or distance < 2.62 or distance > 5.10:
		return false
	var run: Vector3 = opponent.charge_heading
	var across := run.cross(Vector3.UP)
	var local := (position - opponent.position).slide(Vector3.UP)
	if local.dot(run) < 2.2 or absf(local.dot(across)) > 1.5:
		return false
	var motion := linear_velocity.slide(Vector3.UP)
	var lateral := local.dot(across)
	if absf(lateral + motion.dot(across) * 0.28) > 1.60:
		return false
	var best := -INF
	var chosen := Vector3.ZERO
	for side: float in [-1.0, 1.0]:
		var lane := (across * side + run * 0.16).normalized()
		var end := position + lane * 1.45
		if _rail_overflow(end, radius - Vector2.ONE * 1.12) > 0.25:
			continue
		var facing := forward.dot(lane)
		var score := absf(lateral + 1.45 * side) + 1.4 * maxf(facing, -facing * 0.49)
		score += 0.24 * motion.dot(lane)
		if score > best:
			best = score
			chosen = lane
	if chosen.is_zero_approx():
		return false
	dodge_heading = chosen
	dodge_reverse = forward.dot(chosen) < -0.68
	evaded_charge = opponent.charge_id
	_enter(Maneuver.EVADE)
	return true

func _exit_pass(why: String, radius: Vector2, forward: Vector3, toward: Vector3) -> Vector2:
	_recover(forward, toward, radius)
	note = why
	return _recover_order(0.0, radius, forward, toward, recovery_gap)

func _choose_escape(forward: Vector3, toward: Vector3, radius: Vector2) -> void:
	var away := -toward if not toward.is_zero_approx() else -forward
	var back: Vector3 = opponent.global_basis.z
	var right: Vector3 = opponent.global_basis.x
	var threat := opponent.position + _lead(0.32, 0.77)
	var limit := radius - Vector2.ONE * 1.34
	var motion := linear_velocity.slide(Vector3.UP).limit_length(3.5)
	var turn_rate := float(tune.turn_speed) * lerpf(0.44, 0.77, drive_grip())
	var forward_travel := 1.65 / (drive_speed * 0.85)
	var reverse_travel := 1.65 / (float(cfg.reverse_speed) * 0.90)
	var best := -INF
	for degrees in [0.0, 28.0, -28.0, 55.0, -55.0, 82.0, -82.0, 110.0, -110.0]:
		var route := away.rotated(Vector3.UP, deg_to_rad(degrees))
		var endpoint := position + route * 1.65
		var alignment := forward.dot(route)
		var angle := acos(clampf(alignment, -1.0, 1.0))
		var forward_eta := angle / turn_rate + forward_travel
		var reverse_eta := (PI - angle) / turn_rate + reverse_travel
		var score := (endpoint - threat).slide(Vector3.UP).length() - 7.0 * _rail_overflow(endpoint, limit)
		score -= 1.45 * _nose_risk(endpoint, threat, back, right)
		score -= lerpf(2.6, 1.8, drive_grip()) * minf(forward_eta, reverse_eta)
		score += 0.15 * motion.dot(route)
		score -= 2.6 * maxf(0.0, (route.dot(failed_escape) - 0.50) / 0.50)
		if score > best:
			best = score
			recovery_direction = route
			recovery_reverse = reverse_eta < forward_eta
	escape_leg_origin = position

func _recover_order(delta: float, radius: Vector2, forward: Vector3, toward: Vector3, distance: float) -> Vector2:
	recovery_clear = 0.0 if opponent_contact else recovery_clear + delta
	var travel := (position - recovery_origin).slide(Vector3.UP).length()
	var separated := recovery_clear >= 0.14 and distance >= maxf(3.0, recovery_gap + 0.49) and travel > 0.49
	var limit := 1.42 + (1.0 - drive_grip()) * 0.83
	if (separated and maneuver_age >= 0.34) or maneuver_age >= limit:
		failed_escape = Vector3.ZERO if separated else recovery_direction
		if capability == Capability.ARMED:
			_begin_flank(radius)
		else:
			_resume_tactics(radius, toward)
		note = "separated; new approach" if separated else "escape time limit; change route"
		return Vector2.ZERO
	var progress := (position - escape_leg_origin).slide(Vector3.UP).dot(recovery_direction)
	var inward := _wall_inward(radius)
	var near_bad_rail := not inward.is_zero_approx() and recovery_direction.dot(inward) < -0.30
	if not recovery_replanned and maneuver_age > 0.55 + (1.0 - drive_grip()) * 0.37:
		if (progress < 0.15 and (opponent_contact or wall_contact)) or (near_bad_rail and wall_contact):
			failed_escape = recovery_direction
			recovery_replanned = true
			_choose_escape(forward, toward, radius)
			note = "blocked exit; alternate route"
	return _heading_order(forward, recovery_direction, drive_speed, recovery_reverse)

static func _nose_risk(point: Vector3, center: Vector3, back: Vector3, right: Vector3) -> float:
	var local := point - center
	var ahead := -local.dot(back)
	if ahead < 0.9 or ahead > 4.1:
		return 0.0
	return clampf((1.55 - absf(local.dot(right))) / 1.55, 0.0, 1.0)
