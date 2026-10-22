class_name VehicleController
extends Node
## Base class for vehicle behavior. Subclasses provide control intent only.


## Positive accelerates forward, negative brakes and then reverses.
func get_throttle() -> float:
	return 0.0


## Positive steers right, negative steers left.
func get_steer() -> float:
	return 0.0


func wants_handbrake() -> bool:
	return false
