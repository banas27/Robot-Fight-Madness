extends "res://scripts/combat/riptide_tracked_routes.gd"
## Leave the drum's nose using a turn the loaded wheels can reach.

func _choose_escape(forward: Vector3, toward: Vector3, radius: Vector2) -> void:
	super._choose_escape(forward, toward, radius)
	var nose := deck_forward(opponent.global_basis)
	if nose.dot(-toward) < 0.42 or position.distance_to(opponent.position) > 3.15:
		return
	var grip := supported_drive_grip()
	var max_turn := lerpf(0.38, 0.90, grip)
	var threat := opponent.position + _lead(0.28, 0.62)
	var best := -INF
	for travel_sign in [1.0, -1.0]:
		for steer_fraction in [-1.0, -0.50, 0.0, 0.50, 1.0]:
			var travel: Vector3 = (forward * travel_sign).rotated(Vector3.UP, max_turn * steer_fraction)
			if travel.dot(toward) > 0.22:
				continue
			var reach: float = 1.75 if travel_sign > 0.0 else 1.22
			var destination := position + travel * reach
			var relative := (destination - threat).slide(Vector3.UP)
			var room: float = _room(destination, travel * travel_sign, radius)
			var outside_nose := 1.0 - maxf(0.0, nose.dot(relative.normalized()))
			var score := 0.85 * relative.length() + 3.3 * outside_nose
			score += minf(room, 1.0) * 0.52 - 4.2 * maxf(0.0, -room)
			score -= 3.3 * maxf(0.0, failed_escape.dot(travel) - 0.45)
			score -= 0.52 * absf(steer_fraction) * (1.0 - grip)
			if score > best:
				best = score
				recovery_direction = travel
				recovery_reverse = travel_sign < 0.0
				escape_margin = room
	reversal_delay = clampf(-linear_velocity.dot(recovery_direction) * 0.12, 0.0, 0.27)

func _exit_order(delta: float, radius: Vector2, forward: Vector3, toward: Vector3, distance: float) -> Vector2:
	var beside_drum := deck_forward(opponent.global_basis).dot(-toward) < 0.55
	var moved := (position - recovery_origin).slide(Vector3.UP).length()
	# A clear shoulder is useful space even if the opponent follows our exit.
	if recovery_clear >= 0.17 and moved >= 0.48 and not opponent_contact \
			and beside_drum and distance >= 2.48 and not strike_latched:
		_enter(Maneuver.LINE_UP, "clear of drum arc")
		stalled = 0.0
		return Vector2.ZERO
	return super._exit_order(delta, radius, forward, toward, distance)
