class_name FollowCamera
extends Camera2D
## Follows the player and handles wheel and action zoom.

const ZOOM_STEP: float = 1.15
const MIN_ZOOM: float = 0.5
const MAX_ZOOM: float = 8.0
const DEFAULT_LIMIT_PX: int = 10000000

@export var target: Node2D = null
@export var default_zoom: Vector2 = Vector2.ONE * 3.0


func _ready() -> void:
	position_smoothing_enabled = true
	zoom = default_zoom


func snap_to_target() -> void:
	if target == null or not is_instance_valid(target):
		return
	global_position = target.global_position
	reset_smoothing()


## Restricts the camera to a rectangle given in global meters.
func set_limits_m(rect_m: Rect2) -> void:
	var top_left: Vector2 = Units.to_px(rect_m.position)
	var bottom_right: Vector2 = Units.to_px(rect_m.position + rect_m.size)
	limit_left = int(top_left.x)
	limit_top = int(top_left.y)
	limit_right = int(bottom_right.x)
	limit_bottom = int(bottom_right.y)


func clear_limits() -> void:
	limit_left = -DEFAULT_LIMIT_PX
	limit_top = -DEFAULT_LIMIT_PX
	limit_right = DEFAULT_LIMIT_PX
	limit_bottom = DEFAULT_LIMIT_PX


func _process(_delta: float) -> void:
	if target != null and is_instance_valid(target):
		global_position = target.global_position
	if not _is_current():
		return
	if Input.is_action_just_pressed("zoom_in"):
		_zoom_by(ZOOM_STEP)
	if Input.is_action_just_pressed("zoom_out"):
		_zoom_by(1.0 / ZOOM_STEP)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_current():
		return
	var mouse_button := event as InputEventMouseButton
	if mouse_button == null or not mouse_button.pressed:
		return
	if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom_by(ZOOM_STEP)
		get_viewport().set_input_as_handled()
	elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_by(1.0 / ZOOM_STEP)
		get_viewport().set_input_as_handled()


func _zoom_by(factor: float) -> void:
	zoom = (zoom * factor).clamp(Vector2.ONE * MIN_ZOOM, Vector2.ONE * MAX_ZOOM)


func _is_current() -> bool:
	return get_viewport().get_camera_2d() == self
