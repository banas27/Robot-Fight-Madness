extends Node3D
## Draw the same shape resources and owner transforms used by the solver.
const Shapes = preload("res://scripts/shapes.gd")
const Robot = preload("res://scripts/combat/robot.gd")
var parts: Array[Node3D] = []
var rotors: Array[Node3D] = []
var robots: Array[Robot] = []
var wheel_shapes: Array[Dictionary] = []
var marker: MeshInstance3D
var contact_lines: ImmediateMesh
var legend: Label
var visible_overlay := false
var marker_life := 0.0

func add_robot(robot: Robot) -> void:
	var holder := Node3D.new()
	robot.add_child(holder)
	parts.append(holder)
	var colors := {"chassis": Color("79e1f9"), "wheel": Color("be94ff"), "support": Color("6dff9f"),
		"core": Color("ffa64b"), "tooth": Color("ffe069")}
	var materials := {}
	for role in colors:
		materials[role] = _material(colors[role])
	for owner: int in robot.get_shape_owners():
		var group := Node3D.new()
		holder.add_child(group)
		group.transform = robot.shape_owner_get_transform(owner)
		var role: String = robot.shape_roles[owner]
		if role == "wheel":
			wheel_shapes.append({"robot": robot, "owner": owner, "group": group})
		for i in range(robot.shape_owner_get_shape_count(owner)):
			var shape := robot.shape_owner_get_shape(owner, i)
			var native := shape.get_debug_mesh()
			var edges := ArrayMesh.new()
			for surface in range(native.get_surface_count()):
				if native.surface_get_primitive_type(surface) == Mesh.PRIMITIVE_LINES:
					edges.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, native.surface_get_arrays(surface))
			var wire := Shapes.attach(group, edges, Vector3.ZERO, materials[role])
			wire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if owner == robot.rotor_owner:
			robots.append(robot)
			rotors.append(group)
	holder.hide()

func toggle() -> void:
	visible_overlay = not visible_overlay
	for part in parts:
		part.visible = visible_overlay
	if legend == null:
		var layer := CanvasLayer.new()
		layer.layer = 2
		add_child(layer)
		legend = Label.new()
		layer.add_child(legend)
		legend.position = Vector2(31, 1190)
		legend.add_theme_font_size_override("font_size", 16)
		legend.text = "CYAN hull  VIOLET wheels  GREEN supports  AMBER core  YELLOW teeth  PINK hit"
	legend.visible = visible_overlay
	if marker != null:
		marker.visible = visible_overlay and marker_life > 0.0

func impact(point: Vector3, normal: Vector3) -> void:
	if not visible_overlay:
		return
	if marker == null:
		contact_lines = ImmediateMesh.new()
		marker = Shapes.attach(self, contact_lines, Vector3.ZERO, null)
	contact_lines.clear_surfaces()
	contact_lines.surface_begin(Mesh.PRIMITIVE_LINES, _material(Color("ff56a5")))
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		contact_lines.surface_add_vertex(point - axis * 0.10)
		contact_lines.surface_add_vertex(point + axis * 0.10)
	contact_lines.surface_add_vertex(point)
	contact_lines.surface_add_vertex(point + normal * 0.48)
	contact_lines.surface_end()
	marker_life = 0.65
	marker.show()

func _process(delta: float) -> void:
	if not visible_overlay:
		return
	for i in range(robots.size()):
		rotors[i].transform = robots[i].shape_owner_get_transform(robots[i].rotor_owner)
	for wheel in wheel_shapes:
		wheel.group.visible = not wheel.robot.is_shape_owner_disabled(wheel.owner)
	marker_life -= delta
	if marker != null and marker_life <= 0.0:
		marker.hide()

func _material(color: Color) -> StandardMaterial3D:
	var material := Shapes.material(color)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	return material
