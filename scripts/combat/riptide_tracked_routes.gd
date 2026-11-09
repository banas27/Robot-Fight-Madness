extends "res://scripts/combat/riptide_tracked_flank.gd"
## Keep the saw cut and evaluate room to leave it.
var escape_segment_origin := Vector3.ZERO
var escape_margin := 0.0
var cut_margin := 0.0
var failed_route_timer := 0.0
var reversal_delay := 0.0

func _drive_order(delta: float, radius: Vector2, forward: Vector3) -> Vector2:
	failed_route_timer = maxf(0.0, failed_route_timer - delta)
	if failed_route_timer == 0.0:
		failed_escape = Vector3.ZERO
	return super._drive_order(delta, radius, forward)

func _cut_open(front: float, lateral: float) -> bool:
	return super._cut_open(front, lateral) or (front < 0.92 and lateral > 1.36)

func _cut_closed(front: float, cut: float, distance: float) -> bool:
	# The leading teeth have not arrived at 0.24 s on many shoulder cuts.
	# Allow the committed heading to carry a closing pass into reach.
	if maneuver_age < 0.32:
		return false
	var toward := (opponent.position - position).slide(Vector3.UP).normalized()
	var closing := (linear_velocity - opponent.linear_velocity).dot(toward)
	return absf(cut) > 1.12 or (front > 0.95 and (distance < 2.8 or closing < 0.45))

func _exit_available(radius: Vector2, forward: Vector3, toward: Vector3, aim: Vector3, distance: float) -> bool:
	var contact_pose := position + aim * clampf(distance - 2.33, 0.0, 0.95)
	var reverse_room := _room(contact_pose - aim * 0.95, aim, radius)
	var cross := aim.cross(Vector3.UP)
	var nose := deck_forward(opponent.global_basis)
	# Also test the shoulder continuation that leads away from the drum.
	var best := reverse_room if aim.dot(toward) > 0.56 else -INF
	for side: float in [-1.0, 1.0]:
		var lane := (aim * 0.58 + cross * side * 0.81).normalized()
		if lane.dot(toward) > 0.48 or lane.dot(nose) > 0.78:
			continue
		best = maxf(best, _room(contact_pose + lane * 0.92, lane, radius))
	cut_margin = best if is_finite(best) else -2.0
	return best > -0.10 and _room(contact_pose, forward, radius) > -0.18

func _gate_preference(gate: Vector3, center: Vector3, nose: Vector3, forward: Vector3, radius: Vector2) -> float:
	var move := (gate - position).slide(Vector3.UP).normalized()
	var heading := -move if forward.dot(move) < -0.78 and drive_grip() < 0.77 else move
	var slack := _room(gate, heading, radius)
	var drum := Vector3(center.x, position.y, center.z) + nose * 0.95
	var nearest := Geometry3D.get_closest_point_to_segment(drum, position, Vector3(gate.x, position.y, gate.z))
	var intrudes := drum.distance_to(nearest) < minf(drum.distance_to(position) - 0.12, 1.58)
	var repeats := maxf(0.0, failed_escape.dot(move) - 0.38)
	return 0.85 * clampf(slack, -1.2, 0.7) - (2.0 if intrudes else 0.0) - 1.6 * repeats

func _choose_escape(forward: Vector3, toward: Vector3, radius: Vector2) -> void:
	last_approach_side = lane_side
	escape_segment_origin = position
	var threat := opponent.position + _lead(0.28, 0.62)
	var nose := deck_forward(opponent.global_basis)
	var start_gap := (position - threat).slide(Vector3.UP).length()
	var start_room := _room(position, forward, radius)
	var inward := _wall_inward(radius)
	var grip := drive_grip()
	var best := -INF
	var routes: Array[Vector3] = [forward, -forward]
	if not inward.is_zero_approx():
		routes.append(inward)
		routes.append(inward.rotated(Vector3.UP, PI * 0.29))
		routes.append(inward.rotated(Vector3.UP, -PI * 0.29))
	for degrees: float in [0, 35, -35, 70, -70, 105, -105]:
		routes.append((-toward).rotated(Vector3.UP, deg_to_rad(degrees)))
	for lane in routes:
		var alignment := forward.dot(lane)
		var reverse := alignment < 0.0
		var heading := -lane if reverse else lane
		var turn := acos(clampf(absf(alignment), 0.0, 1.0))
		var endpoint := position + lane * lerpf(1.18, 1.64, grip)
		var room := _room(endpoint, heading, radius)
		var separation := (endpoint - threat).slide(Vector3.UP)
		var gain := separation.length() - start_gap
		var pursuit := maxf(0.0, nose.dot(separation.normalized()))
		var score := 1.55 * gain - 1.35 * pursuit - turn * lerpf(2.90, 1.18, grip)
		score += 1.0 * clampf(room - start_room, -1.3, 0.9) - 4.5 * maxf(0.0, -room)
		score -= 4.2 * maxf(0.0, failed_escape.dot(lane) - 0.43)
		score -= 2.0 * maxf(0.0, lane.dot(toward) - 0.08)
		score += 1.2 * lane.dot(inward) + 0.12 * linear_velocity.dot(lane)
		if score > best:
			best = score
			recovery_direction = lane
			recovery_reverse = reverse
			escape_margin = room
	reversal_delay = clampf(-linear_velocity.dot(recovery_direction) * 0.12, 0.0, 0.27)

func _exit_order(delta: float, radius: Vector2, forward: Vector3, toward: Vector3, distance: float) -> Vector2:
	recovery_clear = recovery_clear + delta if not opponent_contact else 0.0
	var moved := (position - recovery_origin).slide(Vector3.UP).length()
	var segment_progress := (position - escape_segment_origin).dot(recovery_direction)
	var room := _room(position, forward, radius)
	var exposed := -deck_forward(opponent.global_basis).dot(toward)
	var separation := recovery_clear >= 0.17 and distance >= maxf(2.88, recovery_gap + 0.45) and moved >= 0.40
	var repositioned := recovery_clear >= 0.21 and moved > 0.64 and room > 0.40 \
		and exposed < 0.40 and distance >= 2.76
	var clear := repositioned or (separation and (room > 0.18 or exposed < 0.63 or distance > 3.44))
	var expired := maneuver_age > 1.13 + 0.65 * (1.0 - drive_grip())
	if clear or expired:
		if not clear:
			_remember_failure()
		_enter(Maneuver.LINE_UP, "exit opened a new approach" if clear else "exit exhausted")
		stalled = 0.0
		return Vector2.ZERO
	if not recovery_replanned and maneuver_age > 0.35 + reversal_delay and segment_progress < 0.16 			and (wall_contact or opponent_contact or distance < recovery_gap + 0.08):
		_remember_failure()
		_choose_escape(forward, toward, radius)
		recovery_replanned = true
	return _heading_order(forward, recovery_direction, drive_speed, recovery_reverse)

func _remember_failure() -> void:
	failed_escape = recovery_direction
	failed_route_timer = 1.35

static func _room(point: Vector3, heading: Vector3, radius: Vector2) -> float:
	# Planar swept envelope of the wheel width and longer saw nose.
	var nose := point + heading * 1.20
	var tail := point - heading * 0.68
	var side := heading.cross(Vector3.UP).abs() * 0.85
	return minf(radius.x - maxf(absf(nose.x), absf(tail.x)) - side.x,
		radius.y - maxf(absf(nose.z), absf(tail.z)) - side.z) - 0.13

func decision_note() -> Dictionary:
	return {"cut_exit_room_m": cut_margin, "escape_room_m": escape_margin,
		"exit_lane": [recovery_direction.x, recovery_direction.z],
		"exit_reverse": recovery_reverse, "failed_route_s": failed_route_timer,
		"segment_progress_m": (position - escape_segment_origin).dot(recovery_direction)}
