extends Area2D

@export var speed: float = 400.0
var screen_size: Vector2

func _ready():
	screen_size = get_viewport_rect().size

func _process(delta):
	var velocity = Vector2.ZERO

	if Input.is_action_pressed("move_down"):
		velocity.y += 1
	if Input.is_action_pressed("move_up"):
		velocity.y -= 1

	if velocity.length() > 0:
		velocity = velocity.normalized()

		if velocity.y < 0:
			$AnimatedSprite2D.rotation_degrees = -210
			$AnimatedSprite2D.animation = "up"
		elif velocity.y > 0:
			$AnimatedSprite2D.rotation_degrees = 210
			$AnimatedSprite2D.animation = "down"

		$AnimatedSprite2D.play()
	else:
		$AnimatedSprite2D.stop()

	position += velocity * speed * delta
	position = position.clamp(Vector2.ZERO, screen_size)
