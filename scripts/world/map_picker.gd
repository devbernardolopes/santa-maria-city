class_name MapPicker
extends Node2D
## Debug polygon picker: outlines the top-most polygon and reports its OSM data.

signal picked(info: Dictionary)

const OUTLINE_SCREEN_WIDTH: float = 3.0

@onready var _outline: Line2D = $Outline

var _map: MapLoader = null


func _ready() -> void:
	_map = get_parent().get_node_or_null("Map") as MapLoader
	_outline.closed = true
	_outline.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("debug_pick"):
		return
	if get_viewport().get_camera_2d() == null:
		return
	var world_point: Vector2 = Vector2.ZERO
	if event is InputEventMouseButton:
		world_point = get_global_mouse_position()
	elif event is InputEventJoypadButton:
		world_point = _screen_center_world()
	else:
		return
	_pick_at(world_point)
	get_viewport().set_input_as_handled()


func clear_pick() -> void:
	_outline.points = PackedVector2Array()
	_outline.visible = false
	picked.emit({})


func _pick_at(world_point: Vector2) -> void:
	if _map == null:
		clear_pick()
		return
	var info: Dictionary = _map.pick(world_point)
	if info.is_empty():
		clear_pick()
		return
	var points_value: Variant = info.get("points")
	if not (points_value is PackedVector2Array):
		clear_pick()
		return
	var world_points: PackedVector2Array = points_value
	if world_points.is_empty():
		clear_pick()
		return
	_outline.points = _to_local_points(world_points)
	var camera: Camera2D = get_viewport().get_camera_2d()
	_outline.width = OUTLINE_SCREEN_WIDTH / maxf(camera.zoom.x, 0.0001) if camera != null else OUTLINE_SCREEN_WIDTH
	_outline.visible = true
	var osm_id: String = str(info.get("id", ""))
	if not osm_id.is_empty():
		DisplayServer.clipboard_set(osm_id)
	picked.emit(info)


func _to_local_points(world_points: PackedVector2Array) -> PackedVector2Array:
	var local_points := PackedVector2Array()
	for point: Vector2 in world_points:
		local_points.append(to_local(point))
	return local_points


func _screen_center_world() -> Vector2:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera != null:
		return camera.get_screen_center_position()
	var viewport: Viewport = get_viewport()
	var center: Vector2 = viewport.get_visible_rect().size * 0.5
	return viewport.get_canvas_transform().affine_inverse() * center
