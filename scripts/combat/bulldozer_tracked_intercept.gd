extends "res://scripts/combat/robot.gd"
## Intercept lateral motion, then keep a ram pointed through the contact.
var dead_push := 0.0
var last_escape := Vector3.ZERO
var drive_mode := -2

func _drive_order(delta: float, radius: Vector2, forward: Vector3) -> Vector2:
	maneuver_age += delta
	var offset := (opponent.position - position).slide(Vector3.UP)
	var distance := offset.length()
	var toward := offset.normalized()
	var left := _track_grip(0) > 0.0
	var right := _track_grip(1) > 0.0
	var mode := 2 if left and right else (-1 if left else (1 if right else 0))
	if mode != drive_mode:
		drive_mode = mode
		_enter(Maneuver.HOLD if mode == 0 else Maneuver.LINE_UP, "track drive availability changed")
	if mode == 0 or toward.is_zero_approx():
		return Vector2.ZERO
	var inward := _wall_inward(radius)
	var nose_angle := forward.signed_angle_to(toward, Vector3.UP)
	if maneuver == Maneuver.RECOVER:
		return _back_out(delta, radius, forward, toward, distance)
	var nose_at_rail := wall_contact and forward.dot(inward) < -0.36
	if nose_at_rail or (wall_contact and opponent_contact and maneuver_age > 0.40):
		_recover(forward, toward, radius, "leave rail before another ram")
		return _back_out(delta, radius, forward, toward, distance)

	var lateral := opponent.linear_velocity.slide(Vector3.UP).slide(toward)
	var horizon := clampf((distance - 1.95) / (drive_speed * 2.0), 0.0, 0.32)
	var aim := (offset + (lateral * horizon).limit_length(0.72)).normalized()
	var alignment := forward.signed_angle_to(aim, Vector3.UP)
	if maneuver == Maneuver.ATTACK:
		if opponent_contact and absf(nose_angle) < 0.80:
			_enter(Maneuver.RAM_PRESS, "connected ram")
			contact_lost = 0.0
			dead_push = 0.0
		elif maneuver_age >= 1.28 or (maneuver_age > 0.34 and absf(nose_angle) > 0.96):
			_enter(Maneuver.BRAKE, "ram missed")
			return Vector2.ZERO
		else:
			var correction := clampf(charge_heading.signed_angle_to(aim, Vector3.UP), -0.15, 0.15)
			return _drivable_order(forward.signed_angle_to(charge_heading.rotated(Vector3.UP, correction), Vector3.UP), drive_speed)
	if maneuver == Maneuver.RAM_PRESS:
		contact_lost = 0.0 if opponent_contact else contact_lost + delta
		var advances := opponent.linear_velocity.dot(forward) >= 0.45
		dead_push = dead_push + delta if opponent_contact and not advances else maxf(0.0, dead_push - delta * 2.0)
		if contact_lost > 0.18 or absf(nose_angle) > 1.02:
			_enter(Maneuver.BRAKE, "contact slipped off drum")
			return Vector2.ZERO
		if dead_push > 0.39 or maneuver_age > 2.16:
			_recover(forward, toward, radius, "push ceased to advance")
			return _back_out(delta, radius, forward, toward, distance)
		var press_correction := clampf(charge_heading.signed_angle_to(toward, Vector3.UP), -0.23, 0.23)
		var press_heading := charge_heading.rotated(Vector3.UP, press_correction)
		return _drivable_order(forward.signed_angle_to(press_heading, Vector3.UP), drive_speed)
	if maneuver == Maneuver.BRAKE and maneuver_age >= 0.19:
		_enter(Maneuver.LINE_UP, "realign after miss")
	if maneuver == Maneuver.BRAKE:
		return Vector2.ZERO

	var room := _rail_overflow(position + forward * 1.15, radius - Vector2.ONE * 1.16) < 0.30
	var can_connect := absf(alignment) < (0.26 if drive_mode == 2 else 0.34)
	if maneuver_age > 0.16 and can_connect and distance < 4.35 and room:
		charge_heading = aim
		charge_id += 1
		_enter(Maneuver.ATTACK, "committed intercept" if not weapon_disabled else "drive with front armour")
		return _drivable_order(alignment, drive_speed if not weapon_disabled else drive_speed * 0.75)
	var throttle := (0.73 if room else 0.26) * clampf(1.0 - absf(alignment) * 1.13, 0.0, 1.0)
	return _drivable_order(alignment, drive_speed * throttle)

func _drivable_order(angle: float, speed: float) -> Vector2:
	if drive_mode == 2:
		return _steer(angle, speed)
	# A right belt turns left going forwards. A left belt turns left in
	# reverse. Only request the arc the surviving belt can generate.
	var reverse := absf(angle) > 0.21 and angle * drive_mode < 0.0
	var travel := -0.82 if reverse else maxf(speed * 0.67, minf(absf(angle), 0.82))
	return _steer(angle, travel)

func _choose_escape(forward: Vector3, toward: Vector3, radius: Vector2) -> void:
	var inward := _wall_inward(radius)
	var best := -INF
	for degrees: float in [0, 28, -28, 58, -58, 88, -88]:
		var lane := (-toward).rotated(Vector3.UP, deg_to_rad(degrees))
		var align := forward.dot(lane)
		var reverse := align < 0.0
		var angle := forward.signed_angle_to(-lane if reverse else lane, Vector3.UP)
		if drive_mode != 2 and absf(angle) > 0.16 and angle * drive_mode * (-1.0 if reverse else 1.0) < 0.0:
			continue
		var score := -lane.dot(toward) + absf(align) * 0.80 + lane.dot(inward) * 0.50
		score -= 5.5 * _rail_overflow(position + lane * 1.22, radius - Vector2.ONE * 1.24)
		score -= 0.87 * maxf(0.0, last_escape.dot(lane))
		if score > best:
			best = score
			recovery_direction = lane
			recovery_reverse = reverse
	if best == -INF:
		recovery_reverse = forward.dot(toward) > 0.0
		recovery_direction = -forward if recovery_reverse else forward

func _back_out(delta: float, radius: Vector2, forward: Vector3, toward: Vector3, distance: float) -> Vector2:
	recovery_clear = 0.0 if opponent_contact else recovery_clear + delta
	var travel := (position - recovery_origin).dot(recovery_direction)
	var clear := recovery_clear >= 0.14 and travel > 0.35 and distance > recovery_gap + 0.32
	if clear or maneuver_age > (0.94 if drive_mode == 2 else 1.30):
		last_escape = Vector3.ZERO if clear else recovery_direction
		_enter(Maneuver.LINE_UP, "room to realign" if clear else "reverse did not open room")
		return Vector2.ZERO
	if not recovery_replanned and maneuver_age > 0.34 and travel < 0.12 and (opponent_contact or wall_contact):
		last_escape = recovery_direction
		_choose_escape(forward, toward, radius)
		recovery_replanned = true
	return _heading_order(forward, recovery_direction, drive_speed * (0.76 if drive_mode == 2 else 0.65), recovery_reverse)
