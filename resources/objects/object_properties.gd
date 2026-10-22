class_name ObjectProperties
extends Resource
## Shared physical and interaction properties for world objects (vegetation, items, vehicles).

@export_group("Mass and motion")
@export var mass_kg: float = 1.0
@export var movable: bool = true
@export_range(0.0, 2.0, 0.01) var friction: float = 0.6

@export_group("Fire")
@export var flammable: bool = false
@export var ignition_temperature_c: float = 300.0
@export var ignition_energy_j: float = 0.0
@export var heat_release_j_per_kg: float = 0.0

@export_group("Breaking")
@export var breakable: bool = false
@export var breaking_force_n: float = 0.0
@export var breaking_energy_j: float = 0.0

@export_group("Age")
@export var max_age_years: float = 0.0
@export var decay_years: float = 0.0


## Compact English summary for inspection messages; empty when nothing is set.
func describe() -> String:
	var parts: PackedStringArray = []
	if mass_kg > 0.0:
		parts.append("%s kg" % _number_text(mass_kg))
	if flammable:
		var fire_text: String = "ignites at %s °C" % _number_text(ignition_temperature_c)
		if ignition_energy_j > 0.0:
			fire_text += " (%s J)" % _number_text(ignition_energy_j)
		parts.append(fire_text)
	else:
		parts.append("not flammable")
	if breakable and breaking_force_n > 0.0:
		parts.append("breaks at %s N" % _number_text(breaking_force_n))
	if max_age_years > 0.0:
		parts.append("lifespan %s y" % _number_text(max_age_years))
	return " · ".join(parts)


func _number_text(value: float) -> String:
	if absf(value - roundf(value)) < 0.05:
		return str(int(roundf(value)))
	if absf(value) >= 1000.0:
		return "%.0f" % value
	return "%.2f" % value
