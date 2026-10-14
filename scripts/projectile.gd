extends Area2D

@export var value: int = 1
# chance to spawn higher = more common.
@export var spawn_weight: float = 65.0
# Speed relative to the current base speed set in the game
@export var speed_multiplier: float = 1.0
# Vertical sway in pixels. 0 = straight line.
@export var wobble_amplitude: float = 0.0
# Sway cycles per second.
@export var wobble_frequency: float = 1.0

var speed: float = 250.0 # overwritten by Main before spawning
var _base_y := 0.0
var _t := 0.0
var _phase := 0.0


func _ready() -> void:
	add_to_group("projectiles")
	_base_y = position.y
	_phase = randf() * TAU


func _process(delta: float) -> void:
	_t += delta
	position.x -= speed * delta

	if wobble_amplitude > 0.0:
		position.y = _base_y + sin(_t * TAU * wobble_frequency + _phase) * wobble_amplitude

	if position.x < -100.0:
		queue_free()
