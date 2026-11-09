extends RefCounted
## Optional fixed-tick trace for combat QA. No viewer-facing output.
var entries := [{}, {}]
var strikes: Array[Dictionary] = []
var pending: Array[Dictionary] = []
var next_sample := 0.0
var detailed := false
var tracked_ai := false
var tracked_metrics := {"nonfinite_ticks": 0, "first_nonfinite_s": null, "push_s": [0.0, 0.0],
	"productive_push_s": [0.0, 0.0], "longest_quiet_s": 0.0}
var last_exchange := 0.0
var productive_run := [0.0, 0.0]
var contact_time := 0.0
var contact_runs := {}
var deep_contacts: Array[Dictionary] = []
const EXIT_WINDOW := 0.60

func _init() -> void:
	for i in range(2):
		entries[i] = {"name": "", "state": -1, "near_rail_s": 0.0, "corner_s": 0.0,
			"slow_contact_s": 0.0, "pin_s": 0.0, "transitions": [], "recoveries": [], "escape": {},
			"state_seconds": {}, "slow_run_s": 0.0, "longest_slow_run_s": 0.0,
			"stalled_s": 0.0, "stall_run_s": 0.0, "passes": [], "pass_index": -1, "samples": [], "exit_watch": []}

func tick(bots: Array[RigidBody3D], delta: float, time: float, radius: Vector2, fighting: bool) -> void:
	var gap: float = (bots[0].position - bots[1].position).slide(Vector3.UP).length()
	var sample_now := fighting and time + 0.000001 >= next_sample
	if sample_now:
		next_sample += 0.2
	for i in range(2):
		var bot = bots[i]
		var row: Dictionary = entries[i]
		row.name = str(bot.name)
		var near_x: bool = absf(bot.position.x) > radius.x - 1.66
		var near_z: bool = absf(bot.position.z) > radius.y - 1.66
		if fighting:
			var state_key := str(int(bot.maneuver))
			row.state_seconds[state_key] = float(row.state_seconds.get(state_key, 0.0)) + delta
			row.slow_run_s = float(row.slow_run_s) + delta if bot.linear_velocity.slide(Vector3.UP).length() < 0.45 else 0.0
			row.longest_slow_run_s = maxf(row.longest_slow_run_s, row.slow_run_s)
			row.near_rail_s += delta * int(near_x or near_z)
			row.corner_s += delta * int(near_x and near_z)
			row.slow_contact_s += delta * int(bot.opponent_contact and bot.linear_velocity.slide(Vector3.UP).length() < 0.65)
			row.pin_s += delta * int(bot.opponent_contact and bot.wall_contact)
			var stalled: bool = gap < 3.15 and bot.linear_velocity.slide(Vector3.UP).length() < 0.65 \
				and (bot.opponent_contact or bot.wall_contact or bot.maneuver in [bot.Maneuver.ATTACK, bot.Maneuver.RECOVER, bot.Maneuver.REPOSITION])
			if stalled:
				var previous: float = row.stall_run_s
				row.stall_run_s += delta
				if row.stall_run_s >= 0.35:
					row.stalled_s += delta if previous >= 0.35 else row.stall_run_s
			else:
				row.stall_run_s = 0.0
			if sample_now:
				row.samples.append(_decision(bot, time, gap))
			if bot.weapon_disabled or bot.opponent.weapon_disabled:
				_sample_failure(bot, row, gap, delta, time)
		var escape: Dictionary = row.escape
		if not escape.is_empty():
			escape.gain = maxf(escape.gain, gap - float(escape.gap))
			escape.clear_s = float(escape.clear_s) + delta if not bot.opponent_contact else 0.0
			var moved: float = (bot.position - Vector3(escape.origin[0], escape.origin[1], escape.origin[2])).slide(Vector3.UP).length()
			if not escape.separated and escape.clear_s >= 0.13 and gap - float(escape.gap) >= 0.45 and moved >= 0.35:
				escape.separated = true
				escape.separation_at = time
				escape.exit_clear = true
				escape.repinned = false
				row.exit_watch.append(escape)
		_follow_exits(bot, row.exit_watch, gap, time, fighting)
		var state: int = int(bot.maneuver) if fighting else -1
		if state == row.state:
			if state == 2:
				var routes: Array = escape.routes
				var direction := xyz(bot.recovery_direction)
				if routes.back().direction != direction:
					routes.append({"time": time, "direction": direction, "reverse": bot.recovery_reverse})
			continue
		if not escape.is_empty():
			escape.end = time
			escape.end_gap = gap
			row.recoveries.append(escape)
			row.escape = {}
		var continuation: bool = tracked_ai and bot.kind == "drum" and state == bot.Maneuver.RAM_PRESS and row.pass_index >= 0
		if row.pass_index >= 0 and not continuation:
			row.passes[row.pass_index].end = time
			row.pass_index = -1
		row.state = state
		if not fighting:
			continue
		var transition := _decision(bot, time, gap)
		if state == bot.Maneuver.REPOSITION and bot.kind == "saw":
			transition.flank = "rear" if bot.route_rear else "side"
			transition.waypoint = xyz(bot.flank_goal)
			transition.routes_around_front = bot.route_gate
		if bot.kind == "drum" and state in [bot.Maneuver.ATTACK, bot.Maneuver.RAM_PRESS]:
			transition.charge_heading = xyz(bot.charge_heading)
		row.transitions.append(transition)
		if state == bot.Maneuver.ATTACK:
			row.pass_index = row.passes.size()
			var intent := "charge" if bot.kind == "drum" else ("rear" if bot.route_rear else "side")
			if bot.has_method("attack_intent"):
				intent = bot.attack_intent()
			row.passes.append({"start": time, "intent": intent, "hits": 0, "side_rear_hits": 0})
		if state == 2:
			row.escape = {"start": time, "gap": gap, "gain": 0.0, "clear_s": 0.0,
				"origin": xyz(bot.position), "separated": false,
				"routes": [{"time": time, "direction": xyz(bot.recovery_direction), "reverse": bot.recovery_reverse}],
				"rail": near_x or near_z}
	for i in range(pending.size() - 1, -1, -1):
		var sample: Dictionary = pending[i]
		var defender = sample.defender
		var result: Dictionary = sample.result
		result.planar_deflection = maxf(result.planar_deflection,
			(defender.linear_velocity - sample.velocity).slide(Vector3.UP).length())
		result.yaw_change_deg = maxf(result.yaw_change_deg,
			rad_to_deg(absf(angle_difference(sample.yaw, defender.rotation.y))))
		result.lift_m = maxf(result.lift_m, defender.position.y - sample.height)
		if time - float(result.time) >= 0.16 or not fighting:
			pending.remove_at(i)

func observe_tick(bots: Array[RigidBody3D], delta: float, time: float, pair: Dictionary) -> void:
	var finite := is_finite(pair.weapon_depth)
	var exchange: bool = pair.hits.any(func(hit): return not hit.is_empty())
	for i in range(2):
		var bot = bots[i]
		var opponent = bots[1 - i]
		var forward: Vector3 = bot.deck_forward(bot.global_basis)
		finite = finite and bot.global_transform.is_finite() and bot.linear_velocity.is_finite() \
			and bot.angular_velocity.is_finite() and bot.last_order.is_finite() and is_finite(bot.rotor_speed)
		var pushing := false
		for contact in bot.contacts:
			finite = finite and contact.point.is_finite() and contact.normal.is_finite() \
				and contact.relative.is_finite() and is_finite(contact.depth) and is_finite(contact.strength)
			if contact.other_id == opponent.get_instance_id() and bot.last_order.x > 0.4 \
					and forward.dot(contact.normal) < -0.35 and bot.to_local(contact.point).z < -0.30:
				pushing = true
		var productive: bool = pushing and opponent.linear_velocity.dot(forward) >= 0.45
		tracked_metrics.push_s[i] += delta * int(pushing)
		tracked_metrics.productive_push_s[i] += delta * int(productive)
		productive_run[i] = productive_run[i] + delta if productive else 0.0
		exchange = exchange or productive_run[i] >= 0.15
	if not finite:
		tracked_metrics.nonfinite_ticks += 1
		if tracked_metrics.first_nonfinite_s == null:
			tracked_metrics.first_nonfinite_s = time
	tracked_metrics.longest_quiet_s = maxf(tracked_metrics.longest_quiet_s, time - last_exchange)
	if exchange:
		last_exchange = time

func _follow_exits(bot, watches: Array, gap: float, time: float, fighting: bool) -> void:
	for i in range(watches.size() - 1, -1, -1):
		var exit: Dictionary = watches[i]
		exit.exit_clear = exit.exit_clear and not bot.opponent_contact and gap >= float(exit.gap) + 0.20
		exit.repinned = exit.repinned or (bot.opponent_contact and bot.wall_contact)
		if time + 0.000001 >= float(exit.separation_at) + EXIT_WINDOW:
			exit.sustained = exit.exit_clear
			watches.remove_at(i)
		elif not fighting:
			exit.followup_censored = true
			watches.remove_at(i)

func _decision(bot, time: float, gap: float) -> Dictionary:
	var toward: Vector3 = (bot.opponent.position - bot.position).slide(Vector3.UP).normalized()
	var row := {"time": time, "state": int(bot.maneuver), "gap": gap, "grip": bot.drive_grip(),
		"position": xyz(bot.position), "velocity": xyz(bot.linear_velocity), "facing": -bot.global_basis.z.dot(toward),
		"target_front": bot.opponent.global_basis.z.dot(toward), "waypoint": xyz(bot.flank_goal),
		"wall": bot.wall_contact, "contact": bot.opponent_contact, "rotor": bot.rotor_speed,
		"reason": bot.transition_reason}
	if bot.has_method("decision_note"):
		row.decision = bot.decision_note()
	if detailed:
		row.wheels = bot.wheel_state.duplicate()
		if bot.tracked_drive:
			row.tracks = bot.track_state.duplicate()
			row.road_wheels = bot.road_wheel_state.duplicate()
		row.weapon_disabled = bot.weapon_disabled
		row.cooldown = bot.cooldown
		row.latched = bot.strike_latched
		row.target_local = xyz(bot.to_local(bot.opponent.position))
		row.heading = xyz(-bot.global_basis.z)
		row.motor_speed = bot.last_order.x
		row.motor_yaw = bot.last_order.y
		row.yaw_velocity = bot.angular_velocity.y
		row.recovery_age = bot.maneuver_age if bot.maneuver == bot.Maneuver.RECOVER else 0.0
	return row

func observe_weapon(reason: String, attacker, contact: Dictionary) -> void:
	if attacker.kind != "saw":
		return
	if not contact_runs.has(reason):
		contact_runs[reason] = []
	var runs: Array = contact_runs[reason]
	var tick := roundi(contact_time * Engine.physics_ticks_per_second)
	if not runs.is_empty() and int(runs.back().last_tick) >= tick - 1:
		runs.back().last_tick = tick
		runs.back().end = contact_time
		return
	runs.append({"start": contact_time, "end": contact_time, "last_tick": tick,
		"roles": [contact.local_role, contact.other_role], "point": xyz(contact.point),
		"attacker_local": xyz(attacker.to_local(contact.point)), "state": int(attacker.maneuver)})

func inspect_depth(own, other, contact: Dictionary) -> void:
	var query := PhysicsShapeQueryParameters3D.new()
	var rid: RID = own.get_rid()
	query.shape_rid = PhysicsServer3D.body_get_shape(rid, contact.local_shape)
	query.transform = own.global_transform * PhysicsServer3D.body_get_shape_transform(rid, contact.local_shape)
	query.collision_mask = other.collision_layer
	query.exclude = [rid]
	var space: PhysicsDirectSpaceState3D = own.get_world_3d().direct_space_state
	var start := query.transform
	var overlap_offsets := _overlap_offsets(space, query, start, contact.normal, other, contact.other_shape)
	var cross_checks: Array[Dictionary] = []
	if contact.depth >= 0.35:
		for axis: Vector3 in [Vector3.UP, Vector3.DOWN, -contact.normal]:
			cross_checks.append({"axis": xyz(axis),
				"overlap_offsets": _overlap_offsets(space, query, start, axis, other, contact.other_shape)})
	deep_contacts.append({"time": contact_time, "body": str(own.name), "depth": contact.depth,
		"depth_metric": "presolve_witness_projection_m", "shape_query_pose": "published_after_solve",
		"roles": [contact.local_role, contact.other_role], "shapes": [contact.local_shape, contact.other_shape],
		"overlap_offsets": overlap_offsets, "cross_checks": cross_checks,
		"normal": xyz(contact.normal), "point": xyz(contact.point),
		"body_position": xyz(own.position), "opponent_position": xyz(other.position),
		"relative": xyz(contact.relative)})

func _overlap_offsets(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D,
	start: Transform3D, axis: Vector3, other, shape_index: int) -> Array[float]:
	var overlap_offsets: Array[float] = []
	for offset: float in [0.0, 0.02, 0.05, 0.10, 0.20, 0.40]:
		query.transform = start.translated(axis * offset)
		for result in space.intersect_shape(query, 96):
			if result.collider == other and result.shape == shape_index:
				overlap_offsets.append(offset)
				break
	return overlap_offsets

func _sample_failure(bot, row: Dictionary, gap: float, delta: float, time: float) -> void:
	var tail: Dictionary = row.get("failure_tail", {})
	if tail.is_empty():
		tail = {"start": time, "state_seconds": {}, "contact_ticks": {},
			"gap_min": gap, "gap_max": gap, "rotor_stopped": -1.0}
		row.failure_tail = tail
	var state: String = str(int(bot.maneuver))
	tail.state_seconds[state] = float(tail.state_seconds.get(state, 0.0)) + delta
	tail.gap_min = minf(tail.gap_min, gap)
	tail.gap_max = maxf(tail.gap_max, gap)
	if bot.rotor_speed <= 0.001 and tail.rotor_stopped < 0.0:
		tail.rotor_stopped = time
	var seen := {}
	for c in bot.contacts:
		if c.wall:
			continue
		seen[c.local_role + "/" + c.other_role] = true
		if c.local_role == "tooth" and c.other_role in ["chassis", "support", "wheel"]:
			if bot.strike_latched or bot.cooldown > 0.0:
				seen["tooth_rearm"] = true
			if bot.to_local(c.point).z > (-0.70 if bot.kind == "saw" else -0.90):
				seen["tooth_reach"] = true
	for key in seen:
		tail.contact_ticks[key] = int(tail.contact_ticks.get(key, 0)) + 1
	if seen.has("tooth/support") or seen.has("tooth/wheel") or seen.has("tooth/chassis"):
		tail.first_tooth_on_body = tail.get("first_tooth_on_body", time)
		tail.last_tooth_on_body = time

func hit(attacker, defender, contact: Dictionary, damage: int, impulse: Vector3, time: float) -> Dictionary:
	var aim: Vector3 = (defender.position - attacker.position).slide(Vector3.UP).normalized()
	var local: Vector3 = defender.to_local(contact.point)
	var bearing := rad_to_deg(atan2(absf(local.x), -local.z))
	var zone := "rear" if bearing >= 135.0 else ("side" if bearing >= 60.0 else "front")
	var tactics: Dictionary = entries[0 if attacker.kind == "saw" else 1]
	if tactics.pass_index >= 0:
		var pass_record: Dictionary = tactics.passes[tactics.pass_index]
		pass_record.hits += 1
		pass_record.side_rear_hits += int(zone != "front")
	var row := {"time": time, "attacker": str(attacker.name), "part": contact.target_part, "damage": damage, "major": contact.get("major", false),
		"strength": contact.strength, "closing_speed": contact.closing, "attacker_facing": (-attacker.global_basis.z).dot(aim),
		"target_front": defender.global_basis.z.dot(aim), "attack_state": int(attacker.maneuver),
		"point": xyz(contact.point), "defender_local_point": xyz(local), "contact_bearing_deg": bearing, "zone": zone,
		"tangent_impulse": xyz(impulse), "grip_before": defender.drive_grip(),
		"planar_deflection": 0.0, "yaw_change_deg": 0.0, "lift_m": 0.0}
	strikes.append(row)
	pending.append({"defender": defender, "velocity": defender.linear_velocity, "yaw": defender.rotation.y,
		"height": defender.position.y, "result": row})
	return row

static func xyz(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]
