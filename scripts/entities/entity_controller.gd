class_name EntityController
extends Node
## Base class for entity behavior. Subclasses provide movement intent only.


func get_move_vector() -> Vector2:
	return Vector2.ZERO


func wants_run() -> bool:
	return false
