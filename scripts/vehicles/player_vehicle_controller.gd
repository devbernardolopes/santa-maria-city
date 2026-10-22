class_name PlayerVehicleController
extends VehicleController
## Reads the shared movement actions, so keyboard, gamepad, and touch all drive.


func get_throttle() -> float:
	return Input.get_axis("move_down", "move_up")


func get_steer() -> float:
	return Input.get_axis("move_left", "move_right")


func wants_handbrake() -> bool:
	return Input.is_action_pressed("run")
