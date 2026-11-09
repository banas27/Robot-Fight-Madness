extends Control
## Resolution-independent broadcast overlay, authored at 720 x 1280.
var match_node: Node3D
var combat_style := false
var panel_styles: Dictionary = {}
var font: Font = ThemeDB.fallback_font
var white := Color("edf4f6")
var muted := Color("8c9eaf")
var cyan := Color("39d8e7")
var orange := Color("ff9045")
var hp_echo := [1.0, 1.0]

func _process(delta: float) -> void:
	if combat_style and is_instance_valid(match_node) and match_node.bots.size() == 2:
		for i in range(2):
			var ratio := _broadcast_hp(match_node, i) / float(match_node.bots[i].max_hp)
			hp_echo[i] = ratio if match_node.phase == "result" else move_toward(float(hp_echo[i]), ratio, delta * 0.35)
	queue_redraw()

func text_at(value: String, at: Vector2, size_px: int, color: Color) -> void:
	draw_string(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

func centered(value: String, y: float, size_px: int, color: Color) -> void:
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	text_at(value, Vector2((720.0 - width) / 2.0, y), size_px, color)

func panel(rect: Rect2, color: Color, radius: int = 14) -> void:
	var key := Vector2i(color.to_rgba32(), radius)
	var style: StyleBoxFlat = panel_styles.get(key)
	if style == null:
		style = StyleBoxFlat.new()
		style.bg_color = color
		style.set_corner_radius_all(radius)
		panel_styles[key] = style
	draw_style_box(style, rect)

func _draw() -> void:
	if not is_instance_valid(match_node) or match_node.bots.size() != 2:
		return
	draw_set_transform(Vector2.ZERO, 0.0, size / Vector2(720, 1280))
	var m = match_node
	if combat_style:
		_draw_broadcast(m)
		return
	panel(Rect2(28, 34, 664, 182), Color(0.035, 0.055, 0.08, 0.95), 20)
	draw_circle(Vector2(53, 63), 5, cyan)
	text_at("ROBOT FIGHT MADNESS", Vector2(68, 70), 20, white)
	text_at("RIPTIDE", Vector2(48, 119), 30, cyan)
	text_at("BULLDOZER", Vector2(418, 119), 30, orange)
	text_at("SPINNER", Vector2(48, 143), 14, muted)
	text_at("RAMMER", Vector2(418, 143), 14, muted)
	centered("VS", 126, 21, white)
	for i in range(2):
		var x: float = 48.0 if i == 0 else 418.0
		var color: Color = cyan if i == 0 else orange
		var ratio: float = clampf(m.bots[i].hp / float(m.cfg.health), 0.0, 1.0)
		panel(Rect2(x, 162, 254, 9), Color("263443"), 4)
		if ratio > 0.0:
			panel(Rect2(x, 162, 254 * ratio, 9), color, 4)
		text_at("%03d / %03d" % [ceili(m.bots[i].hp), int(m.cfg.health)], Vector2(x, 196), 15, white)
	panel(Rect2(279, 237, 162, 55), Color(0.035, 0.055, 0.08, 0.92), 16)
	var remaining: int = ceili(maxf(0.0, float(m.cfg.fight_seconds) - m.fight_elapsed))
	centered("00:%02d" % remaining, 275, 28, white)
	if m.phase == "intro":
		panel(Rect2(218, 533, 284, 154), Color(0.03, 0.05, 0.08, 0.88), 24)
		centered("CHOOSE YOUR BOT", 573, 17, muted)
		centered(str(maxi(1, ceili(float(m.cfg.intro_seconds) - m.elapsed))), 654, 68, white)
	elif m.phase == "result":
		var y := 505.0
		panel(Rect2(62, y, 596, 216), Color(0.025, 0.045, 0.065, 0.96), 24)
		centered(m.result_reason.to_upper(), y + 47, 18, muted)
		centered(m.winner_name, y + 108, 43, m.winner_color)
		centered("WINS" if m.winner_name != "DRAW" else "REMATCH?", y + 153, 23, white)
	else:
		if m.hit_banner_time > 0.0:
			panel(Rect2(210, 952, 300, 52), Color(0.03, 0.05, 0.08, 0.92), 12)
			centered(m.hit_banner, 986, 21, white)
	panel(Rect2(40, 1060, 640, 112), Color(0.035, 0.055, 0.08, 0.95), 20)
	text_at("THE PIT / 01", Vector2(64, 1097), 19, white)
	text_at("ORIGINAL ROBOT COMBAT SIMULATION", Vector2(64, 1127), 13, muted)
	text_at("MATCH %04d" % m.match_seed, Vector2(493, 1097), 16, muted)
	text_at("Who should fight next?", Vector2(64, 1152), 16, cyan)

func _draw_broadcast(m: Node3D) -> void:
	if m.phase != "fight":
		return
	panel(Rect2(46, 108, 592, 156), Color("101a23f7"), 20)
	_at_center("ROBOT FIGHT MADNESS", 342, 141, 19, muted)
	for i in range(2):
		var x := 66.0 if i == 0 else 407.0
		var color: Color = m.bots[i].team_color
		var robot_name: String = String(m.bots[i].tune.name).to_upper()
		var icon_pos := Vector2(x + 13, 178)
		var disabled: bool = m.bots[i].weapon_disabled
		_weapon_icon(icon_pos, m.bots[i].kind == "saw", muted.darkened(0.25) if disabled else color)
		if disabled:
			draw_line(icon_pos + Vector2(-11, -11), icon_pos + Vector2(11, 11), white, 2.7, true)
			draw_line(icon_pos + Vector2(-11, 11), icon_pos + Vector2(11, -11), white, 2.7, true)
		text_at(robot_name, Vector2(x + 35, 188), 29, color)
		var health := _broadcast_hp(m, i)
		var maximum: float = m.bots[i].max_hp
		var ratio := clampf(health / maximum, 0.0, 1.0)
		panel(Rect2(x, 205, 211, 14), Color("293644"), 6)
		if m.phase != "result" and hp_echo[i] > ratio:
			panel(Rect2(x, 205, 211 * hp_echo[i], 14), color.lerp(white, 0.60), 6)
		if ratio > 0.0:
			panel(Rect2(x, 205, 211 * ratio, 14), color, 6)
		text_at("%d / %d" % [ceili(health), int(maximum)], Vector2(x, 244), 19, white)
	var remaining: int = ceili(maxf(0.0, float(m.cfg.fight_seconds) - m.fight_elapsed))
	panel(Rect2(292, 164, 100, 61), Color("24313d"), 13)
	_at_center("0:%02d" % remaining, 342, 203, 29, white)
	if not m.current_notice.is_empty():
		var notice: Dictionary = m.current_notice
		var color: Color = m.bots[0].team_color if notice.robot == String(m.bots[0].name) else m.bots[1].team_color
		panel(Rect2(105, 277, 474, 54), Color("101a23f7"), 13)
		draw_circle(Vector2(126, 304), 4.5, color)
		var notice_text: String = m.COMPONENT_NOTICES[notice.kind]
		text_at("%s  /  %s" % [notice.robot.to_upper(), notice_text], Vector2(141, 312), 21, white)

func _broadcast_hp(m: Node3D, i: int) -> float:
	return m.final_hp[i] if m.phase == "result" else m.bots[i].hp

func result_percentages(ratios: Array[float], draw_match: bool) -> Array[String]:
	var digits := 1
	if draw_match:
		var middle := (ratios[0] + ratios[1]) * 50.0
		var value := "%.1f%%" % middle
		return [value, value]
	while digits < 5:
		var units := 100.0 * pow(10.0, digits)
		if roundi(ratios[0] * units) != roundi(ratios[1] * units):
			break
		digits += 1
	var format := "%%.%df%%%%" % digits
	return [format % (ratios[0] * 100.0), format % (ratios[1] * 100.0)]

func _at_center(value: String, x: float, y: float, size_px: int, color: Color) -> void:
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	text_at(value, Vector2(x - width * 0.5, y), size_px, color)

func _weapon_icon(at: Vector2, saw: bool, color: Color) -> void:
	if saw:
		draw_arc(at, 8.5, 0, TAU, 24, color, 2.0, true)
		draw_circle(at, 2.0, color, true, -1.0, true)
		for i in range(8):
			var tip := Vector2.from_angle(TAU * i / 8.0)
			draw_line(at + tip * 8.0, at + (tip + tip.orthogonal() * 0.16) * 12.0, color, 2.3, true)
	else:
		panel(Rect2(at.x - 11, at.y - 6, 22, 12), color, 3)
		for x in [-7.0, 0.0, 7.0]:
			draw_colored_polygon(PackedVector2Array([at + Vector2(x - 3, -4), at + Vector2(x + 3, -4), at + Vector2(x + 2, -11)]), color)
			draw_colored_polygon(PackedVector2Array([at + Vector2(x - 3, 4), at + Vector2(x + 3, 4), at + Vector2(x - 2, 11)]), color)
