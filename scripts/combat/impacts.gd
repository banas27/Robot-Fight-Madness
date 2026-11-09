extends Node3D
## Fixed visual and voice pools shared by all confirmed impact events.
const Shapes = preload("res://scripts/shapes.gd")
const RATE := 24000

class Particle:
	var node: Node3D
	var velocity := Vector3.ZERO
	var life := 0.0
	var total := 0.0
	var size := 0.0
	var tint := Color.WHITE

var rng := RandomNumberGenerator.new()
var sparks: Array[Particle] = []
var shards: Array[Particle] = []
var puffs: Array[Particle] = []
var voices: Array[AudioStreamPlayer] = []
var sounds: Dictionary = {}
var lights: Array[OmniLight3D] = []
var light_life := [0.0, 0.0]
var light_power := [0.0, 0.0]
var light_index := 0
var volume: float
var peak_particles := 0
var peak_voices := 0

func setup(settings: Dictionary, seed_value: int) -> void:
	rng.seed = seed_value ^ 0x4dbb
	volume = clampf(float(settings.impact_volume_db), -24.0, -9.0)
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var spark_mat := Shapes.material(Color("ffca78"), 0.0, 1.8)
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var core_mat := Shapes.material(Color("ffeaca"), 0.0, 2.4)
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var chip_mat := Shapes.material(Color("8495a1"), 0.49)
	chip_mat.roughness = 0.52
	for i in range(clampi(int(settings.spark_pool), 8, 96)):
		sparks.append(_mesh_particle(box, spark_mat if i % 3 else core_mat))
	for i in range(clampi(int(settings.debris_pool), 0, 32)):
		shards.append(_mesh_particle(box, chip_mat))
	var gradient := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(32):
			var edge := 1.0 - Vector2((x - 15.5) / 15.5, (y - 15.5) / 15.5).length()
			gradient.set_pixel(x, y, Color(1, 1, 1, pow(maxf(0, edge), 1.65)))
	var smoke_texture := ImageTexture.create_from_image(gradient)
	for i in range(clampi(int(settings.smoke_pool), 0, 24)):
		var sprite := Sprite3D.new()
		sprite.texture = smoke_texture
		sprite.pixel_size = 1.0 / 32.0
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sprite)
		sprite.hide()
		var particle := Particle.new()
		particle.node = sprite
		puffs.append(particle)
	for i in range(2):
		var light := OmniLight3D.new()
		light.light_color = Color("ffbf77")
		light.omni_range = 1.65
		light.omni_attenuation = 1.7
		light.light_energy = 0
		add_child(light)
		lights.append(light)
	for name in ["bump", "scrape", "saw", "drum", "clash", "shutdown"]:
		sounds[name] = _synthesize(name)
	for i in range(3):
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		voices.append(voice)

func _mesh_particle(mesh: Mesh, material: Material) -> Particle:
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.material_override = material
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(item)
	item.hide()
	var particle := Particle.new()
	particle.node = item
	return particle

func impact(event: Dictionary) -> void:
	var kind: String = event.kind
	var power: float = event.strength
	var point: Vector3 = event.point
	var normal: Vector3 = event.normal
	var strike := kind == "saw" or kind == "drum"
	var major: bool = event.get("major", false)
	var powered := kind in ["saw", "drum", "clash", "shutdown"]
	var count := roundi(lerpf(7, 17, power)) if powered else (3 if kind == "scrape" else roundi(power * 4))
	if strike:
		count = roundi(lerpf(14, 19, power)) if major else roundi(lerpf(4, 8, power))
	if kind == "shutdown":
		count = 19
	var side := Vector3.UP.cross(normal).normalized()
	if side.length_squared() < 0.1:
		side = Vector3.RIGHT
	var direction := (normal * 0.52 + Vector3.UP * 0.72).normalized()
	var bias := 1.0
	if event.has("relative"):
		var slide: Vector3 = event.relative - normal * event.relative.dot(normal)
		bias = -1.0 if slide.dot(side) < 0.0 else 1.0
		direction = (direction + slide.normalized() * 0.24).normalized()
	for i in range(count):
		var fan := side * rng.randf_range(0.35, 1.10) * bias * (-1.0 if i % 4 == 0 else 1.0)
		var jitter := Vector3(rng.randf_range(-0.30, 0.30), rng.randf_range(-0.19, 0.43), rng.randf_range(-0.30, 0.30))
		var launch := direction + fan + jitter if powered else normal * 0.3 + fan + Vector3.UP * 0.23 + jitter
		var velocity := launch.normalized() * rng.randf_range(3.2, 5.3 + power * 3.8)
		var life := rng.randf_range(0.11, 0.23) if strike else rng.randf_range(0.17, 0.33)
		_spawn(sparks, point + normal * 0.024, velocity, life, rng.randf_range(0.054, 0.093))
	if (strike and major) or (not strike and powered and power > 0.53):
		for i in range(2 + roundi(power * 3)):
			var velocity := direction * rng.randf_range(0.7, 2.4) + Vector3(rng.randf_range(-1, 1), rng.randf_range(0.9, 2.6), rng.randf_range(-1, 1))
			_spawn(shards, point, velocity, rng.randf_range(0.26, 0.51), rng.randf_range(0.035, 0.079))
	if kind == "scrape" or kind == "shutdown":
		for i in range(4 if kind == "shutdown" else 1):
			puff(point + Vector3.UP * (0.22 if kind == "shutdown" else 0.05), kind == "scrape")
	if (strike and major) or (not strike and powered and power > 0.44):
		lights[light_index].position = point + Vector3.UP * 0.12
		light_life[light_index] = 0.075
		light_power[light_index] = power * 1.18
		light_index = (light_index + 1) % lights.size()
	_play(kind, power)

func puff(point: Vector3, dust: bool = false) -> void:
	var motion := Vector3(rng.randf_range(-0.23, 0.23), 0.42 if dust else 0.61, rng.randf_range(-0.23, 0.23))
	var color := Color(0.64, 0.54, 0.42, 0.37) if dust else Color(0.29, 0.33, 0.36, 0.63)
	_spawn(puffs, point, motion, 0.64 if dust else 0.96, 0.33 if dust else 0.54, color)

func _spawn(pool: Array[Particle], point: Vector3, speed: Vector3, life: float, size: float, tint: Color = Color.WHITE) -> void:
	for particle in pool:
		if particle.life <= 0.0:
			particle.life = life
			particle.total = life
			particle.node.position = point
			particle.velocity = speed
			particle.size = size
			particle.tint = tint
			return

func _process(delta: float) -> void:
	var alive := _step(sparks, delta, "spark") + _step(shards, delta, "shard") + _step(puffs, delta, "puff")
	peak_particles = maxi(peak_particles, alive)
	for i in range(lights.size()):
		light_life[i] = maxf(0, float(light_life[i]) - delta)
		lights[i].light_energy = float(light_power[i]) * float(light_life[i]) / 0.075

func _step(pool: Array[Particle], delta: float, kind: String) -> int:
	var active_count := 0
	for particle in pool:
		if particle.life <= 0.0:
			continue
		particle.life = maxf(0, particle.life - delta)
		if particle.life == 0.0:
			particle.node.hide()
			continue
		active_count += 1
		var fade := particle.life / particle.total
		var node := particle.node
		node.position += particle.velocity * delta
		if kind == "puff":
			var sprite := node as Sprite3D
			sprite.modulate = Color(particle.tint, particle.tint.a * fade)
			node.scale = Vector3.ONE * particle.size * (1.5 - fade * 0.55)
		else:
			particle.velocity.y -= delta * 12.0
			if node.position.y < 0.035:
				node.position.y = 0.035
				particle.velocity.y = absf(particle.velocity.y) * 0.22
				particle.velocity *= 0.67
			if kind == "spark" and particle.velocity.length_squared() > 0.1:
				node.basis = Basis.looking_at(particle.velocity, Vector3.UP if absf(particle.velocity.normalized().y) < 0.99 else Vector3.RIGHT)
				node.scale = Vector3(0.028, 0.028, particle.size + particle.velocity.length() * 0.031) * maxf(0.18, fade)
			else:
				node.rotate_x(delta * 9.0)
				node.rotate_y(delta * 13.0)
				node.scale = Vector3(1.0, 0.63, 0.8) * particle.size * fade
		node.show()
	return active_count

func _play(kind: String, power: float) -> void:
	var selected: AudioStreamPlayer
	var quietest: AudioStreamPlayer
	var playing := 0
	var gain := volume - (1.0 - power) * 11.0 - (6.5 if kind == "scrape" else 0.0)
	for voice in voices:
		if voice.playing:
			playing += 1
			if quietest == null or voice.volume_db < quietest.volume_db:
				quietest = voice
		elif selected == null:
			selected = voice
	if selected == null:
		if quietest == null or gain < quietest.volume_db + 3.0:
			return
		selected = quietest
		selected.stop()
	else:
		playing += 1
	selected.stream = sounds[kind]
	selected.pitch_scale = rng.randf_range(0.92, 1.08)
	selected.volume_db = gain
	selected.play()
	peak_voices = maxi(peak_voices, playing)

func _synthesize(kind: String) -> AudioStreamWAV:
	var noise := RandomNumberGenerator.new()
	noise.seed = 0x254d + kind.hash()
	var duration := 0.20 if kind == "bump" else (0.18 if kind == "scrape" else (0.49 if kind == "shutdown" else 0.31))
	var samples := PackedByteArray()
	samples.resize(roundi(duration * RATE) * 2)
	var last := 0.0
	for i in range(samples.size() / 2):
		var t := float(i) / RATE
		var grain := noise.randf_range(-1, 1)
		var edge := grain - last
		last = grain
		var sample := 0.0
		var bass := sin(TAU * (81.0 * t + 1.85 * (1.0 - exp(-t * 34.0)))) * exp(-t * 22.0)
		var ring := (sin(TAU * 422.0 * t) * 0.22 + sin(TAU * 971.0 * t) * 0.16 + sin(TAU * 1537.0 * t) * 0.13) * exp(-t * 22.0)
		match kind:
			"bump": sample = bass * 0.73 + grain * exp(-t * 96.0) * 0.25
			"scrape": sample = (edge * 0.26 + sin(TAU * 1270.0 * t) * 0.10) * pow(sin(PI * t / duration), 2) * (0.62 + sin(TAU * t * 58.0) * 0.29)
			"saw": sample = bass * 0.38 + ring * 1.16 + edge * exp(-t * 61.0) * 0.35
			"drum": sample = bass * 0.84 + ring * 0.69 + grain * exp(-t * 51.0) * 0.41
			"clash": sample = bass * 0.49 + ring * 1.35 + edge * exp(-t * 70.0) * 0.26
			"shutdown": sample = bass * 0.66 + grain * exp(-t * 13.0) * 0.30 + sin(TAU * (106.0 * t - 70.0 * t * t)) * exp(-t * 7.0) * 0.32
		var window := minf(t * 900.0, 1.0) * clampf((duration - t) * 110.0, 0.0, 1.0)
		samples.encode_s16(i * 2, roundi(tanh(sample) * window * 28600.0))
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = RATE
	sound.data = samples
	return sound
