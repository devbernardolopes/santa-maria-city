class_name PlaceholderInterior
extends Interior
## Procedural fallback room used when an entrance has no authored interior scene.
##
## The manager sets room_size_m and room_label from the building footprint before the
## node enters the tree. Walls are solid for PhysicsLayers.WORLD and the exit is a normal
## Interactable, so the room works with the same input and collision paths as the world.

const FLOOR_COLOR: Color = Color(0.42, 0.4, 0.36)
const WALL_COLOR: Color = Color(0.2, 0.19, 0.18)
const WALL_THICKNESS_M: float = 0.3
const ENTRY_OFFSET_M: float = 1.2
const LABEL_MARGIN_PX: float = 8.0
const LABEL_COLOR: Color = Color(0.9, 0.88, 0.8)

## Room size in meters; the manager sets it from the building footprint.
@export var room_size_m: Vector2 = Vector2(8.0, 6.0)
## Floor label: the entrance label or the building OSM id.
@export var room_label: String = ""


func _ready() -> void:
	room_size_m = Vector2(maxf(room_size_m.x, 1.0), maxf(room_size_m.y, 1.0))
	if bounds_m.size.x <= 0.0 or bounds_m.size.y <= 0.0:
		bounds_m = Rect2(
			Vector2.ONE * -WALL_THICKNESS_M,
			room_size_m + Vector2.ONE * (WALL_THICKNESS_M * 2.0)
		)
	var size_px: Vector2 = Units.to_px(room_size_m)
	_build_floor(size_px)
	_build_walls(size_px)
	var objects_node := Node2D.new()
	objects_node.name = "Objects"
	objects_node.y_sort_enabled = true
	add_child(objects_node)
	_build_entry_and_exit(size_px, objects_node)
	_build_label()
	super._ready()


func _build_floor(size_px: Vector2) -> void:
	var floor_polygon := Polygon2D.new()
	floor_polygon.name = "Floor"
	floor_polygon.polygon = PackedVector2Array(
		[
			Vector2.ZERO,
			Vector2(size_px.x, 0.0),
			size_px,
			Vector2(0.0, size_px.y),
		]
	)
	floor_polygon.color = FLOOR_COLOR
	floor_polygon.z_index = -1
	add_child(floor_polygon)


func _build_walls(size_px: Vector2) -> void:
	var thickness: float = Units.m_to_px(WALL_THICKNESS_M)
	var half: float = thickness * 0.5
	_build_wall(Rect2(Vector2(-half, -half), Vector2(size_px.x + thickness, thickness)))
	_build_wall(Rect2(Vector2(-half, size_px.y - half), Vector2(size_px.x + thickness, thickness)))
	_build_wall(Rect2(Vector2(-half, -half), Vector2(thickness, size_px.y + thickness)))
	_build_wall(Rect2(Vector2(size_px.x - half, -half), Vector2(thickness, size_px.y + thickness)))


func _build_wall(rect_px: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	var points: PackedVector2Array = _rect_points(rect_px)
	var collision := CollisionPolygon2D.new()
	collision.build_mode = CollisionPolygon2D.BUILD_SOLIDS
	collision.polygon = points
	body.add_child(collision)
	var visual := Polygon2D.new()
	visual.polygon = points
	visual.color = WALL_COLOR
	visual.z_index = 1
	body.add_child(visual)
	add_child(body)


func _build_entry_and_exit(size_px: Vector2, objects_node: Node2D) -> void:
	var wall_px: float = Units.m_to_px(WALL_THICKNESS_M)
	var center_x: float = size_px.x * 0.5
	var exit := InteriorExit.new()
	exit.name = "Exit"
	exit.position = Vector2(center_x, size_px.y - wall_px)
	objects_node.add_child(exit)
	var entry := Marker2D.new()
	entry.name = "EntryPoint"
	entry.position = Vector2(center_x, size_px.y - wall_px - Units.m_to_px(ENTRY_OFFSET_M))
	add_child(entry)


func _build_label() -> void:
	if room_label.is_empty():
		return
	var label := Label.new()
	label.name = "RoomLabel"
	label.text = room_label
	label.position = Vector2.ONE * LABEL_MARGIN_PX
	label.z_index = 2
	label.add_theme_color_override("font_color", LABEL_COLOR)
	add_child(label)


func _rect_points(rect_px: Rect2) -> PackedVector2Array:
	return PackedVector2Array(
		[
			rect_px.position,
			Vector2(rect_px.end.x, rect_px.position.y),
			rect_px.end,
			Vector2(rect_px.position.x, rect_px.end.y),
		]
	)
