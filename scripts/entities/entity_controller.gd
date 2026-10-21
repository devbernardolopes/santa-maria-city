class_name EntityController
extends Node
## Base class for entity behavior. Subclasses provide movement intent only.

enum MovementMode {
	OMNI,
	RELATIVE,
}

@export var movement_mode: MovementMode = MovementMode.OMNI
## Rotation speed in radians per second when in RELATIVE movement mode.
@export var turn_rate_rad_s: float = PI
## Speed factor applied when moving backwards in RELATIVE movement mode.
@export var reverse_speed_factor: float = 0.5


func get_move_vector() -> Vector2:
	return Vector2.ZERO


func get_move_intent() -> Vector2:
	return get_move_vector()


func wants_run() -> bool:
	return false
