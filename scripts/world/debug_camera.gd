class_name DebugCamera
extends Camera2D
## Debug camera: frames the map data, pans with actions, and zooms/drags.

const PAN_SPEED_MPS: float = 60.0
const ZOOM_STEP: float = 1.15
const MIN_ZOOM: float = 0.0025
const MAX_ZOOM: float = 8.0
const FRAME_MARGIN: float = 0.9

var _dragging: bool = false
var _map: MapLoader = null


func _ready() -> void:
	_map = get_parent().get_node_or_null("Map") as MapLoader
	if _map == null:
		push_warning("DebugCamera: Map node not found; map framing is disabled.")
		return
	if _map.is_loaded:
		_frame_map()


func _process(delta: float) -> void:
	var direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if direction != Vector2.ZERO:
		position += direction * Units.m_to_px(PAN_SPEED_MPS) * delta / zoom.x
	if Input.is_action_just_pressed("zoom_in"):
		_zoom_by(ZOOM_STEP)
	if Input.is_action_just_pressed("zoom_out"):
		_zoom_by(1.0 / ZOOM_STEP)


func _unhandled_input(event: InputEvent) -> void:
	var mouse_button := event as InputEventMouseButton
	if mouse_button != null:
		if mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(ZOOM_STEP)
			return
		if mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(1.0 / ZOOM_STEP)
			return
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mouse_button.pressed
		return
	var mouse_motion := event as InputEventMouseMotion
	if mouse_motion != null and _dragging:
		position -= mouse_motion.relative / zoom


func on_map_loaded() -> void:
	_frame_map()


func _frame_map() -> void:
	if _map == null or _map.map_bounds_px.size == Vector2.ZERO:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var map_pixels: Vector2 = _map.map_bounds_px.size
	if map_pixels.x <= 0.0 or map_pixels.y <= 0.0:
		return
	var fit_zoom: float = minf(viewport_size.x / map_pixels.x, viewport_size.y / map_pixels.y) * FRAME_MARGIN
	zoom = Vector2.ONE * clampf(fit_zoom, MIN_ZOOM, MAX_ZOOM)
	position = _map.map_bounds_px.get_center()


func _zoom_by(factor: float) -> void:
	zoom = (zoom * factor).clamp(Vector2.ONE * MIN_ZOOM, Vector2.ONE * MAX_ZOOM)
