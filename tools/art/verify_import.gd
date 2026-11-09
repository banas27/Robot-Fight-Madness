extends SceneTree
## Actual Godot import, material and pivot-motion contract (headless).
const RobotVisual = preload("res://scripts/art/robot_visual.gd")

func _initialize() -> void:
	check.call_deferred()

func check() -> void:
	verify(load("res://scripts/art/riptide_visual.gd").new(), Vector3(0, 0.04, -0.87),
		Vector3.UP, "godot-asset-check.json")
	verify(load("res://scripts/art/bulldozer_visual.gd").new(), Vector3(0, -0.021, -1.125),
		Vector3.RIGHT, "godot-bulldozer-check.json")
	var arena: Node3D = load("res://scenes/review/arena_art_review.tscn").instantiate()
	root.add_child(arena)
	var bulldozer: RobotVisual = arena.get_node("Bulldozer/ArtReview")
	var initial_drum_basis := bulldozer.weapon_pivot.basis
	await physics_frame
	await physics_frame
	assert(not bulldozer.weapon_pivot.basis.is_equal_approx(initial_drum_basis))
	assert(bulldozer.weapon_pivot.basis.x.is_equal_approx(Vector3.RIGHT))
	print("RFS_DRUM_ANIMATION_PASS")
	arena.queue_free()
	await process_frame
	quit()

func verify(visual: RobotVisual, weapon_position: Vector3, weapon_axis: Vector3, report_name: String) -> void:
	root.add_child(visual)
	assert(visual.armor_materials.size() == 2, "Expected team color on chassis and weapon")
	assert(visual.weapon_pivot.position.is_equal_approx(weapon_position))
	var initial_positions: Array[Vector3] = []
	for wheel in visual.wheel_pivots:
		assert(wheel != null)
		initial_positions.append(wheel.global_position)
	var chassis: Node3D = visual.model.find_child("Chassis", true, false)
	var chassis_transform := chassis.global_transform
	var weapon_origin: Vector3 = visual.weapon_pivot.global_position
	var weapon_angle := PI / 2.0
	visual.update_visual(0.25, weapon_angle, 1.0, 0.4, 1.0)
	assert(visual.weapon_pivot.global_position.is_equal_approx(weapon_origin))
	assert(visual.weapon_pivot.basis.is_equal_approx(Basis(weapon_axis, weapon_angle)))
	assert(chassis.global_transform.is_equal_approx(chassis_transform))
	for i in range(visual.wheel_pivots.size()):
		var wheel: Node3D = visual.wheel_pivots[i]
		assert(wheel.global_position.is_equal_approx(initial_positions[i]))
		assert(wheel.basis.x.is_equal_approx(Vector3.RIGHT))
		assert(absf(wheel.rotation.x) > 0.1)
	for mat in visual.armor_materials:
		assert(mat.albedo_color.is_equal_approx(Color.WHITE))
	visual.update_visual(0.0, 0.0, 0.0, 0.0, 0.0, true)
	for mat in visual.armor_materials:
		assert(mat.albedo_color.is_equal_approx(visual.armor_color.darkened(0.65)))
	assert_no_collision(visual)
	var result := {"passed": true, "wheel_pivots": 4, "weapon_pivots": 1, "armor_surfaces": visual.armor_materials.size(), "pivot_positions_stable": true, "axes_correct": true, "hit_and_defeat_tint": true, "no_asset_collision": true}
	var output := FileAccess.open("res://qa/art-r01/" + report_name, FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "\t") + "\n")
	print("RFS_GODOT_ASSET_PASS ", report_name, " ", JSON.stringify(result))
	visual.queue_free()

func assert_no_collision(node: Node) -> void:
	assert(not node is CollisionObject3D and not node is CollisionShape3D)
	for child in node.get_children():
		assert_no_collision(child)
