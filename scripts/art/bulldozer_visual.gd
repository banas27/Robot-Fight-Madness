extends "res://scripts/art/robot_visual.gd"

func _init() -> void:
	model_scene = preload("res://assets/robots/bulldozer/bulldozer_v03.glb")
	armor_material_name = "Armor_Orange"
	armor_color = Color("ff9045")
	wheel_radius = 0.295
	weapon_axis = Vector3.RIGHT
