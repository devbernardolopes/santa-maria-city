class_name VegetationChunkData
extends RefCounted
## Immutable generated plants for one 128 m chunk; parallel typed arrays.

var positions_m: PackedVector2Array = PackedVector2Array()
var species_index: PackedInt32Array = PackedInt32Array()
var radii_m: PackedFloat32Array = PackedFloat32Array()
var rotations: PackedFloat32Array = PackedFloat32Array()
var ages_years: PackedFloat32Array = PackedFloat32Array()
var keys: PackedStringArray = PackedStringArray()


func count() -> int:
	return positions_m.size()


func add(
	position_m: Vector2,
	new_species_index: int,
	radius_m: float,
	rotation: float,
	age_years: float,
	key: String
) -> void:
	positions_m.append(position_m)
	species_index.append(new_species_index)
	radii_m.append(radius_m)
	rotations.append(rotation)
	ages_years.append(age_years)
	keys.append(key)
