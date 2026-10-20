class_name MapStyle
extends Resource
## Data-driven appearance for every map layer, with fallbacks to category defaults.

const FALLBACK_COLOR: Color = Color("b0b0b0")

@export var landuse: Array[TerrainStyle] = []
@export var waterways: Array[TerrainStyle] = []
@export var roads: Array[TerrainStyle] = []
@export var buildings: Array[TerrainStyle] = []

@export var default_landuse: TerrainStyle = null
@export var default_waterway: TerrainStyle = null
@export var default_road: TerrainStyle = null
@export var default_building: TerrainStyle = null

var _kind_index: Dictionary = {}
var _index_built: bool = false
var _fallback_style: TerrainStyle = null


func get_style(category: StringName, kind: String) -> TerrainStyle:
	_ensure_index()
	var category_styles: Dictionary = {}
	var stored_category: Variant = _kind_index.get(category)
	if stored_category is Dictionary:
		category_styles = stored_category
	var stored_style: Variant = category_styles.get(kind)
	if stored_style is TerrainStyle:
		return stored_style
	var default_style: TerrainStyle = _default_for(category)
	if default_style != null:
		return default_style
	return _get_fallback_style()


func _ensure_index() -> void:
	if _index_built:
		return
	_kind_index.clear()
	_index_styles(&"landuse", landuse)
	_index_styles(&"waterways", waterways)
	_index_styles(&"roads", roads)
	_index_styles(&"buildings", buildings)
	_index_built = true


func _index_styles(category: StringName, styles: Array[TerrainStyle]) -> void:
	var category_styles: Dictionary = {}
	for style: TerrainStyle in styles:
		if style == null:
			continue
		category_styles[String(style.kind)] = style
	_kind_index[category] = category_styles


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
		_fallback_style.color = FALLBACK_COLOR
	return _fallback_style


static func create_default() -> MapStyle:
	var style := MapStyle.new()
	style.landuse.assign([
		_make_style(&"residential", Color("e3dccd")),
		_make_style(&"grass", Color("b8d98a")),
		_make_style(&"wood", Color("7fb069")),
		_make_style(&"pitch", Color("9ccc7a")),
		_make_style(&"playground", Color("d9c8a0")),
	])
	style.default_landuse = _make_style(&"", Color("d8e0c8"))
	style.default_waterway = _make_style(&"", Color("7fb3d5"))
	style.roads.assign([
		_make_style(&"tertiary", Color("f2d98d")),
		_make_style(&"residential", Color("ffffff")),
		_make_style(&"service", Color("f0f0f0")),
		_make_style(&"footway", Color("e0b8b0")),
	])
	style.default_road = _make_style(&"", Color("eeeeee"))
	style.default_building = _make_style(&"", Color("b5a69a"))
	return style


static func _make_style(kind: StringName, color: Color) -> TerrainStyle:
	var style := TerrainStyle.new()
	style.kind = kind
	style.color = color
	return style
