extends Node
## Read-only observer used by the inherited release audit scene.
const Robot = preload("res://scripts/combat/robot.gd")
const Fit = preload("res://scripts/combat/collision_fit.gd")
const Pack = preload("res://scripts/combat/contact_audit.gd")
const WINDOW := 54
var arena: Node3D
var center_tick := 0
var output := ""
var tick_rows: Array[Dictionary] = []
var frame_rows: Array[Dictionary] = []
var phases: Array[Dictionary] = []
var meshes: Dictionary = {}
var frame := 0
var phase_key := ""

func _ready() -> void:
	arena = get_parent()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--deck-tick="):
			center_tick = int(arg.trim_prefix("--deck-tick="))
		elif arg.begins_with("--deck-report="):
			output = arg.trim_prefix("--deck-report=")
	if center_tick <= 0 or output.is_empty():
		push_error("Pass --deck-tick and --deck-report after --.")
		get_tree().quit(2)
		return
	process_physics_priority = -10
	if DisplayServer.get_name() != "headless":
		RenderingServer.frame_post_draw.connect(_record_frame)

func _physics_process(delta: float) -> void:
	if arena.phase != "fight":
		return
	var tick := roundi((arena.fight_elapsed + delta) * Engine.physics_ticks_per_second)
	if abs(tick - center_tick) > WINDOW:
		return
	var robots: Array[Dictionary] = []
	for bot: Robot in arena.bots:
		var row := _pose(bot)
		row.velocity = Pack.xyz(bot.linear_velocity)
		row.angular_velocity = Pack.xyz(bot.angular_velocity)
		row.wheel_states = bot.wheel_state.duplicate()
		row.hp = bot.hp
		row.cooldown = bot.cooldown
		row.latched = bot.strike_latched
		row.rotor_speed = bot.rotor_speed
		row.weapon_disabled = bot.weapon_disabled
		row.support = bot.supported_wheels
		row.supported_grip = bot.supported_drive_grip()
		row.maneuver = Robot.Maneuver.keys()[bot.maneuver]
		row.contacts = _contacts(bot)
		row.deck_witnesses = _deck_witnesses(bot)
		if bot.kind == "saw" and bot.art != null:
			row.wheel_meshes = _wheel_meshes(bot)
		robots.append(row)
	tick_rows.append({"tick": tick, "robots": robots})

func _record_frame() -> void:
	var phase: String = arena.phase
	if phase == "intro":
		phase = "intro_riptide" if arena.elapsed + 0.000001 < arena.intro_shot_seconds else "intro_bulldozer"
	if phase != phase_key:
		phases.append({"phase": phase, "first_frame": frame, "episode_time": arena.elapsed})
		phase_key = phase
	var tick := roundi(arena.fight_elapsed * Engine.physics_ticks_per_second)
	if phase == "fight" and abs(tick - center_tick) <= WINDOW:
		var row := _pose(arena.bots[0])
		row.wheel_meshes = _wheel_meshes(arena.bots[0])
		frame_rows.append({"frame": frame, "tick": tick, "riptide": row})
	frame += 1

func _pose(bot: Robot) -> Dictionary:
	var transform := bot.global_transform
	var lowest := INF
	var shape_index := -1
	for owner in bot.get_shape_owners():
		if bot.is_shape_owner_disabled(owner):
			continue
		var shape_pose := transform * bot.shape_owner_get_transform(owner)
		for i in range(bot.shape_owner_get_shape_count(owner)):
			var shape := bot.shape_owner_get_shape(owner, i)
			var minimum := _shape_bottom(shape, shape_pose)
			if minimum < lowest:
				lowest = minimum
				shape_index = bot.shape_owner_get_shape_index(owner, i)
	return {"name": str(bot.name), "transform": Pack.pack_transform(transform), "bottom_y": lowest,
		"shape": shape_index, "role": bot.role_for_shape(shape_index)}

func _shape_bottom(shape: Shape3D, pose: Transform3D) -> float:
	if shape is BoxShape3D:
		var vertical := Vector3(pose.basis.x.y, pose.basis.y.y, pose.basis.z.y).abs()
		return pose.origin.y - vertical.dot(shape.size) * 0.5
	if shape is CylinderShape3D:
		var axis_y := absf(pose.basis.y.y)
		return pose.origin.y - shape.height * 0.5 * axis_y - shape.radius * sqrt(maxf(0.0, 1.0 - axis_y * axis_y))
	assert(shape is ConvexPolygonShape3D, "Unexpected shape in the release arena")
	var minimum := INF
	for point: Vector3 in shape.points:
		minimum = minf(minimum, (pose * point).y)
	return minimum

func _contacts(bot: Robot) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for contact in bot.contacts:
		var row := contact.duplicate()
		row.erase("other_id")
		for key in ["point", "normal", "relative"]:
			row[key] = Pack.xyz(row[key])
		rows.append(row)
	return rows

func _deck_witnesses(bot: Robot) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var state := PhysicsServer3D.body_get_direct_state(bot.get_rid())
	for i in range(state.get_contact_count()):
		var other := state.get_contact_collider_object(i) as CollisionObject3D
		if other == null or other.collision_layer != Fit.DECK:
			continue
		var normal := state.get_contact_local_normal(i)
		var own := state.get_contact_local_position(i)
		var deck := state.get_contact_collider_position(i)
		rows.append({"shape": state.get_contact_local_shape(i), "normal": Pack.xyz(normal),
			"point": Pack.xyz(own), "projection": (deck - own).dot(normal)})
	return rows

func _wheel_meshes(bot: Robot) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for wheel in range(bot.art.wheel_pivots.size()):
		var pivot := bot.art.wheel_pivots[wheel]
		if not bot.art.model.is_ancestor_of(pivot):
			continue
		var instance := pivot.get_child(0) as MeshInstance3D
		var transform := instance.global_transform
		if not meshes.has(instance.mesh):
			var vertices := PackedVector3Array()
			for surface in range(instance.mesh.get_surface_count()):
				vertices.append_array(instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
			meshes[instance.mesh] = vertices
		var bottom := Vector3(0, INF, 0)
		for vertex: Vector3 in meshes[instance.mesh]:
			var point := transform * vertex
			if point.y < bottom.y:
				bottom = point
		var pixel: Vector2 = arena.camera.unproject_position(bottom)
		rows.append({"wheel": wheel, "bottom": Pack.xyz(bottom), "pixel": [pixel.x, pixel.y]})
	return rows

func _exit_tree() -> void:
	if output.is_empty():
		return
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write deck audit: " + output)
		return
	file.store_string(JSON.stringify({"ticks": tick_rows, "rendered_frames": frame_rows,
		"phase_frames": phases, "frame_count": frame}) + "\n")
