extends "res://tools/verify_tracks.gd"
## A recorded fixture that commands the existing drive actuator and damage API.
var arena: Match
var drum: Robot
var art: TracksArt
var fixture_label: Label
var title: Label
var detail: Label
var peak_debris_speed := 0.0
var peak_debris_spin := 0.0

func label_at(parent: CanvasLayer, y: float, font_size: int) -> Label:
	var label := Label.new()
	label.position = Vector2(34, y)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color("101923"))
	label.add_theme_constant_override("outline_size", 8)
	parent.add_child(label)
	return label

func slate(chapter: String, description: String) -> void:
	var top := 1094.0 if chapter.begins_with("08") else 43.0
	fixture_label.position.y = top
	title.position.y = top + 31.0
	detail.position.y = top + 69.0
	title.text = chapter
	detail.text = description

func prepare_shot() -> void:
	arena.set_physics_process(false)
	arena.set_process(false)
	arena.phase = "fight"
	drum = arena.bots[1] as Robot
	if drum.art == null:
		drum.art = drum.make_visual()
		drum.add_child(drum.art)
	art = drum.art as TracksArt
	drum.freeze = false
	drum.position = Vector3(0, 0.4, 0)
	drum.rotation.y = 0.0
	arena.bots[0].position = Vector3(3.2, 0.4, 4.3)
	arena.bots[0].hide()
	for child in arena.get_children():
		if child is CanvasLayer:
			child.hide()
	frame_drum(4.5)

func frame_drum(width: float, offset := Vector3.ZERO) -> void:
	var camera := arena.camera
	var anchor := drum.global_position.slide(Vector3.UP) + offset
	camera.position = anchor + drum.global_basis * Vector3(-7.7, 3.2, -5.2)
	camera.look_at(anchor + Vector3(0, 0.18, 0))
	camera.size = width

func take(seconds: float, thrust := 0.0, torque := 0.0) -> void:
	await drive_for(drum, thrust, torque, roundi(seconds * Engine.physics_ticks_per_second))

func cruise_take(direction: float) -> void:
	var forward := Robot.deck_forward(drum.global_basis)
	frame_drum(4.7, forward * 0.57 * direction)
	var before := art.travel.duplicate()
	await take(0.72, 8.0 * direction)
	var travel := belt_travel(art, before)
	check(drum.linear_velocity.dot(forward) * direction > 0.5
		and travel.x * direction < -0.05 and travel.y * direction < -0.05, title.text)
	await take(0.62)

func pivot_takes() -> void:
	for direction in [1.0, -1.0]:
		var label := "03  PIVOT LEFT" if direction > 0.0 else "04  PIVOT RIGHT"
		slate(label, "The belts travel in opposite directions")
		frame_drum(4.5)
		var before := art.travel.duplicate()
		await take(0.68, 0.0, 180.0 * direction)
		var travel := belt_travel(art, before)
		check(travel.x * direction > 0.03 and travel.y * direction < -0.03
			and drum.angular_velocity.y * direction > 0.2, label)
		await take(0.55)

func loose_parts() -> Array[RigidBody3D]:
	var pieces: Array[RigidBody3D] = []
	for child in arena.get_children():
		if child is RigidBody3D and child not in arena.bots:
			pieces.append(child)
	return pieces

func sample_debris() -> void:
	if not is_instance_valid(arena):
		return
	for piece in loose_parts():
		peak_debris_speed = maxf(peak_debris_speed, piece.linear_velocity.length())
		peak_debris_spin = maxf(peak_debris_spin, piece.angular_velocity.length())

func check_debris() -> Array[RigidBody3D]:
	var pieces := loose_parts()
	var peak_speed := 0.0
	var peak_spin := 0.0
	for _sample in range(18):
		await physics_frame
		for piece in pieces:
			peak_speed = maxf(peak_speed, piece.linear_velocity.length())
			peak_spin = maxf(peak_spin, piece.angular_velocity.length())
	check(pieces.size() == 2 and peak_speed < 0.045 and peak_spin < 0.18,
		"belt strip and road wheel settle for 100 ms (%.3f m/s, %.3f rad/s)" % [peak_speed, peak_spin])
	check(peak_debris_speed < 2.5 and peak_debris_spin < 12.0,
		"release stays bounded (%.3f m/s, %.3f rad/s peaks)" % [peak_debris_speed, peak_debris_spin])
	return pieces

func damaged_showcase() -> void:
	slate("08  WINNER SHOWCASE", "Staged result / actual damage snapshot")
	arena.bots[0].hp = 0
	arena._finish("knockout")
	var view := arena.episode_view
	if view == null:
		view = EpisodeView.new()
		view.match_node = arena
		arena.add_child(view)
	else:
		view.get_parent().show()
	view._process(0.0)
	view.studio_camera.position = Vector3(-5.2, 2.9, -8.3)
	view.studio_camera.look_at(Vector3(0, 0.05, -0.04))
	var winner := view.models[1] as TracksArt
	check(arena.result_snapshot.robots[1].drive == "Left track thrown"
		and winner.track_wear[0] == Robot.Wheel.DETACHED and not winner.links[0][0].visible
		and not winner.road_wheels[1].visible and winner.road_wheels[0].visible,
		"showcase keeps the lost belt and idler absent and reports the left track thrown")
	for tick in range(roundi(3.5 * Engine.physics_ticks_per_second)):
		await physics_frame
		arena.result_elapsed = float(tick) / Engine.physics_ticks_per_second

func run() -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 10
	root.add_child(overlay)
	fixture_label = label_at(overlay, 43, 22)
	fixture_label.text = "VALIDATION FIXTURE"
	title = label_at(overlay, 74, 30)
	detail = label_at(overlay, 112, 22)
	arena = stage()
	current_scene = arena
	prepare_shot()
	physics_frame.connect(sample_debris)

	slate("01  FORWARD", "Both grounded belts drive forward")
	await take(0.34)
	await cruise_take(1.0)
	slate("02  REVERSE", "Both belts reverse with the chassis")
	await cruise_take(-1.0)
	await pivot_takes()

	var left := shape_on_side(drum, 0)
	var idler := road_hub(drum, 1)
	slate("05  LEFT MOTOR FAILED", "The left belt rolls passively on the deck")
	frame_drum(4.3)
	drum.damage_component(Robot.WHEEL_FAILED, "track", left)
	await take(0.58, 10.0)
	check(drum.track_state[0] == Robot.Wheel.DRIVE_FAILED and drum.supported_tracks == 3
		and is_equal_approx(drum.supported_drive_grip(), 0.5), "failed left motor leaves a passive grounded belt")
	await take(0.65)

	slate("06  LEFT BELT THROWN", "Three road wheels take over left-side support")
	frame_drum(4.0)
	drum.damage_component(Robot.WHEEL_MOUNT_BROKEN - Robot.WHEEL_FAILED, "track", left)
	await take(1.45)
	check(drum.supported_tracks == 2 and drum.is_shape_owner_disabled(drum.shape_find_owner(left))
		and (drum.supported_road_wheels & 7) != 0 and is_equal_approx(drum.supported_drive_grip(), 0.5),
		"lost belt collider and drive are removed, with road wheels supplying support")

	slate("07A  ROAD WHEEL DAMAGED", "Left center idler takes a separate hit")
	drum.damage_component(Robot.WHEEL_SEVERE, "road_wheel", idler)
	await take(1.13)
	check(art.road_wear[1] == Robot.Wheel.SEVERE and not art.road_finishes[1].is_empty(),
		"damaged idler stays attached with its own finish")
	await take(0.30, 10.0)
	slate("07B  ROAD WHEEL DETACHED", "The two outer road wheels remain on the chassis")
	drum.damage_component(Robot.WHEEL_MOUNT_BROKEN - Robot.WHEEL_SEVERE, "road_wheel", idler)
	await take(0.30, 10.0)
	await take(2.45)
	check((drum.supported_road_wheels & 2) == 0 and (drum.supported_road_wheels & 5) != 0
		and drum.is_shape_owner_disabled(drum.road_tread_owners[1]) and art.road_wheels[1].get_parent() is RigidBody3D,
		"the idler leaves with its art and surviving road wheels retain support")
	var pieces := await check_debris()
	await damaged_showcase()

	slate("09  RESET", "Both track assemblies restored and debris cleared")
	check(reload_current_scene() == OK, "production scene reload starts")
	await scene_changed
	arena = current_scene as Match
	prepare_shot()
	await take(0.65)
	var debris_removed := true
	for piece in pieces:
		debris_removed = debris_removed and not is_instance_valid(piece)
	check(debris_removed and drum.track_state == [0, 0] and drum.road_wheel_state == [0, 0, 0, 0, 0, 0]
		and drum.supported_tracks == 3 and drum.supported_drive_grip() == 1.0
		and art.links[0][0].visible and art.links[1][0].visible,
		"reload restores both assemblies, clears damage and frees debris")
	await take(0.65)
	print("RFS_TRACK_REVIEW ", failures, " failures")
	quit(0 if failures == 0 else 1)
