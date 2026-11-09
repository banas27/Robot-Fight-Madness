extends "res://scripts/hud.gd"
## Independent render world. The studio only owns visual rigs, never physics bodies.
const Shapes = preload("res://scripts/shapes.gd")
const SawArt = preload("res://scripts/art/riptide_visual.gd")
const DrumArt = preload("res://scripts/art/bulldozer_visual.gd")
const RobotArt = preload("res://scripts/art/robot_visual.gd")
const CombatRobot = preload("res://scripts/combat/robot.gd")
const SIZE := Vector2(720, 1280)
const TURN_RATE := 0.19
const INK := Color("0b111beF")
const LINE := Color("344357")
var studio: SubViewport
var studio_camera: Camera3D
var plinths: Array[Node3D] = []
var models: Array[RobotArt] = []
var shot := -2
var shot_time := 0.0
var showing_result := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	studio = SubViewport.new()
	studio.size = Vector2i(SIZE)
	studio.world_3d = World3D.new()
	studio.gui_disable_input = true
	studio.msaa_3d = Viewport.MSAA_2X
	# Render before the texture has ever been sampled, including movie frame zero.
	studio.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(studio)
	var stage := Node3D.new()
	studio.add_child(stage)
	_build_stage(stage)
	for i in range(2):
		var bot = match_node.bots[i]
		var plinth := Node3D.new()
		stage.add_child(plinth)
		_build_plinth(plinth, bot.team_color)
		var model: RobotArt = SawArt.new() if bot.kind == "saw" else DrumArt.new()
		plinth.add_child(model)
		model.position.y = 0.40
		plinths.append(plinth)
		models.append(model)
	_process(0.0)

func _build_stage(stage: Node3D) -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0d1420")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d6e8ff")
	env.ambient_light_energy = 0.46
	world.environment = env
	stage.add_child(world)
	var floor := Shapes.material(Color("131e2d"), 0.12)
	floor.roughness = 0.82
	Shapes.box(stage, Vector3(80, 0.10, 80), Vector3(0, -0.38, 0), floor)
	var key := DirectionalLight3D.new()
	stage.add_child(key)
	key.position = Vector3(-3.5, 6.5, -4.5)
	key.look_at(Vector3.ZERO)
	key.light_energy = 0.98
	key.light_color = Color("fff1de")
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 14.0
	var fill := OmniLight3D.new()
	stage.add_child(fill)
	fill.position = Vector3(3.2, 2.3, -3.3)
	fill.light_energy = 0.78
	fill.light_color = Color("cfe8ff")
	fill.omni_range = 9.0
	studio_camera = Camera3D.new()
	stage.add_child(studio_camera)
	studio_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	studio_camera.keep_aspect = Camera3D.KEEP_WIDTH
	studio_camera.far = 32.0
	studio_camera.current = true

func _build_plinth(plinth: Node3D, accent: Color) -> void:
	var frame := Shapes.material(Color("182330"), 0.57)
	frame.roughness = 0.48
	var deck := Shapes.material(Color("293847"), 0.44)
	deck.roughness = 0.55
	var bevel := Shapes.material(Color("3b4e61"), 0.64)
	var trim := Shapes.material(accent.darkened(0.08), 0.12, 0.52)
	_disc(plinth, 1.52, 1.42, 0.17, -0.245, frame)
	_disc(plinth, 1.54, 1.52, 0.064, -0.129, bevel)
	_disc(plinth, 1.54, 1.54, 0.027, -0.084, trim)
	_disc(plinth, 1.44, 1.54, 0.072, -0.036, deck)
	var notch := Shapes.material(Color("6f8191"), 0.55)
	for i in range(16):
		var bearing := TAU * float(i) / 16.0
		var radial := Vector3(cos(bearing), 0, sin(bearing))
		var mark := Shapes.box(plinth, Vector3(0.069, 0.004, 0.021), radial * 1.365 + Vector3.UP * 0.003, notch)
		mark.rotation.y = -bearing
	var rim := OmniLight3D.new()
	plinth.add_child(rim)
	rim.position = Vector3(0.9, 1.75, 1.9)
	rim.light_color = accent
	rim.light_energy = 1.35
	rim.omni_range = 5.4

func _disc(parent: Node3D, top: float, bottom: float, height: float, y: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 72
	Shapes.attach(parent, mesh, Vector3(0, y, 0), material)

func _process(_delta: float) -> void:
	if match_node.phase == "fight":
		if visible:
			hide()
			studio.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if not visible or studio.render_target_update_mode == SubViewport.UPDATE_DISABLED:
		show()
		studio.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if match_node.phase == "result":
		if not showing_result:
			showing_result = true
			_load_result(match_node.result_snapshot)
		shot_time = match_node.result_elapsed
		if shot >= 0:
			models[shot].rotation.y = 0.10 - TURN_RATE * shot_time
		else:
			var turn := 0.34 + TURN_RATE * 0.75 * shot_time
			models[0].rotation.y = turn
			models[1].rotation.y = -turn
	else:
		var span: float = match_node.intro_shot_seconds
		var index := 1 if match_node.elapsed + 0.000001 >= span else 0
		if shot != index:
			_set_shot(index)
		shot_time = maxf(0.0, match_node.elapsed - span * index)
		models[shot].rotation.y = 0.10 - TURN_RATE * shot_time
		models[shot].update_visual(0.0, shot_time * (2.4 if shot == 0 else 1.7), 0.0, 0.0)
	queue_redraw()

func _set_shot(index: int) -> void:
	shot = index
	var draw_match := shot < 0
	for i in range(plinths.size()):
		plinths[i].visible = draw_match or i == shot
		# The camera faces positive Z, so positive world X is screen left.
		plinths[i].position.x = (1.71 if i == 0 else -1.71) if draw_match else 0.0
	studio_camera.size = 7.30 if draw_match else 4.34
	studio_camera.position = Vector3(0, 6.8, -15.0) if draw_match else Vector3(4.15, 3.85, -7.35)
	studio_camera.look_at(Vector3(0, 0.05, -0.04))

func _load_result(snapshot: Dictionary) -> void:
	_set_shot(snapshot.winner_index)
	for i in range(models.size()):
		var state: Dictionary = snapshot.robots[i]
		var visual := models[i]
		visual.show_damage(state.armor_damage, state.wheel_states, state.weapon_damage, state.weapon_disabled)
		visual.update_visual(0.0, state.rotor_angle, 0.0, 0.0, 0.0, state.hp <= 0.0)
		for wheel in range(visual.wheel_pivots.size()):
			var pivot := visual.wheel_pivots[wheel]
			pivot.visible = state.wheel_states[wheel] != CombatRobot.Wheel.DETACHED
			if pivot.visible:
				pivot.basis = state.wheel_bases[wheel]

static func reveal(time: float, at: float) -> float:
	if time + 0.000001 < at:
		return 0.0
	return lerpf(0.18, 1.0, smoothstep(0.0, 0.26, maxf(0.0, time - at)))

func _draw() -> void:
	if studio == null or match_node.phase == "fight":
		return
	draw_set_transform(Vector2.ZERO, 0.0, size / SIZE)
	draw_rect(Rect2(Vector2.ZERO, SIZE), Color("0d1420"))
	draw_texture_rect(studio.get_texture(), Rect2(Vector2.ZERO, SIZE), false)
	_at_center("ROBOT FIGHT MADNESS", 342, 132, 23, Color("bccbdd"))
	panel(Rect2(56, 154, 572, 2), LINE, 1)
	if showing_result:
		_draw_showcase(match_node.result_snapshot)
	elif shot >= 0:
		_draw_profile(match_node.bots[shot])

func _draw_profile(bot) -> void:
	var spec: Dictionary = bot.tune
	var accent: Color = bot.team_color
	_at_center("FIGHTER  %02d / 02" % (shot + 1), 342, 212, 23, accent)
	_at_center(String(spec.name).to_upper(), 342, 279, 66, white)
	_at_center(spec.weapon_name, 342, 320, 30, Color("d2e0ec"))
	panel(Rect2(56, 815, 572, 128), INK, 18)
	var labels := ["HEALTH", "SPEED", "ATTACK"]
	var values := [spec.max_hp, spec.speed_rating, spec.base_attack]
	for i in range(labels.size()):
		var alpha := reveal(shot_time, 0.5 + 0.5 * i)
		if alpha <= 0.0:
			continue
		var x := 152.0 + i * 190.0
		var offset := 13.0 * (1.0 - alpha)
		panel(Rect2(x - 36, 835 + offset, 72, 3), Color(accent, alpha), 1)
		_at_center(labels[i], x, 873 + offset, 22, Color(Color("bfd0dd"), alpha))
		_at_center(str(int(values[i])), x, 922 + offset, 48, Color(white, alpha))
	var alpha := reveal(shot_time, 2.0)
	if alpha > 0.0:
		var offset := 13.0 * (1.0 - alpha)
		for i in range(spec.intro_lines.size()):
			_at_center(spec.intro_lines[i], 342, 986 + offset + i * 35.0, 30, Color(white, alpha))

func _draw_showcase(snapshot: Dictionary) -> void:
	var draw_match: bool = snapshot.winner_index < 0
	var winner: Dictionary = {} if draw_match else snapshot.robots[snapshot.winner_index]
	var ratios: Array[float] = [snapshot.robots[0].ratio, snapshot.robots[1].ratio]
	var percentages := result_percentages(ratios, draw_match)
	if snapshot.reason == "knockout":
		_at_center("DOUBLE KNOCKOUT" if draw_match else "KNOCKOUT", 342, 213, 23, Color("bfcedc"))
	else:
		_at_center("TIME UP", 342, 213, 23, Color("bfcedc"))
	_at_center("DRAW" if draw_match else "%s WINS" % winner.name.to_upper(), 342, 278, 55, white if draw_match else winner.color)
	if snapshot.reason != "knockout":
		_at_center("EQUAL HEALTH REMAINING (%)" if draw_match else "ON HEALTH REMAINING (%)", 342, 322, 24, Color("c7d4e2"))
	if draw_match:
		for i in range(2):
			_draw_draw_card(snapshot.robots[i], percentages[i], 52.0 + i * 296.0)
	else:
		panel(Rect2(56, 812, 572, 191), INK, 18)
		var index: int = snapshot.winner_index
		var health := "%d / %d HP · %s" % [ceili(winner.hp), int(winner.max_hp), percentages[index]]
		_condition_line("Health", health, winner.color, 861)
		_condition_line("Weapon", winner.weapon, white, 916)
		_condition_line("Drive", winner.drive, white, 971)
	_at_center("Who should fight next?", 342, 1052, 25, Color("c7d4e2"))

func _condition_line(label: String, value: String, color: Color, y: float) -> void:
	text_at(label, Vector2(81, y), 27, Color("b9c9d9"))
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 27).x
	text_at(value, Vector2(602 - width, y), 27, color)

func _draw_draw_card(state: Dictionary, percent: String, left: float) -> void:
	var x := left + 141.0
	panel(Rect2(left, 786, 282, 218), INK, 16)
	_at_center(state.name.to_upper(), x, 823, 26, state.color)
	_at_center("%d / %d HP · %s" % [ceili(state.hp), int(state.max_hp), percent], x, 863, 22, white)
	_at_center("WEAPON", x, 897, 17, Color("b9c9d9"))
	_at_center(state.weapon, x, 925, 23, white)
	_at_center("DRIVE", x, 957, 17, Color("b9c9d9"))
	_at_center(state.drive, x, 986, 20, white)
