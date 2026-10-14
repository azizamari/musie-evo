extends Area2D
 
@export var min_speed: float = 250.0
@export var max_speed: float = 450.0
@export var value: int = 1
 
var speed: float
 
 
func _ready() -> void:
	add_to_group("projectiles")
	speed = randf_range(min_speed, max_speed)
 
 
func _process(delta: float) -> void:
	position.x -= speed * delta
 
	# Clean up once ki tfout l edge
	if position.x < -100.0:
		queue_free()
 
