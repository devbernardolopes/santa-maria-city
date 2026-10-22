class_name VehicleTerrainProfile
extends Resource
## Terrain handling for vehicles: speed and grip multipliers by surface, then kind.
##
## Kept separate from TerrainRules (pedestrian walking speed) because a car on grass
## and a person on grass do not behave the same way.

const MIN_FACTOR: float = 0.05
const MAX_FACTOR: float = 1.2

const DEFAULT_SPEED_BY_KIND: Dictionary = {
	&"grass": 0.6,
	&"wood": 0.5,
	&"playground": 0.7,
	&"pitch": 0.7,
	&"residential": 1.0,
	&"stream": 0.3,
}
const DEFAULT_SPEED_BY_SURFACE: Dictionary = {
	&"asphalt": 1.0,
	&"concrete": 1.0,
	&"paving_stones": 0.92,
	&"cobblestone": 0.88,
	&"dirt": 0.7,
	&"unpaved": 0.68,
	&"ground": 0.68,
	&"gravel": 0.72,
	&"sand": 0.45,
}
const DEFAULT_GRIP_BY_KIND: Dictionary = {
	&"grass": 0.55,
	&"wood": 0.5,
	&"playground": 0.7,
	&"pitch": 0.65,
	&"residential": 1.0,
	&"stream": 0.3,
}
const DEFAULT_GRIP_BY_SURFACE: Dictionary = {
	&"asphalt": 1.0,
	&"concrete": 1.0,
	&"paving_stones": 0.92,
	&"cobblestone": 0.82,
	&"dirt": 0.65,
	&"unpaved": 0.62,
	&"ground": 0.62,
	&"gravel": 0.55,
	&"sand": 0.4,
}

## Keys are StringName (kind or surface), values are multipliers.
@export var speed_by_kind: Dictionary = {}
@export var speed_by_surface: Dictionary = {}
@export var grip_by_kind: Dictionary = {}
@export var grip_by_surface: Dictionary = {}

static var _shared: VehicleTerrainProfile = null


func get_speed_factor(sample: TerrainSample) -> float:
	if sample == null:
		return 1.0
	var surface_factor: float = _factor_of(speed_by_surface, sample.surface)
	if not is_nan(surface_factor):
		return clampf(surface_factor, MIN_FACTOR, MAX_FACTOR)
	var kind_factor: float = _factor_of(speed_by_kind, sample.kind)
	if not is_nan(kind_factor):
		return clampf(kind_factor, MIN_FACTOR, MAX_FACTOR)
	return 1.0


func get_grip_factor(sample: TerrainSample) -> float:
	if sample == null:
		return 1.0
	var surface_factor: float = _factor_of(grip_by_surface, sample.surface)
	if not is_nan(surface_factor):
		return clampf(surface_factor, MIN_FACTOR, MAX_FACTOR)
	var kind_factor: float = _factor_of(grip_by_kind, sample.kind)
	if not is_nan(kind_factor):
		return clampf(kind_factor, MIN_FACTOR, MAX_FACTOR)
	return 1.0


static func create_default() -> VehicleTerrainProfile:
	var profile := VehicleTerrainProfile.new()
	profile.speed_by_kind = DEFAULT_SPEED_BY_KIND.duplicate()
	profile.speed_by_surface = DEFAULT_SPEED_BY_SURFACE.duplicate()
	profile.grip_by_kind = DEFAULT_GRIP_BY_KIND.duplicate()
	profile.grip_by_surface = DEFAULT_GRIP_BY_SURFACE.duplicate()
	return profile


## Shared fallback instance for callers that have no authored profile.
static func shared_default() -> VehicleTerrainProfile:
	if _shared == null:
		_shared = create_default()
	return _shared


## NAN when the key is missing or empty; warns (but returns NAN) on non-numeric entries.
func _factor_of(table: Dictionary, key: StringName) -> float:
	if key.is_empty():
		return NAN
	var value: Variant = table.get(key)
	if value == null:
		value = table.get(String(key))
	if value == null:
		return NAN
	if not (value is float) and not (value is int):
		push_warning("VehicleTerrainProfile: entry for '%s' is not a number; ignored." % String(key))
		return NAN
	return float(value)
