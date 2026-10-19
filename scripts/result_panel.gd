class_name ResultPanel
extends CanvasLayer

# Set by the level script before the panel is added
var won := false
var reason := "" # "win", "died" or "ammo"
var score := 0
var max_score := 10
var damage := 0.0 # share of the boss's health removed, 0 to 1
var next_scene := "res://scenes/titlescreen.tscn"
var font: Font

# Colors picked to match the how-to-play art
@export var panel_color := Color("fcc6fb")
@export var border_color := Color("c35bc8")
@export var title_color := Color("e0489b")
@export var text_color := Color("8a2f8f")
@export var accent_color := Color("ffd9a8")

var _root: Control
var _dim: ColorRect
var _score_label: Label
var _damage_label: Label
var _damage_bar: ProgressBar
var _shown_score := -1
var _score_tween: Tween
var _input_ready := false
var _leaving := false


func _ready() -> void:
	layer = 20 # above the HUD and the intro

	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.0, 0.0, 0.6)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	center.add_child(_build_panel())

	_pop_in()
	_play_reveal()
	# Ignore input briefly, so a held or mashed Space doesn't skip the popup
	get_tree().create_timer(0.7).timeout.connect(_unlock_input)


func _unlock_input() -> void:
	_input_ready = true


func _unhandled_input(event: InputEvent) -> void:
	if not _input_ready or _leaving:
		return
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_leave()


# --- Layout ---

func _build_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = panel_color
	style.border_color = border_color
	style.set_border_width_all(10)
	style.set_corner_radius_all(40)
	style.set_content_margin_all(40)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 16
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(560.0, 0.0)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	col.add_child(_label(_title_text(), 46, title_color, accent_color))
	col.add_child(_label(_subtitle_text(), 18, text_color))

	# Score sits in a plain holder so it can pop in size without the layout fighting it
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0.0, 110.0)
	_score_label = _label("+0", 84, accent_color, title_color)
	_score_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_score_label.resized.connect(func(): _score_label.pivot_offset = _score_label.size * 0.5)
	holder.add_child(_score_label)
	col.add_child(holder)
	col.add_child(_label("of %d pts" % max_score, 18, text_color))

	# Boss damage
	_damage_label = _label("Boss damage 0%", 18, text_color)
	col.add_child(_damage_label)
	_damage_bar = ProgressBar.new()
	_damage_bar.show_percentage = false
	_damage_bar.step = 0.0
	_damage_bar.custom_minimum_size = Vector2(0.0, 20.0)
	_damage_bar.add_theme_stylebox_override("background", _box(Color(1.0, 1.0, 1.0, 0.5), 10))
	_damage_bar.add_theme_stylebox_override("fill", _box(title_color, 10))
	col.add_child(_damage_bar)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 8.0)
	col.add_child(spacer)

	var hint := _label("> PRESS SPACE TO CONTINUE <", 18, title_color, accent_color)
	col.add_child(hint)
	var pulse := hint.create_tween().set_loops()
	pulse.tween_property(hint, "modulate:a", 0.4, 0.7)
	pulse.tween_property(hint, "modulate:a", 1.0, 0.7)

	return panel


func _title_text() -> String:
	match reason:
		"died":
			return "KNOCKED OUT!"
		"ammo":
			return "OUT OF AMMO!"
	return "BOSS DEFEATED!" if won else "GAME OVER"


func _subtitle_text() -> String:
	match reason:
		"died":
			return "The boss got you this time."
		"ammo":
			return "No notes left to fire."
	return "Full reward for this level!" if won else ""


func _label(text: String, size: int, color: Color, outline: Color = Color(0.0, 0.0, 0.0, 0.0)) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline.a > 0.0:
		l.add_theme_color_override("font_outline_color", outline)
		l.add_theme_constant_override("outline_size", maxi(4, int(size / 8.0)))
	if font:
		l.add_theme_font_override("font", font)
	return l


func _box(color: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	return sb


# --- Animation ---

func _pop_in() -> void:
	_root.pivot_offset = get_viewport().get_visible_rect().size * 0.5
	_root.scale = Vector2(0.75, 0.75)
	_root.modulate.a = 0.0
	_dim.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(_root, "scale", Vector2.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_root, "modulate:a", 1.0, 0.2)
	tw.tween_property(_dim, "modulate:a", 1.0, 0.25)


# Damage bar fills first, then the score counts up to its value
func _play_reveal() -> void:
	var tw := create_tween()
	tw.tween_interval(0.4)
	tw.tween_method(_set_damage_shown, 0.0, damage, 0.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.15)
	tw.tween_method(_set_score_shown, 0.0, float(score), clampf(0.12 * score, 0.3, 1.5))
	tw.tween_callback(_on_score_landed)


func _set_damage_shown(v: float) -> void:
	_damage_bar.value = v * 100.0
	_damage_label.text = "Boss damage %d%%" % roundi(v * 100.0)


func _set_score_shown(v: float) -> void:
	var n := floori(v + 0.001)
	if n == _shown_score:
		return
	_shown_score = n
	_score_label.text = "+%d" % n
	_pop_score(1.18)


func _on_score_landed() -> void:
	_score_label.text = "+%d" % score
	_pop_score(1.35)
	if won:
		_confetti()


func _pop_score(size: float) -> void:
	if _score_tween and _score_tween.is_valid():
		_score_tween.kill()
	_score_label.scale = Vector2.ONE * size
	_score_tween = create_tween()
	_score_tween.tween_property(_score_label, "scale", Vector2.ONE, 0.3) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _confetti() -> void:
	var vp := get_viewport().get_visible_rect().size
	var p := CPUParticles2D.new()
	p.position = Vector2(vp.x * 0.5, -20.0)
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = 90
	p.lifetime = 2.2
	p.direction = Vector2.DOWN
	p.spread = 70.0
	p.initial_velocity_min = 250.0
	p.initial_velocity_max = 650.0
	p.gravity = Vector2(0.0, 500.0)
	p.damping_min = 40.0
	p.damping_max = 80.0
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 5.0
	p.scale_amount_max = 10.0
	var g := Gradient.new()
	g.set_color(0, title_color)
	g.set_color(1, accent_color)
	g.add_point(0.5, border_color)
	p.color_initial_ramp = g
	add_child(p)
	p.emitting = true


func _leave() -> void:
	_leaving = true
	var tw := create_tween().set_parallel()
	tw.tween_property(_root, "modulate:a", 0.0, 0.2)
	tw.tween_property(_dim, "modulate:a", 1.0, 0.2)
	tw.chain().tween_callback(_change_scene)


func _change_scene() -> void:
	get_tree().change_scene_to_file(next_scene)
