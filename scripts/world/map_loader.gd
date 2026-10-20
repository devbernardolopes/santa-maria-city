class_name MapLoader
extends Node2D
## Loads res://data/map.json and draws every feature as a styled Polygon2D.

signal map_loaded(counts: Dictionary)

const MAP_PATH: String = "res://data/map.json"

@export var style: MapStyle = null

var map_size_m: Vector2 = Vector2.ZERO
var meta: Dictionary = {}
var is_loaded: bool = false

var _active_style: MapStyle = null
var _polygons_by_osm_id: Dictionary = {}


func _ready() -> void:
	_load_map.call_deferred()


func get_polygons(osm_id: String) -> Array[Polygon2D]:
	var polygons: Array[Polygon2D] = []
	if _polygons_by_osm_id.has(osm_id):
		polygons.assign(_polygons_by_osm_id[osm_id])
	return polygons


func _load_map() -> void:
	if is_loaded:
		return
	var file: FileAccess = FileAccess.open(MAP_PATH, FileAccess.READ)
	if file == null:
		push_error("MapLoader: could not open %s (error %s)." % [MAP_PATH, error_string(FileAccess.get_open_error())])
		return
	var json := JSON.new()
	var parse_error: Error = json.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		push_error("MapLoader: invalid JSON in %s at line %d: %s" % [MAP_PATH, json.get_error_line(), json.get_error_message()])
		return
	var parsed: Variant = json.data
	if not (parsed is Dictionary):
		push_error("MapLoader: %s must contain a JSON object." % MAP_PATH)
		return
	var data: Dictionary = parsed
	var required_keys: Array[String] = ["landuse", "waterways", "roads", "buildings", "meta"]
	for key: String in required_keys:
		if not data.has(key):
			push_error("MapLoader: %s is missing the '%s' key." % [MAP_PATH, key])
			return
	var layer_keys: Array[String] = ["landuse", "waterways", "roads", "buildings"]
	for key: String in layer_keys:
		if not (data[key] is Array):
			push_error("MapLoader: '%s' in %s must be an array." % [key, MAP_PATH])
			return
	var meta_value: Variant = data["meta"]
	if not (meta_value is Dictionary):
		push_error("MapLoader: 'meta' in %s must be an object." % MAP_PATH)
		return
	var meta_data: Dictionary = meta_value
	if not _read_meta(meta_data):
		return
	_active_style = style if style != null else MapStyle.create_default()
	_build_layer(data["landuse"], "Landuse", &"landuse")
	_build_layer(data["waterways"], "Waterways", &"waterways")
	_build_layer(data["roads"], "Roads", &"roads")
	_build_layer(data["buildings"], "Buildings", &"buildings")
	is_loaded = true
	var counts: Dictionary = {}
	var counts_value: Variant = meta["counts"]
	if counts_value is Dictionary:
		counts = counts_value
	map_loaded.emit(counts)


func _read_meta(meta_data: Dictionary) -> bool:
	var required_keys: Array[String] = ["size_m", "counts", "attribution"]
	for key: String in required_keys:
		if not meta_data.has(key):
			push_error("MapLoader: %s is missing 'meta.%s'." % [MAP_PATH, key])
			return false
	var size_value: Variant = meta_data["size_m"]
	if not (size_value is Array):
		push_error("MapLoader: 'meta.size_m' in %s must be an array." % MAP_PATH)
		return false
	var size_array: Array = size_value
	if size_array.size() < 2:
		push_error("MapLoader: 'meta.size_m' in %s must contain two numbers." % MAP_PATH)
		return false
	map_size_m = Vector2(float(size_array[0]), float(size_array[1]))
	var counts_value: Variant = meta_data["counts"]
	if not (counts_value is Dictionary):
		push_error("MapLoader: 'meta.counts' in %s must be an object." % MAP_PATH)
		return false
	var attribution_value: Variant = meta_data["attribution"]
	if not (attribution_value is String) or String(attribution_value).is_empty():
		push_error("MapLoader: 'meta.attribution' in %s must be a non-empty string." % MAP_PATH)
		return false
	meta = meta_data
	return true


func _build_layer(features: Array, layer_name: String, category: StringName) -> void:
	var layer := Node2D.new()
	layer.name = layer_name
	add_child(layer)
	for feature: Variant in features:
		if not (feature is Dictionary):
			continue
		var feature_data: Dictionary = feature
		var osm_id: String = str(feature_data.get("id", ""))
		var kind: String = str(feature_data.get("kind", ""))
		var polys_value: Variant = feature_data.get("polys")
		if not (polys_value is Array):
			continue
		var polys: Array = polys_value
		for polygon_rings: Variant in polys:
			if not (polygon_rings is Array):
				continue
			var rings: Array = polygon_rings
			if rings.is_empty():
				continue
			var outer_ring_value: Variant = rings[0]
			if not (outer_ring_value is Array):
				continue
			var points: PackedVector2Array = _ring_to_px(outer_ring_value)
			if points.size() < 3:
				continue
			var polygon := Polygon2D.new()
			polygon.polygon = points
			_apply_style(polygon, _active_style.get_style(category, kind))
			polygon.set_meta("osm_id", osm_id)
			polygon.set_meta("kind", kind)
			layer.add_child(polygon)
			_index_polygon(osm_id, polygon)


func _ring_to_px(ring: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point_value: Variant in ring:
		if not (point_value is Array):
			continue
		var point: Array = point_value
		if point.size() < 2:
			continue
		points.append(Units.to_px(Vector2(float(point[0]), float(point[1]))))
	return points


func _apply_style(polygon: Polygon2D, terrain_style: TerrainStyle) -> void:
	var texture: Texture2D = terrain_style.texture
	if texture == null:
		polygon.color = terrain_style.color
		return
	var tile_meters: float = maxf(terrain_style.meters_per_tile, 0.001)
	var pixels_per_tile: float = tile_meters * Units.PX_PER_METER
	polygon.texture = texture
	polygon.color = terrain_style.tint
	polygon.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	polygon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	polygon.uv = PackedVector2Array()
	polygon.texture_scale = Vector2.ONE * (float(texture.get_width()) / pixels_per_tile)


func _index_polygon(osm_id: String, polygon: Polygon2D) -> void:
	var polygons: Array[Polygon2D] = []
	if _polygons_by_osm_id.has(osm_id):
		polygons.assign(_polygons_by_osm_id[osm_id])
	polygons.append(polygon)
	_polygons_by_osm_id[osm_id] = polygons
