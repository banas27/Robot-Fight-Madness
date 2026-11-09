extends "res://scripts/art/robot_visual.gd"

func _init() -> void:
	model_scene = preload("res://assets/robots/riptide/riptide_v02.glb")
	armor_material_name = "Armor_Cyan"
	armor_color = Color("39d8e7")
	wheel_radius = 0.32
