extends "res://scripts/combat/robot.gd"
## Keep the baseline recovery clock and orders. Near a rail under pressure,
## pick the direction and gear that can start moving with limited turning.

var chose_rail_exit := false

func decision_note() -> String:
	return "drive out along a reachable rail exit" if maneuver == Maneuver.RECOVER and chose_rail_exit else ""

func _choose_escape(forward: Vector3, toward: Vector3, radius: Vector2) -> void:
	chose_rail_exit = recovery_wall and (opponent_contact or position.distance_to(opponent.position) < 3.25)
	if not chose_rail_exit:
		super._choose_escape(forward, toward, radius)
		return

	var limit := radius - Vector2.ONE * 1.26
	var present_rail_cost := _rail_overflow(position, limit)
	var pressure := opponent.position + _lead(0.22, 0.62)
	var grip := drive_grip()
	var best := -INF
	for reverse in [false, true]:
		var gear_axis := -forward if reverse else forward
		var travel := 1.13 if reverse else 1.48
		for degrees in [0.0, -24.0, 24.0, -42.0, 42.0]:
			var turn := deg_to_rad(degrees)
			var route := gear_axis.rotated(Vector3.UP, turn)
			var endpoint := position + route * travel
			# Test the first movement on the current heading as well as the
			# endpoint. A good endpoint is useless if we drive into the rail first.
			var first := position + gear_axis * 0.30
			var rail_entry := maxf(0.0, _rail_overflow(first, limit) - present_rail_cost)
			var gap := (endpoint - pressure).slide(Vector3.UP).length()
			var score := gap - 6.2 * _rail_overflow(endpoint, limit) - 4.0 * rail_entry
			score -= 2.7 * maxf(0.0, route.dot(toward))
			score -= absf(turn) * lerpf(2.4, 1.15, grip)
			score -= 1.65 * maxf(0.0, (route.dot(failed_escape) - 0.52) / 0.48)
			if score > best:
				best = score
				recovery_direction = route
				recovery_reverse = reverse
