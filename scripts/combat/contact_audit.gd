extends RefCounted
## Optional read-only sampling of one wheel/drum shape pair. Witnesses are
## generated before resolution and published at the next script iteration.
const WINDOW_TICKS := 108
var center_tick := 0
var indices := PackedInt32Array()
var shape_specs: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var submitted: Dictionary = {}

func configure(options: String) -> bool:
	var fields := options.split(",")
	if fields.size() != 3:
		return false
	for field in fields:
		if not field.is_valid_int() or int(field) < 0:
			return false
	center_tick = int(fields[0])
	indices = PackedInt32Array([int(fields[1]), int(fields[2])])
	return center_tick > WINDOW_TICKS + 1

func submit(bots: Array[RigidBody3D], next_time: float) -> void:
	var tick := roundi(next_time * Engine.physics_ticks_per_second)
	if abs(tick - center_tick) > WINDOW_TICKS:
		return
	submitted = _pose(bots)
	submitted.tick = tick

func publish(bots: Array[RigidBody3D], time: float) -> void:
	var tick := roundi(time * Engine.physics_ticks_per_second)
	if abs(tick - center_tick) > WINDOW_TICKS:
		return
	if submitted.get("tick", -1) != tick or submitted.engine_frame + 1 != Engine.get_physics_frames():
		push_error("Missing paired solver input at combat tick %d." % tick)
		return
	var published := _pose(bots)
	var witnesses: Array[Array] = [[], []]
	for i in range(bots.size()):
		var bot = bots[i]
		for witness in bot.audit_witnesses:
			if witness.engine_frame != published.engine_frame:
				continue
			var row := {"projection_m": maxf(0.0, (witness.other_point - witness.own_point).dot(witness.normal))}
			for key in ["own_point", "other_point", "normal", "own_point_velocity", "other_point_velocity", "reported_impulse"]:
				row[key] = xyz(witness[key])
			witnesses[i].append(row)
	samples.append({"tick": tick, "observed_time_s": time, "solver_input": submitted,
		"published": published, "input_witnesses_world": witnesses})

func evidence() -> Dictionary:
	return {"center_tick": center_tick, "physics_hz": Engine.physics_ticks_per_second,
		"engine": Engine.get_version_info(), "shapes": shape_specs, "samples": samples}

func _pose(bots: Array[RigidBody3D]) -> Dictionary:
	if shape_specs.is_empty():
		for i in range(bots.size()):
			shape_specs.append(describe_shape(bots[i], indices[i]))
	var bodies: Array[Dictionary] = []
	for i in range(bots.size()):
		var bot = bots[i]
		var rid: RID = bot.get_rid()
		var body: Transform3D = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM)
		var local := PhysicsServer3D.body_get_shape_transform(rid, indices[i])
		bodies.append({"body_world": pack_transform(body), "shape_local": pack_transform(local),
			"shape_world": pack_transform(body * local), "linear_velocity": xyz(bot.linear_velocity),
			"angular_velocity": xyz(bot.angular_velocity), "hp": bot.hp, "wheel_states": bot.wheel_state.duplicate(),
			"weapon_disabled": bot.weapon_disabled, "rotor_speed": bot.rotor_speed, "drive_grip": bot.drive_grip(),
			"action": int(bot.maneuver), "wall_contact": bot.wall_contact, "opponent_contact": bot.opponent_contact,
			"shape_disabled": bot.is_shape_owner_disabled(bot.shape_find_owner(indices[i]))})
	return {"engine_frame": Engine.get_physics_frames(), "bodies": bodies,
		"wheel_query": intersects(bots[0], indices[0], bots[1], indices[1]),
		"drum_query": intersects(bots[1], indices[1], bots[0], indices[0])}

static func intersects(own: CollisionObject3D, own_index: int, other: CollisionObject3D, other_index: int) -> bool:
	if own.is_shape_owner_disabled(own.shape_find_owner(own_index)):
		return false
	var rid := own.get_rid()
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape_rid = PhysicsServer3D.body_get_shape(rid, own_index)
	var body: Transform3D = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM)
	query.transform = body * PhysicsServer3D.body_get_shape_transform(rid, own_index)
	query.exclude = [rid]
	query.collision_mask = other.collision_layer
	for hit in own.get_world_3d().direct_space_state.intersect_shape(query, 96):
		if hit.collider == other and hit.shape == other_index:
			return true
	return false

static func describe_shape(bot, index: int) -> Dictionary:
	var owner: int = bot.shape_find_owner(index)
	var shape: Shape3D
	for slot in range(bot.shape_owner_get_shape_count(owner)):
		if bot.shape_owner_get_shape_index(owner, slot) == index:
			shape = bot.shape_owner_get_shape(owner, slot)
			break
	assert(shape != null)
	var row := {"body": str(bot.name), "body_instance_id": bot.get_instance_id(), "shape_index": index,
		"shape_owner_id": owner, "role": bot.role_for_shape(index), "type": shape.get_class(), "margin": shape.margin,
		"mass": bot.mass, "center_of_mass": xyz(bot.center_of_mass)}
	if shape is CylinderShape3D:
		row.radius = shape.radius
		row.height = shape.height
	elif shape is ConvexPolygonShape3D:
		var points: Array[Array] = []
		var bounds := AABB(shape.points[0], Vector3.ZERO)
		for point in shape.points:
			bounds = bounds.expand(point)
			points.append(xyz(point))
		row.points = points
		row.bounds = [xyz(bounds.position), xyz(bounds.end)]
	return row

static func xyz(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

static func pack_transform(value: Transform3D) -> Array[Array]:
	return [xyz(value.basis.x), xyz(value.basis.y), xyz(value.basis.z), xyz(value.origin)]
