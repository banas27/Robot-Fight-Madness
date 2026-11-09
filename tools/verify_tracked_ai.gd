extends SceneTree
## Controlled damaged-drive checks. Full-fight evaluation uses the normal match loop.
const Arena = preload("res://scenes/review/arena_tracked_bulldozer_test.tscn")
const Robot = preload("res://scripts/combat/robot.gd")
const SawPolicy = preload("res://scripts/combat/riptide_tracked_flank.gd")
const DrumPolicy = preload("res://scripts/combat/bulldozer_tracked_intercept.gd")
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS ", message)
	else:
		failures += 1
		push_error(message)

func shape_on_side(bot: Robot, side: int) -> int:
	for owner in bot.get_shape_owners():
		if bot.shape_roles[owner] == "track":
			var shape := bot.shape_owner_get_shape_index(owner, 0)
			if bot.track_for_shape(shape) == side:
				return shape
	return -1

func arc_fixture(failed: int, thrown: bool) -> void:
	var arena := Arena.instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	var saw := arena.bots[0] as Robot
	var drum := arena.bots[1] as Robot
	var surviving_turn := 1.0 if failed == 0 else -1.0
	saw.position = Vector3(-4.0 * surviving_turn, 0.40, -1.8)
	drum.position = Vector3(0, 0.40, 0)
	drum.rotation.y = 0.0
	drum.freeze = false
	drum.active = true
	drum.trace_orders = true
	var shape := shape_on_side(drum, failed)
	drum.damage_component(72.0 if thrown else 39.0, "track", shape)
	var delta := 1.0 / Engine.physics_ticks_per_second
	var origin := drum.position
	for _tick in range(105):
		await physics_frame
		drum.step(delta, arena._arena_radius())
	check(drum.track_state[failed] == (Robot.Wheel.DETACHED if thrown else Robot.Wheel.DRIVE_FAILED),
		"fixture exercises the requested track damage state")
	check(drum.position.distance_to(origin) > 0.10 and drum.rotation.y * surviving_turn > 0.12,
		"surviving belt generates a translated turn toward the offset target")
	drum.damage_component(72.0, "track", shape_on_side(drum, 1 - failed))
	drum.step(delta, arena._arena_radius())
	check(drum.maneuver == Robot.Maneuver.HOLD and drum.last_order.is_zero_approx(),
		"candidate stops requesting drive after both motors are lost")
	arena.queue_free()
	await process_frame

func saw_fixture() -> void:
	var arena := Arena.instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	var saw := arena.bots[0] as Robot
	var drum := arena.bots[1] as Robot
	saw.position = Vector3(3.45, 0.40, 0)
	saw.rotation.y = PI * 0.5
	drum.position = Vector3(0, 0.40, 0)
	drum.rotation.y = 0.0
	saw.freeze = false
	saw.active = true
	saw.rotor_speed = float(saw.tune.weapon_speed)
	var first_wheel := -1
	for owner in saw.get_shape_owners():
		if saw.shape_roles[owner] == "wheel":
			first_wheel = saw.shape_owner_get_shape_index(owner, 0)
			break
	saw.damage_component(39.0, "wheel", first_wheel)
	var delta := 1.0 / Engine.physics_ticks_per_second
	var aligned_cut := false
	var tooth_hits := 0
	for _tick in range(275):
		await physics_frame
		var pair := preload("res://scripts/combat/weapon_contact.gd").read_pair(arena.bots, delta)
		if not pair.hits[0].is_empty():
			tooth_hits += 1
			arena.resolve_strikes(pair.hits[0], {})
		saw.step(delta, arena._arena_radius())
		if saw.maneuver == Robot.Maneuver.ATTACK:
			aligned_cut = aligned_cut or Robot.deck_forward(saw.global_basis).dot((drum.position - saw.position).normalized()) > 0.80
		if tooth_hits > 0 and saw.maneuver == Robot.Maneuver.RECOVER:
			break
	check(saw.failed_wheel_count == 1 and aligned_cut and tooth_hits > 0,
		"one failed wheel can still line up a cut and score on a stationary side")
	check(saw.maneuver == Robot.Maneuver.RECOVER, "scored cut starts recovery")
	arena.queue_free()
	await process_frame

func run() -> void:
	var probe := Arena.instantiate()
	root.add_child(probe)
	var selected: bool = probe.bots[0].get_script() == SawPolicy and probe.bots[1].get_script() == DrumPolicy
	probe.queue_free()
	await process_frame
	if not selected:
		push_error("Select both candidates with --riptide-ai=tracked-flank --bulldozer-ai=tracked-intercept")
		quit(2)
		return
	await arc_fixture(0, false)
	await arc_fixture(1, true)
	await saw_fixture()
	print("RFS_TRACKED_AI_FIXTURES ", failures, " failures")
	quit(1 if failures else 0)
