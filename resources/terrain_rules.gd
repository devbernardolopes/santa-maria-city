class_name TerrainRules
extends Resource
## Terrain-dependent movement multipliers, looked up by surface first, then kind.

const MIN_SPEED_FACTOR: float = 0.1
const MAX_SPEED_FACTOR: float = 2.0
const DEFAULT_SPEED_BY_KIND: Dictionary = {
	&"grass": 0.95,
	&"wood": 0.8,
	&"playground": 0.9,
	&"pitch": 1.0,
	&"residential": 1.0,
	&"stream": 0.6,
}
const DEFAULT_SPEED_BY_SURFACE: Dictionary = {
	&"asphalt": 1.0,
	&"concrete": 1.0,
	&"paving_stones": 0.97,
	&"cobblestone": 0.92,
	&"dirt": 0.9,
	&"unpaved": 0.9,
	&"ground": 0.9,
	&"gravel": 0.88,
}

## Keys are StringName (kind or surface), values are speed factors.
@export var speed_by_kind: Dictionary = {}
@export var speed_by_surface: Dictionary = {}

static var _shared: TerrainRules = null


func get_speed_factor(sample: TerrainSample) -> float:
	if sample == null:
		return 1.0
	var surface_factor: float = _factor_of(speed_by_surface, sample.surface)
	if not is_nan(surface_factor):
		return clampf(surface_factor, MIN_SPEED_FACTOR, MAX_SPEED_FACTOR)
	var kind_factor: float = _factor_of(speed_by_kind, sample.kind)
	if not is_nan(kind_factor):
		return clampf(kind_factor, MIN_SPEED_FACTOR, MAX_SPEED_FACTOR)
	return 1.0


static func create_default() -> TerrainRules:
	var rules := TerrainRules.new()
	rules.speed_by_kind = DEFAULT_SPEED_BY_KIND.duplicate()
	rules.speed_by_surface = DEFAULT_SPEED_BY_SURFACE.duplicate()
	return rules


## Shared fallback instance for callers that have no authored TerrainRules.
static func shared_default() -> TerrainRules:
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
		push_warning("TerrainRules: speed entry for '%s' is not a number; ignored." % String(key))
		return NAN
	return float(value)
