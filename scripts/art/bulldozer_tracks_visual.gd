extends "res://scripts/art/robot_visual.gd"
## Preview rig. Belt distance is independent on each side.
const TRACK: String = "res://config/bulldozer_tracks.json"
var track: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TRACK))
var links: Array[Array] = [[], []]
var idlers: Array[Node3D] = []
var travel := [0.0, 0.0]
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
		idlers.append(model.find_child("Idler_" + letter, true, false) as Node3D)
		assert(idlers[side] != null)
		for index in range(int(track.links_per_side)):
			var shoe := model.find_child("TrackLink_%s%02d" % [letter, index], true, false) as Node3D
			assert(shoe != null, "Missing track shoe")
			links[side].append(shoe)

func update_visual(delta: float, weapon_angle: float, forward_speed: float, yaw_speed: float, flash: float = 0.0, defeated: bool = false) -> void:
	super.update_visual(delta, weapon_angle, forward_speed, yaw_speed, flash, defeated)
	var step_length := loop_length / float(track.links_per_side)
	for side in range(2):
		var x := float(track.center_x) * (-1.0 if side == 0 else 1.0)
		var speed := forward_speed + yaw_speed * x
		idlers[side].rotate_x(-speed * delta / 0.224)
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
