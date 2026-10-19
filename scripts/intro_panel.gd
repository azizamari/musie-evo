class_name IntroPanel
extends CanvasLayer

## Emitted after the panel closes. Main starts the round on this.
signal started

@export var title := "HOW TO PLAY"
@export var move_title := "Move"
@export var move_text := "Swim up and down."
# Arrow keys to draw: -1 = up, 1 = down
@export var move_arrows: Array = [-1, 1]
# Set by Main from game_duration
@export var boss_time: float = 30.0
# Set by Main, icons and values are read from these scenes
@export var projectile_scenes: Array[PackedScene] = []
# Also show the algue with a "Stun!" label
@export var show_hazards := true
@export var icon_size := 56.0
# On = crisp pixel-art icons. Off = smooth, better for painted art
@export var pixel_art := false

@export_group("Image mode")
# Full-screen artwork for the panel (e.g. 1920x1080 with transparent edges).
# Empty = the panel is built in code instead
@export var panel_texture: Texture2D
# Centers of the +1, +2, +3 circles, in the image's own pixels
@export var pickup_slots: Array[Vector2] = [Vector2(712, 685), Vector2(876, 688), Vector2(1041, 686)]
# Where the algue goes (above "STUN!"), in the image's own pixels
@export var hazard_slot := Vector2(1278, 686)
# Icon size in the image's pixels (the circles are 130 wide)
@export var slot_icon_size: float = 100.0
# Gentle up and down float of the icons, in the image's pixels (0 = off)
@export var icon_bob: float = 6.0

@export_group("Colors")
@export var panel_color := Color(0.04, 0.09, 0.16, 0.94)
@export var border_color := Color(0.45, 0.85, 1.0)
@export var text_color := Color(0.92, 0.97, 1.0)
@export var muted_color := Color(0.62, 0.74, 0.86)
@export var tier_colors: Array[Color] = [Color.WHITE, Color(0.45, 0.9, 1.0), Color(1.0, 0.82, 0.3)]
@export var hazard_color := Color(1.0, 0.45, 0.45)

var _root: Control
var _dim: ColorRect
var _closing := false
var _icons := [] # image mode: icons that float
var _k := 1.0 # image mode: image pixels -> screen pixels
var _t := 0.0


func _ready() -> void:
	layer = 10 # above the HUD

	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.0, 0.0, 0.55)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if pixel_art:
		_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_root)

	if panel_texture:
		_build_image_panel()
	else:
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(center)
		center.add_child(_build_panel())

	_pop_in()


func _process(delta: float) -> void:
	if _icons.is_empty() or icon_bob <= 0.0:
		return
	_t += delta
	for e in _icons:
		var icon_rect: Control = e.node
		icon_rect.position.y = e.y + sin(_t * 2.2 + e.phase) * icon_bob * _k


func _unhandled_input(event: InputEvent) -> void:
	# ui_accept = Space or Enter by default
	if not _closing and event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_dismiss()


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


func _dismiss() -> void:
	if _closing:
		return
	_closing = true

	var tw := create_tween().set_parallel()
	tw.tween_property(_root, "scale", Vector2(0.85, 0.85), 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(_root, "modulate:a", 0.0, 0.18)
	tw.tween_property(_dim, "modulate:a", 0.0, 0.25)
	tw.chain().tween_callback(func():
		started.emit()
		queue_free())


# --- Image mode ---

func _build_image_panel() -> void:
	# Fit the artwork to the screen, keeping its shape
	var vp := get_viewport().get_visible_rect().size
	var img := panel_texture.get_size()
	_k = minf(vp.x / img.x, vp.y / img.y)
	var drawn := img * _k
	var top_left := (vp - drawn) * 0.5

	var art := TextureRect.new()
	art.texture = panel_texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.position = top_left
	art.size = drawn
	_root.add_child(art)

	# Drop the projectile sprites into the drawn circles
	var found := _read_projectiles()
	var pickups: Array = found.pickups
	var hazards: Array = found.hazards
	for i in mini(pickups.size(), pickup_slots.size()):
		_place_icon(pickups[i].icon, top_left + pickup_slots[i] * _k, i)
	if show_hazards and not hazards.is_empty():
		_place_icon(hazards[0].icon, top_left + hazard_slot * _k, pickups.size())


func _place_icon(icon: Dictionary, center: Vector2, index: int) -> void:
	var icon_rect := TextureRect.new()
	icon_rect.texture = icon.get("texture")
	icon_rect.modulate = icon.get("color", Color.WHITE)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_rect.size = Vector2.ONE * slot_icon_size * _k
	icon_rect.position = center - icon_rect.size * 0.5
	_root.add_child(icon_rect)
	_icons.append({"node": icon_rect, "y": icon_rect.position.y, "phase": index * 0.9})


# Value, type and sprite of each projectile scene, pickups sorted 1, 2, 3
func _read_projectiles() -> Dictionary:
	var pickups := []
	var hazards := []
	for scene in projectile_scenes:
		if scene == null:
			continue
		var temp = scene.instantiate()
		var entry := {"value": temp.value, "icon": _icon_of(temp)}
		if temp.is_hazard:
			hazards.append(entry)
		else:
			pickups.append(entry)
		temp.free()
	pickups.sort_custom(func(a, b): return a.value < b.value)
	return {"pickups": pickups, "hazards": hazards}


# --- Layout (code-built panel) ---

func _build_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = panel_color
	style.border_color = border_color
	style.set_border_width_all(3)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(28)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_size = 12
	panel.add_theme_stylebox_override("panel", style)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	panel.add_child(col)

	var heading := _label(title, 30, text_color)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(heading)

	# 1. Movement
	var move_keys := HBoxContainer.new()
	move_keys.add_theme_constant_override("separation", 8)
	for a in move_arrows:
		move_keys.add_child(_key("", int(a)))
	col.add_child(_row(move_keys, move_title, move_text))

	# 2. Attack
	col.add_child(_row(_key("SPACE", 0, 130.0), "Attack",
		"The boss shows up after %d seconds. Your points become ammo." % roundi(boss_time)))

	# 3. Points
	col.add_child(_points_section())

	# Start
	var start := Button.new()
	start.text = "START"
	start.focus_mode = Control.FOCUS_NONE
	start.custom_minimum_size = Vector2(180.0, 48.0)
	start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start.add_theme_font_size_override("font_size", 22)
	_style_button(start)
	start.pressed.connect(_dismiss)
	col.add_child(start)

	var hint := _label("or press SPACE", 14, muted_color)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
	var pulse := hint.create_tween().set_loops()
	pulse.tween_property(hint, "modulate:a", 0.35, 0.7)
	pulse.tween_property(hint, "modulate:a", 1.0, 0.7)

	return panel


func _row(keys: Control, heading: String, desc: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)

	var key_box := CenterContainer.new()
	key_box.custom_minimum_size = Vector2(140.0, 0.0)
	key_box.add_child(keys)
	row.add_child(key_box)

	var text_col := VBoxContainer.new()
	text_col.add_theme_constant_override("separation", 2)
	text_col.add_child(_label(heading, 20, text_color))
	var d := _label(desc, 15, muted_color)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(300.0, 0.0)
	text_col.add_child(d)
	row.add_child(text_col)

	return row


func _points_section() -> VBoxContainer:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 10)

	var heading := _label("Catch these for points", 20, text_color)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	section.add_child(heading)

	var items := HBoxContainer.new()
	items.alignment = BoxContainer.ALIGNMENT_CENTER
	items.add_theme_constant_override("separation", 28)
	section.add_child(items)

	var found := _read_projectiles()
	var pickups: Array = found.pickups
	var hazards: Array = found.hazards

	for i in pickups.size():
		var c: Color = tier_colors[mini(i, tier_colors.size() - 1)] if not tier_colors.is_empty() else text_color
		items.add_child(_item(pickups[i].icon, "+%d" % pickups[i].value, c))

	if show_hazards and not hazards.is_empty():
		items.add_child(VSeparator.new())
		for e in hazards:
			items.add_child(_item(e.icon, "Stun!", hazard_color))

	return section


func _item(icon: Dictionary, text: String, color: Color) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER

	var icon_rect := TextureRect.new()
	icon_rect.texture = icon.get("texture")
	icon_rect.modulate = icon.get("color", Color.WHITE)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.custom_minimum_size = Vector2(icon_size, icon_size)
	v.add_child(icon_rect)

	var l := _label(text, 20, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)

	return v


# --- Helpers ---

# First frame of the scene's sprite, plus its tint
func _icon_of(node: Node) -> Dictionary:
	var root_tint := Color.WHITE
	if node is CanvasItem:
		root_tint = (node as CanvasItem).modulate

	for c in node.get_children():
		if c is Sprite2D and c.texture:
			var s := c as Sprite2D
			var tex: Texture2D = s.texture
			if s.region_enabled:
				var at := AtlasTexture.new()
				at.atlas = s.texture
				at.region = s.region_rect
				tex = at
			elif s.hframes > 1 or s.vframes > 1:
				var frame_size := s.texture.get_size() / Vector2(s.hframes, s.vframes)
				var at := AtlasTexture.new()
				at.atlas = s.texture
				at.region = Rect2(Vector2(s.frame_coords) * frame_size, frame_size)
				tex = at
			return {"texture": tex, "color": s.modulate * root_tint}

		if c is AnimatedSprite2D and c.sprite_frames:
			var a := c as AnimatedSprite2D
			if a.sprite_frames.has_animation(a.animation) and a.sprite_frames.get_frame_count(a.animation) > 0:
				return {"texture": a.sprite_frames.get_frame_texture(a.animation, 0), "color": a.modulate * root_tint}

	return {}


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _key(text: String, arrow: int, width: float = 46.0) -> Control:
	var k := KeyCap.new()
	k.text = text
	k.arrow = arrow
	k.custom_minimum_size = Vector2(width, 46.0)
	return k


func _style_button(b: Button) -> void:
	var states := {
		"normal": Color(0.1, 0.42, 0.58),
		"hover": Color(0.16, 0.55, 0.74),
		"pressed": Color(0.07, 0.3, 0.42),
	}
	for state in states:
		var sb := StyleBoxFlat.new()
		sb.bg_color = states[state]
		sb.border_color = border_color
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(10)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", text_color)
	b.add_theme_color_override("font_hover_color", Color.WHITE)


# Keyboard key drawn in code: an arrow (-1 up, 1 down) or a text label
class KeyCap extends Control:
	var text := ""
	var arrow := 0
	var face := Color(0.92, 0.95, 1.0)
	var edge := Color(0.5, 0.58, 0.72)
	var ink := Color(0.08, 0.12, 0.2)
	const DEPTH := 5.0

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)

		var base := StyleBoxFlat.new()
		base.bg_color = edge
		base.set_corner_radius_all(8)
		draw_style_box(base, r)

		var top := StyleBoxFlat.new()
		top.bg_color = face
		top.set_corner_radius_all(8)
		draw_style_box(top, Rect2(r.position, r.size - Vector2(0.0, DEPTH)))

		var c := Vector2(size.x * 0.5, (size.y - DEPTH) * 0.5)
		if arrow != 0:
			var h := size.y * 0.2
			var pts := PackedVector2Array([
				c + Vector2(0.0, h * arrow),
				c + Vector2(-h, -h * 0.8 * arrow),
				c + Vector2(h, -h * 0.8 * arrow),
			])
			draw_colored_polygon(pts, ink)
		else:
			var font := get_theme_default_font()
			var fs := 18
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var baseline := c.y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
			draw_string(font, Vector2(c.x - w * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
