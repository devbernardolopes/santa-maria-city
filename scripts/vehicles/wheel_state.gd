class_name WheelState
extends RefCounted
## Runtime condition of one wheel. Authored geometry stays on WheelSpec.

var spec: WheelSpec = null
var present: bool = true
var pressure_kpa: float = 220.0
var tread: float = 1.0


func _init(spec_value: WheelSpec = null) -> void:
	spec = spec_value
	if spec != null:
		pressure_kpa = spec.nominal_pressure_kpa


func get_offset_m() -> Vector2:
	return spec.offset_m if spec != null else Vector2.ZERO


func get_nominal_pressure_kpa() -> float:
	return spec.nominal_pressure_kpa if spec != null else 220.0


func is_steerable() -> bool:
	return spec != null and spec.steerable


func is_driven() -> bool:
	return spec != null and spec.driven


func is_flat(flat_pressure_kpa: float) -> bool:
	return not present or pressure_kpa <= flat_pressure_kpa


## 0 when missing, tapered down for flat or worn tires, 1 when nominal.
func get_grip_factor(flat_pressure_kpa: float) -> float:
	if not present:
		return 0.0
	var nominal: float = get_nominal_pressure_kpa()
	var pressure_factor: float = 0.4
	if pressure_kpa > flat_pressure_kpa and nominal > flat_pressure_kpa:
		pressure_factor = lerpf(
			0.4,
			1.0,
			clampf((pressure_kpa - flat_pressure_kpa) / (nominal - flat_pressure_kpa), 0.0, 1.0)
		)
	var tread_factor: float = lerpf(0.6, 1.0, clampf(tread, 0.0, 1.0))
	return clampf(pressure_factor * tread_factor, 0.0, 1.0)


func describe(flat_pressure_kpa: float) -> String:
	if not present:
		return "missing"
	if is_flat(flat_pressure_kpa):
		return "flat"
	return "%d kPa" % int(roundf(pressure_kpa))
