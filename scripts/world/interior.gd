class_name Interior
extends Node2D
## Contract for interior scenes: a "EntryPoint" (Marker2D) and "Objects" (Node2D) child,
## optional bounds_m for camera limits, and an exit signal.
##
## The manager places one interior at InteriorManager.INTERIOR_ORIGIN_M, far outside the
## imported city. Interior scenes are authored in local meters with their origin at the
## room's top-left corner.

signal exit_requested(actor: Entity)

## Room bounds in meters, local to the interior's origin. Empty means "use the footprint".
@export var bounds_m: Rect2 = Rect2()

var _entry_point: Marker2D = null
var _objects: Node2D = null


func _ready() -> void:
	_entry_point = get_node_or_null("EntryPoint") as Marker2D
	_objects = get_node_or_null("Objects") as Node2D
	if _entry_point == null:
		push_warning(
			(
				"Interior '%s': missing 'EntryPoint' (Marker2D); the player appears inside the door."
				% name
			)
		)
	if _objects == null:
		push_warning("Interior '%s': missing 'Objects' (Node2D)." % name)


func request_exit(actor: Entity) -> void:
	exit_requested.emit(actor)


func has_entry_point() -> bool:
	return _entry_point != null


func get_entry_point_global() -> Vector2:
	if _entry_point == null:
		return global_position
	return _entry_point.global_position


## Room bounds in meters, local to the interior origin.
func get_bounds_m() -> Rect2:
	return bounds_m
