extends SceneTree
## Place real bodies in a few diagnostic situations, then use the normal
## fixed-tick solver and orders. Full fights are evaluated separately.
const Arena = preload("res://scenes/arena_combat.tscn")
const Match = preload("res://scripts/combat/match.gd")
const Robot = preload("res://scripts/combat/robot.gd")
const Trace = preload("res://scripts/combat/trace.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var results: Array[Dictionary] = []
	for scenario in ["stationary_flank", "frontal_charge", "rail_escape", "damaged_wheel"]:
		results.append(await play(scenario))
		await physics_frame
	print("RFS_SCENARIOS " + JSON.stringify(results))
	quit()

func play(scenario: String) -> Dictionary:
	var arena := Arena.instantiate() as Match
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.trace = Trace.new()
	var saw := arena.bots[0] as Robot
	var drum := arena.bots[1] as Robot
	arena._start_fight()
	saw.position = Vector3(3.0, 0.40, 1.12)
	saw.rotation.y = PI * 0.5
	drum.position = Vector3(0, 0.40, 0)
	drum.rotation.y = 0.0
	drum.freeze = true
	drum.active = false
	var ticks := 450
	match scenario:
		"frontal_charge":
			saw.position = Vector3(0.06, 0.40, 2.1)
			saw.rotation.y = -0.8
			drum.position = Vector3(0, 0.40, -2.85)
			drum.rotation.y = PI
			drum.freeze = false
			drum.active = true
			drum.linear_velocity = Vector3(0, 0, 2.1)
			drum.rotor_speed = float(drum.tune.weapon_speed)
			drum.charge_heading = Vector3.BACK
			drum.charge_id = 1
			drum._enter(Robot.Maneuver.ATTACK)
			ticks = 225
		"rail_escape":
			saw.position = Vector3(2.79, 0.40, 0.02)
			saw.rotation.y = -1.10
			drum.position = Vector3(0.1, 0.40, 0.12)
			drum.rotation.y = -PI * 0.5
			saw._recover(-saw.basis.z, (drum.position - saw.position).normalized(), arena._arena_radius())
		"damaged_wheel":
			for owner in saw.get_shape_owners():
				if saw.shape_roles[owner] == "wheel":
					var shape := saw.shape_owner_get_shape_index(owner, 0)
					saw.damage_component(42.0, "wheel", shape)
					break
			ticks = 585
	var dt := 1.0 / Engine.physics_ticks_per_second
	var first_contact := -1.0
	for i in range(ticks):
		await physics_frame
		arena._physics_process(dt)
		if first_contact < 0.0 and saw.opponent_contact:
			first_contact = arena.fight_elapsed
	arena.trace.tick(arena.bots, 0.0, arena.fight_elapsed, arena._arena_radius(), false)
	var outcome := {"scenario": scenario, "policy": arena.riptide_ai, "hp": [saw.hp, drum.hp],
		"grip": saw.drive_grip(), "first_contact_s": first_contact,
		"riptide": arena.trace.entries[0], "hits": arena.trace.strikes}
	arena.queue_free()
	return outcome
