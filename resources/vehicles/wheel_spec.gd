class_name WheelSpec
extends Resource
## Authored description of one wheel on a vehicle.

## Local offset in metres: +X is right of the car, +Y is forward (north-facing sprites).
@export var offset_m: Vector2 = Vector2.ZERO
## True for wheels that turn with the steering input.
@export var steerable: bool = false
## True for wheels that receive engine torque.
@export var driven: bool = true
@export var radius_m: float = 0.32
@export_range(0.0, 600.0, 1.0) var nominal_pressure_kpa: float = 220.0
