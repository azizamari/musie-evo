extends Area2D

# Same signals and API as the fish player, so the level script works with both
signal collected(value: int)
signal stunned(duration: float)
signal fire_requested(spawn_pos: Vector2)
signal health_changed(current: int, max_health: int)
signal damaged(amount: int)
signal died

@export_group("Jump")
# Height of the first jump in pixels
@export var jump_height: float = 140.0
# Seconds to reach the top of the first jump (lower = snappier)
@export var time_to_apex: float = 0.38
# Height of the second jump, measured from where you press it
@export var double_jump_height: float = 110.0
@export var air_jumps: int = 1
# Gravity multiplier while falling (higher = snappier landings, less floaty)
@export var fall_gravity_multiplier: float = 1.7
# Let go of jump early and upward speed is multiplied by this (short hops)
@export var jump_cut: float = 0.45
# Lighter gravity near the top while jump is held, gives a small hang time
@export var apex_gravity_multiplier: float = 0.5
# Vertical speed under which you count as "at the top"
@export var apex_threshold: float = 70.0
@export var max_fall_speed: float = 1100.0
# Press jump this many seconds before landing and it still fires on touchdown
@export var jump_buffer: float = 0.12
# Seconds after takeoff before the double jump can fire. Earlier presses are queued, not lost
@export var double_jump_delay: float = 0.12
# Shortest possible hop: an earlier release is applied once this time has passed
@export var min_jump_time: float = 0.08
# Off = the double jump always goes full height, even on a quick tap
@export var double_jump_cuttable := false
# Input action used for jumping (Up arrow by default)
@export var jump_action := "move_up"

@export_group("Combat")
@export var max_health: int = 5
# Seconds between shots while holding Space
@export var fire_interval: float = 0.18
# Where bullets spawn relative to the hedgehog (in front of it)
@export var muzzle_offset := Vector2(40.0, 0.0)
# Blink time after a boss hit where bullets can't hurt you
@export var hit_invuln: float = 1.0

@export_group("Stun")
# Algue pulls you down if you're in the air
@export var stun_knockdown: float = 350.0
# Blinking grace period after a stun where algue passes through
@export var invuln_after_stun: float = 0.6
@export var dizzy_wobble_deg: float = 20.0

@export_group("Juice")
# Squash and stretch strength added per point collected
@export var punch_per_point: float = 0.12
@export var punch_duration: float = 0.45
@export var recoil_punch: float = 0.08
# Tall and thin on takeoff
@export var takeoff_stretch: float = 0.22
# Max flat and wide on a hard landing
@export var landing_squash: float = 0.35
@export var spin_on_double_jump := true
@export var spin_duration: float = 0.35
@export var dust_enabled := true
@export var dust_color := Color(0.85, 0.8, 0.7, 0.85)
@export var shadow_enabled := true
# Hide the shadow while standing, fade it in as you leave the ground
@export var shadow_only_in_air := true

@export_group("Ground")
# Platform to stand on. Empty = uses a sibling node named "Platform" if there is one
@export var platform: Control

@export_group("Sprite")
# Animation names, any that don't exist in your SpriteFrames are skipped
@export var ground_anim := "run"
@export var rise_anim := "jump"
# Same as rise_anim = stay in the jump animation for the whole air time
@export var fall_anim := "jump"
# Distance from the origin to the feet. -1 = measure the visible pixels of the sprite
@export var feet_offset: float = -1.0

var velocity := Vector2.ZERO
var health := 0
var can_shoot := false # Main turns this on during the boss phase
var _gravity := 0.0
var _jump_velocity := 0.0
var _double_jump_velocity := 0.0
var _ground_y := 0.0
var _on_ground := true
var _air_jumps_left := 0
var _buffer_left := 0.0
var _air_time := 0.0
var _double_queued := false
var _cut_pending := false
var _cuttable := true
var _fire_cd := 0.0
var _stun_left := 0.0
var _invuln_left := 0.0
var _t := 0.0
var _base_scale := Vector2.ONE
var _base_rot := 0.0
var _scale_tween: Tween
var _flash_tween: Tween
var _spin_tween: Tween
var _shadow: Shadow
var _head_offset := 32.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	_base_scale = sprite.scale
	_base_rot = sprite.rotation
	health = max_health
	_air_jumps_left = air_jumps
	_recalc_jump()

	# Measure the visible part of the sprite (ignores transparent padding)
	var vis := _visible_rect()
	if feet_offset < 0.0:
		feet_offset = vis.end.y
	_head_offset = -vis.position.y

	# Snap onto the platform so the feet touch its top edge
	if platform == null and get_parent():
		var found := get_parent().get_node_or_null("Platform")
		if found is Control:
			platform = found as Control
	if platform:
		position.y += platform.global_position.y - (global_position.y + feet_offset * scale.y)
	_ground_y = position.y

	if shadow_enabled:
		_shadow = Shadow.new()
		_shadow.radius = vis.size.x * 0.4
		add_child(_shadow)
		move_child(_shadow, 0) # draw under the sprite

	area_entered.connect(_on_area_entered)
	_ensure_fire_action()
	_play(ground_anim)


# Jump defined by height and time, so tuning feels predictable
func _recalc_jump() -> void:
	var t := maxf(time_to_apex, 0.05)
	_gravity = 2.0 * jump_height / (t * t)
	_jump_velocity = -_gravity * t
	_double_jump_velocity = -sqrt(2.0 * _gravity * double_jump_height)


# --- Used by the level script ---

func reset_for_round() -> void:
	health = max_health
	can_shoot = false
	velocity = Vector2.ZERO
	position.y = _ground_y
	_on_ground = true
	_air_jumps_left = air_jumps
	_cut_pending = false
	_double_queued = false
	_buffer_left = 0.0
	_stun_left = 0.0
	_invuln_left = 0.0
	_kill_flash()
	sprite.modulate = Color.WHITE
	health_changed.emit(health, max_health)


# Heights the hedgehog can reach, so projectiles and the boss stay catchable
func get_spawn_band() -> Vector2:
	var reach := jump_height + double_jump_height
	return Vector2(_ground_y - reach * 0.95, _ground_y)


# Text for the "how to play" popup
func intro_move() -> Dictionary:
	return {
		"title": "Jump",
		"text": "Press again in the air to double jump. Tap for a short hop, hold for a high one.",
		"arrows": [-1],
	}


# --- Input and movement ---

func _process(delta: float) -> void:
	_t += delta
	if _stun_left > 0.0:
		_stun_left -= delta
	if _invuln_left > 0.0:
		_invuln_left -= delta
		if _invuln_left <= 0.0:
			sprite.modulate = Color.WHITE

	var can_control := _stun_left <= 0.0

	if not _on_ground:
		_air_time += delta

	# In the air with a jump left: queue the double jump. Otherwise buffer for landing
	_buffer_left -= delta
	if can_control and Input.is_action_just_pressed(jump_action):
		if not _on_ground and _air_jumps_left > 0:
			_double_queued = true
		else:
			_buffer_left = jump_buffer

	if can_control and _on_ground and _buffer_left > 0.0:
		_buffer_left = 0.0
		_jump(_jump_velocity, false)

	# Fires as soon as the first jump has had time to lift off, so fast taps still get both jumps
	if can_control and _double_queued and not _on_ground and _air_time >= double_jump_delay:
		_double_queued = false
		_jump(_double_jump_velocity, true)

	# Variable height: releasing early cuts the rise, but never below the minimum hop
	if _cuttable and Input.is_action_just_released(jump_action) and velocity.y < 0.0:
		_cut_pending = true
	if _cut_pending and _air_time >= min_jump_time:
		_cut_pending = false
		if velocity.y < 0.0:
			velocity.y *= jump_cut

	if not _on_ground:
		var g := _gravity
		var holding := can_control and Input.is_action_pressed(jump_action)
		if holding and absf(velocity.y) < apex_threshold:
			g *= apex_gravity_multiplier # hang at the top
		elif velocity.y > 0.0:
			g *= fall_gravity_multiplier # fall faster than you rise

		# Exact for constant gravity, so the arc is the same at any frame rate
		position.y += velocity.y * delta + 0.5 * g * delta * delta
		velocity.y = minf(velocity.y + g * delta, max_fall_speed)

		# Don't leave the top of the screen
		if position.y - _head_offset * scale.y < 0.0:
			position.y = _head_offset * scale.y
			velocity.y = maxf(velocity.y, 0.0)

		if position.y >= _ground_y:
			_land()

	# Hold Space to shoot, the level script checks and spends the ammo
	_fire_cd -= delta
	if can_shoot and can_control and _fire_cd <= 0.0 and Input.is_action_pressed("fire"):
		_fire_cd = fire_interval
		fire_requested.emit(position + muzzle_offset)
		_punch(recoil_punch)

	_update_sprite(delta)


func _jump(v: float, is_double: bool) -> void:
	velocity.y = v
	_on_ground = false
	_air_time = 0.0
	_cut_pending = false
	_cuttable = double_jump_cuttable if is_double else true
	_restart_anim(rise_anim) # replay the jump from frame 0, also on double jump
	if is_double:
		_air_jumps_left -= 1
		_puff(10, Vector2.DOWN, position + Vector2(0.0, feet_offset * 0.6 * scale.y))
		_punch(-takeoff_stretch * 0.7)
		if spin_on_double_jump:
			_spin()
	else:
		_puff(8, Vector2.UP, position + Vector2(0.0, feet_offset * scale.y))
		_punch(-takeoff_stretch) # negative = tall and thin


func _land() -> void:
	var impact := velocity.y
	position.y = _ground_y
	velocity.y = 0.0
	_on_ground = true
	_air_jumps_left = air_jumps
	_cut_pending = false
	# A double jump still waiting when you touch down becomes a normal jump
	if _double_queued:
		_double_queued = false
		_buffer_left = jump_buffer

	# Harder landings squash more
	var k := clampf(impact / max_fall_speed, 0.0, 1.0)
	_punch(maxf(k * landing_squash, 0.06))
	if impact > 200.0:
		_puff(int(lerpf(6.0, 14.0, k)), Vector2.UP, position + Vector2(0.0, feet_offset * scale.y))


# --- Collisions ---

# ki tsir collision with the projectile
func _on_area_entered(area: Area2D) -> void:
	# Boss bullets
	if area.is_in_group("enemy_bullets"):
		if _invuln_left <= 0.0 and health > 0:
			_take_damage(area.damage)
		area.queue_free()
		return

	if not area.is_in_group("projectiles"):
		return

	if area.is_hazard:
		if _invuln_left > 0.0:
			return # pass through during stun / grace period
		_get_stunned(area)
	else:
		collected.emit(area.value)
		_punch(punch_per_point * area.value)
		_flash(Color(2.0, 2.0, 2.0))

	area.queue_free()


func _get_stunned(hazard: Area2D) -> void:
	var duration: float = hazard.stun_duration
	_stun_left = duration
	_invuln_left = duration + invuln_after_stun
	_buffer_left = 0.0
	_double_queued = false
	_cut_pending = false

	# Tangled: lose the jump and get pulled down
	if not _on_ground:
		velocity.y = maxf(velocity.y, stun_knockdown)

	if _spin_tween and _spin_tween.is_valid():
		_spin_tween.kill()
	_kill_flash()
	_punch(0.35)
	stunned.emit(duration)


func _take_damage(amount: int) -> void:
	health = maxi(health - amount, 0)
	_invuln_left = hit_invuln
	_kill_flash()
	_punch(-0.3)
	health_changed.emit(health, max_health)
	damaged.emit(amount)

	if health == 0:
		can_shoot = false
		_flash_tween = create_tween()
		_flash_tween.tween_property(sprite, "modulate", Color(1.0, 0.3, 0.3, 0.3), 0.6)
		died.emit()


# --- Visuals ---

func _update_sprite(delta: float) -> void:
	# Animation by state, frozen while stunned
	if _stun_left > 0.0:
		sprite.pause()
	elif _on_ground:
		_play(ground_anim)
	elif velocity.y < 0.0:
		_play(rise_anim)
	else:
		_play(fall_anim)

	# Dizzy wobble while stunned, the spin owns rotation during a double jump
	if _stun_left > 0.0:
		sprite.rotation = _base_rot + deg_to_rad(dizzy_wobble_deg) * sin(_t * 18.0)
	elif not _is_spinning():
		sprite.rotation = lerp_angle(sprite.rotation, _base_rot, 1.0 - exp(-12.0 * delta))

	# Red pulse while stunned, then blink during the grace period
	if _stun_left > 0.0:
		var pulse := 0.5 + 0.5 * sin(_t * 40.0)
		sprite.modulate = Color(1.0, 0.35, 0.35).lerp(Color.WHITE, pulse * 0.4)
	elif _invuln_left > 0.0:
		var a := 0.35 if fmod(_invuln_left, 0.12) < 0.06 else 1.0
		sprite.modulate = Color(1.0, 1.0, 1.0, a)

	# Shadow stays on the platform and shrinks with height
	if _shadow:
		var height := _ground_y - position.y
		var k := clampf(height / maxf(jump_height + double_jump_height, 1.0), 0.0, 1.0)
		_shadow.position = Vector2(0.0, height / scale.y + feet_offset)
		_shadow.scale = Vector2.ONE * lerpf(1.0, 0.45, k)
		var alpha := lerpf(0.4, 0.12, k)
		if shadow_only_in_air:
			alpha *= smoothstep(0.0, 16.0, height)
		_shadow.modulate.a = alpha


func _play(anim: String) -> void:
	var frames := sprite.sprite_frames
	if frames == null:
		return
	if frames.has_animation(anim):
		if sprite.animation != anim:
			sprite.play(anim)
		# A finished non-looping animation holds its last frame instead of restarting
		elif not sprite.is_playing() and frames.get_animation_loop(anim):
			sprite.play()
	elif not sprite.is_playing() and frames.get_animation_loop(sprite.animation):
		sprite.play()


func _restart_anim(anim: String) -> void:
	var frames := sprite.sprite_frames
	if frames and frames.has_animation(anim):
		sprite.play(anim)
		sprite.frame = 0


func _spin() -> void:
	if _spin_tween and _spin_tween.is_valid():
		_spin_tween.kill()
	sprite.rotation = _base_rot
	_spin_tween = create_tween()
	_spin_tween.tween_property(sprite, "rotation", _base_rot + TAU, spin_duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_spin_tween.tween_callback(func(): sprite.rotation = _base_rot)


func _is_spinning() -> bool:
	return _spin_tween != null and _spin_tween.is_valid() and _spin_tween.is_running()


# Positive = squash wide, negative = stretch tall. Springs back elastically
func _punch(strength: float) -> void:
	if _scale_tween and _scale_tween.is_valid():
		_scale_tween.kill()
	sprite.scale = _base_scale * Vector2(1.0 + strength, 1.0 - strength * 0.6)
	_scale_tween = create_tween()
	_scale_tween.tween_property(sprite, "scale", _base_scale, punch_duration) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _flash(color: Color) -> void:
	if _invuln_left > 0.0:
		return # stun visuals own the color right now
	_kill_flash()
	sprite.modulate = color
	_flash_tween = create_tween()
	_flash_tween.tween_property(sprite, "modulate", Color.WHITE, 0.15)


func _kill_flash() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()


# Small one-shot dust burst, added to the level so it doesn't follow the hedgehog
func _puff(amount: int, dir: Vector2, at: Vector2) -> void:
	if not dust_enabled or get_parent() == null:
		return
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = 0.4
	p.direction = dir
	p.spread = 70.0
	p.initial_velocity_min = 50.0
	p.initial_velocity_max = 130.0
	p.damping_min = 80.0
	p.damping_max = 120.0
	p.gravity = Vector2(0.0, 150.0)
	p.scale_amount_min = 3.0
	p.scale_amount_max = 6.0
	var ramp := Gradient.new()
	ramp.set_color(0, dust_color)
	ramp.set_color(1, Color(dust_color, 0.0))
	p.color_ramp = ramp
	p.position = at
	get_parent().add_child(p)
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.3).timeout.connect(func():
		if is_instance_valid(p):
			p.queue_free())


# Box around the non-transparent pixels of the first frame, in the hedgehog's local space
func _visible_rect() -> Rect2:
	var frames := sprite.sprite_frames
	if frames == null or not frames.has_animation(sprite.animation) \
			or frames.get_frame_count(sprite.animation) == 0:
		return Rect2(-32.0, -32.0, 64.0, 64.0)

	var tex := frames.get_frame_texture(sprite.animation, 0)
	var size := tex.get_size()
	var used := Rect2(Vector2.ZERO, size)
	var img := tex.get_image()
	if img:
		if img.is_compressed():
			img.decompress()
		var r := img.get_used_rect()
		if r.size.x > 0 and r.size.y > 0:
			used = Rect2(r)

	var origin := sprite.offset - (size * 0.5 if sprite.centered else Vector2.ZERO)
	var s := sprite.scale.abs()
	return Rect2(sprite.position + (used.position + origin) * s, used.size * s)


# Adds a "fire" action bound to Space if it isn't in the Input Map yet
func _ensure_fire_action() -> void:
	if InputMap.has_action("fire"):
		return
	InputMap.add_action("fire")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_SPACE
	InputMap.action_add_event("fire", ev)


# Soft oval shadow drawn in code
class Shadow extends Node2D:
	var radius := 24.0

	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.3))
		draw_circle(Vector2.ZERO, radius, Color.BLACK)
