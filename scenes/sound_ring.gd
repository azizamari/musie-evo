extends Area2D

@export var speed: float = 380.0
@export var direction := Vector2.LEFT
@export var damage: int = 1
@export var pulse_amount: float = 0.1
@export var pulse_speed: float = 4.0

var _t := 0.0
var _visual: Node2D
var _base_scale := Vector2.ONE


func _ready() -> void:
	add_to_group("enemy_bullets") # the hedgehog takes damage from this group
	direction = direction.normalized()

	for c in get_children():
		if c is Sprite2D or c is AnimatedSprite2D:
			_visual = c as Node2D
			break
	if _visual:
		_base_scale = _visual.scale
		# Pop in from small
		_visual.scale = _base_scale * 0.3
		create_tween().tween_property(_visual, "scale", _base_scale, 0.15) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_t += delta
	position += direction * speed * delta

	if _visual and _t > 0.15 and pulse_amount > 0.0:
		_visual.scale = _base_scale * (1.0 + sin(_t * TAU * pulse_speed) * pulse_amount)

	var size := get_viewport_rect().size
	if position.x < -150.0 or position.x > size.x + 150.0:
		queue_free()
