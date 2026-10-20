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

var _kind_index: Dictionary = {}
var _id_index: Dictionary = {}
var _index_dirty: bool = true
var _indexed_sizes: Vector4i = Vector4i(-1, -1, -1, -1)
var _indexed_styles: Array[TerrainStyle] = []
var _fallback_style: TerrainStyle = null


func get_style(category: StringName, kind: String, surface: String = "") -> TerrainStyle:
	_ensure_index()
	var normalized_surface: String = normalize_surface(surface)
	var category_index: Dictionary = _category_index(_kind_index, category)
	var surfaces: Dictionary = {}
	var surfaces_value: Variant = category_index.get(kind)
	if surfaces_value is Dictionary:
		surfaces = surfaces_value
	var exact_value: Variant = surfaces.get(normalized_surface)
	if exact_value is TerrainStyle:
		return exact_value
	var base_value: Variant = surfaces.get("")
	if base_value is TerrainStyle:
		return base_value
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


func invalidate_index() -> void:
	_index_dirty = true


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


static func create_default() -> MapStyle:
	var style := MapStyle.new()
	style.landuse.assign([
		_make_style(&"residential", &"residential", &"", Color("e3dccd")),
		_make_style(&"grass", &"grass", &"", Color("b8d98a")),
		_make_style(&"wood", &"wood", &"", Color("7fb069")),
		_make_style(&"pitch", &"pitch", &"", Color("9ccc7a")),
		_make_style(&"playground", &"playground", &"", Color("d9c8a0")),
	])
	style.default_landuse = _make_style(&"default_landuse", &"", &"", Color("d8e0c8"))
	style.default_waterway = _make_style(&"default_waterway", &"", &"", Color("7fb3d5"))
	style.roads.assign([
		_make_style(&"tertiary", &"tertiary", &"", Color("f2d98d")),
		_make_style(&"residential", &"residential", &"", Color("ffffff")),
		_make_style(&"service", &"service", &"", Color("f0f0f0")),
		_make_style(&"footway", &"footway", &"", Color("e0b8b0")),
	])
	var road_kinds: Array[StringName] = [&"service", &"residential", &"tertiary", &"unclassified"]
	for road_kind: StringName in road_kinds:
		for surface_value: Variant in ROAD_SURFACE_COLORS:
			var surface: StringName = StringName(str(surface_value))
			var color: Color = ROAD_SURFACE_COLORS[surface_value]
			var variant_id: StringName = StringName("%s_%s" % [String(road_kind), String(surface)])
			style.roads.append(_make_style(variant_id, road_kind, surface, color))
	style.default_road = _make_style(&"default_road", &"", &"", Color("eeeeee"))
	style.default_building = _make_style(&"default_building", &"", &"", Color("b5a69a"))
	return style


static func _make_style(id: StringName, kind: StringName, surface: StringName, color: Color) -> TerrainStyle:
	var style := TerrainStyle.new()
	style.id = id
	style.kind = kind
	style.surface = surface
	style.color = color
	return style
