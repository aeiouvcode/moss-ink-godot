class_name InkSlider
extends Control
## Hairline slider drawn with vectors so it stays crisp at any pixel ratio.

signal changed(value: int)
signal released(value: int)

var min_value := 0
var max_value := 100
var value := 50
var ink := Color(0.110, 0.153, 0.196)
var hair := Color(0.110, 0.153, 0.196, 0.28)
var _drag := false


func _init() -> void:
	custom_minimum_size = Vector2(0, 30)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL


func set_value(v: int) -> void:
	value = clampi(v, min_value, max_value)
	queue_redraw()


func _ratio() -> float:
	return float(value - min_value) / float(max_value - min_value)


func _draw() -> void:
	var y := size.y * 0.5
	var x := _ratio() * size.x
	draw_line(Vector2(0, y), Vector2(size.x, y), hair, 1.0)
	draw_line(Vector2(0, y), Vector2(x, y), ink, 2.0)
	var knob := Rect2(x - 4, y - 9, 8, 18)
	draw_rect(knob, Color(0.851, 0.867, 0.878))
	draw_rect(knob, ink, false, 1.5 if has_focus() else 1.0)
	draw_line(Vector2(x, y - 4), Vector2(x, y + 4), ink, 1.0)


func _set_from(px: float) -> void:
	var v := int(round(lerpf(min_value, max_value, clampf(px / size.x, 0.0, 1.0))))
	if v != value:
		value = v
		queue_redraw()
		changed.emit(value)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_drag = e.pressed
		if e.pressed:
			_set_from(e.position.x)
		else:
			released.emit(value)
		accept_event()
	elif e is InputEventMouseMotion and _drag:
		_set_from(e.position.x)
		accept_event()
	elif e.is_action_pressed("ui_left") or e.is_action_pressed("ui_right"):
		var step := -1 if e.is_action_pressed("ui_left") else 1
		value = clampi(value + step, min_value, max_value)
		queue_redraw()
		changed.emit(value)
		released.emit(value)
		accept_event()
