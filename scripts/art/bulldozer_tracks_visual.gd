extends "res://scripts/art/robot_visual.gd"
## Preview rig. Belt distance is independent on each side.
const TRACK: String = "res://config/bulldozer_tracks.json"
var track: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TRACK))
var links: Array[Array] = [[], []]
var road_wheels: Array[Node3D] = []
var travel := [0.0, 0.0]
var track_wear := [0, 0]
var road_wear := [0, 0, 0, 0, 0, 0]
var belt_finishes: Array[Dictionary] = [{}, {}]
var road_finishes: Array[Dictionary] = [{}, {}, {}, {}, {}, {}]
const DETACHED := 4
var straight := 0.0
var bend := 0.0
var loop_length := 0.0

func _init() -> void:
	model_scene = preload("res://assets/robots/bulldozer/bulldozer_v05_tracks.glb")
	armor_material_name = "Armor_Orange"
	armor_color = Color("ff9045")
	wheel_radius = float(track.pitch_radius)
	weapon_axis = Vector3.RIGHT
	straight = 2.0 * float(track.half_run)
	bend = PI * wheel_radius
	loop_length = 2.0 * (straight + bend)

func _ready() -> void:
	super._ready()
	for side in range(2):
		var letter := "L" if side == 0 else "R"
		var idler := model.find_child("Idler_" + letter, true, false) as Node3D
		assert(idler != null)
		road_wheels.append_array([wheel_pivots[side], idler, wheel_pivots[side + 2]])
		for index in range(int(track.links_per_side)):
			var shoe := model.find_child("TrackLink_%s%02d" % [letter, index], true, false) as Node3D
			assert(shoe != null, "Missing track shoe")
			links[side].append(shoe)

func show_track_damage(stages: Array, road_stages: Array) -> void:
	for side in range(2):
		var stage: int = stages[side]
		if stage == track_wear[side]:
			continue
		track_wear[side] = stage
		if stage == DETACHED:
			for shoe: Node3D in links[side]:
				if model.is_ancestor_of(shoe):
					shoe.hide()
		else:
			_tint_parts(links[side], belt_finishes[side], TREAD_TINT[stage])
	for wheel in range(road_wheels.size()):
		var stage: int = road_stages[wheel]
		if stage == road_wear[wheel]:
			continue
		road_wear[wheel] = stage
		var pivot := road_wheels[wheel]
		if stage == DETACHED:
			if model.is_ancestor_of(pivot):
				pivot.hide()
		else:
			_tint_parts([pivot], road_finishes[wheel], HUB_TINT[stage])

func _tint_parts(parts: Array, finishes: Dictionary, tint: Color) -> void:
	if finishes.is_empty():
		for part: Node3D in parts:
			var mesh := part.get_child(0) as MeshInstance3D
			for surface in range(mesh.mesh.get_surface_count()):
				var original := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
				var key := original.resource_name
				if not finishes.has(key):
					finishes[key] = [original.albedo_color, original.duplicate()]
				mesh.set_surface_override_material(surface, finishes[key][1])
	for finish: Array in finishes.values():
		var material := finish[1] as StandardMaterial3D
		var original: Color = finish[0]
		material.albedo_color = original.lerp(tint, 0.7)
		material.roughness = 0.88

func release_belt_strip(side: int, debris: RigidBody3D) -> void:
	var bottom := float(track.center_y) - wheel_radius
	for shoe: Node3D in links[side]:
		if absf(shoe.position.z) <= 0.192 and absf(shoe.position.y - bottom) < 0.005:
			shoe.reparent(debris, true)

func release_road_wheel(wheel: int, debris: RigidBody3D) -> void:
	road_wheels[wheel].reparent(debris, true)

func update_visual(delta: float, weapon_angle: float, forward_speed: float, yaw_speed: float, flash: float = 0.0,
		defeated: bool = false, belt_support: int = 3, road_support: int = 0) -> void:
	super.update_visual(delta, weapon_angle, 0.0, 0.0, flash, defeated)
	var step_length := loop_length / float(track.links_per_side)
	for side in range(2):
		var x := float(track.center_x) * (-1.0 if side == 0 else 1.0)
		var speed := forward_speed + yaw_speed * x
		var grounded := bool(belt_support & (1 << side))
		for wheel in range(side * 3, side * 3 + 3):
			if road_wear[wheel] != DETACHED and (grounded or road_support & (1 << wheel)):
				var radius := 0.224 if wheel % 3 == 1 else 0.250
				road_wheels[wheel].rotate_x(-speed * delta / radius)
		if not grounded or track_wear[side] == DETACHED:
			continue
		travel[side] = fposmod(float(travel[side]) - speed * delta, loop_length)
		for index in range(links[side].size()):
			var shoe := links[side][index] as Node3D
			shoe.transform = _shoe_pose(x, fposmod(index * step_length + travel[side], loop_length))

func _shoe_pose(x: float, distance: float) -> Transform3D:
	var half_run := straight * 0.5
	var y := float(track.center_y)
	if distance < straight:
		return Transform3D(Basis.IDENTITY, Vector3(x, y + wheel_radius, distance - half_run))
	if distance < straight + bend:
		return _bend_pose(x, y, half_run, (distance - straight) / wheel_radius)
	if distance < 2.0 * straight + bend:
		return Transform3D(Basis(Vector3.RIGHT, PI), Vector3(x, y - wheel_radius, half_run - (distance - straight - bend)))
	return _bend_pose(x, y, -half_run, PI + (distance - 2.0 * straight - bend) / wheel_radius)

func _bend_pose(x: float, y: float, z: float, angle: float) -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, angle), Vector3(x, y + wheel_radius * cos(angle), z + wheel_radius * sin(angle)))
