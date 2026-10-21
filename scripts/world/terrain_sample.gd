class_name TerrainSample
extends RefCounted
## One terrain lookup result: category, kind, surface, style id, and OSM id.

const DEFAULT_CATEGORY: StringName = &"ground"
const DEFAULT_KIND: StringName = &"ground"

var category: StringName = DEFAULT_CATEGORY
var kind: StringName = DEFAULT_KIND
var surface: StringName = &""
var style_id: StringName = &""
var osm_id: String = ""

static var _default: TerrainSample = null


## Shared sample for "no terrain info here"; callers never get null.
static func default_sample() -> TerrainSample:
	if _default == null:
		_default = TerrainSample.new()
	return _default
