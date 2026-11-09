extends Node3D
## Shared appearance controller for the art review scenes.
var model_scene: PackedScene
var armor_material_name: String
var armor_color: Color
var wheel_radius: float
var weapon_axis := Vector3.UP

var weapon_pivot: Node3D
var wheel_pivots: Array[Node3D] = []
var armor_materials: Array[StandardMaterial3D] = []
var model: Node3D
var weapon_armor: Array[StandardMaterial3D] = []
var armor_wear := 0.0
var rotor_wear := 0.0
var wheel_wear := [0, 0, 0, 0]
var wheel_marks: Array[Node3D] = [null, null, null, null]
# A failed drive leaves an attached wheel free to roll on its bearing.
const WHEEL_SLIP := [0.0, 0.10, 0.24, 0.0]
const TREAD_TINT := [Color.WHITE, Color("594e45"), Color("725442"), Color("4c3a31")]
const HUB_TINT := [Color.WHITE, Color("aa8060"), Color("c87340"), Color("784331")]
var rotor_broken := false

func _ready() -> void:
	model = model_scene.instantiate()
	add_child(model)
	weapon_pivot = model.find_child("WeaponPivot", true, false)
	assert(weapon_pivot != null, "Missing weapon pivot")
	for wheel_name in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		var wheel: Node3D = model.find_child(wheel_name, true, false)
		assert(wheel != null, "Missing wheel pivot: " + wheel_name)
		wheel_pivots.append(wheel)
	_collect_armor(model)

func _collect_armor(node: Node) -> void:
	if node is MeshInstance3D:
		for surface in range(node.mesh.get_surface_count()):
			var material: Material = node.get_active_material(surface)
			if material is StandardMaterial3D and material.resource_name == armor_material_name:
				var unique: StandardMaterial3D = material.duplicate()
				node.set_surface_override_material(surface, unique)
				armor_materials.append(unique)
				if weapon_pivot.is_ancestor_of(node):
					weapon_armor.append(unique)
	for child in node.get_children():
		_collect_armor(child)

func show_damage(armor: float, wheels: Array, weapon: float, disabled: bool) -> void:
	armor_wear = lerpf(0.62, 1.0, clampf((armor - 18.0) / 38.0, 0.0, 1.0)) if armor >= 18.0 else 0.0
	if armor_wear > 0.0:
		for material in armor_materials:
			if material not in weapon_armor:
				material.roughness = 0.72
	rotor_wear = clampf(weapon / 49.0, 0.0, 1.0) if weapon > 11.0 else 0.0
	rotor_broken = disabled
	for i in range(wheel_pivots.size()):
		var stage: int = wheels[i]
		if stage == wheel_wear[i]:
			continue
		wheel_wear[i] = stage
		if stage == 4: # The independent loose wheel keeps its face marking.
			continue
		_mark_wheel(i, stage)
		var wheel := wheel_pivots[i].get_child(0) as MeshInstance3D
		for surface in range(wheel.mesh.get_surface_count()):
			var original := wheel.mesh.surface_get_material(surface) as StandardMaterial3D
			if original == null or original.resource_name not in ["Tire_Rubber", "Weapon_Steel", "Safety_Amber"]:
				continue
			var worn := wheel.get_surface_override_material(surface) as StandardMaterial3D
			if worn == null:
				worn = original.duplicate() as StandardMaterial3D
				wheel.set_surface_override_material(surface, worn)
			worn.albedo_color = TREAD_TINT[stage] if original.resource_name == "Tire_Rubber" else HUB_TINT[stage]
			worn.roughness = 0.88

func _mark_wheel(index: int, stage: int) -> void:
	var wheel := wheel_pivots[index]
	if wheel_marks[index] != null:
		wheel_marks[index].queue_free()
		wheel_marks[index].hide()
	var mark := Node3D.new()
	wheel.add_child(mark)
	wheel_marks[index] = mark
	var side := signf(wheel.position.x)
	if stage == 3:
		# A pale cross on the exposed hub travels with the passive wheel.
		mark.position.x = side * (0.153 if wheel_radius > 0.31 else 0.132)
		_mark_bar(mark, Vector3.ZERO, PI * 0.25, 0.205, 0.037, Color("fff0ca"))
		_mark_bar(mark, Vector3.ZERO, -PI * 0.25, 0.205, 0.037, Color("fff0ca"))
	else:
		# Scuffs follow the outer tire face, outside the raised hub.
		mark.position.x = side * (0.114 if wheel_radius > 0.31 else 0.111)
		for j in range(stage + 1):
			var pos := Vector3(0.0, 0.16 + float(j) * 0.021, -0.07 + float(j) * 0.026)
			_mark_bar(mark, pos, -0.64, 0.105 - float(j) * 0.012, 0.014, Color("d4ba94"))

func _mark_bar(parent: Node3D, point: Vector3, angle: float, length: float, width: float, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.005, length, width)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	var stripe := MeshInstance3D.new()
	stripe.mesh = box
	stripe.material_override = material
	stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(stripe)
	stripe.position = point
	stripe.rotation.x = angle

func update_visual(delta: float, weapon_angle: float, forward_speed: float, yaw_speed: float, flash: float = 0.0, defeated: bool = false) -> void:
	weapon_pivot.basis = Basis(weapon_axis, weapon_angle)
	for i in range(wheel_pivots.size()):
		if wheel_wear[i] == 4:
			continue
		var pivot := wheel_pivots[i]
		# Positive forward travel (-Z) rolls about -X. Include turning at each axle.
		var speed := forward_speed + yaw_speed * pivot.position.x
		pivot.rotate_x(-speed * (1.0 - WHEEL_SLIP[wheel_wear[i]]) * delta / wheel_radius)
	for material in armor_materials:
		var rotor := material in weapon_armor
		var wear := rotor_wear if rotor else armor_wear
		var tint := armor_color.lerp(Color("393e42"), minf(wear * 0.69, 0.69))
		if rotor and rotor_broken:
			tint = Color("45454a")
		material.albedo_color = tint.darkened(0.65) if defeated else tint.lerp(Color.WHITE, flash)
