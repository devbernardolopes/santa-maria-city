class_name TouchJoystick
extends Control
## Multitouch virtual joystick that feeds the move_* actions.

const DEADZONE: float = 0.15
const KNOB_RADIUS_RATIO: float = 0.24
const RING_WIDTH_RATIO: float = 0.035
const BASE_COLOR: Color = Color(0.08, 0.08, 0.08, 0.32)
const RING_COLOR: Color = Color(1.0, 1.0, 1.0, 0.65)
const KNOB_COLOR: Color = Color(1.0, 1.0, 1.0, 0.82)
const ACTION_STRENGTH_MIN: float = 0.55
const ACTION_STRENGTH_RANGE: float = 0.45

var _touch_index: int = -1
var _value: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _exit_tree() -> void:
	release_all()


func _notification(what: int) -> void:
	if what == CanvasItem.NOTIFICATION_VISIBILITY_CHANGED and not visible:
		release_all()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _touch_index == -1 and get_global_rect().has_point(touch.position):
			_touch_index = touch.index
			_update_from_position(touch.position)
		elif not touch.pressed and touch.index == _touch_index:
			release_all()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_index:
			_update_from_position(drag.position)


func release_all() -> void:
	_touch_index = -1
	_value = Vector2.ZERO
	_apply_actions()
	queue_redraw()


func _update_from_position(position: Vector2) -> void:
	var center: Vector2 = get_global_rect().get_center()
	var radius: float = maxf(size.x * 0.5 - _knob_radius(), 1.0)
	_value = ((position - center) / radius).limit_length(1.0)
	if _value.length() < DEADZONE:
		_value = Vector2.ZERO
	_apply_actions()
	queue_redraw()


func _apply_actions() -> void:
	_apply_axis("move_left", "move_right", _value.x)
	_apply_axis("move_up", "move_down", _value.y)


func _apply_axis(negative_action: StringName, positive_action: StringName, value: float) -> void:
	var magnitude: float = absf(value)
	if magnitude <= DEADZONE:
		Input.action_release(negative_action)
		Input.action_release(positive_action)
		return
	var action: StringName = positive_action if value > 0.0 else negative_action
	var opposite: StringName = negative_action if value > 0.0 else positive_action
	Input.action_release(opposite)
	var normalized: float = clampf((magnitude - DEADZONE) / (1.0 - DEADZONE), 0.0, 1.0)
	Input.action_press(action, ACTION_STRENGTH_MIN + ACTION_STRENGTH_RANGE * normalized)


func _knob_radius() -> float:
	return size.x * KNOB_RADIUS_RATIO


func _draw() -> void:
	var radius: float = size.x * 0.5 - 1.0
	if radius <= 0.0:
		return
	var center: Vector2 = size * 0.5
	draw_circle(center, radius, BASE_COLOR)
	draw_arc(
		center,
		radius,
		0.0,
		TAU,
		64,
		RING_COLOR,
		maxf(1.0, radius * RING_WIDTH_RATIO),
		true
	)
	var knob_radius: float = _knob_radius()
	var knob_position: Vector2 = center + _value * (radius - knob_radius)
	draw_circle(knob_position, knob_radius, KNOB_COLOR)
