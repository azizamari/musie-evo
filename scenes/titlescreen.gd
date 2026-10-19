extends CanvasItem

@export_file("*.tscn") var next_scene := "res://scenes/start.tscn"
@export var fade_time: float = 0.3

var _leaving := false


func _unhandled_input(event: InputEvent) -> void:
	if _leaving:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_SPACE:
		get_viewport().set_input_as_handled()
		_go()


func _go() -> void:
	_leaving = true
	if fade_time <= 0.0:
		get_tree().change_scene_to_file(next_scene)
		return
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, fade_time)
	tw.tween_callback(func(): get_tree().change_scene_to_file(next_scene))
