class_name ShakeCamera
extends Camera2D

## followed this tutorial https://www.youtube.com/watch?v=LGt-jjVf-ZU

## Max pixel offset at full trauma.
@export var max_offset := Vector2(28.0, 20.0)
## Trauma lost per second (higher = shorter shakes).
@export var decay: float = 2.5
## How fast the shake jitters.
@export var shake_speed: float = 30.0

var trauma := 0.0
var _t := 0.0
var _noise := FastNoiseLite.new()


func _ready() -> void:
	# Same framing as having no camera, so nothing shifts on screen
	anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	position = Vector2.ZERO
	_noise.seed = randi()
	_noise.frequency = 0.5


func add_trauma(amount: float) -> void:
	trauma = minf(trauma + amount, 1.0)


func _process(delta: float) -> void:
	if trauma <= 0.0:
		offset = Vector2.ZERO
		return

	trauma = maxf(trauma - decay * delta, 0.0)
	_t += delta * shake_speed

	# Squared trauma: small hits stay subtle, big hits really kick
	var s := trauma * trauma
	offset = Vector2(
		max_offset.x * s * _noise.get_noise_2d(_t, 0.0),
		max_offset.y * s * _noise.get_noise_2d(0.0, _t)
	)
