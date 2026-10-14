extends Node2D

signal game_over(final_score: int)

@export var player: Area2D
@export var score_label: Label
@export var timer_label: Label

@export_group("Game")
@export var game_duration: float = 30.0

@export_group("Projectiles")
@export var projectile_scenes: Array[PackedScene] = []
@export var base_speed: float = 250.0
@export var speed_variance: float = 0.15
@export var spawn_margin: float = 40.0

@export_group("Difficulty")
@export var end_speed_multiplier: float = 2.0 # speed fi ekher l game
# avg seconds between spawns f start w f lekher
@export var start_interval: float = 1.4
@export var end_interval: float = 0.5

var score := 0
var time_left := 0.0
var _running := false
var _weights: Array[float] = []
var _total_weight := 0.0
var _spawn_timer := Timer.new()


func _ready() -> void:
	assert(player != null, "Assign Player in the Main inspector")
	if projectile_scenes.is_empty():
		push_error("Add projectile scenes to Main > Projectile Scenes")
		return

	player.collected.connect(_on_collected)
	_spawn_timer.one_shot = true
	_spawn_timer.timeout.connect(_spawn)
	add_child(_spawn_timer)

	_cache_weights()
	start_game()


func start_game() -> void:
	score = 0
	time_left = game_duration
	_running = true
	player.set_process(true)
	_update_labels()
	_schedule_next()


func _process(delta: float) -> void:
	if not _running:
		return
	time_left = maxf(time_left - delta, 0.0)
	_update_labels()
	if time_left <= 0.0:
		_end_game()


# 0.0 at the start of the round, 1.0 when time runs out
func _progress() -> float:
	return clampf(1.0 - time_left / maxf(game_duration, 0.01), 0.0, 1.0)


func _schedule_next() -> void:
	var interval := lerpf(start_interval, end_interval, _progress())
	_spawn_timer.start(interval * randf_range(0.7, 1.3))


func _spawn() -> void:
	if not _running:
		return

	var p = _pick_scene().instantiate()
	var size := get_viewport_rect().size

	# Extra margin for wobbling variants so they stay on screen.
	var margin: float = spawn_margin + p.wobble_amplitude
	p.position = Vector2(size.x + spawn_margin, randf_range(margin, size.y - margin))

	var difficulty := lerpf(1.0, end_speed_multiplier, _progress())
	var variance := randf_range(1.0 - speed_variance, 1.0 + speed_variance)
	p.speed = base_speed * difficulty * p.speed_multiplier * variance

	add_child(p)
	_schedule_next()


# Read each scene's spawn_weight once so rarity lives on the projectile scene
func _cache_weights() -> void:
	_weights.clear()
	_total_weight = 0.0
	for scene in projectile_scenes:
		var temp = scene.instantiate()
		var w: float = temp.spawn_weight
		_weights.append(w)
		_total_weight += w
		temp.free()


func _pick_scene() -> PackedScene:
	var roll := randf() * _total_weight
	for i in projectile_scenes.size():
		roll -= _weights[i]
		if roll <= 0.0:
			return projectile_scenes[i]
	return projectile_scenes.back()


func _on_collected(value: int) -> void:
	if not _running:
		return
	score += value
	_update_labels()


func _end_game() -> void:
	_running = false
	_spawn_timer.stop()
	player.set_process(false)
	get_tree().call_group("projectiles", "queue_free")
	game_over.emit(score)


func _update_labels() -> void:
	if score_label:
		score_label.text = "Points: %d" % score
	if timer_label:
		timer_label.text = "Time: %d" % ceili(time_left)
