extends RefCounted
## Converts solver manifolds into one strike per attacker and contact episode.
const Robot = preload("res://scripts/combat/robot.gd")

static func is_weapon(role: String) -> bool:
	return role == "tooth" or role == "core"

static func read_pair(bots: Array[RigidBody3D], delta: float) -> Dictionary:
	var hits: Array[Dictionary] = [{}, {}]
	var touching := [false, false]
	var clash: Dictionary = {}
	var weapon_depth := 0.0
	for i in range(2):
		var own := bots[i] as Robot
		var other := bots[1 - i] as Robot
		for contact in own.contacts:
			if contact.other_id != other.get_instance_id():
				continue
			var point: Vector3 = contact.point
			var local_weapon := is_weapon(contact.local_role)
			var other_weapon := is_weapon(contact.other_role)
			if local_weapon or other_weapon:
				weapon_depth = maxf(weapon_depth, float(contact.depth))
			if local_weapon and other_weapon:
				var relative: Vector3 = contact.relative + _surface_motion(own, point) - _surface_motion(other, point)
				var power := clampf((relative.length() * 0.27 + float(contact.strength)) / 6.4, 0.17, 0.91)
				if power > float(clash.get("strength", 0.0)):
					clash = {"kind": "clash", "point": point, "normal": contact.normal,
						"relative": relative, "strength": power}
				continue
			if not local_weapon and not other_weapon:
				continue
			var attacker_index := i if local_weapon else 1 - i
			touching[attacker_index] = true
			var role: String = contact.local_role if local_weapon else contact.other_role
			if role != "tooth":
				continue
			var attacker := bots[attacker_index] as Robot
			var defender := bots[1 - attacker_index] as Robot
			if not attacker.active or attacker.hp <= 0.0 or defender.hp <= 0.0:
				continue
			if attacker.weapon_disabled or attacker.strike_latched or attacker.cooldown > 0.0 or attacker.rotor_speed < float(attacker.tune.weapon_speed) * 0.46:
				continue
			if attacker.to_local(point).z > (-0.70 if attacker.kind == "saw" else -0.90):
				continue
			var normal: Vector3 = contact.normal if local_weapon else -contact.normal
			var spin := _surface_motion(attacker, point)
			var relative: Vector3 = (contact.relative if local_weapon else -contact.relative) + spin
			var normal_speed := relative.dot(normal)
			var closing := maxf(0.0, -normal_speed)
			var tangent := relative - normal * normal_speed
			if closing < 0.42 and (tangent.length() < 3.7 or normal_speed > 1.1):
				continue
			var score := closing + tangent.length() * 0.24 + float(contact.strength) * 0.65
			if score > float(hits[attacker_index].get("score", 0.0)):
				var strength := clampf(score / (16.0 if attacker.kind == "saw" else 10.0), 0.23, 1.0)
				hits[attacker_index] = {"point": point, "normal": normal, "relative": relative,
					"tangent": spin - normal * spin.dot(normal), "closing": closing,
					"strength": strength, "score": score, "target_part": contact.other_role if local_weapon else contact.local_role,
					"target_shape": contact.other_shape if local_weapon else contact.local_shape}
	for i in range(2):
		var bot := bots[i] as Robot
		bot.clear_contact_time = 0.0 if touching[i] else bot.clear_contact_time + delta
		if bot.clear_contact_time >= 0.13:
			bot.strike_latched = false
	return {"hits": hits, "clash": clash, "weapon_depth": weapon_depth}

static func _surface_motion(bot: Robot, point: Vector3) -> Vector3:
	var angular := bot.global_basis * bot.weapon_axis * bot.rotor_speed
	return angular.cross(point - bot.to_global(bot.weapon_pivot))
