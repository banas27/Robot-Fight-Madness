extends SceneTree
## Query and solve the captured two-shape poses without the other combat
## shapes, deck or prior contact cache. Every pair starts from the same pose.
const Audit = preload("res://scripts/combat/contact_audit.gd")
const Robot = preload("res://scripts/combat/robot.gd")
const CASES := ["candidate-166-swapped", "rail-exit-15", "rail-exit-4"]

class ProbeBody extends RigidBody3D:
	var witnesses: Array[Dictionary] = []

	func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
		witnesses.clear()
		for i in range(state.get_contact_count()):
			var own := state.get_contact_local_position(i)
			var other := state.get_contact_collider_position(i)
			var normal := state.get_contact_local_normal(i).normalized()
			witnesses.append({"projection_m": maxf(0.0, (other - own).dot(normal)),
				"own_world": Audit.xyz(own), "other_world": Audit.xyz(other),
				"normal_world": Audit.xyz(normal), "reported_impulse": Audit.xyz(state.get_contact_impulse(i))})

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	Engine.physics_ticks_per_second = 180
	var source := "res://qa/wheel-drum/phase"
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			source = arg.trim_prefix("--capture-dir=")
		elif arg.begins_with("--fixture-report="):
			output = arg.trim_prefix("--fixture-report=")
	var evidence: Dictionary = {}
	for case in CASES:
		var capture = JSON.parse_string(FileAccess.get_file_as_string(source.path_join(case + ".trace.json")))
		assert(capture is Dictionary and capture.has("wheel_drum"), "Missing phase capture for " + case)
		var audit: Dictionary = capture.wheel_drum
		var frame: Dictionary
		for item in audit.samples:
			if int(item.tick) == int(audit.center_tick):
				frame = item
				break
		assert(not frame.is_empty())
		var specs: Array = audit.shapes
		var fixed_hub := project_hub(specs[0])
		var controls := await check_controls(specs, null)
		var fixed_controls := await check_controls(specs, fixed_hub)
		if controls.is_empty() or fixed_controls.is_empty():
			quit(1)
			return
		var input := await trial(specs, frame.solver_input.bodies, null, false)
		var published := await trial(specs, frame.published.bodies, null, false)
		assert(input.overlap_before == frame.solver_input.wheel_query)
		assert(published.overlap_before == frame.published.wheel_query)
		assert(input.overlap_before and published.overlap_before == (case != "rail-exit-4"))
		var cylinder := await trial(specs, frame.solver_input.bodies, null, true)
		var faceted := await trial(specs, frame.solver_input.bodies, fixed_hub, true)
		assert(peak_projection(cylinder) > 0.16, "Original witness spike did not reproduce for " + case)
		assert(peak_projection(faceted) < 0.025, "Revised hub generated a deep witness for " + case)
		assert(vector(faceted.response[0].displacement).length() < 0.02, "Revised hub pushed the wheel body too far in one tick.")
		evidence[case] = {"tick": frame.tick, "controls": controls, "revised_controls": fixed_controls,
			"input_query": input.overlap_before,
			"published_query": published.overlap_before, "isolated_cylinder": cylinder, "isolated_prism": faceted}
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		assert(file != null, "Could not write fixture evidence.")
		file.store_string(JSON.stringify(evidence, "\t") + "\n")
	print("RFS_WHEEL_DRUM_FIXTURES_COMPLETE")
	quit()

func project_hub(spec: Dictionary) -> Shape3D:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/combat.json"))
	var bot := Robot.new()
	bot.configure("saw", config, 0.0, false)
	var index := int(spec.shape_index)
	var owner := bot.shape_find_owner(index)
	var shape := bot.shape_owner_get_shape(owner, 0) as ConvexPolygonShape3D
	assert(bot.role_for_shape(index) == "wheel" and shape != null and shape.points.size() == 64)
	assert(is_equal_approx(shape.margin, spec.margin))
	for point in shape.points:
		assert(is_equal_approx(Vector2(point.x, point.z).length(), spec.radius))
		assert(is_equal_approx(absf(point.y) * 2.0, spec.height))
	bot.free()
	return shape

func peak_projection(trial_result: Dictionary) -> float:
	var peak := 0.0
	for body in trial_result.witnesses:
		for witness in body:
			peak = maxf(peak, witness.projection_m)
	return peak

func check_controls(specs: Array, hub: Shape3D) -> Dictionary:
	var ident := Audit.pack_transform(Transform3D.IDENTITY)
	var wheel := {"body_world": ident, "shape_local": ident, "linear_velocity": [0, 0.10, 0], "angular_velocity": [0, 0, 0]}
	var drum := wheel.duplicate()
	drum.linear_velocity = [0, 0, 0]
	drum.body_world = Audit.pack_transform(Transform3D(Basis.IDENTITY, Vector3(0.50, 0.0, 0.0)))
	var separated := await trial(specs, [wheel, drum], hub, true)
	if separated.overlap_before or not separated.witnesses[0].is_empty():
		push_error("Separated fixture returned a contact.")
		return {}
	var drum_half_height: float = specs[1].bounds[1][1]
	drum.body_world = Audit.pack_transform(Transform3D(Basis.IDENTITY, Vector3(0.04, drum_half_height + 0.01, 0.0)))
	var intersecting := await trial(specs, [wheel, drum], hub, true)
	if not intersecting.overlap_before or intersecting.witnesses[0].is_empty():
		push_error("Intersecting fixture did not report a contact: %s" % intersecting)
		return {}
	return {"separated": separated, "deliberate_intersection": intersecting}

func trial(specs: Array, poses: Array, hub: Shape3D, solve: bool) -> Dictionary:
	await physics_frame
	var stage := Node3D.new()
	root.add_child(stage)
	var bodies: Array[ProbeBody] = []
	for i in range(2):
		var spec: Dictionary = specs[i]
		var pose: Dictionary = poses[i]
		var body := ProbeBody.new()
		body.freeze = not solve
		body.gravity_scale = 0.0
		body.can_sleep = false
		body.axis_lock_angular_x = true
		body.axis_lock_angular_z = true
		body.max_contacts_reported = 16
		body.mass = spec.mass
		body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		body.center_of_mass = vector(spec.center_of_mass)
		body.transform = unpack(pose.body_world)
		var collider := CollisionShape3D.new()
		collider.shape = hub if hub != null and i == 0 else make_shape(spec)
		collider.transform = unpack(pose.shape_local)
		body.add_child(collider)
		stage.add_child(body)
		if solve:
			body.linear_velocity = vector(pose.linear_velocity)
			body.angular_velocity = vector(pose.angular_velocity)
			body.sleeping = false
		bodies.append(body)
	if not solve:
		await physics_frame
	var before := pair_query(bodies)
	await physics_frame
	var after := pair_query(bodies)
	var response: Array[Dictionary] = []
	var witnesses: Array[Array] = []
	for i in range(2):
		var body := bodies[i]
		response.append({"displacement": Audit.xyz(body.position - unpack(poses[i].body_world).origin),
			"delta_velocity": Audit.xyz(body.linear_velocity - vector(poses[i].linear_velocity)),
			"angular_velocity": Audit.xyz(body.angular_velocity)})
		witnesses.append(body.witnesses.duplicate())
	stage.free()
	return {"overlap_before": before, "overlap_after": after, "response": response, "witnesses": witnesses}

func pair_query(bodies: Array[ProbeBody]) -> bool:
	var wheel := Audit.intersects(bodies[0], 0, bodies[1], 0)
	var drum := Audit.intersects(bodies[1], 0, bodies[0], 0)
	assert(wheel == drum, "Pair queries disagreed about the intersection.")
	return wheel

func make_shape(spec: Dictionary) -> Shape3D:
	if spec.type == "CylinderShape3D":
		var cylinder := CylinderShape3D.new()
		cylinder.radius = spec.radius
		cylinder.height = spec.height
		cylinder.margin = spec.margin
		return cylinder
	var hull := ConvexPolygonShape3D.new()
	var points := PackedVector3Array()
	for point in spec.points:
		points.append(vector(point))
	hull.points = points
	hull.margin = spec.margin
	return hull

func vector(raw: Array) -> Vector3:
	return Vector3(raw[0], raw[1], raw[2])

func unpack(raw: Array) -> Transform3D:
	return Transform3D(Basis(vector(raw[0]), vector(raw[1]), vector(raw[2])), vector(raw[3]))
