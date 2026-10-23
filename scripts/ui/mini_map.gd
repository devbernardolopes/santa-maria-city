class_name MiniMap
extends Control
## A flat-color, local map view rendered independently from the World camera.

enum Shape {
	CIRCLE,
	SQUARE,
	RECTANGLE,
}

const DEFAULT_SIZE_PX: Vector2 = Vector2(180.0, 180.0)
const DEFAULT_VISIBLE_RANGE_M: Vector2 = Vector2(120.0, 120.0)
const DEFAULT_SCREEN_ANCHOR: Vector2 = Vector2(1.0, 0.0)
const DEFAULT_SCREEN_OFFSET_PX: Vector2 = Vector2(-16.0, 16.0)
const MIN_SIZE_PX: float = 72.0
const RESTORE_BUTTON_SIZE: Vector2 = Vector2(72.0, 44.0)
const UPDATE_INTERVAL_S: float = 1.0 / 20.0
const MASK_SHADER_CODE: String = """
shader_type canvas_item;
uniform int mini_map_shape = 0;
void fragment() {
	if (mini_map_shape == 0) {
		vec2 delta = UV - vec2(0.5);
		if (dot(delta, delta) > 0.25) {
			discard;
		}
	}
}
"""

@export var shape: Shape = Shape.CIRCLE:
	set(value):
		shape = value
		_apply_layout()

@export var size_px: Vector2 = DEFAULT_SIZE_PX:
	set(value):
		size_px = value
		_apply_layout()

@export_range(0.0, 1.0, 0.01) var opacity: float = 0.85:
	set(value):
		opacity = clampf(value, 0.0, 1.0)
		_apply_opacity()

@export var screen_anchor: Vector2 = DEFAULT_SCREEN_ANCHOR:
	set(value):
		screen_anchor = value
		_apply_layout()

@export var screen_offset_px: Vector2 = DEFAULT_SCREEN_OFFSET_PX:
	set(value):
		screen_offset_px = value
		_apply_layout()

@export var visible_range_m: Vector2 = DEFAULT_VISIBLE_RANGE_M:
	set(value):
		visible_range_m = value
		_request_render()

## Configure keyboard and controller bindings directly in the inspector. Empty uses Tab.
@export var toggle_events: Array[InputEvent] = []
@export var initially_visible: bool = true

var _map: MapLoader = null
var _focus: Node2D = null
var _user_visible: bool = true
var _has_center: bool = false
var _center_m: Vector2 = Vector2.ZERO
var _heading_rad: float = PI * 0.5
var _render_timer: float = 0.0
var _render_dirty: bool = true
var _viewport: SubViewport = null
var _viewport_container: SubViewportContainer = null
var _renderer: MiniMapRenderer = null
var _restore_button: Button = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_ensure_toggle_events()
	_create_viewport()
	_create_restore_button()
	_user_visible = initially_visible
	gui_input.connect(_on_gui_input)
	get_viewport().size_changed.connect(_apply_layout)
	_apply_opacity()
	_apply_layout()
	_apply_visibility()


func _process(delta: float) -> void:
	_render_timer = maxf(0.0, _render_timer - delta)
	if _focus == null or not is_instance_valid(_focus):
		return
	var focus_m: Vector2 = Units.to_m(_focus.global_position)
	if _is_in_map_bounds(focus_m):
		if not _has_center or focus_m.distance_squared_to(_center_m) > 0.0001:
			_center_m = focus_m
			_has_center = true
			_render_dirty = true
	var next_heading: float = _focus_heading_rad()
	if not is_equal_approx(next_heading, _heading_rad):
		_heading_rad = next_heading
		_render_dirty = true
	if _render_dirty and _render_timer <= 0.0:
		_refresh_renderer()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	for toggle_event: InputEvent in toggle_events:
		if toggle_event != null and event.is_match(toggle_event):
			set_user_visible(not _user_visible)
			get_viewport().set_input_as_handled()
			return


func set_map(map: MapLoader) -> void:
	_map = map
	_render_dirty = true
	_request_render()


func set_focus(focus: Node2D) -> void:
	_focus = focus
	_render_dirty = true
	_request_render()


func set_user_visible(value: bool) -> void:
	if _user_visible == value:
		return
	_user_visible = value
	_apply_visibility()
	_request_render()


func is_user_visible() -> bool:
	return _user_visible


## Test-facing count from the most recent renderer update.
func get_drawn_polygon_count() -> int:
	return _renderer.last_drawn_polygon_count if _renderer != null else 0


func get_effective_size_px() -> Vector2:
	return size


func _ensure_toggle_events() -> void:
	if not toggle_events.is_empty():
		return
	var tab_event := InputEventKey.new()
	tab_event.keycode = KEY_TAB
	toggle_events.append(tab_event)


func _create_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_renderer = MiniMapRenderer.new()
	_renderer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.add_child(_renderer)
	_viewport_container = SubViewportContainer.new()
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## The viewport is sized to the configured HUD panel; stretching would override it.
	_viewport_container.stretch = false
	_viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = MASK_SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	_viewport_container.material = material
	add_child(_viewport_container)
	_viewport_container.add_child(_viewport)


func _create_restore_button() -> void:
	_restore_button = Button.new()
	_restore_button.text = "Map"
	_restore_button.focus_mode = Control.FOCUS_NONE
	_restore_button.custom_minimum_size = RESTORE_BUTTON_SIZE
	_restore_button.pressed.connect(_on_restore_pressed)
	add_child(_restore_button)


func _apply_layout() -> void:
	if not is_inside_tree():
		return
	var requested_size := Vector2(
		maxf(MIN_SIZE_PX, size_px.x), maxf(MIN_SIZE_PX, size_px.y)
	)
	if shape == Shape.CIRCLE or shape == Shape.SQUARE:
		var side: float = minf(requested_size.x, requested_size.y)
		requested_size = Vector2.ONE * side
	var viewport_size: Vector2 = get_viewport_rect().size
	var max_size := Vector2(
		maxf(MIN_SIZE_PX, viewport_size.x - 16.0), maxf(MIN_SIZE_PX, viewport_size.y - 16.0)
	)
	size = requested_size.min(max_size)
	var anchor := screen_anchor.clamp(Vector2.ZERO, Vector2.ONE)
	position = viewport_size * anchor + screen_offset_px - size * anchor
	if _viewport != null:
		var render_size := Vector2i(maxi(1, roundi(size.x)), maxi(1, roundi(size.y)))
		_viewport.size = render_size
		_renderer.size = Vector2(render_size)
		_renderer.position = Vector2.ZERO
	if _viewport_container != null:
		_viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var material := _viewport_container.material as ShaderMaterial
		if material != null:
			material.set_shader_parameter("mini_map_shape", int(shape))
	if _restore_button != null:
		_restore_button.position = (size - RESTORE_BUTTON_SIZE) * 0.5
	_request_render()


func _apply_opacity() -> void:
	if _viewport_container != null:
		_viewport_container.modulate.a = opacity


func _apply_visibility() -> void:
	if _viewport_container != null:
		_viewport_container.visible = _user_visible
	if _restore_button != null:
		_restore_button.visible = not _user_visible


func _request_render() -> void:
	_render_dirty = true
	_render_timer = 0.0


func _refresh_renderer() -> void:
	_render_dirty = false
	_render_timer = UPDATE_INTERVAL_S
	if _viewport == null or _renderer == null or _map == null or not _map.is_loaded or not _has_center:
		return
	var range_m := Vector2(maxf(1.0, visible_range_m.x), maxf(1.0, visible_range_m.y))
	var bounds_m := Rect2(_center_m - range_m * 0.5, range_m)
	_renderer.set_contents(_map.get_mini_map_polygons(bounds_m), _center_m, range_m, _heading_rad)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _is_in_map_bounds(point_m: Vector2) -> bool:
	if _map == null or _map.map_bounds_px.size.x <= 0.0 or _map.map_bounds_px.size.y <= 0.0:
		return false
	var bounds_m := Rect2(Units.to_m(_map.map_bounds_px.position), Units.to_m(_map.map_bounds_px.size))
	return bounds_m.has_point(point_m)


func _focus_heading_rad() -> float:
	if _focus is Entity:
		var entity: Entity = _focus as Entity
		return entity.facing.angle()
	return _focus.global_rotation


func _on_gui_input(event: InputEvent) -> void:
	if not _user_visible:
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			set_user_visible(false)
	elif event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			set_user_visible(false)


func _on_restore_pressed() -> void:
	set_user_visible(true)


class MiniMapRenderer extends Control:
	var _features: Array[Dictionary] = []
	var _center_m: Vector2 = Vector2.ZERO
	var _range_m: Vector2 = Vector2.ONE
	var _heading_rad: float = PI * 0.5
	var last_drawn_polygon_count: int = 0


	func set_contents(
		features: Array[Dictionary], center_m: Vector2, range_m: Vector2, heading_rad: float
	) -> void:
		_features = features
		_center_m = center_m
		_range_m = range_m
		_heading_rad = heading_rad
		queue_redraw()


	func _draw() -> void:
		last_drawn_polygon_count = 0
		for feature: Dictionary in _features:
			var polygon: Polygon2D = feature.get("polygon") as Polygon2D
			if polygon == null or not is_instance_valid(polygon):
				continue
			var color_value: Variant = feature.get("color", Color.WHITE)
			var color: Color = color_value if color_value is Color else Color.WHITE
			var points := PackedVector2Array()
			for point: Vector2 in polygon.polygon:
				var point_m: Vector2 = Units.to_m(polygon.to_global(point))
				points.append(_map_to_local(point_m))
			if points.size() >= 3:
				draw_colored_polygon(points, color)
				last_drawn_polygon_count += 1
		_draw_heading_arrow()


	func _map_to_local(point_m: Vector2) -> Vector2:
		var relative: Vector2 = (point_m - _center_m) / _range_m
		return size * (Vector2.ONE * 0.5 + relative)


	func _draw_heading_arrow() -> void:
		var center: Vector2 = size * 0.5
		var radius: float = clampf(minf(size.x, size.y) * 0.055, 5.0, 12.0)
		var forward := Vector2.from_angle(_heading_rad)
		var side: Vector2 = forward.orthogonal()
		var points := PackedVector2Array([
			center + forward * radius,
			center - forward * radius * 0.7 + side * radius * 0.65,
			center - forward * radius * 0.7 - side * radius * 0.65,
		])
		draw_colored_polygon(points, Color("202020"))
