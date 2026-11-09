extends Node3D
const Shapes = preload("res://scripts/shapes.gd")
@export var visual_script: Script
@export var title: String
@export var weapon_speed := 0.0
var visual: Node3D
var camera: Camera3D
var angle := 0.0
var paused := false
var screenshot_path := ""
var frames := 0
var quit_after_capture := false

func _ready() -> void:
	get_window().content_scale_size = Vector2i(1200, 900)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			screenshot_path = arg.trim_prefix("--screenshot=")
		if arg == "--capture-and-quit":
			quit_after_capture = true
	visual = visual_script.new()
	add_child(visual)
	visual.position.y = 0.4
	var floor_material := Shapes.material(Color("182630"), 0.0)
	floor_material.roughness = 0.85
	Shapes.box(self, Vector3(200, 0.05, 200), Vector3(0, -0.03, 0), floor_material)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("101b24")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("bfdbed")
	environment.environment.ambient_light_energy = 0.4
	add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55, -35, 0)
	key.light_energy = 0.8
	key.shadow_enabled = true
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-30, 145, 0)
	rim.light_color = Color("ffe0b3")
	rim.light_energy = 0.35
	add_child(rim)
	camera = Camera3D.new()
	add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.1
	camera.position = Vector3(3.2, 3.1, -4.0)
	camera.look_at(Vector3(0, 0.35, -0.25))
	camera.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	var heading := Label.new()
	heading.text = title
	heading.position = Vector2(40, 28)
	heading.add_theme_font_size_override("font_size", 23)
	layer.add_child(heading)
	var footer := Label.new()
	footer.text = "GLB IN GODOT  |  1 unit = 1 meter  |  Powder coat / graphite / steel\nSpace: motion on/off   •   Left / Right: orbit   •   1: hero   2: top   3: front   •   Esc: close"
	footer.position = Vector2(40, 812)
	footer.add_theme_font_size_override("font_size", 17)
	footer.modulate = Color("b2c7d2")
	layer.add_child(footer)

func _process(delta: float) -> void:
	frames += 1
	# Captures use a fixed pose; interactive mode demonstrates pivot motion slowly.
	if not paused and screenshot_path == "":
		angle += delta * weapon_speed
		visual.update_visual(delta, angle, 0.3, 0.0)
	if Input.is_physical_key_pressed(KEY_LEFT):
		visual.rotate_y(delta)
	if Input.is_physical_key_pressed(KEY_RIGHT):
		visual.rotate_y(-delta)
	if frames == 20 and screenshot_path != "" and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var error := get_viewport().get_texture().get_image().save_png(screenshot_path)
		print("RFS_REVIEW_CAPTURE ", screenshot_path, " error=", error)
		if quit_after_capture:
			get_tree().quit(error)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE: get_tree().quit()
			KEY_SPACE: paused = not paused
			KEY_1: camera.position = Vector3(3.2, 3.1, -4.0)
			KEY_2: camera.position = Vector3(0, 6, -0.249)
			KEY_3: camera.position = Vector3(0, 1.2, -5)
		camera.look_at(Vector3(0, 0.35, -0.25))
