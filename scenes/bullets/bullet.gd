extends Area2D

@export var speed: float = 700.0
@export var direction := Vector2.RIGHT
@export var damage: int = 1
@export var from_player: bool = true


func _ready() -> void:
	add_to_group("player_bullets" if from_player else "enemy_bullets")
	direction = direction.normalized()
	rotation = direction.angle() # draw the bullet sprite facing right


func _process(delta: float) -> void:
	position += direction * speed * delta

	var size := get_viewport_rect().size
	if position.x < -100.0 or position.x > size.x + 100.0 \
			or position.y < -100.0 or position.y > size.y + 100.0:
		queue_free()
