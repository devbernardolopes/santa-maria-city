@tool
class_name MapStyle
extends Resource
## Data-driven appearance for every map layer, with surface variants and fallbacks.

const FALLBACK_COLOR: Color = Color("b0b0b0")
const ROAD_SURFACE_COLORS: Dictionary = {
	"asphalt": Color("c9c9cf"),
	"paving_stones": Color("e4d9cc"),
	"cobblestone": Color("d6cbbd"),
	"concrete": Color("dcdcdc"),
	"dirt": Color("c8b08a"),
	"unpaved": Color("c8b08a"),
	"ground": Color("c8b08a"),
	"gravel": Color("c8b08a"),
	"paved": Color("d2d2d4"),
	"compacted": Color("c9b892"),
	"sett": Color("d0c4b4"),
	"fine_gravel": Color("d4c3a2"),
	"earth": Color("c2aa84"),
	"metal": Color("c3c7cc"),
	"wood": Color("b99a71"),
	"grass": Color("a9c685"),
}
## Base colors by road kind. `*_link` kinds resolve through their base kind.
const ROAD_COLORS: Dictionary = {
	&"motorway": Color("f2b06b"),
	&"motorway_link": Color("f2b06b"),
	&"trunk": Color("f0c080"),
	&"trunk_link": Color("f0c080"),
	&"primary": Color("f4d58a"),
	&"primary_link": Color("f4d58a"),
	&"secondary": Color("f7e3a1"),
	&"secondary_link": Color("f7e3a1"),
	&"tertiary": Color("f2d98d"),
	&"tertiary_link": Color("f2d98d"),
	&"unclassified": Color("f5f0e4"),
	&"residential": Color("ffffff"),
	&"living_street": Color("f7f2e8"),
	&"pedestrian": Color("f3e7dd"),
	&"service": Color("f0f0f0"),
	&"footway": Color("e0b8b0"),
	&"path": Color("e6c9a8"),
	&"cycleway": Color("d9c2c8"),
	&"steps": Color("d8c0b8"),
	&"track": Color("d6c3a1"),
	&"raceway": Color("c9c9c9"),
	&"bridleway": Color("d9c7a4"),
}
const ROAD_SURFACE_VARIANT_KINDS: Array[StringName] = [
	&"service",
	&"residential",
	&"tertiary",
	&"unclassified",
]
const LANDUSE_COLORS: Dictionary = {
	&"residential": Color("e3dccd"),
	&"garages": Color("c9c4bc"),
	&"commercial": Color("e7d6c4"),
	&"retail": Color("e8d9c9"),
	&"industrial": Color("d6cdc4"),
	&"railway": Color("cfc6bd"),
	&"military": Color("c9c2a8"),
	&"farmland": Color("d9cf99"),
	&"orchard": Color("b6cc8a"),
	&"vineyard": Color("b9c77f"),
	&"allotments": Color("c8d39a"),
	&"meadow": Color("c3d99b"),
	&"grassland": Color("c0d693"),
	&"grass": Color("b8d98a"),
	&"park": Color("a9d58c"),
	&"garden": Color("cfe2a7"),
	&"recreation_ground": Color("b9d99a"),
	&"playground": Color("d9c8a0"),
	&"pitch": Color("9ccc7a"),
	&"stadium": Color("b7d39c"),
	&"sports_centre": Color("b7d39c"),
	&"fitness_station": Color("c0d6a6"),
	&"dog_park": Color("c8d9a3"),
	&"nature_reserve": Color("9fc98a"),
	&"forest": Color("6f9c5c"),
	&"wood": Color("7fb069"),
	&"scrub": Color("9abf7a"),
	&"tree_row": Color("8fae72"),
	&"fell": Color("b4c39a"),
	&"cemetery": Color("bbc6ad"),
	&"religious": Color("d8d2c3"),
	&"greenfield": Color("c9d6a0"),
	&"brownfield": Color("c8bfb2"),
	&"construction": Color("c9c1b5"),
	&"landfill": Color("b9ad9c"),
	&"quarry": Color("b7b0a5"),
	&"cliff": Color("b0a99c"),
	&"sand": Color("ded2a8"),
	&"wetland": Color("9bbfa8"),
	&"water": Color("7fb3d5"),
	&"reservoir": Color("7fb3d5"),
	&"swimming_pool": Color("8ccbe0"),
	&"basin": Color("8ccbe0"),
	&"salt_pond": Color("a7d0dc"),
	&"track": Color("cbb894"),
	&"bleachers": Color("c9c2b4"),
	&"yes": Color("d8e0c8"),
}
const WATERWAY_COLORS: Dictionary = {
	&"stream": Color("7fb3d5"),
	&"river": Color("6fa8cc"),
	&"dam": Color("9aa5a3"),
	&"weir": Color("9aa5a3"),
	&"ditch": Color("8fb9cf"),
	&"drain": Color("9bb5bf"),
}

@export var landuse: Array[TerrainStyle] = []:
	set(value):
		landuse = value
		invalidate_index()

@export var waterways: Array[TerrainStyle] = []:
	set(value):
		waterways = value
		invalidate_index()

@export var roads: Array[TerrainStyle] = []:
	set(value):
		roads = value
		invalidate_index()

@export var buildings: Array[TerrainStyle] = []:
	set(value):
		buildings = value
		invalidate_index()

@export var default_landuse: TerrainStyle = null:
	set(value):
		default_landuse = value
		invalidate_index()

@export var default_waterway: TerrainStyle = null:
	set(value):
		default_waterway = value
		invalidate_index()

@export var default_road: TerrainStyle = null:
	set(value):
		default_road = value
		invalidate_index()

@export var default_building: TerrainStyle = null:
	set(value):
		default_building = value
		invalidate_index()

@export_tool_button("Add missing styles")
var add_missing_styles_button: Callable = add_missing_defaults

@export_tool_button("Reset to defaults")
var reset_to_defaults_button: Callable = fill_defaults

var _kind_index: Dictionary = {}
var _id_index: Dictionary = {}
var _index_dirty: bool = true
var _indexed_sizes: Vector4i = Vector4i(-1, -1, -1, -1)
var _indexed_styles: Array[TerrainStyle] = []
var _fallback_style: TerrainStyle = null


func get_style(category: StringName, kind: String, surface: String = "") -> TerrainStyle:
	_ensure_index()
	var normalized_surface: String = normalize_surface(surface)
	var style: TerrainStyle = _find_style(category, kind, normalized_surface)
	if style == null and category == &"roads":
		var base_kind: String = _base_road_kind(kind)
		if base_kind != kind:
			style = _find_style(category, base_kind, normalized_surface)
	if style != null:
		return style
	var default_style: TerrainStyle = _default_for(category)
	if default_style != null:
		return default_style
	return _get_fallback_style()


func get_style_by_id(category: StringName, style_id: StringName) -> TerrainStyle:
	_ensure_index()
	var id_index: Dictionary = _category_index(_id_index, category)
	var style_value: Variant = id_index.get(String(style_id))
	if style_value is TerrainStyle:
		return style_value
	return null


func is_empty() -> bool:
	return (
		landuse.is_empty()
		and waterways.is_empty()
		and roads.is_empty()
		and buildings.is_empty()
		and default_landuse == null
		and default_waterway == null
		and default_road == null
		and default_building == null
	)


func invalidate_index() -> void:
	_index_dirty = true


## Appends default entries that are missing, preserving every existing style and value.
func add_missing_defaults() -> void:
	var defaults: MapStyle = create_default()
	var added: int = 0
	added += _merge_styles(landuse, defaults.landuse)
	added += _merge_styles(waterways, defaults.waterways)
	added += _merge_styles(roads, defaults.roads)
	added += _merge_styles(buildings, defaults.buildings)
	if default_landuse == null:
		default_landuse = _duplicate_style(defaults.default_landuse)
		added += 1
	if default_waterway == null:
		default_waterway = _duplicate_style(defaults.default_waterway)
		added += 1
	if default_road == null:
		default_road = _duplicate_style(defaults.default_road)
		added += 1
	if default_building == null:
		default_building = _duplicate_style(defaults.default_building)
		added += 1
	invalidate_index()
	emit_changed()
	print("MapStyle: added %d missing style entr%s." % [added, "y" if added == 1 else "ies"])


func _find_style(category: StringName, kind: String, surface: String) -> TerrainStyle:
	var category_index: Dictionary = _category_index(_kind_index, category)
	var surfaces_value: Variant = category_index.get(kind)
	if not (surfaces_value is Dictionary):
		return null
	var surfaces: Dictionary = surfaces_value
	var exact_value: Variant = surfaces.get(surface)
	if exact_value is TerrainStyle:
		return exact_value
	var base_value: Variant = surfaces.get("")
	if base_value is TerrainStyle:
		return base_value
	return null


func _merge_styles(target: Array[TerrainStyle], defaults: Array[TerrainStyle]) -> int:
	var existing: Dictionary = {}
	for style: TerrainStyle in target:
		if style != null:
			existing[_style_key(style)] = true
	var added: int = 0
	for style: TerrainStyle in defaults:
		if style == null:
			continue
		var key: String = _style_key(style)
		if existing.has(key):
			continue
		target.append(_duplicate_style(style))
		existing[key] = true
		added += 1
	return added


func _style_key(style: TerrainStyle) -> String:
	return "%s|%s" % [String(style.kind), normalize_surface(String(style.surface))]


func _duplicate_style(style: TerrainStyle) -> TerrainStyle:
	if style == null:
		return null
	return style.duplicate(true) as TerrainStyle


func _ensure_index() -> void:
	var sizes := Vector4i(landuse.size(), waterways.size(), roads.size(), buildings.size())
	if sizes != _indexed_sizes:
		_index_dirty = true
		_indexed_sizes = sizes
	if not _index_dirty:
		return
	_disconnect_indexed_styles()
	_kind_index.clear()
	_id_index.clear()
	_index_styles(&"landuse", landuse)
	_index_styles(&"waterways", waterways)
	_index_styles(&"roads", roads)
	_index_styles(&"buildings", buildings)
	_index_default(&"landuse", default_landuse)
	_index_default(&"waterways", default_waterway)
	_index_default(&"roads", default_road)
	_index_default(&"buildings", default_building)
	_index_dirty = false


func _index_styles(category: StringName, styles: Array[TerrainStyle]) -> void:
	var category_index: Dictionary = _category_index(_kind_index, category)
	var id_index: Dictionary = _category_index(_id_index, category)
	for style: TerrainStyle in styles:
		if style == null:
			continue
		var kind_key: String = String(style.kind)
		var surface_key: String = normalize_surface(String(style.surface))
		var surfaces: Dictionary = {}
		var surfaces_value: Variant = category_index.get(kind_key)
		if surfaces_value is Dictionary:
			surfaces = surfaces_value
		surfaces[surface_key] = style
		category_index[kind_key] = surfaces
		if not String(style.id).is_empty():
			id_index[String(style.id)] = style
		_track_style(style)
	_kind_index[category] = category_index
	_id_index[category] = id_index


func _index_default(category: StringName, style: TerrainStyle) -> void:
	if style == null:
		return
	var id_index: Dictionary = _category_index(_id_index, category)
	if not String(style.id).is_empty():
		id_index[String(style.id)] = style
	_id_index[category] = id_index
	_track_style(style)


func _category_index(index: Dictionary, category: StringName) -> Dictionary:
	var category_value: Variant = index.get(category)
	if category_value is Dictionary:
		return category_value
	return {}


func _track_style(style: TerrainStyle) -> void:
	if not _indexed_styles.has(style):
		_indexed_styles.append(style)
	if not style.changed.is_connected(_on_style_changed):
		style.changed.connect(_on_style_changed)


func _disconnect_indexed_styles() -> void:
	for style: TerrainStyle in _indexed_styles:
		if is_instance_valid(style) and style.changed.is_connected(_on_style_changed):
			style.changed.disconnect(_on_style_changed)
	_indexed_styles.clear()


func _on_style_changed() -> void:
	invalidate_index()


func _default_for(category: StringName) -> TerrainStyle:
	match category:
		&"landuse":
			return default_landuse
		&"waterways":
			return default_waterway
		&"roads":
			return default_road
		&"buildings":
			return default_building
	return null


func _get_fallback_style() -> TerrainStyle:
	if _fallback_style == null:
		_fallback_style = TerrainStyle.new()
		_fallback_style.id = &"fallback"
		_fallback_style.color = FALLBACK_COLOR
	return _fallback_style


static func normalize_surface(raw: String) -> String:
	var normalized: String = raw.to_lower().strip_edges()
	normalized = normalized.get_slice(";", 0).strip_edges()
	normalized = normalized.get_slice(":", 0).strip_edges()
	return normalized


static func _base_road_kind(kind: String) -> String:
	if kind.ends_with("_link"):
		return kind.trim_suffix("_link")
	return kind


static func create_default() -> MapStyle:
	var style := MapStyle.new()
	style.fill_defaults()
	return style


## Replaces every category and default style with the built-in palette.
func fill_defaults() -> void:
	landuse.assign([])
	waterways.assign([])
	buildings.assign([])
	for kind_value: Variant in LANDUSE_COLORS:
		var kind: StringName = StringName(str(kind_value))
		var color: Color = LANDUSE_COLORS[kind_value]
		landuse.append(_make_style(kind, kind, &"", color))
	for kind_value: Variant in WATERWAY_COLORS:
		var kind: StringName = StringName(str(kind_value))
		var color: Color = WATERWAY_COLORS[kind_value]
		waterways.append(_make_style(kind, kind, &"", color))
	for kind_value: Variant in ROAD_COLORS:
		var kind: StringName = StringName(str(kind_value))
		var color: Color = ROAD_COLORS[kind_value]
		roads.append(_make_style(kind, kind, &"", color))
	for road_kind: StringName in ROAD_SURFACE_VARIANT_KINDS:
		for surface_value: Variant in ROAD_SURFACE_COLORS:
			var surface: StringName = StringName(str(surface_value))
			var color: Color = ROAD_SURFACE_COLORS[surface_value]
			var variant_id: StringName = StringName("%s_%s" % [String(road_kind), String(surface)])
			roads.append(_make_style(variant_id, road_kind, surface, color))
	default_landuse = _make_style(&"default_landuse", &"", &"", Color("d8e0c8"))
	default_waterway = _make_style(&"default_waterway", &"", &"", Color("7fb3d5"))
	default_road = _make_style(&"default_road", &"", &"", Color("eeeeee"))
	default_building = _make_style(&"default_building", &"", &"", Color("b5a69a"))
	invalidate_index()
	emit_changed()


static func _make_style(id: StringName, kind: StringName, surface: StringName, color: Color) -> TerrainStyle:
	var style := TerrainStyle.new()
	style.id = id
	style.kind = kind
	style.surface = surface
	style.color = color
	return style
