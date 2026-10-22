class_name TerrainSample
extends RefCounted
## One terrain lookup result: category, kind, surface, style id, and OSM id.

const DEFAULT_CATEGORY: StringName = &"ground"
const DEFAULT_KIND: StringName = &"ground"
## Landuse kinds that behave like water: styled as water, block movement, block plants.
const WATER_LANDUSE_KINDS: Array[StringName] = [
	&"water",
	&"reservoir",
	&"swimming_pool",
	&"basin",
]

var category: StringName = DEFAULT_CATEGORY
var kind: StringName = DEFAULT_KIND
var surface: StringName = &""
var style_id: StringName = &""
var osm_id: String = ""

static var _default: TerrainSample = null


## True for landuse polygons that should be treated as water by collision and vegetation.
static func is_water_landuse(category_value: StringName, kind_value: StringName) -> bool:
	return category_value == &"landuse" and WATER_LANDUSE_KINDS.has(kind_value)


## Shared sample for "no terrain info here"; callers never get null.
static func default_sample() -> TerrainSample:
	if _default == null:
		_default = TerrainSample.new()
	return _default
