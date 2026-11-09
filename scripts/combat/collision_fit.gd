extends RefCounted
## Dimensions follow the Riptide and Bulldozer GLB build profiles.
## Stationary supports are separate from the axle owner that carries the teeth.
const BODY := 1
const WALL := 2
const DECK := 4
const AXIAL := Basis(Vector3.BACK, PI * 0.5)
const MARGIN := 0.002
static var wheel_support: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/wheel_support.json"))

static func install(bot) -> void:
	var saw: bool = bot.kind == "saw"
	bot.weapon_axis = Vector3.UP if saw else Vector3.RIGHT
	bot.weapon_pivot = Vector3(0, 0.04, -0.87) if saw else Vector3(0, -0.021, -1.125)
	if saw:
		_saw_body(bot)
	else:
		_drum_body(bot)
	for side in [-1.0, 1.0]:
		for end in [-1.0, 1.0]:
			var axle := Vector3(side * (0.73 if saw else 0.605), -0.08 if saw else -0.105,
				end * (0.43 if saw else 0.433))
			if saw:
				# Keep the tread envelope, with explicit edges for the
				# crossed-axis contact against Bulldozer's drum.
				_round_prism(bot, "wheel", axle, 0.320, 0.224, AXIAL)
			else:
				_cylinder(bot, "wheel", axle, 0.294, 0.218, AXIAL)
			var hub: Vector3 = axle + Vector3.RIGHT * side * (0.132 if saw else 0.117)
			if saw:
				# Use explicit rim and cap faces where the drum crosses the
				# hub. GodotPhysics can pick a far cap witness for the cylinder.
				_round_prism(bot, "wheel", hub, 0.108, 0.058, AXIAL)
			else:
				_cylinder(bot, "wheel", hub, 0.097, 0.041, AXIAL)
	bot.rotor_owner = bot.create_shape_owner(bot)
	bot.shape_roles[bot.rotor_owner] = "tooth"
	if saw:
		_saw_weapon(bot)
	else:
		_drum_weapon(bot)
	bot.sync_weapon_shapes()
	_install_wheel_support(bot, 0.43 if saw else 0.433)

static func _install_wheel_support(bot, axle_z: float) -> void:
	var fit: Dictionary = wheel_support[bot.kind]
	var skid: Array = fit.skid_center
	var bearing: Array = fit.bearing_center
	for side in [-1.0, 1.0]:
		_box(bot, "chassis", Vector3(side * skid[0], skid[1], skid[2]), _dimensions(fit.skid_size))
		for end in [-1.0, 1.0]:
			_box(bot, "chassis", Vector3(side * bearing[0], bearing[1], end * axle_z), _dimensions(fit.bearing_size))

static func _dimensions(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])

# Bottom of the installed solid geometry relative to the chassis origin.
static func lowest_surface_y(bot, orientation: Basis) -> float:
	var lowest := INF
	var chassis := Transform3D(orientation, Vector3.ZERO)
	for owner in bot.get_shape_owners():
		if bot.is_shape_owner_disabled(owner):
			continue
		var pose: Transform3D = chassis * bot.shape_owner_get_transform(owner)
		for i in range(bot.shape_owner_get_shape_count(owner)):
			var shape: Shape3D = bot.shape_owner_get_shape(owner, i)
			if shape is BoxShape3D:
				var vertical := Vector3(pose.basis.x.y, pose.basis.y.y, pose.basis.z.y).abs()
				lowest = minf(lowest, pose.origin.y - vertical.dot(shape.size) * 0.5)
			elif shape is CylinderShape3D:
				var axis_y := absf(pose.basis.y.y)
				var reach: float = shape.height * 0.5 * axis_y + shape.radius * sqrt(maxf(0.0, 1.0 - axis_y * axis_y))
				lowest = minf(lowest, pose.origin.y - reach)
			elif shape is ConvexPolygonShape3D:
				for point: Vector3 in shape.points:
					lowest = minf(lowest, (pose * point).y)
	return lowest

static func _saw_body(bot) -> void:
	var footprint := PackedVector2Array([Vector2(-0.49,-0.64), Vector2(0.49,-0.64), Vector2(0.595,-0.20),
		Vector2(0.57,0.48), Vector2(0.45,0.68), Vector2(-0.45,0.68), Vector2(-0.57,0.48), Vector2(-0.595,-0.20)])
	_prism(bot, "chassis", footprint, 0.205, 0.355)
	_box(bot, "chassis", Vector3(0,0.015,0.30), Vector3(1.01,0.32,0.69))
	_box(bot, "chassis", Vector3(0,-0.01,0.67), Vector3(0.79,0.15,0.098))
	_box(bot, "chassis", Vector3(0,0.363,0.13), Vector3(0.36,0.113,0.93))
	_box(bot, "support", Vector3(0,0.30,-0.68), Vector3(0.175,0.094,0.39))
	_cylinder(bot, "support", Vector3(0,0.275,-0.87), 0.098, 0.054)

static func _drum_body(bot) -> void:
	var footprint := PackedVector2Array([Vector2(-0.635,-0.755), Vector2(0.635,-0.755), Vector2(0.714,-0.635),
		Vector2(0.714,0.635), Vector2(0.607,0.754), Vector2(-0.607,0.754), Vector2(-0.714,0.635), Vector2(-0.714,-0.635)])
	_prism(bot, "chassis", footprint, 0.196, 0.342)
	_box(bot, "chassis", Vector3(0,0.006,0.035), Vector3(0.94,0.39,1.44))
	_box(bot, "chassis", Vector3(0,0.076,-0.72), Vector3(0.98,0.22,0.156))
	_box(bot, "chassis", Vector3(0,-0.047,0.745), Vector3(0.93,0.17,0.152))
	for side in [-1.0, 1.0]:
		var shoulder := PackedVector2Array([Vector2(0.548,-0.726), Vector2(0.728,-0.694), Vector2(0.802,-0.525),
			Vector2(0.802,0.539), Vector2(0.727,0.693), Vector2(0.548,0.725)])
		var guard := PackedVector2Array([Vector2(0.748,-0.634), Vector2(0.773,-0.628), Vector2(0.808,-0.497),
			Vector2(0.808,0.497), Vector2(0.773,0.628), Vector2(0.748,0.634)])
		_prism(bot, "chassis", shoulder, 0.194, 0.375, side)
		_prism(bot, "chassis", guard, -0.092, 0.254, side)
		_box(bot, "chassis", Vector3(side * 0.814,0.006,0.014), Vector3(0.026,0.069,0.81))
		var fork := [Vector2(0.193,-0.680), Vector2(0.307,-0.682), Vector2(0.288,-0.807), Vector2(0.114,-1.151),
			Vector2(0.055,-1.213), Vector2(-0.065,-1.215), Vector2(-0.125,-1.151), Vector2(-0.116,-1.077), Vector2(0.135,-0.766)]
		var points := PackedVector3Array()
		for x in [0.670, 0.792]:
			for yz: Vector2 in fork:
				points.append(Vector3(side * x, yz.x, yz.y))
		bot.add_solid(_convex(points), Transform3D.IDENTITY, "support")
		_cylinder(bot, "support", Vector3(side * 0.799,-0.021,-1.125), 0.096, 0.058, AXIAL)

static func _saw_weapon(bot) -> void:
	var pivot: Vector3 = bot.weapon_pivot
	_core(bot, pivot + Vector3.UP * 0.0655, 0.479, 0.034, Basis.IDENTITY)
	_cylinder(bot, "core", pivot + Vector3.UP * 0.028, 0.240, 0.047)
	_cylinder(bot, "core", pivot + Vector3.UP * 0.097, 0.207, 0.039)
	_cylinder(bot, "core", pivot + Vector3.UP * 0.133, 0.120, 0.065)
	_cylinder(bot, "core", pivot + Vector3.UP * 0.174, 0.066, 0.018)
	# One small convex wedge per tooth. Keep the actual gaps between teeth.
	var profile := [Vector2(0,0.465), Vector2(0.16,0.484), Vector2(0.37,0.516),
		Vector2(0.74,0.595), Vector2(0.89,0.586), Vector2(0.97,0.508), Vector2(1,0.465)]
	for tooth in range(24):
		var points := PackedVector3Array()
		for y in [0.049, 0.082]:
			for edge: Vector2 in profile:
				var a := (tooth + edge.x) * TAU / 24.0
				points.append(Vector3(cos(a) * edge.y, y, -sin(a) * edge.y))
		bot.shape_owner_add_shape(bot.rotor_owner, _convex(points))

static func _drum_weapon(bot) -> void:
	var pivot: Vector3 = bot.weapon_pivot
	_core(bot, pivot, 0.182, 1.197, AXIAL)
	for side in [-1.0, 1.0]:
		_core(bot, pivot + Vector3.RIGHT * side * 0.554, 0.196, 0.051, AXIAL)
		_core(bot, pivot + Vector3.RIGHT * side * 0.606, 0.185, 0.046, AXIAL)
	for station in range(-2, 3):
		for tooth in range(3):
			var phase := deg_to_rad(39.0 + station * 19.0) + tooth * TAU / 3.0
			var radial := Vector3(0, cos(phase), -sin(phase))
			var tangent := Vector3(0, sin(phase), cos(phase))
			var points := PackedVector3Array()
			for section: Vector3 in [Vector3(0.174,1.0,0.0), Vector3(0.204,0.87,0.005),
					Vector3(0.292 if station == 0 else 0.279,0.075,0.021)]:
				for i in range(8):
					var a := (i + 0.5) * TAU / 8.0
					points.append(Vector3.RIGHT * (station * 0.216 + 0.076 * section.y * cos(a))
						+ radial * section.x + tangent * (section.z + 0.051 * section.y * sin(a)))
			bot.shape_owner_add_shape(bot.rotor_owner, _convex(points))

static func _box(bot, role: String, at: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	shape.margin = MARGIN
	bot.add_solid(shape, Transform3D(Basis.IDENTITY, at), role)

static func _cylinder(bot, role: String, at: Vector3, radius: float, height: float, basis: Basis = Basis.IDENTITY) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	shape.margin = MARGIN
	bot.add_solid(shape, Transform3D(basis, at), role)

static func _core(bot, at: Vector3, radius: float, height: float, basis: Basis) -> void:
	# Inscribed faces give the solver explicit rim/cap edges for crossed rotors.
	_round_prism(bot, "core", at, radius, height, basis)

static func _round_prism(bot, role: String, at: Vector3, radius: float, height: float, basis: Basis) -> void:
	var points := PackedVector3Array()
	for y in [-height * 0.5, height * 0.5]:
		for i in range(32):
			var angle := TAU * i / 32.0
			points.append(Vector3(radius * cos(angle), y, radius * sin(angle)))
	bot.add_solid(_convex(points), Transform3D(basis, at), role)

static func _prism(bot, role: String, footprint: PackedVector2Array, low: float, high: float, side: float = 1.0) -> void:
	var points := PackedVector3Array()
	for y in [low, high]:
		for xz in footprint:
			points.append(Vector3(xz.x * side, y, xz.y))
	bot.add_solid(_convex(points), Transform3D.IDENTITY, role)

static func _convex(points: PackedVector3Array) -> ConvexPolygonShape3D:
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	shape.margin = MARGIN
	return shape
