extends "res://scripts/combat/robot.gd"
## Approach a shoulder, then line the saw up with the actual side surface.
var lane_side := 1.0
var cut_heading := Vector3.ZERO
var target_zone := "side"
var last_approach_side := 0.0

func _drive_order(delta: float, radius: Vector2, forward: Vector3) -> Vector2:
	maneuver_age += delta
	var offset := (opponent.position - position).slide(Vector3.UP)
	var distance := offset.length()
	var toward := offset.normalized()
	var nose := deck_forward(opponent.global_basis)
	var inward := _wall_inward(radius)
	var available := Capability.NO_DRIVE if drive_grip() <= 0.0 else (Capability.UNARMED if weapon_disabled else Capability.ARMED)
	if available != capability:
		capability = available
		_enter(Maneuver.HOLD if available == Capability.NO_DRIVE else Maneuver.LINE_UP, "own capability changed")
	if capability == Capability.NO_DRIVE or toward.is_zero_approx():
		return Vector2.ZERO
	var blocked := opponent_contact and linear_velocity.slide(Vector3.UP).length() < 0.55
	stalled = stalled + delta if blocked else maxf(0.0, stalled - 2.0 * delta)
	if maneuver == Maneuver.RECOVER:
		return _exit_order(delta, radius, forward, toward, distance)
	if (wall_contact and (opponent_contact or forward.dot(inward) < -0.4)) or stalled > 0.53:
		_recover(forward, toward, radius, "blocked at rail" if wall_contact else "no translation at contact")
		return _exit_order(delta, radius, forward, toward, distance)
	if capability == Capability.UNARMED:
		if maneuver != Maneuver.GUARD:
			_enter(Maneuver.GUARD, "saw disabled")
		# Protect the wheels and use the room inside the arena if pressed.
		var angle := forward.signed_angle_to(toward, Vector3.UP)
		var retreat := distance < 3.0 and _rail_overflow(position - forward, radius - Vector2.ONE * 1.35) < 0.12
		return _steer(angle, -0.85 * maxf(0.0, cos(angle)) if retreat else 0.0)

	var front := -nose.dot(toward)
	var right := nose.cross(Vector3.UP)
	var estimated_center := opponent.position + _lead(clampf((distance - 1.8) * 0.14, 0.06, 0.24), 0.48)
	var side := signf(-toward.dot(right))
	if is_zero_approx(side):
		side = lane_side
	# The side guard is at about x=.8. Aim slightly inboard of it so the
	# leading saw teeth, rather than the wheel, enter the envelope first.
	var flank_point := estimated_center + right * side * 0.62 - nose * 0.09
	if front < -0.76:
		flank_point = estimated_center - nose * 0.64
	var aim := (flank_point - position).slide(Vector3.UP).normalized()
	var cut := forward.signed_angle_to(aim, Vector3.UP)
	if maneuver == Maneuver.ATTACK:
		var scored := exchange_hit and maneuver_age >= 0.11
		var closed := maneuver_age >= 0.24 and (front > 0.86 or absf(cut) > 1.08)
		if scored or closed or (stalled > 0.28 and maneuver_age > 0.32) or maneuver_age >= 0.86:
			_recover(forward, toward, radius, "saw hit" if scored else ("drum covered the cut" if closed else "pass exhausted"))
			return _exit_order(delta, radius, forward, toward, distance)
		var adjust := clampf(cut_heading.signed_angle_to(aim, Vector3.UP), -0.30, 0.30)
		var angle := forward.signed_angle_to(cut_heading.rotated(Vector3.UP, adjust), Vector3.UP)
		return _steer(angle, drive_speed * clampf(1.0 - absf(angle), 0.22, 1.0))

	if maneuver != Maneuver.REPOSITION:
		_enter(Maneuver.REPOSITION, "choose reachable shoulder")
		route_wait = 0.0
	var mobile := drive_grip()
	var approach_limit := 2.55 + (1.0 - mobile) * 1.1
	var ready := not strike_latched and cooldown <= 0.12 and rotor_speed >= float(tune.weapon_speed) * 0.46
	var aligned := absf(cut) < lerpf(0.40, 0.72, mobile)
	# A side cut can start from an open shoulder, even when a full rear
	# route would let the slower opponent pivot back onto the approach.
	var open := front < 0.70 or (front < 0.88 and absf(offset.dot(right)) > 1.04)
	if ready and aligned and open and distance < 3.36:
		cut_heading = aim
		target_zone = "rear" if front < -0.76 else ("side" if front < 0.50 else "shoulder")
		_enter(Maneuver.ATTACK, "teeth aligned on " + target_zone)
		return _steer(cut, drive_speed)
	if (escape_requested and opponent_contact and front > 0.85) or maneuver_age > approach_limit:
		_recover(forward, toward, radius, "threat closed the lane" if escape_requested else "approach expired")
		return _exit_order(delta, radius, forward, toward, distance)

	route_wait -= delta
	if route_wait <= 0.0:
		var old_side := lane_side
		var best := -INF
		var limit := radius - Vector2.ONE * 1.23
		for sign_candidate: float in [turn_side, -turn_side]:
			# Place the gate on our side of the drum when facing its nose.
			# The earlier lateral move avoids spending the opening inside
			# the drum's closing lane before the shoulder can open.
			var gate_depth := clampf(distance - 1.55, 0.65, 3.6) if front > 0.67 else -0.20
			var gate := estimated_center + right * sign_candidate * 2.15 + nose * gate_depth
			var route := (gate - position).slide(Vector3.UP)
			var alignment := forward.dot(route.normalized())
			var score := -route.length() + alignment * (1.10 + (1.0 - mobile) * 1.65) - 5.0 * _rail_overflow(gate, limit)
			score += 0.62 if sign_candidate == old_side and maneuver_age > 0.08 else 0.0
			score -= 0.48 if sign_candidate == last_approach_side and maneuver_age < 0.35 else 0.0
			if score > best:
				best = score
				lane_side = sign_candidate
				flank_goal = gate
		route_wait = 0.34
	var lane := (flank_goal - position).slide(Vector3.UP)
	var align_now := open and distance < 3.55 and (side == lane_side or front < -0.35)
	var heading := aim if align_now else lane.normalized()
	var reverse := not align_now and mobile < 0.77 and forward.dot(heading) < -0.78
	var speed := drive_speed * (0.60 if align_now else 0.90)
	if align_now and (not ready or not aligned):
		speed *= 0.44
	return _heading_order(forward, heading, speed, reverse)

func _choose_escape(forward: Vector3, toward: Vector3, radius: Vector2) -> void:
	last_approach_side = lane_side
	var nose := deck_forward(opponent.global_basis)
	var threat := opponent.position + _lead(0.25, 0.58)
	var inward := _wall_inward(radius)
	var best := -INF
	for degrees: float in [0, 35, -35, 70, -70, 105, -105]:
		var lane := -toward.rotated(Vector3.UP, deg_to_rad(degrees))
		var endpoint := position + lane * 1.58
		var relative := (endpoint - threat).slide(Vector3.UP)
		var align := forward.dot(lane)
		var score := relative.length() - 1.0 * maxf(0.0, nose.dot(relative.normalized()))
		score += absf(align) * (0.85 + (1.0 - drive_grip()) * 2.2) + 0.28 * align
		score += 0.6 * lane.dot(inward) - 5.0 * _rail_overflow(endpoint, radius - Vector2.ONE * 1.30)
		score -= 1.5 * maxf(0.0, failed_escape.dot(lane))
		if score > best:
			best = score
			recovery_direction = lane
			recovery_reverse = align < 0.0

func _exit_order(delta: float, radius: Vector2, forward: Vector3, toward: Vector3, distance: float) -> Vector2:
	recovery_clear = recovery_clear + delta if not opponent_contact else 0.0
	var travel := (position - recovery_origin).dot(recovery_direction)
	var clear := recovery_clear >= 0.15 and distance >= maxf(2.94, recovery_gap + 0.47) and travel > 0.38
	var expired := maneuver_age > 1.02 + 0.90 * (1.0 - drive_grip())
	if clear or expired:
		failed_escape = Vector3.ZERO if clear else recovery_direction
		_enter(Maneuver.LINE_UP, "usable separation" if clear else "exit expired")
		stalled = 0.0
		return Vector2.ZERO
	if not recovery_replanned and maneuver_age > 0.36 and travel < 0.14 and (opponent_contact or wall_contact):
		failed_escape = recovery_direction
		_choose_escape(forward, toward, radius)
		recovery_replanned = true
	return _heading_order(forward, recovery_direction, drive_speed, recovery_reverse)

func attack_intent() -> String:
	return target_zone
