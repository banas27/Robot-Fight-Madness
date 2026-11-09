extends SceneTree
## Probe the actual static colliders, then reload and switch scenes in one process.
const CurrentArena = preload("res://scenes/review/arena_tracked_bulldozer_test.tscn")
const LargerArena = preload("res://scenes/review/arena_tracked_bulldozer_large.tscn")
const Match = preload("res://scripts/combat/match.gd")
const Fit = preload("res://scripts/combat/collision_fit.gd")
const EPSILON := 0.00002
var failures := 0
var reference_poses: Array[Transform3D] = []

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS ", message)
	else:
		failures += 1
		push_error(message)

func close(a: float, b: float) -> bool:
	return absf(a - b) < EPSILON

func ray(arena: Match, from: Vector3, to: Vector3, mask: int) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	return arena.get_world_3d().direct_space_state.intersect_ray(query)

func check_geometry(is_larger: bool) -> void:
	await physics_frame
	await physics_frame
	var arena := current_scene as Match
	var radius := arena._arena_radius()
	var scale := sqrt(2.0) if is_larger else 1.0
	var inner_half := Vector2(7.9, 10.3) * scale * 0.5
	var variant := "larger" if is_larger else "current"
	check(arena.larger_arena == is_larger and arena.bulldozer_uses_tracks
		and arena.bots[1].tracked_drive and arena.bots[1].road_tread_owners.size() == 6,
		variant + " scene selects its own arena and the tracked chassis")
	check(close(radius.x, inner_half.x + 0.15) and close(radius.y, inner_half.y + 0.15),
		variant + " AI and containment use the selected rail centres")
	var measured := Vector2.ZERO
	for axis in [0, 1]:
		var direction := Vector3.RIGHT if axis == 0 else Vector3.BACK
		for sign_value: float in [-1.0, 1.0]:
			var heading := direction * sign_value
			var origin := Vector3.UP * 0.30
			var outside := origin + heading * (radius[axis] + 0.9)
			var inside_hit := ray(arena, origin, outside, Fit.WALL)
			var outside_hit := ray(arena, outside, origin, Fit.WALL)
			if inside_hit.is_empty() or outside_hit.is_empty():
				check(false, variant + " rail collision is present")
				continue
			var inside: float = inside_hit.position.dot(heading)
			var thickness: float = outside_hit.position.dot(heading) - inside
			var top: Vector3 = heading * radius[axis]
			var height_hit := ray(arena, top + Vector3.UP, top, Fit.WALL)
			check(close(inside, inner_half[axis]) and close(thickness, 0.30)
				and not height_hit.is_empty() and close(height_hit.position.y, 0.575),
				variant + " rail inner face, thickness and top")
			measured[axis] += inside
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var corner := Vector3(sx * (inner_half.x - 0.06), 1.0, sz * (inner_half.y - 0.06))
			var ground := ray(arena, corner, corner - Vector3.UP * 2.0, Fit.DECK)
			check(not ground.is_empty() and close(ground.position.y, 0.0),
				variant + " floor covers the corner at the same height")
	var saw := arena.bots[0]
	var pose := saw.transform
	saw.position.x = 3.70
	check(saw._wall_inward(radius).is_zero_approx() == is_larger,
		variant + " retains the same wall approach clearance in world units")
	saw.position.x = radius.x - 1.0
	check(saw._wall_inward(radius) == Vector3.LEFT, variant + " AI detects its own near rail")
	saw.transform = pose
	var poses: Array[Transform3D] = []
	for bot in arena.bots:
		poses.append(bot.transform)
	if reference_poses.is_empty():
		reference_poses = poses
	else:
		check(poses == reference_poses, variant + " build and reset preserve both spawn transforms")
	check(close(measured.x, inner_half.x * 2.0) and close(measured.y, inner_half.y * 2.0),
		variant + " dimensions measured between collider faces")
	if is_larger:
		var drum := arena.bots[1]
		var drum_pose := drum.transform
		saw.position = Vector3(inner_half.x - 1.14, 0.4, -inner_half.y + 1.14)
		drum.position = Vector3(-saw.position.x, 0.4, -saw.position.z)
		check(arena._fighter_frame_width(0.0) > float(arena.presentation.camera_max_width),
			"opposite corners need extra projected width in the larger arena")
		# Invoke the presentation path only. Frozen fighters should stay put.
		arena.headless = false
		arena._process(1.0 / 30.0)
		arena.headless = true
		check(arena.camera.size + EPSILON >= arena._fighter_frame_width(0.0),
			"larger arena camera fits the corner stress pose")
		saw.transform = pose
		drum.transform = drum_pose
	print("RFS_ARENA_SIZE ", variant, " ", measured.x, " × ", measured.y, " m")

func run() -> void:
	change_scene_to_packed(CurrentArena)
	await scene_changed
	await check_geometry(false)
	change_scene_to_packed(LargerArena)
	await scene_changed
	await check_geometry(true)
	reload_current_scene()
	await scene_changed
	await check_geometry(true)
	change_scene_to_packed(CurrentArena)
	await scene_changed
	await check_geometry(false)
	reload_current_scene()
	await scene_changed
	await check_geometry(false)
	print("RFS_ARENA_FIXTURES ", failures, " failures")
	quit(1 if failures else 0)
