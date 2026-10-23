class_name TouchJoystick
extends Control
## On-screen joystick of the touch controls. It presses the move_* actions with the
## strength of the stick, and "sprint" when it is pushed to the edge.

@export var radius := 100.0
@export var dead_zone := 0.12
@export var sprint_threshold := 0.92

var touch_index := -1
var output := Vector2.ZERO
var _center := Vector2.ZERO
var _knob := Vector2.ZERO


func _ready() -> void:
	_reset_center()


func _reset_center() -> void:
	_center = size / 2.0
	_knob = _center
	queue_redraw()


## The joystick appears where the finger touches (inside its area).
func start(index: int, pos: Vector2) -> void:
	touch_index = index
	var local := pos - global_position
	_center = local.clamp(Vector2(radius, radius), size - Vector2(radius, radius)) if size.x > radius * 2.0 else size / 2.0
	drag(pos)


func drag(pos: Vector2) -> void:
	var v := (pos - global_position - _center).limit_length(radius)
	_knob = _center + v
	output = v / radius
	if output.length() < dead_zone:
		output = Vector2.ZERO
	_apply()
	queue_redraw()


func release() -> void:
	touch_index = -1
	output = Vector2.ZERO
	_apply()
	_reset_center()


func _apply() -> void:
	_set_action("move_right", maxf(0.0, output.x))
	_set_action("move_left", maxf(0.0, -output.x))
	_set_action("move_back", maxf(0.0, output.y))
	_set_action("move_forward", maxf(0.0, -output.y))
	_set_action("sprint", 1.0 if output.length() >= sprint_threshold else 0.0)


func _set_action(action: String, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _draw() -> void:
	draw_circle(_center, radius, Color(0.05, 0.07, 0.12, 0.35))
	draw_arc(_center, radius, 0.0, TAU, 64, Color(0.93, 0.78, 0.42, 0.6), 3.0, true)
	draw_circle(_knob, radius * 0.42, Color(0.93, 0.78, 0.42, 0.75 if touch_index >= 0 else 0.45))
