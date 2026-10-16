extends Area2D

signal health_changed(current: int, max_health: int)
signal hit(damage: int)
signal enraged
signal died

@export var max_health: int = 12
@export var bullet_scene: PackedScene
# Sprite to squash and flash. Leave empty to use the first sprite child
@export var visual: Node2D

@export_group("Movement")
@export var enter_duration: float = 1.5
# Vertical patrol range in pixels (auto-limited to the screen)
@export var patrol_amplitude: float = 200.0
# Patrol cycles per second
@export var patrol_speed: float = 0.35

@export_group("Attack")
@export var fire_interval: float = 1.3
@export var bullet_speed: float = 350.0
# Where bullets spawn relative to the boss (its left side)
@export var muzzle_offset := Vector2(-60.0, 0.0)
# Health ratio where the boss gets angry: faster fire and 3-way spread
@export var rage_threshold: float = 0.5
@export var rage_fire_interval: float = 0.75
@export var spread_deg: float = 14.0

var health := 0
var target: Node2D # set by Main so the boss can aim at the player
var _active := false
var _dead := false
var _raging := false
var _t := 0.0
var _fire_cd := 0.0
var _home_y := 0.0
var _base_scale := Vector2.ONE
var _rest_color := Color.WHITE
var _scale_tween: Tween
var _flash_tween: Tween


func _ready() -> void:
	health = max_health
	if visual == null:
		for c in get_children():
			if c is Sprite2D or c is AnimatedSprite2D:
				visual = c
				break
	if visual:
		_base_scale = visual.scale
		if visual is AnimatedSprite2D:
			(visual as AnimatedSprite2D).play()
	area_entered.connect(_on_area_entered)
	health_changed.emit(health, max_health)


# Slide in from off-screen, then start fighting
func enter(to: Vector2) -> void:
	var size := get_viewport_rect().size
	patrol_amplitude = minf(patrol_amplitude, size.y * 0.5 - 80.0)
	var tw := create_tween()
	tw.tween_property(self, "position", to, enter_duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_begin)


func _begin() -> void:
	_home_y = position.y
	_fire_cd = 0.6
	_active = true


func stop() -> void:
	_active = false


func _process(delta: float) -> void:
	if not _active or _dead:
		return

	_t += delta
	position.y = _home_y + sin(_t * TAU * patrol_speed) * patrol_amplitude

	_fire_cd -= delta
	if _fire_cd <= 0.0:
		_fire()
		_fire_cd = rage_fire_interval if _raging else fire_interval


func _fire() -> void:
	if bullet_scene == null:
		return

	var origin := position + muzzle_offset
	var dir := Vector2.LEFT
	if is_instance_valid(target):
		dir = (target.position - origin).normalized()

	var angles := [0.0]
	if _raging:
		angles = [-spread_deg, 0.0, spread_deg]

	for a in angles:
		var b = bullet_scene.instantiate()
		b.position = origin
		b.direction = dir.rotated(deg_to_rad(a))
		b.speed = bullet_speed
		get_parent().add_child(b)

	_punch(0.1)


func _on_area_entered(area: Area2D) -> void:
	if _dead or not area.is_in_group("player_bullets"):
		return
	take_damage(area.damage)
	area.queue_free()


func take_damage(amount: int) -> void:
	if _dead:
		return
	health = maxi(health - amount, 0)
	health_changed.emit(health, max_health)
	hit.emit(amount)
	_punch(-0.12)
	_flash(Color(2.5, 2.5, 2.5))

	if health == 0:
		_die()
	elif not _raging and float(health) / max_health <= rage_threshold:
		_raging = true
		_rest_color = Color(1.0, 0.7, 0.7) # stays tinted while angry
		enraged.emit()
		_punch(0.3)


func _die() -> void:
	_dead = true
	_active = false
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	died.emit()

	if visual == null:
		queue_free()
		return
	_kill_tweens()
	var tw := create_tween().set_parallel()
	tw.tween_property(visual, "scale", _base_scale * 1.8, 0.7) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.7)
	tw.chain().tween_callback(queue_free)


func _punch(strength: float) -> void:
	if visual == null:
		return
	if _scale_tween and _scale_tween.is_valid():
		_scale_tween.kill()
	visual.scale = _base_scale * Vector2(1.0 + strength, 1.0 - strength * 0.6)
	_scale_tween = create_tween()
	_scale_tween.tween_property(visual, "scale", _base_scale, 0.4) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _flash(color: Color) -> void:
	if visual == null:
		return
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	visual.modulate = color
	_flash_tween = create_tween()
	_flash_tween.tween_property(visual, "modulate", _rest_color, 0.12)


func _kill_tweens() -> void:
	for tw in [_scale_tween, _flash_tween]:
		if tw and tw.is_valid():
			tw.kill()
