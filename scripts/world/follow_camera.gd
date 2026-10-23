class_name FollowCamera
extends Camera2D
## Follows a target and either zooms manually or lets the game control zoom by speed.

enum Mode {
	## Player-controlled zoom with the wheel and zoom actions.
	MANUAL,
	## Game-controlled zoom and look-ahead; all zoom input is ignored.
	AUTO,
}

#const ZOOM_STEP: float = 1.15
const ZOOM_STEP: float = 1.15
const MIN_ZOOM: float = 0.05
const MAX_ZOOM: float = 8.0
const DEFAULT_LIMIT_PX: int = 10000000

@export var target: Node2D = null
@export var default_zoom: Vector2 = Vector2.ONE * 3.0
@export var mode: Mode = Mode.MANUAL

@export_group("Auto mode")
@export var auto_idle_zoom: float = 3.0
@export var auto_speed_zoom: float = 1.8
@export var auto_speed_reference_mps: float = 30.0
@export var auto_zoom_response: float = 2.5
@export var look_ahead_s: float = 0.35
@export var look_ahead_max_m: float = 12.0

var _manual_zoom: Vector2 = Vector2.ONE * 3.0
var _look_ahead_m: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Keep smoothing and the follow update on the physics clock. Idle-time smoothing
	# catches up between physics ticks and makes moving sprites jitter backwards.
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	position_smoothing_enabled = true
	zoom = default_zoom
	_manual_zoom = default_zoom


func snap_to_target() -> void:
	if target == null or not is_instance_valid(target):
		return
	_look_ahead_m = Vector2.ZERO
	global_position = target.global_position
	reset_smoothing()


func set_mode(value: Mode) -> void:
	if mode == value:
		return
	if mode == Mode.MANUAL:
		_manual_zoom = zoom
	mode = value
	if mode == Mode.MANUAL:
		_look_ahead_m = Vector2.ZERO
		zoom = _manual_zoom


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


func _physics_process(delta: float) -> void:
	_update_follow(delta)


func _process(_delta: float) -> void:
	if not _is_current():
		return
	if mode != Mode.MANUAL:
		return
	if Input.is_action_just_pressed("zoom_in"):
		_zoom_by(ZOOM_STEP)
	if Input.is_action_just_pressed("zoom_out"):
		_zoom_by(1.0 / ZOOM_STEP)


func _update_follow(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var target_offset_m: Vector2 = Vector2.ZERO
	if mode == Mode.AUTO:
		var velocity_mps: Vector2 = _target_velocity_mps()
		target_offset_m = velocity_mps * look_ahead_s
		if target_offset_m.length() > look_ahead_max_m:
			target_offset_m = target_offset_m.normalized() * look_ahead_max_m
		var speed_ratio: float = clampf(
			velocity_mps.length() / maxf(auto_speed_reference_mps, 0.1), 0.0, 1.0
		)
		var target_zoom: Vector2 = Vector2.ONE * lerpf(auto_idle_zoom, auto_speed_zoom, speed_ratio)
		var zoom_factor: float = 1.0 - exp(-maxf(auto_zoom_response, 0.01) * delta)
		zoom = zoom.lerp(target_zoom, zoom_factor).clamp(
			Vector2.ONE * MIN_ZOOM, Vector2.ONE * MAX_ZOOM
		)
	var offset_factor: float = 1.0 - exp(-maxf(auto_zoom_response, 0.01) * delta)
	_look_ahead_m = _look_ahead_m.lerp(target_offset_m, offset_factor)
	global_position = target.global_position + Units.to_px(_look_ahead_m)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_current() or mode != Mode.MANUAL:
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


func _target_velocity_mps() -> Vector2:
	if target == null or not is_instance_valid(target):
		return Vector2.ZERO
	if not target.has_method("get_velocity_mps"):
		return Vector2.ZERO
	var value: Variant = target.call("get_velocity_mps")
	if value is Vector2:
		return value
	return Vector2.ZERO


func _zoom_by(factor: float) -> void:
	zoom = (zoom * factor).clamp(Vector2.ONE * MIN_ZOOM, Vector2.ONE * MAX_ZOOM)
	_manual_zoom = zoom


func _is_current() -> bool:
	return get_viewport().get_camera_2d() == self
