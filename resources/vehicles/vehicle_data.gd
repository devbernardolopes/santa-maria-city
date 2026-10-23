class_name VehicleData
extends Resource
## Static definition of one vehicle: body, art, handling, durability, wheels, and capacity.
##
## Runtime state (health, tire pressure, occupants, contents) lives on the Vehicle node.

@export_group("Identity")
@export var id: StringName = &""
@export var display_name: String = "Car"
@export_enum("car", "van", "truck", "bus", "motorcycle", "emergency") var kind: String = "car"
## Shared physical description (mass, flammability, breaking, lifespan).
@export var properties: ObjectProperties = null

@export_group("Body")
@export var length_m: float = 4.5
@export var width_m: float = 1.9
## Visible body length of the sprite in pixels; used to scale art from length_m.
@export var sprite_length_px: float = 218.0
@export var sprite_faces_north: bool = true
@export var frames: Array[Texture2D] = []
@export var frame_time_s: float = 0.12
@export var default_lights_enabled: bool = false

@export_group("Durability")
@export var max_health: float = 900.0
## Impacts slower than this never damage the vehicle.
@export var impact_damage_threshold_mps: float = 4.0
@export var impact_damage_per_mps: float = 8.0

@export_group("Motion")
@export var max_speed_mps: float = 34.0
@export var max_reverse_speed_mps: float = 8.0
@export var acceleration_mps2: float = 7.5
@export var brake_mps2: float = 18.0
@export var engine_braking_mps2: float = 2.0
## Constant deceleration from tires and drivetrain while rolling.
@export var rolling_resistance_mps2: float = 0.6
@export var max_steer_deg: float = 32.0
@export var steer_rate_deg_s: float = 140.0
## Steering fraction kept at top speed (lower = heavier feel at speed).
@export_range(0.05, 1.0, 0.01) var high_speed_steer_factor: float = 0.35
## How quickly sideways slip is cancelled; lower values slide more.
@export var lateral_grip: float = 9.0
@export_range(0.0, 1.0, 0.01) var handbrake_grip_factor: float = 0.15
## 0 derives it from length_m.
@export var wheelbase_m: float = 0.0
@export var terrain_profile: VehicleTerrainProfile = null

@export_group("Wheels")
## Number of wheels used when no explicit WheelSpec list is authored.
@export_range(2, 10) var wheel_count: int = 4
## Optional custom layout; overrides wheel_count when not empty.
@export var wheels: Array[WheelSpec] = []
@export var default_tire_radius_m: float = 0.32
@export_range(0.0, 600.0, 1.0) var default_tire_pressure_kpa: float = 220.0
## At or below this pressure a tire is considered flat.
@export_range(0.0, 300.0, 1.0) var flat_tire_pressure_kpa: float = 110.0

@export_group("Occupancy and storage")
@export_range(1, 64) var seat_count: int = 4
@export var can_store_items: bool = false
@export_range(0, 512) var storage_slots: int = 0
@export var storage_capacity_kg: float = 0.0


func get_display_name() -> String:
	if not display_name.is_empty():
		return display_name
	if not id.is_empty():
		return String(id)
	return "Vehicle"


func get_mass_kg() -> float:
	if properties == null:
		return 1.0
	return maxf(0.1, properties.mass_kg)


## Effective load (kg) an entity must be able to push to move this vehicle.
func get_push_load_kg() -> float:
	var resistance: float = 1.0
	if properties != null:
		resistance = properties.push_resistance
	return PushRules.push_load_kg(get_mass_kg(), resistance)


## False when the shared physical properties mark the vehicle as fixed.
func is_pushable() -> bool:
	return properties == null or properties.movable


func get_wheelbase_m() -> float:
	var value: float = wheelbase_m if wheelbase_m > 0.0 else length_m * 0.6
	return maxf(0.5, value)


## Authored wheel layout, or a generated one for wheel_count (2, 4, or 6).
func get_wheels() -> Array[WheelSpec]:
	if not wheels.is_empty():
		return wheels
	var result: Array[WheelSpec] = []
	var count: int = maxi(2, wheel_count)
	var half_wheelbase: float = get_wheelbase_m() * 0.5
	var half_width: float = maxf(0.3, width_m * 0.42)
	if count == 2:
		result.append(_make_wheel(Vector2(0.0, half_wheelbase), true, false))
		result.append(_make_wheel(Vector2(0.0, -half_wheelbase), false, true))
		return result
	if count == 6:
		for side: float in [-half_width, half_width]:
			result.append(_make_wheel(Vector2(side, half_wheelbase), true, false))
			result.append(_make_wheel(Vector2(side, 0.0), false, true))
			result.append(_make_wheel(Vector2(side, -half_wheelbase), false, true))
		return result
	for side: float in [-half_width, half_width]:
		result.append(_make_wheel(Vector2(side, half_wheelbase), true, true))
		result.append(_make_wheel(Vector2(side, -half_wheelbase), false, true))
	return result


func get_wheel_count() -> int:
	return get_wheels().size()


func has_light_frames() -> bool:
	return frames.size() > 1


func _make_wheel(offset_m: Vector2, steerable: bool, driven: bool) -> WheelSpec:
	var spec := WheelSpec.new()
	spec.offset_m = offset_m
	spec.steerable = steerable
	spec.driven = driven
	spec.radius_m = default_tire_radius_m
	spec.nominal_pressure_kpa = default_tire_pressure_kpa
	return spec
