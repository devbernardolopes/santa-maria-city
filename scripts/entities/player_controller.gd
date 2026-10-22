class_name PlayerController
extends EntityController
## Reads the shared movement actions, so keyboard, gamepad, and touch all work.


func get_move_vector() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func get_move_intent() -> Vector2:
	var x: float = Input.get_axis("move_left", "move_right")
	var y: float = Input.get_axis("move_down", "move_up")
	return Vector2(x, y)


func wants_run() -> bool:
	return Input.is_action_pressed("run")
