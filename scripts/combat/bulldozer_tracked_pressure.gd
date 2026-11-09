extends "res://scripts/combat/bulldozer_tracked_intercept.gd"
## Re-aim a connected push when the target slides along the drum.

func _drivable_order(angle: float, speed: float) -> Vector2:
	if maneuver == Maneuver.RAM_PRESS and maneuver_age >= 0.18 and opponent_contact:
		var forward := deck_forward(global_basis)
		var offset := (opponent.position - position).slide(Vector3.UP)
		var actual_angle := forward.signed_angle_to(offset.normalized(), Vector3.UP)
		# Keep the initial interception commitment. After contact, use the
		# live target angle within a small correction from the ram heading.
		var correction := clampf(actual_angle - angle, -0.32, 0.32)
		angle += correction * minf(1.0, (maneuver_age - 0.18) * 5.0)
	return super._drivable_order(angle, speed)
