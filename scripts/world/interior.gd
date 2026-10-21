class_name Interior
extends Node2D
## Contract for interior scenes: required "EntryPoint" (Marker2D) and "Objects" (Node2D)
## children, optional bounds_m for camera limits, and an exit signal.

signal exit_requested(actor: Entity)

## Room bounds in meters, local to InteriorManager.INTERIOR_ORIGIN_M. Empty derives
## them from the drawn polygons (see get_bounds_m).
@export var bounds_m: Rect2 = Rect2()

var _entry_point: Marker2D = null
var _objects: Node2D = null


func _ready() -> void:
	_entry_point = get_node_or_null("EntryPoint") as Marker2D
	_objects = get_node_or_null("Objects") as Node2D
	if _entry_point == null:
		push_warning("Interior '%s': missing 'EntryPoint' (Marker2D); the player appears at the interior origin." % name)
	if _objects == null:
		push_warning("Interior '%s': missing 'Objects' (Node2D)." % name)


func request_exit(actor: Entity) -> void:
	exit_requested.emit(actor)


func get_entry_point_global() -> Vector2:
	if _entry_point == null:
		return global_position
	return _entry_point.global_position


## bounds_m when set; otherwise an AABB around every Polygon2D grown by 1 m,
## falling back to an 8 x 6 m box at the entry point.
func get_bounds_m() -> Rect2:
	if bounds_m.size.x > 0.0 and bounds_m.size.y > 0.0:
		return bounds_m
	var polygons: Array[Polygon2D] = []
	_collect_polygons(self, polygons)
	var has_bounds: bool = false
	var bounds := Rect2()
	for polygon: Polygon2D in polygons:
		for point: Vector2 in polygon.polygon:
			var local_point: Vector2 = to_local(polygon.to_global(point))
			if not has_bounds:
				bounds = Rect2(local_point, Vector2.ZERO)
				has_bounds = true
			else:
				bounds = bounds.expand(local_point)
	if not has_bounds:
		var entry_local: Vector2 = to_local(get_entry_point_global())
		return Rect2(entry_local - Vector2(4.0, 3.0), Vector2(8.0, 6.0))
	return bounds.grow(1.0)


func _collect_polygons(node: Node, result: Array[Polygon2D]) -> void:
	for child: Node in node.get_children():
		var polygon := child as Polygon2D
		if polygon != null:
			result.append(polygon)
		_collect_polygons(child, result)
