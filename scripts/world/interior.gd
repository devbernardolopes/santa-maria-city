class_name Interior
extends Node2D
## Contract for interior scenes: required "EntryPoint" (Marker2D) and "Objects" (Node2D)
## children, optional bounds_m for camera limits, and an exit signal.

signal exit_requested(actor: Entity)

## Room bounds in meters, local to the interior's origin. Set automatically.
@export var bounds_m: Rect2 = Rect2()

var _entry_point: Marker2D = null
var _objects: Node2D = null
var _current_bounds_m: Rect2 = Rect2()


func _ready() -> void:
	_entry_point = get_node_or_null("EntryPoint") as Marker2D
	_objects = get_node_or_null("Objects") as Node2D
	if _entry_point == null:
		push_warning(
			(
				"Interior '%s': missing 'EntryPoint' (Marker2D); the player appears at the interior origin."
				% name
			)
		)
	if _objects == null:
		push_warning("Interior '%s': missing 'Objects' (Node2D)." % name)


func request_exit(actor: Entity) -> void:
	exit_requested.emit(actor)


func get_entry_point_global() -> Vector2:
	if _entry_point == null:
		return global_position
	return _entry_point.global_position


func get_bounds_m() -> Rect2:
	return bounds_m


func get_current_bounds_m() -> Rect2:
	return _current_bounds_m
