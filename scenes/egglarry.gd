extends Sprite2D

@export var pulse_amount: float = 0.06
@export var pulse_speed: float = 1.0

var _base_scale: Vector2
var _t := 0.0


func _ready() -> void:
	_base_scale = scale


func _process(delta: float) -> void:
	_t += delta
	var s := 1.0 + sin(_t * TAU * pulse_speed) * pulse_amount
	scale = _base_scale * s
