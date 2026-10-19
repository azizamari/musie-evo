extends Area2D

# Same signals and API as the seal, so the level script works unchanged
signal collected(value: int)
signal stunned(duration: float)
signal fire_requested(spawn_pos: Vector2)
signal health_changed(current: int, max_health: int)
signal damaged(amount: int)
signal died

@export_group("Movement")
@export var max_speed: float = 450.0
# How quickly Larry speeds up and stops (higher = snappier, 20+ feels instant)
@export var responsiveness: float = 12.0

@export_group("Combat")
@export var max_health: int = 5
# Seconds between shots while holding Space
@export var fire_interval: float = 0.18
# Where bullets spawn relative to Larry (in front of him)
@export var muzzle_offset := Vector2(50.0, 0.0)
# Blink time after a boss hit where bullets can't hurt you
@export var hit_invuln: float = 1.0

@export_group("Stun")
# Push away from the algue on hit
@export var knockback: float = 300.0
# Blinking grace period after a stun where algue passes through
@export var invuln_after_stun: float = 0.6
@export var dizzy_wobble_deg: float = 25.0

@export_group("Juice")
# Squash and stretch strength added per point collected
@export var punch_per_point: float = 0.12
@export var punch_duration: float = 0.45
@export var recoil_punch: float = 0.08

@export_group("Sprite")
# Larry's only animation, played the whole time
@export var fly_anim := "idle"
# Leans into the movement, nose up going up, nose down going down
@export var max_tilt_deg: float = 12.0
# Small hover float while flying (0 = off)
@export var hover_amplitude: float = 3.0
@export var hover_speed: float = 1.5

var velocity := Vector2.ZERO
var screen_size: Vector2
var health := 0
var can_shoot := false # the level script turns this on during the boss phase
var _fire_cd := 0.0
var _t := 0.0
var _sprite_base_y := 0.0
var _base_rot := 0.0
var _base_scale := Vector2.ONE
var _stun_left := 0.0
var _invuln_left := 0.0
var _scale_tween: Tween
var _flash_tween: Tween

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	screen_size = get_viewport_rect().size
	_sprite_base_y = sprite.position.y
	_base_rot = sprite.rotation
	_base_scale = sprite.scale
	health = max_health
	area_entered.connect(_on_area_entered)
	_ensure_fire_action()
	_play(fly_anim)


# Called by the level script at the start of every round
func reset_for_round() -> void:
	health = max_health
	can_shoot = false
	velocity = Vector2.ZERO
	_stun_left = 0.0
	_invuln_left = 0.0
	_kill_flash()
	sprite.modulate = Color.WHITE
	health_changed.emit(health, max_health)


# --- Movement ---

func _process(delta: float) -> void:
	if _stun_left > 0.0:
		_stun_left -= delta
	if _invuln_left > 0.0:
		_invuln_left -= delta
		if _invuln_left <= 0.0:
			sprite.modulate = Color.WHITE

	var can_control := _stun_left <= 0.0
	var input_dir := Input.get_axis("move_up", "move_down") if can_control else 0.0

	# One smooth ease toward the target speed. While stunned it drifts out slower
	var rate := responsiveness if can_control else 3.0
	velocity.y = lerpf(velocity.y, input_dir * max_speed, 1.0 - exp(-rate * delta))

	position += velocity * delta
	var clamped := position.clamp(Vector2.ZERO, screen_size)
	if clamped.y != position.y:
		velocity.y = 0.0 # stop at the edge instead of pushing into it
	position = clamped

	# Hold Space to shoot, the level script checks and spends the ammo
	_fire_cd -= delta
	if can_shoot and can_control and _fire_cd <= 0.0 and Input.is_action_pressed("fire"):
		_fire_cd = fire_interval
		fire_requested.emit(position + muzzle_offset)
		_punch(recoil_punch)

	_update_sprite(delta)


# --- Collisions ---

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

	# Knock Larry away from the algue vertically
	var dir := signf(global_position.y - hazard.global_position.y)
	if dir == 0.0:
		dir = 1.0 if randf() < 0.5 else -1.0
	velocity.y = dir * knockback

	_kill_flash()
	_punch(-0.35)
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
	_t += delta
	var speed_ratio := velocity.y / max_speed # -1 up and 1 down

	# Lean into the movement, wobble while stunned
	var target_rot := _base_rot + deg_to_rad(max_tilt_deg * speed_ratio)
	if _stun_left > 0.0:
		target_rot += deg_to_rad(dizzy_wobble_deg) * sin(_t * 18.0)
	sprite.rotation = lerp_angle(sprite.rotation, target_rot, 1.0 - exp(-10.0 * delta))

	# Keep flying, freeze while stunned
	if _stun_left > 0.0:
		sprite.pause()
	else:
		_play(fly_anim)

	# Red pulse while stunned, then blink during the grace period
	if _stun_left > 0.0:
		var pulse := 0.5 + 0.5 * sin(_t * 40.0)
		sprite.modulate = Color(1.0, 0.35, 0.35).lerp(Color.WHITE, pulse * 0.4)
	elif _invuln_left > 0.0:
		var a := 0.35 if fmod(_invuln_left, 0.12) < 0.06 else 1.0
		sprite.modulate = Color(1.0, 1.0, 1.0, a)

	# Hover float
	sprite.position.y = _sprite_base_y + sin(_t * TAU * hover_speed) * hover_amplitude


func _play(anim: String) -> void:
	var frames := sprite.sprite_frames
	if frames == null:
		return
	if frames.has_animation(anim):
		if sprite.animation != anim:
			sprite.play(anim)
		elif not sprite.is_playing():
			sprite.play()
	elif not sprite.is_playing():
		sprite.play()


# Positive = stretch wide, negative = squash tall. Springs back elastically
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


# Adds a "fire" action bound to Space if it isn't in the Input Map yet
func _ensure_fire_action() -> void:
	if InputMap.has_action("fire"):
		return
	InputMap.add_action("fire")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_SPACE
	InputMap.action_add_event("fire", ev)
