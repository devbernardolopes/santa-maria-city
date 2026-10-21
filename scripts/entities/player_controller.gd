class_name PlayerController
extends EntityController
## Reads the shared movement actions, so keyboard, gamepad, and touch all work.


func get_move_vector() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func wants_run() -> bool:
	return Input.is_action_pressed("run")
