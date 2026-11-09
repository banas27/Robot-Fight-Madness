extends Node3D
const Shapes = preload("res://scripts/shapes.gd")
const Robot = preload("res://scripts/robot.gd")
const HUD = preload("res://scripts/hud.gd")

var cfg: Dictionary
var bots: Array[RigidBody3D] = []
var phase := "intro"
var elapsed := 0.0
var fight_elapsed := 0.0
var result_elapsed := 0.0
var match_seed := 1
var rng := RandomNumberGenerator.new()
var autostop := false
var report_path := ""
var screenshot_path := ""
var screenshot_taken := false
var finished := false
var winner_name := ""
var winner_color := Color.WHITE
var result_reason := ""
var events: Array[Dictionary] = []
var effects: Array[Dictionary] = []
var camera: Camera3D
var shake := 0.0
var hit_banner := ""
var hit_banner_time := 0.0
var peak_speed := 0.0
var max_extent := 0.0
var sound_player: AudioStreamPlayer
var hit_sound: AudioStreamWAV
var camera_home := Vector3(9.0, 15.5, 17.5)

func _ready() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://config/match.json"))
	if not parsed is Dictionary:
		push_error("config/match.json must contain a JSON object.")
		get_tree().quit(2)
		return
	cfg = parsed
	for key in ["intro_seconds", "fight_seconds", "result_seconds", "health", "spinner_damage", "rammer_damage", "spinner_cooldown", "rammer_cooldown", "drive_speed", "charge_speed", "arena_half_width", "arena_half_length"]:
		if not cfg.has(key) or not (cfg[key] is float or cfg[key] is int) or float(cfg[key]) <= 0.0:
			push_error("Invalid positive numeric configuration: " + key)
			get_tree().quit(2)
			return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			match_seed = int(arg.get_slice("=", 1))
		elif arg == "--autostop":
			autostop = true
		elif arg.begins_with("--report="):
			report_path = arg.trim_prefix("--report=")
		elif arg.begins_with("--screenshot="):
			screenshot_path = arg.trim_prefix("--screenshot=")
	rng.seed = match_seed
	autostop = autostop or "--write-movie" in OS.get_cmdline_args()
	_build_arena()
	_build_bots()
	_build_sound()
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := HUD.new()
	hud.match_node = self
	layer.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	print("RFS_BEGIN seed=%d" % match_seed)

func _build_arena() -> void:
	var steel := Shapes.material(Color("52616c"), 0.45)
	var dark := Shapes.material(Color("202d39"), 0.4)
	var floor_mat := Shapes.material(Color("34434f"), 0.2)
	var accent := Shapes.material(Color("d3ad62"), 0.4)
	var w := float(cfg.arena_half_width)
	var l := float(cfg.arena_half_length)
	Shapes.solid_box(self, Vector3(w * 2 + 1.1, 0.35, l * 2 + 1.1), Vector3(0, -0.25, 0), dark)
	Shapes.box(self, Vector3(w * 2, 0.08, l * 2), Vector3(0, -0.04, 0), floor_mat)
	for x in range(-4, 5):
		Shapes.box(self, Vector3(0.018, 0.008, l * 2), Vector3(x, 0.007, 0), steel)
	for z in range(-5, 6):
		Shapes.box(self, Vector3(w * 2, 0.008, 0.018), Vector3(0, 0.007, z), steel)
	for x in [-w, w]:
		Shapes.solid_box(self, Vector3(0.3, 0.65, l * 2 + 0.3), Vector3(x, 0.25, 0), dark)
		Shapes.box(self, Vector3(0.34, 0.045, l * 2), Vector3(x, 0.6, 0), accent)
	for z in [-l, l]:
		Shapes.solid_box(self, Vector3(w * 2, 0.65, 0.3), Vector3(0, 0.25, z), dark)
		Shapes.box(self, Vector3(w * 2, 0.045, 0.34), Vector3(0, 0.6, z), accent)
	for x in [-w, w]:
		for z in [-l, l]:
			Shapes.box(self, Vector3(0.6, 1.05, 0.6), Vector3(x, 0.45, z), steel)
			Shapes.box(self, Vector3(0.62, 0.05, 0.62), Vector3(x, 1.0, z), Shapes.material(Color("dfe8ea"), 0, 1))
	for z in [-3.4, 3.4]:
		var color := Color("39d8e7") if z > 0 else Color("ff9045")
		Shapes.box(self, Vector3(2.2, 0.015, 0.07), Vector3(0, 0.02, z), Shapes.material(color, 0, 0.5))
	for z in [-l + 0.55, l - 0.55]:
		for x in range(-3, 4):
			var stripe := Shapes.box(self, Vector3(0.36, 0.015, 0.45), Vector3(x, 0.02, z), accent)
			stripe.rotation.y = 0.45
	var ring := TorusMesh.new()
	ring.inner_radius = 1.72
	ring.outer_radius = 1.78
	Shapes.attach(self, ring, Vector3(0, 0.025, 0), steel).scale.y = 0.12
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("101c28")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c5def1")
	environment.ambient_light_energy = 0.35
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world.environment = environment
	add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55, -25, 0)
	key.light_energy = 0.9
	key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35, 135, 0)
	fill.light_color = Color("9ed9ff")
	fill.light_energy = 0.25
	add_child(fill)
	camera = Camera3D.new()
	add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = 14.5
	camera.position = camera_home
	camera.look_at(Vector3.ZERO)
	camera.current = true

func _build_bots() -> void:
	for i in range(2):
		var bot := Robot.new()
		bot.name = "Riptide" if i == 0 else "Bulldozer"
		bot.setup("spinner" if i == 0 else "rammer", Color("39d8e7") if i == 0 else Color("ff9045"), cfg, rng.randf_range(0, 6))
		add_child(bot)
		bot.position = Vector3(rng.randf_range(-0.4, 0.4), 0.4, 3.4 if i == 0 else -3.4)
		bot.rotation.y = 0.0 if i == 0 else PI
		bots.append(bot)
	bots[0].opponent = bots[1]
	bots[1].opponent = bots[0]

func _build_sound() -> void:
	# Original synthesized impact sound; no third-party audio files.
	hit_sound = AudioStreamWAV.new()
	hit_sound.format = AudioStreamWAV.FORMAT_16_BITS
	hit_sound.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(6615 * 2)
	var audio_rng := RandomNumberGenerator.new()
	audio_rng.seed = 44
	for i in range(6615):
		var t := float(i) / 22050.0
		var noise := audio_rng.randf_range(-1, 1)
		var sample := (noise * exp(-t * 35.0) * 0.5 + sin(TAU * 95.0 * t) * exp(-t * 18.0) * 0.5) * 0.75
		data.encode_s16(i * 2, int(clampf(sample, -1, 1) * 32767))
	hit_sound.data = data
	sound_player = AudioStreamPlayer.new()
	sound_player.stream = hit_sound
	sound_player.volume_db = -9
	add_child(sound_player)

func _physics_process(delta: float) -> void:
	if bots.size() != 2 or finished:
		return
	elapsed += delta
	hit_banner_time = maxf(0.0, hit_banner_time - delta)
	if phase == "intro" and elapsed >= float(cfg.intro_seconds):
		phase = "fight"
		for bot in bots:
			bot.active = true
	if phase == "fight":
		fight_elapsed += delta
	for bot in bots:
		bot.step(delta)
		peak_speed = maxf(peak_speed, bot.linear_velocity.length())
		max_extent = maxf(max_extent, maxf(absf(bot.position.x) / float(cfg.arena_half_width), absf(bot.position.z) / float(cfg.arena_half_length)))
	if phase == "fight":
		# Snapshot both attacks before applying either, allowing a fair double KO.
		var attacks: Array[bool] = [bots[0].attack_available(), bots[1].attack_available()]
		for i in range(2):
			if attacks[i]:
				_hit(bots[i], bots[1 - i])
		if bots[0].hp <= 0 or bots[1].hp <= 0:
			_finish("knockout")
		elif fight_elapsed >= float(cfg.fight_seconds):
			_finish("time limit / health decision")
	elif phase == "result":
		result_elapsed += delta
		if result_elapsed >= float(cfg.result_seconds):
			finished = true
			_write_report()
			if autostop:
				get_tree().quit()
	_update_effects(delta)
	shake = maxf(0.0, shake - delta * 1.4)
	camera.position = camera_home + Vector3(sin(elapsed * 70), cos(elapsed * 58), 0) * shake * 0.1
	if not screenshot_taken and screenshot_path != "" and elapsed > 6.0 and DisplayServer.get_name() != "headless":
		screenshot_taken = true
		_save_screenshot.call_deferred()

func _hit(attacker: RigidBody3D, defender: RigidBody3D) -> void:
	var damage: float = attacker.spend_attack()
	var direction := (defender.position - attacker.position).normalized()
	defender.receive_hit(damage, direction, 10.5 if attacker.kind == "rammer" else 5.5)
	var point := (attacker.position + defender.position) * 0.5
	_sparks(point)
	shake = 0.8
	hit_banner = "RAM HIT  -%d" % int(damage) if attacker.kind == "rammer" else "SPINNER HIT  -%d" % int(damage)
	hit_banner_time = 0.65
	sound_player.pitch_scale = 0.8 if attacker.kind == "rammer" else 1.25
	if DisplayServer.get_name() != "headless" and not "Dummy" in OS.get_cmdline_args():
		sound_player.stop()
		sound_player.play()
	events.append({"time": snappedf(fight_elapsed, 0.001), "attacker": attacker.name, "damage": damage, "target_hp": defender.hp})

func _sparks(at: Vector3) -> void:
	# Separate visual RNG so sparks never alter combat variation.
	var vfx_rng := RandomNumberGenerator.new()
	vfx_rng.seed = events.size() + 301
	var mat := Shapes.material(Color("ffcf76"), 0.0, 2.0)
	for i in range(12):
		var spark := Shapes.box(self, Vector3(0.045, 0.045, 0.17), at, mat)
		var velocity := Vector3(vfx_rng.randf_range(-3, 3), vfx_rng.randf_range(1, 4), vfx_rng.randf_range(-3, 3))
		effects.append({"node": spark, "velocity": velocity, "life": 0.45})

func _update_effects(delta: float) -> void:
	for i in range(effects.size() - 1, -1, -1):
		var effect: Dictionary = effects[i]
		effect.life -= delta
		if effect.life <= 0:
			effect.node.queue_free()
			effects.remove_at(i)
			continue
		effect.velocity.y -= delta * 9.8
		effect.node.position += effect.velocity * delta
		effect.node.scale = Vector3.ONE * float(effect.life) / 0.45

func _finish(reason: String) -> void:
	phase = "result"
	result_reason = reason
	for bot in bots:
		bot.active = false
	if is_equal_approx(bots[0].hp, bots[1].hp):
		winner_name = "DRAW"
		winner_color = Color.WHITE
	else:
		var winner: RigidBody3D = bots[0] if bots[0].hp > bots[1].hp else bots[1]
		winner_name = str(winner.name).to_upper()
		winner_color = winner.team_color

func _write_report() -> void:
	var report := {"version": "R01", "seed": match_seed, "winner": winner_name, "reason": result_reason, "duration": elapsed, "fight_duration": fight_elapsed, "hp": [bots[0].hp, bots[1].hp], "hits": [bots[0].hit_count, bots[1].hit_count], "recoveries": [bots[0].recovery_count, bots[1].recovery_count], "peak_speed": peak_speed, "max_arena_extent_ratio": max_extent, "events": events}
	print("RFS_RESULT " + JSON.stringify(report))
	if report_path != "":
		var file := FileAccess.open(report_path, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(report, "\t") + "\n")
		else:
			push_error("Could not write report: " + report_path)
			get_tree().quit(3)

func _save_screenshot() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(screenshot_path)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			get_tree().reload_current_scene()
		elif event.keycode == KEY_ESCAPE:
			get_tree().quit()

func _exit_tree() -> void:
	if is_instance_valid(sound_player):
		sound_player.stop()
		sound_player.stream = null
	hit_sound = null
