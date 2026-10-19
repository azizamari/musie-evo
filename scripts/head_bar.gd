class_name HeadBar
extends Node2D

# Health bar that floats above a character's head. The level script creates one
# for the player and one for the boss, no scene setup needed.

@export var bar_size := Vector2(90.0, 12.0)
# Space between the top of the sprite and the bar
@export var gap: float = 12.0
@export var fill_color := Color(1.0, 0.45, 0.75)
# The chunk you just lost, shown for a moment before it drains away
@export var ghost_color := Color(1.0, 0.87, 0.66)
@export var back_color := Color(0.16, 0.05, 0.22, 0.9)
@export var border_color := Color(1.0, 0.87, 0.66)
@export var border_width: float = 2.0

var target: Node2D
var _anchor := Vector2(0.0, -40.0) # top-center of the visible sprite, in the target's space
var _shown := 0.0 # fill being drawn, eases toward _goal
var _goal := 0.0 # real health ratio
var _ghost := 0.0
var _ghost_wait := 0.0
var _shake := 0.0
var _sb_border := StyleBoxFlat.new()
var _sb_back := StyleBoxFlat.new()
var _sb_ghost := StyleBoxFlat.new()
var _sb_fill := StyleBoxFlat.new()


# Attach the bar to a character. It becomes a child, so it disappears with it
func setup(t: Node2D, width: float, fill: Color) -> void:
	target = t
	bar_size.x = width
	fill_color = fill
	top_level = true # ignore the character's scale, draw above the world
	z_index = 10
	_anchor = _measure_head(t)

	var radius := int(bar_size.y * 0.5)
	for pair in [[_sb_border, border_color, radius + int(border_width)],
			[_sb_back, back_color, radius], [_sb_ghost, ghost_color, radius], [_sb_fill, fill_color, radius]]:
		var sb: StyleBoxFlat = pair[0]
		sb.bg_color = pair[1]
		sb.set_corner_radius_all(pair[2])

	t.add_child(self)
	_follow()


func set_health(current: int, max_value: int) -> void:
	var r := clampf(float(current) / maxf(float(max_value), 1.0), 0.0, 1.0)
	if r < _goal:
		# Hit: keep the lost chunk visible briefly, and give the bar a jolt
		_ghost = maxf(_ghost, _shown)
		_ghost_wait = 0.35
		_shake = 1.0
	_goal = r


func _process(delta: float) -> void:
	if not is_instance_valid(target):
		queue_free()
		return

	_shown = lerpf(_shown, _goal, 1.0 - exp(-14.0 * delta))
	if _ghost_wait > 0.0:
		_ghost_wait -= delta
	else:
		_ghost = lerpf(_ghost, _shown, 1.0 - exp(-5.0 * delta))
	_ghost = maxf(_ghost, _shown)
	_shake = maxf(_shake - delta * 4.0, 0.0)

	_follow()
	queue_redraw()


func _follow() -> void:
	var head := target.global_transform * _anchor
	var jitter := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 3.0 * _shake
	global_position = head + Vector2(0.0, -gap - bar_size.y * 0.5) + jitter
	# Stay on screen when the character is at the very top
	global_position.y = maxf(global_position.y, bar_size.y + 4.0)
	scale = Vector2.ONE * (1.0 + 0.15 * _shake)


func _draw() -> void:
	var r := Rect2(-bar_size * 0.5, bar_size)
	draw_style_box(_sb_border, r.grow(border_width))
	draw_style_box(_sb_back, r)
	if _ghost > _shown + 0.002:
		draw_style_box(_sb_ghost, Rect2(r.position, Vector2(bar_size.x * _ghost, bar_size.y)))
	if _shown > 0.002:
		var fill := Rect2(r.position, Vector2(bar_size.x * _shown, bar_size.y))
		draw_style_box(_sb_fill, fill)
		# Thin shine along the top
		if fill.size.x > 6.0:
			draw_rect(Rect2(fill.position + Vector2(3.0, 2.0), Vector2(fill.size.x - 6.0, bar_size.y * 0.22)),
				Color(1.0, 1.0, 1.0, 0.3))


# Top-center of the visible pixels of the character's sprite (ignores transparent padding)
static func _measure_head(t: Node2D) -> Vector2:
	var spr: Node2D = null
	var tex: Texture2D = null
	for c in t.get_children():
		if c is AnimatedSprite2D:
			var a := c as AnimatedSprite2D
			if a.sprite_frames and a.sprite_frames.has_animation(a.animation) \
					and a.sprite_frames.get_frame_count(a.animation) > 0:
				spr = a
				tex = a.sprite_frames.get_frame_texture(a.animation, 0)
				break
		elif c is Sprite2D and (c as Sprite2D).texture:
			spr = c as Sprite2D
			tex = (c as Sprite2D).texture
			break
	if spr == null or tex == null:
		return Vector2(0.0, -40.0)

	var size := tex.get_size()
	var trim := true
	if spr is Sprite2D:
		var s2 := spr as Sprite2D
		size /= Vector2(s2.hframes, s2.vframes)
		trim = s2.hframes == 1 and s2.vframes == 1 and not s2.region_enabled

	var used := Rect2(Vector2.ZERO, size)
	var img := tex.get_image()
	if trim and img:
		if img.is_compressed():
			img.decompress()
		var ur := img.get_used_rect()
		if ur.has_area():
			used = Rect2(ur)

	var centered: bool = spr.centered
	var offset: Vector2 = spr.offset
	var origin := offset - (size * 0.5 if centered else Vector2.ZERO)

	# Run the corners through the sprite's transform, so rotated sprites work too
	var xf := spr.transform
	var min_y := INF
	var min_x := INF
	var max_x := -INF
	for corner in [used.position, Vector2(used.end.x, used.position.y), used.end, Vector2(used.position.x, used.end.y)]:
		var p: Vector2 = xf * (corner + origin)
		min_y = minf(min_y, p.y)
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
	return Vector2((min_x + max_x) * 0.5, min_y)
