extends RigidBody3D
## Force-driven planar arcade combat. Wheels and weapons are visual only.
## This is not an engineering-accurate drivetrain/destruction simulation.
const Shapes = preload("res://scripts/shapes.gd")

var kind: String = "spinner"
var team_color := Color("39d8e7")
var cfg: Dictionary
var opponent: RigidBody3D
var active := false
var hp: float = 100.0
var attack_cooldown: float = 0.0
var drive_clock: float = 0.0
var reverse_until: float = 0.0
var stuck_time: float = 0.0
var turn_bias: float = 1.0
var weapon: Node3D
var wheels: Array[MeshInstance3D] = []
var shell: StandardMaterial3D
var flash: float = 0.0
var hit_count := 0
var recovery_count := 0

func setup(which: String, color: Color, settings: Dictionary, phase: float) -> void:
	kind = which
	team_color = color
	cfg = settings
	hp = float(cfg.health)
	drive_clock = phase
	turn_bias = 1.0 if phase < 3.0 else -1.0
	mass = 3.0 if kind == "rammer" else 2.6
	gravity_scale = 0.0
	linear_damp = 1.3
	angular_damp = 4.0
	lock_rotation = false
	axis_lock_linear_y = true
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	continuous_cd = true
	can_sleep = false
	var physics := PhysicsMaterial.new()
	physics.friction = 0.25
	physics.bounce = 0.15
	physics_material_override = physics
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.34, 0.65, 1.62)
	collider.shape = shape
	add_child(collider)
	_build_model()

func _build_model() -> void:
	var black := Shapes.material(Color("111b25"), 0.4)
	var metal := Shapes.material(Color("93a4af"), 0.8)
	shell = Shapes.material(team_color, 0.55)
	Shapes.box(self, Vector3(1.2, 0.38, 1.35), Vector3(0, 0.05, 0), shell)
	Shapes.box(self, Vector3(0.9, 0.18, 0.85), Vector3(0, 0.32, 0.15), black)
	Shapes.box(self, Vector3(0.12, 0.05, 0.7), Vector3(0, 0.43, 0.15), Shapes.material(team_color, 0.0, 1.5))
	for x in [-0.73, 0.73]:
		for z in [-0.43, 0.43]:
			var wheel := Shapes.cylinder(self, 0.32, 0.23, Vector3(x, -0.04, z), black)
			wheel.rotation.z = PI / 2.0
			wheels.append(wheel)
			var hub := Shapes.cylinder(self, 0.13, 0.25, Vector3(x, -0.04, z), metal)
			hub.rotation.z = PI / 2.0
	for x in [-0.43, 0.43]:
		Shapes.box(self, Vector3(0.13, 0.09, 0.06), Vector3(x, 0.2, -0.7), Shapes.material(Color("efffff"), 0.0, 2.0))
	weapon = Node3D.new()
	add_child(weapon)
	weapon.position = Vector3(0, 0.04, -0.87)
	if kind == "spinner":
		Shapes.cylinder(weapon, 0.55, 0.16, Vector3.ZERO, metal)
		Shapes.box(weapon, Vector3(1.28, 0.22, 0.16), Vector3.ZERO, shell)
		Shapes.cylinder(weapon, 0.15, 0.24, Vector3.ZERO, black)
	else:
		var blade := Shapes.box(weapon, Vector3(1.5, 0.25, 0.58), Vector3(0, -0.03, -0.08), metal)
		blade.rotation.x = -0.3
		for x in [-0.45, 0.45]:
			Shapes.box(weapon, Vector3(0.15, 0.18, 0.7), Vector3(x, 0.08, -0.16), shell)

func step(delta: float) -> void:
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	drive_clock += delta
	flash = maxf(0.0, flash - delta * 5.0)
	shell.albedo_color = team_color.darkened(0.65) if hp <= 0.0 else team_color.lerp(Color.WHITE, flash)
	if kind == "spinner":
		weapon.rotation.y += delta * (35.0 if active else (0.0 if hp <= 0.0 else 3.0))
	for wheel in wheels:
		wheel.rotate_y(linear_velocity.length() * delta * 2.0)
	if not active or hp <= 0.0 or not is_instance_valid(opponent):
		apply_central_force(-linear_velocity * mass * 5.0)
		angular_velocity.y = 0.0
		return
	var offset: Vector3 = opponent.position - position
	offset.y = 0.0
	var distance := offset.length()
	var aim := offset.normalized()
	# A small circling offset prevents endless nose-to-nose pushing.
	if distance < 2.8 and fmod(drive_clock, 4.5) > 2.3:
		aim = (aim + Vector3(-aim.z, 0, aim.x) * 0.8 * turn_bias).normalized()
	var forward := -global_basis.z
	var angle := forward.signed_angle_to(aim, Vector3.UP)
	angular_velocity.y = clampf(angle * 5.0, -4.0, 4.0)
	if linear_velocity.length() < 0.5:
		stuck_time += delta
	else:
		stuck_time = 0.0
	if stuck_time > 0.8:
		reverse_until = drive_clock + 0.65
		stuck_time = 0.0
		recovery_count += 1
	var speed: float = float(cfg.drive_speed)
	if kind == "rammer" and absf(angle) < 0.35 and distance > 1.7:
		speed = float(cfg.charge_speed)
	if drive_clock < reverse_until:
		speed = -4.5 if kind == "rammer" else -2.8
		if kind != "rammer":
			angular_velocity.y += turn_bias * 1.8
	else:
		speed *= clampf(1.0 - absf(angle) / PI, 0.18, 1.0)
	var desired := forward * speed
	var acceleration := (desired - linear_velocity) * 6.0
	apply_central_force(acceleration.limit_length(24.0) * mass)
	linear_velocity = linear_velocity.limit_length(8.0)

func attack_available() -> bool:
	if not active or hp <= 0.0 or attack_cooldown > 0.0:
		return false
	var offset: Vector3 = opponent.position - position
	offset.y = 0.0
	if offset.length() > 2.0:
		return false
	var facing := (-global_basis.z).dot(offset.normalized())
	if kind == "spinner":
		return facing > 0.35
	var approach := (linear_velocity - opponent.linear_velocity).dot(offset.normalized())
	return facing > 0.55 and approach > 1.4

func spend_attack() -> float:
	attack_cooldown = float(cfg.spinner_cooldown if kind == "spinner" else cfg.rammer_cooldown)
	if kind == "rammer":
		# Make room for the next charge instead of staying pressed against a spinner.
		reverse_until = drive_clock + 1.0
	hit_count += 1
	return float(cfg.spinner_damage if kind == "spinner" else cfg.rammer_damage)

func receive_hit(damage: float, direction: Vector3, impulse: float) -> void:
	hp = maxf(0.0, hp - damage)
	flash = 1.0
	apply_central_impulse(direction * impulse)
	apply_torque_impulse(Vector3.UP * turn_bias * 1.2)
	if hp <= 0.0:
		active = false
		shell.albedo_color = team_color.darkened(0.6)
