extends Area2D

signal collected(value: int)

@export var max_speed: float = 400.0
# kedeh lezem bch yousl full speed
@export var accel_rate: float = 4.0
# momentum ki tbadel direction lower = heavier, more watery
@export var reverse_rate: float = 2.5
# drag ki bch thabes l movement (lower = longer bch ihabes)
@export var drag_rate: float = 1.5

@export_group("Sprite")
@export var base_rotation_deg: float = 180.0
@export var max_tilt_deg: float = 30.0
@export var tilt_smoothing: float = 8.0
@export var bob_amplitude: float = 3.0
@export var bob_frequency: float = 0.8

var velocity := Vector2.ZERO
var screen_size: Vector2
var _bob_time := 0.0
var _sprite_base_y := 0.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	screen_size = get_viewport_rect().size
	sprite.rotation_degrees = base_rotation_deg
	_sprite_base_y = sprite.position.y
	area_entered.connect(_on_area_entered)

# ki tsir collision with the projectile
func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("projectiles"):
		collected.emit(area.value)
		area.queue_free()


func _process(delta: float) -> void:
	var input_dir := Input.get_axis("move_up", "move_down")
	var target := Vector2(0.0, input_dir * max_speed)

	var rate := drag_rate
	if input_dir != 0.0:
		rate = reverse_rate if velocity.y * input_dir < 0.0 else accel_rate

	velocity = velocity.lerp(target, 1.0 - exp(-rate * delta))

	position += velocity * delta
	var clamped := position.clamp(Vector2.ZERO, screen_size)
	if clamped.y != position.y:
		velocity.y = 0.0 # kill momentum at the edge so reversing isn't delayed
	position = clamped

	_update_sprite(delta)


func _update_sprite(delta: float) -> void:
	var speed_ratio := velocity.y / max_speed # -1 up and 1 down

	# Tilt follows actual velocity, so it eases in and out with the movement
	var target_rot := deg_to_rad(base_rotation_deg + max_tilt_deg * speed_ratio)
	sprite.rotation = lerp_angle(sprite.rotation, target_rot, 1.0 - exp(-tilt_smoothing * delta))

	# Pick animation from velocity, slow playback as it glides
	if absf(speed_ratio) > 0.05:
		sprite.animation = "up" if speed_ratio < 0.0 else "down"
		sprite.speed_scale = lerpf(0.4, 1.0, absf(speed_ratio))
		sprite.play()
	else:
		sprite.pause()

	# Gentle float, strongest when idle.
	_bob_time += delta
	var bob_strength := 1.0 - absf(speed_ratio)
	sprite.position.y = _sprite_base_y + sin(_bob_time * TAU * bob_frequency) * bob_amplitude * bob_strength
