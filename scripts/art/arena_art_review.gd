extends "res://scripts/match.gd"
## Optional visual review: the original match / robot scripts remain untouched.
const RobotVisual = preload("res://scripts/art/robot_visual.gd")
const RiptideVisual = preload("res://scripts/art/riptide_visual.gd")
const BulldozerVisual = preload("res://scripts/art/bulldozer_visual.gd")
var review_visuals: Array[RobotVisual] = []
var drum_angle := 0.0

func _build_bots() -> void:
	super._build_bots()
	for index in range(bots.size()):
		var bot: RigidBody3D = bots[index]
		# Keep the original nodes alive so the visual adapter can follow their animation.
		for child in bot.get_children():
			if child is Node3D and not child is CollisionShape3D:
				child.visible = false
		var visual: RobotVisual = RiptideVisual.new() if index == 0 else BulldozerVisual.new()
		visual.name = "ArtReview"
		bot.add_child(visual)
		review_visuals.append(visual)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	for index in range(review_visuals.size()):
		var bot: RigidBody3D = bots[index]
		var visual := review_visuals[index]
		var weapon_angle: float = bot.weapon.rotation.y
		if visual is BulldozerVisual:
			if bot.hp > 0.0:
				var spin_speed := 19.0 if bot.active else 3.0
				drum_angle = fposmod(drum_angle + delta * spin_speed, TAU)
			weapon_angle = drum_angle
		visual.update_visual(delta, weapon_angle,
			bot.linear_velocity.dot(-bot.global_basis.z), bot.angular_velocity.y, bot.flash, bot.hp <= 0.0)
