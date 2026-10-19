extends Area2D

# Same signals the level script listens to
signal health_changed(current: int, max_health: int)
signal hit(damage: int)
signal enraged
signal died

enum State { REST, WINDUP, BURST }

@export var max_health: int = 12
# One sound ring (Area2D + sound_ring.gd)
@export var ring_scene: PackedScene
# Optional: the 6-frame blast effect, played at the mouth on every ring
@export var blast_frames: SpriteFrames
@export var blast_offset := Vector2.ZERO
@export var blast_scale := Vector2.ONE
# Platform to stand on. Empty = a sibling node named "Platform"
@export var platform: Control

@export_group("Rhythm")
# Each string is one attack, one character per beat:
# L = low ring (jump over it), H = high ring (stay down), - = rest beat
@export var patterns: Array[String] = ["LLL", "LHL", "L-LL", "HLH"]
# Seconds between beats inside a pattern
@export var beat_interval: float = 0.4
# Seconds of idle between two attacks
@export var rest_time: float = 1.6
@export var ring_speed: float = 380.0
# How far above the low lane the H ring flies (pixels)
@export var high_lane_offset: float = 150.0
# Where rings and the blast come out, relative to the boss (its mouth)
@export var muzzle_offset := Vector2(-80.0, -40.0)

@export_group("Rage")
# Below this health ratio: faster beats, faster rings, red tint
@export var rage_threshold: float = 0.5
@export var rage_beat_interval: float = 0.3
@export var rage_rest_time: float = 1.0
@export var rage_ring_speed: float = 460.0

@export_group("Animation")
@export var idle_anim := "idle"
@export var attack_anim := "attack"
# Attack pose shows this long before the first ring (warns the player)
@export var windup_time: float = 0.35
@export var enter_duration: float = 1.5

var health := 0
var target: Node2D # set by the level script
var _active := false
var _dead := false
var _raging := false
var _state := State.REST
var _state_t := 0.0
var _pattern := ""
var _beat_i := 0
var _feet := 0.0
var _visual: AnimatedSprite2D
var _base_scale := Vector2.ONE
var _rest_color := Color.WHITE
var _scale_tween: Tween
var _flash_tween: Tween


func _ready() -> void:
	health = max_health
	for c in get_children():
		if c is AnimatedSprite2D:
			_visual = c as AnimatedSprite2D
			break
	if _visual:
		_base_scale = _visual.scale
		_feet = _visible_rect().end.y
	_play(idle_anim)

	# The blast must play once and end, so it can clean itself up
	if blast_frames:
		for anim in blast_frames.get_animation_names():
			blast_frames.set_animation_loop(anim, false)

	area_entered.connect(_on_area_entered)
	health_changed.emit(health, max_health)


# --- Called by the level script ---

func enter(to: Vector2) -> void:
	# Stand on the platform, slide in from the right
	var ground := _ground_y(to.y)
	position.y = ground
	var tw := create_tween()
	tw.tween_property(self, "position", Vector2(to.x, ground), enter_duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_begin)


func _begin() -> void:
	_active = true
	_state = State.REST
	_state_t = 0.8 # short breather before the first attack


func stop() -> void:
	_active = false
	_play(idle_anim)


# --- Attack loop ---

func _process(delta: float) -> void:
	if not _active or _dead:
		return

	_state_t -= delta
	match _state:
		State.REST:
			if _state_t <= 0.0:
				_start_windup()
		State.WINDUP:
			if _state_t <= 0.0:
				_state = State.BURST
				_beat_i = 0
				_state_t = 0.0 # first beat right away
		State.BURST:
			if _state_t <= 0.0:
				if _beat_i < _pattern.length():
					_fire_beat(_pattern[_beat_i])
					_beat_i += 1
					_state_t = rage_beat_interval if _raging else beat_interval
				else:
					_state = State.REST
					_state_t = rage_rest_time if _raging else rest_time
					_play(idle_anim)


func _start_windup() -> void:
	_pattern = patterns.pick_random().to_upper() if not patterns.is_empty() else "L"
	_state = State.WINDUP
	_state_t = windup_time
	_play(attack_anim)
	_punch(-0.08) # lean back before the shout


func _fire_beat(c: String) -> void:
	if c != "L" and c != "H":
		return # rest beat

	var low := _low_lane()
	var y := low if c == "L" else low - high_lane_offset

	if ring_scene:
		var r = ring_scene.instantiate()
		r.position = Vector2(position.x + muzzle_offset.x, y)
		r.direction = Vector2.LEFT
		r.speed = rage_ring_speed if _raging else ring_speed
		get_parent().add_child(r)

	_blast(position + muzzle_offset + blast_offset)
	_punch(0.1) # pulse on every beat


# Height of the hedgehog standing on the ground
func _low_lane() -> float:
	if is_instance_valid(target) and target.has_method("get_spawn_band"):
		var band: Vector2 = target.get_spawn_band()
		return band.y
	return position.y


func _blast(at: Vector2) -> void:
	if blast_frames == null or get_parent() == null:
		return
	var names := blast_frames.get_animation_names()
	if names.is_empty():
		return
	var fx := AnimatedSprite2D.new()
	fx.sprite_frames = blast_frames
	fx.position = at
	fx.scale = blast_scale
	get_parent().add_child(fx)
	fx.play(names[0])
	fx.animation_finished.connect(fx.queue_free)


# --- Taking damage ---

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
		_rest_color = Color(1.0, 0.7, 0.7)
		enraged.emit()
		_punch(0.3)


func _die() -> void:
	_dead = true
	_active = false
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	died.emit()

	if _visual == null:
		queue_free()
		return
	for old_tw in [_scale_tween, _flash_tween]:
		if old_tw and old_tw.is_valid():
			old_tw.kill()
	var tw := create_tween().set_parallel()
	tw.tween_property(_visual, "scale", _base_scale * 1.8, 0.7) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.7)
	tw.chain().tween_callback(queue_free)


# --- Helpers ---

func _play(anim: String) -> void:
	if _visual and _visual.sprite_frames and _visual.sprite_frames.has_animation(anim):
		_visual.play(anim)


func _punch(strength: float) -> void:
	if _visual == null:
		return
	if _scale_tween and _scale_tween.is_valid():
		_scale_tween.kill()
	_visual.scale = _base_scale * Vector2(1.0 + strength, 1.0 - strength * 0.6)
	_scale_tween = create_tween()
	_scale_tween.tween_property(_visual, "scale", _base_scale, 0.4) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _flash(color: Color) -> void:
	if _visual == null:
		return
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_visual.modulate = color
	_flash_tween = create_tween()
	_flash_tween.tween_property(_visual, "modulate", _rest_color, 0.12)


# Boss y that puts its feet on the platform's top edge
func _ground_y(fallback: float) -> float:
	if platform == null and get_parent():
		var found := get_parent().get_node_or_null("Platform")
		if found is Control:
			platform = found as Control
	if platform == null:
		return fallback
	var parent_offset := global_position.y - position.y
	return platform.global_position.y - parent_offset - _feet * scale.y


# Box around the non-transparent pixels of the idle frame, in local space
func _visible_rect() -> Rect2:
	var frames := _visual.sprite_frames
	var anim: String = idle_anim if frames and frames.has_animation(idle_anim) else String(_visual.animation)
	if frames == null or not frames.has_animation(anim) or frames.get_frame_count(anim) == 0:
		return Rect2(-32.0, -32.0, 64.0, 64.0)

	var tex := frames.get_frame_texture(anim, 0)
	var size := tex.get_size()
	var used := Rect2(Vector2.ZERO, size)
	var img := tex.get_image()
	if img:
		if img.is_compressed():
			img.decompress()
		var r := img.get_used_rect()
		if r.size.x > 0 and r.size.y > 0:
			used = Rect2(r)

	var origin := _visual.offset - (size * 0.5 if _visual.centered else Vector2.ZERO)
	var s := _visual.scale.abs()
	return Rect2(_visual.position + (used.position + origin) * s, used.size * s)
