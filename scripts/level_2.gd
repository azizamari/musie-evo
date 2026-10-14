extends Node2D

@export var projectile_scene: PackedScene
# Random delay binet spawns.
@export var min_interval: float = 0.6
@export var max_interval: float = 1.6
@export var spawn_margin: float = 40.0
@export var score_label: Label

var score := 0
var _timer := Timer.new()

@onready var player := $Player


func _ready() -> void:
	player.collected.connect(_on_collected)

	_timer.one_shot = true
	_timer.timeout.connect(_spawn)
	add_child(_timer)
	_schedule_next()


func _schedule_next() -> void:
	_timer.start(randf_range(min_interval, max_interval))


func _spawn() -> void:
	var size := get_viewport_rect().size
	var p := projectile_scene.instantiate()
	# start position on the right
	p.position = Vector2(size.x + spawn_margin, randf_range(spawn_margin, size.y - spawn_margin))
	add_child(p)
	_schedule_next()


func _on_collected(value: int) -> void:
	score += value
	if score_label:
		score_label.text = "Points: %d" % score
