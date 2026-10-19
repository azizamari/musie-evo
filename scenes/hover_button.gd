extends BaseButton 

@export var sprite: AnimatedSprite2D
@export var default_anim := "default"
@export var hovered_anim := "hovered"
# Small grow on hover (1.0 = off)
@export var hover_scale: float = 1.08

var _base_scale := Vector2.ONE
var _tween: Tween


func _ready() -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())

	if sprite == null:
		for c in get_children():
			if c is AnimatedSprite2D:
				sprite = c
				break

	if sprite:
		_base_scale = sprite.scale
		_play(default_anim)

	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))


func _on_hover(on: bool) -> void:
	if sprite == null:
		return
	_play(hovered_anim if on else default_anim)

	if _tween and _tween.is_valid():
		_tween.kill()
	var target := _base_scale * (hover_scale if on else 1.0)
	_tween = create_tween()
	_tween.tween_property(sprite, "scale", target, 0.15) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _play(anim: String) -> void:
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim):
		sprite.play(anim)
