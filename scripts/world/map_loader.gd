@tool
class_name MapLoader
extends Node2D
## Loads res://data/map.json and draws every feature as a styled Polygon2D.

signal map_loaded(counts: Dictionary)
signal map_load_failed(message: String)

@export var map_path: String = "res://data/map.json"
const OVERRIDES_PATH: String = "res://data/overlays/style_overrides.json"
const OVERRIDES_VERSION: int = 1
const EDITOR_FRAME_MARGIN: float = 0.9
## Coarse index used by the HUD mini map. It deliberately references the generated polygons
## instead of creating a second copy of the city geometry.
const MINI_MAP_CELL_SIZE_M: float = 128.0

@export var style: MapStyle = null:
	set(value):
		if style == value:
			return
		style = value
		if is_inside_tree():
			rebuild()

## Draw the full map in the editor. Turn off for a fast, empty editor view.
@export var editor_preview: bool = true:
	set(value):
		if editor_preview == value:
			return
		editor_preview = value
		if Engine.is_editor_hint() and is_inside_tree():
			rebuild()

## 2D editor view used once on first open, in meters. Defaults to the original playtest area.
@export var editor_initial_view_m: Rect2 = Rect2(1721.9, 2995.3, 1118.8, 2136.5)

@export_tool_button("Rebuild map") var rebuild_button: Callable = rebuild

@export_tool_button("Frame full map") var frame_full_map_button: Callable = frame_full_map_editor

var map_size_m: Vector2 = Vector2.ZERO
var map_bounds_px: Rect2 = Rect2()
var meta: Dictionary = {}
var is_loaded: bool = false
## Runtime terrain index for the current map; null in the editor and before the map loads.
var terrain: TerrainQuery = null
## Last build timings and counts, for the headless benchmark and console diagnostics.
var build_stats: Dictionary = {}

var _active_style: MapStyle = null
var _polygons_by_osm_id: Dictionary = {}
var _layers: Array[Node2D] = []
var _overrides: Dictionary = {}
var _seen_osm_ids: Dictionary = {}
var _unknown_style_ids: Dictionary = {}
var _computed_bounds_px: Rect2 = Rect2()
var _has_computed_bounds: bool = false
var _road_lines_m: Array[PackedVector2Array] = []
var _road_features_m: Array[Dictionary] = []
var _building_rings_m: Dictionary = {}
var _building_collision: StaticBody2D = null
var _water_collision: StaticBody2D = null
var _collision_skip_count: int = 0
var _polygon_count: int = 0
var _collision_shape_count: int = 0
var _mini_map_entries: Array[Dictionary] = []
var _mini_map_cells: Dictionary = {}
static var _editor_auto_frame_attempted: bool = false


func _ready() -> void:
	rebuild.call_deferred()


func _exit_tree() -> void:
	terrain = null
	TerrainQuery.active = null


func rebuild() -> void:
	if not is_inside_tree():
		return
	_clear_generated()
	is_loaded = false
	map_bounds_px = Rect2()
	map_size_m = Vector2.ZERO
	meta = {}
	terrain = null
	TerrainQuery.active = null
	build_stats = {}
	if Engine.is_editor_hint() and not editor_preview:
		return
	if not Engine.is_editor_hint():
		terrain = TerrainQuery.new()
	_active_style = style if style != null else MapStyle.create_default()
	if style != null and style.is_empty():
		var style_path: String = style.resource_path
		if style_path.is_empty():
			style_path = "<unsaved MapStyle>"
		var warning_text: String = (
			"MapLoader: %s has no style entries; using fallback colors. "
			+ "Click 'Reset to defaults' in the MapStyle inspector."
		)
		push_warning(warning_text % style_path)
	_overrides = _read_overrides()
	if not _load_map():
		terrain = null
		map_load_failed.emit("The map could not be loaded.")
		return
	is_loaded = true
	if not Engine.is_editor_hint():
		var counts: Dictionary = {}
		var counts_value: Variant = meta.get("counts")
		if counts_value is Dictionary:
			counts = counts_value
		map_loaded.emit(counts)
	elif not _editor_auto_frame_attempted:
		_editor_auto_frame_attempted = _frame_editor_view_once()


func get_polygons(osm_id: String) -> Array[Polygon2D]:
	var polygons: Array[Polygon2D] = []
	if _polygons_by_osm_id.has(osm_id):
		polygons.assign(_polygons_by_osm_id[osm_id])
	return polygons


## Returns generated polygons intersecting bounds_m in normal map draw order. Each entry has
## `polygon` (Polygon2D) and `color` (the TerrainStyle base color, never its texture tint).
func get_mini_map_polygons(bounds_m: Rect2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if bounds_m.size.x <= 0.0 or bounds_m.size.y <= 0.0:
		return result
	var seen: Dictionary = {}
	var min_cell := Vector2i(
		floori(bounds_m.position.x / MINI_MAP_CELL_SIZE_M),
		floori(bounds_m.position.y / MINI_MAP_CELL_SIZE_M)
	)
	var max_cell := Vector2i(
		floori(bounds_m.end.x / MINI_MAP_CELL_SIZE_M),
		floori(bounds_m.end.y / MINI_MAP_CELL_SIZE_M)
	)
	for cell_y: int in range(min_cell.y, max_cell.y + 1):
		for cell_x: int in range(min_cell.x, max_cell.x + 1):
			var indices_value: Variant = _mini_map_cells.get(Vector2i(cell_x, cell_y), [])
			if not (indices_value is Array):
				continue
			for index_value: Variant in indices_value:
				var index: int = int(index_value)
				if seen.has(index) or index < 0 or index >= _mini_map_entries.size():
					continue
				seen[index] = true
				var entry: Dictionary = _mini_map_entries[index]
				var entry_bounds_value: Variant = entry.get("bounds_m")
				if entry_bounds_value is Rect2 and bounds_m.intersects(entry_bounds_value):
					result.append(entry)
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("order", 0)) < int(right.get("order", 0))
	)
	return result


func pick(world_point_px: Vector2) -> Dictionary:
	if not is_loaded:
		return {}
	var local_point: Vector2 = to_local(world_point_px)
	for layer_index: int in range(_layers.size() - 1, -1, -1):
		var layer: Node2D = _layers[layer_index]
		for child_index: int in range(layer.get_child_count() - 1, -1, -1):
			var polygon := layer.get_child(child_index) as Polygon2D
			if polygon == null:
				continue
			var bounds_value: Variant = polygon.get_meta("bounds_px", Rect2())
			if bounds_value is Rect2:
				var bounds: Rect2 = bounds_value
				if not bounds.has_point(local_point):
					continue
			if not Geometry2D.is_point_in_polygon(local_point, polygon.polygon):
				continue
			return _picked_info(polygon)
	return {}


func nearest_road_point_m(from_m: Vector2) -> Vector2:
	var nearest: Vector2 = from_m
	var best_distance: float = INF
	for line: PackedVector2Array in _road_lines_m:
		if line.size() < 2:
			continue
		for index: int in range(line.size() - 1):
			var candidate: Vector2 = Geometry2D.get_closest_point_to_segment(
				from_m, line[index], line[index + 1]
			)
			var distance: float = from_m.distance_squared_to(candidate)
			if distance < best_distance:
				best_distance = distance
				nearest = candidate
	return nearest


func get_road_lines_m() -> Array[PackedVector2Array]:
	var lines: Array[PackedVector2Array] = []
	lines.assign(_road_lines_m)
	return lines


## Runtime road metadata in meters: id, kind, width, and centerline.
func get_road_features_m() -> Array[Dictionary]:
	var features: Array[Dictionary] = []
	features.assign(_road_features_m)
	return features


## First outer ring of a building footprint in meters (runtime only); empty when unknown.
func get_building_ring_m(osm_id: String) -> PackedVector2Array:
	var ring_value: Variant = _building_rings_m.get(osm_id)
	if ring_value is PackedVector2Array:
		return ring_value
	return PackedVector2Array()


## Building OSM IDs with a cached ring, sorted for deterministic iteration.
func get_building_ids() -> Array[String]:
	var ids: Array[String] = []
	for key_value: Variant in _building_rings_m:
		ids.append(str(key_value))
	ids.sort()
	return ids


func _load_map() -> bool:
	var build_start_usec: int = Time.get_ticks_usec()
	var file: FileAccess = FileAccess.open(map_path, FileAccess.READ)
	if file == null:
		push_error(
			(
				"MapLoader: could not open %s (error %s)."
				% [map_path, error_string(FileAccess.get_open_error())]
			)
		)
		return false
	var json := JSON.new()
	var parse_error: Error = json.parse(file.get_as_text())
	file.close()
	var parse_end_usec: int = Time.get_ticks_usec()
	if parse_error != OK:
		push_error(
			(
				"MapLoader: invalid JSON in %s at line %d: %s"
				% [
					map_path,
					json.get_error_line(),
					json.get_error_message(),
				]
			)
		)
		return false
	var parsed: Variant = json.data
	if not (parsed is Dictionary):
		push_error("MapLoader: %s must contain a JSON object." % map_path)
		return false
	var data: Dictionary = parsed
	var required_keys: Array[String] = ["landuse", "waterways", "roads", "buildings", "meta"]
	for key: String in required_keys:
		if not data.has(key):
			push_error("MapLoader: %s is missing the '%s' key." % [map_path, key])
			return false
	var layer_keys: Array[String] = ["landuse", "waterways", "roads", "buildings"]
	for key: String in layer_keys:
		if not (data[key] is Array):
			push_error("MapLoader: '%s' in %s must be an array." % [key, map_path])
			return false
	var meta_value: Variant = data["meta"]
	if not (meta_value is Dictionary):
		push_error("MapLoader: 'meta' in %s must be an object." % map_path)
		return false
	var meta_data: Dictionary = meta_value
	if not _read_meta(meta_data):
		return false
	_computed_bounds_px = Rect2()
	_has_computed_bounds = false
	_seen_osm_ids.clear()
	_unknown_style_ids.clear()
	_polygon_count = 0
	_collision_shape_count = 0
	_build_layer(data["landuse"], "Landuse", &"landuse")
	_build_layer(data["waterways"], "Waterways", &"waterways")
	_build_layer(data["roads"], "Roads", &"roads")
	_build_layer(data["buildings"], "Buildings", &"buildings")
	var layers_end_usec: int = Time.get_ticks_usec()
	_collect_road_features(data["roads"])
	var collision_end_usec: int = layers_end_usec
	if not Engine.is_editor_hint():
		_build_collisions(data)
		collision_end_usec = Time.get_ticks_usec()
	if map_bounds_px.size == Vector2.ZERO and _has_computed_bounds:
		map_bounds_px = _computed_bounds_px
	_warn_unknown_overrides()
	if terrain != null:
		terrain.finalize(_meta_bounds_m())
		TerrainQuery.active = terrain
	var build_end_usec: int = Time.get_ticks_usec()
	build_stats = {
		"parse_ms": _usec_to_ms(parse_end_usec - build_start_usec),
		"layers_ms": _usec_to_ms(layers_end_usec - parse_end_usec),
		"collisions_ms": _usec_to_ms(collision_end_usec - layers_end_usec),
		"terrain_ms": _usec_to_ms(build_end_usec - collision_end_usec),
		"total_ms": _usec_to_ms(build_end_usec - build_start_usec),
		"features": _feature_count(data),
		"polygons": _polygon_count,
		"collision_shapes": _collision_shape_count,
		"terrain_entries": _polygon_count if terrain != null else 0,
		"editor": Engine.is_editor_hint(),
	}
	_log_build_stats()
	return true


func _usec_to_ms(usec: int) -> int:
	return int(round(float(usec) / 1000.0))


func _feature_count(data: Dictionary) -> int:
	var total: int = 0
	for key: String in ["landuse", "waterways", "roads", "buildings"]:
		var value: Variant = data.get(key)
		if value is Array:
			total += (value as Array).size()
	return total


func _log_build_stats() -> void:
	if not OS.is_debug_build() and not Engine.is_editor_hint():
		return
	print(
		(
			(
				"MapLoader: %d features, %d polygons, %d collision shapes in %d ms "
				+ "(parse %d, layers %d, collisions %d, terrain %d)."
			)
			% [
				int(build_stats.get("features", 0)),
				int(build_stats.get("polygons", 0)),
				int(build_stats.get("collision_shapes", 0)),
				int(build_stats.get("total_ms", 0)),
				int(build_stats.get("parse_ms", 0)),
				int(build_stats.get("layers_ms", 0)),
				int(build_stats.get("collisions_ms", 0)),
				int(build_stats.get("terrain_ms", 0)),
			]
		)
	)


func _read_meta(meta_data: Dictionary) -> bool:
	var required_keys: Array[String] = ["size_m", "counts", "attribution"]
	for key: String in required_keys:
		if not meta_data.has(key):
			push_error("MapLoader: %s is missing 'meta.%s'." % [map_path, key])
			return false
	var size_value: Variant = meta_data["size_m"]
	if not (size_value is Array):
		push_error("MapLoader: 'meta.size_m' in %s must be an array." % map_path)
		return false
	var size_array: Array = size_value
	if size_array.size() < 2:
		push_error("MapLoader: 'meta.size_m' in %s must contain two numbers." % map_path)
		return false
	map_size_m = Vector2(float(size_array[0]), float(size_array[1]))
	var counts_value: Variant = meta_data["counts"]
	if not (counts_value is Dictionary):
		push_error("MapLoader: 'meta.counts' in %s must be an object." % map_path)
		return false
	var attribution_value: Variant = meta_data["attribution"]
	if not (attribution_value is String) or String(attribution_value).is_empty():
		push_error("MapLoader: 'meta.attribution' in %s must be a non-empty string." % map_path)
		return false
	meta = meta_data
	map_bounds_px = Rect2()
	var bounds_value: Variant = meta_data.get("bounds_m")
	if bounds_value != null:
		if not _parse_bounds(bounds_value):
			push_warning("MapLoader: ignoring invalid 'meta.bounds_m' in %s." % map_path)
	return true


func _parse_bounds(value: Variant) -> bool:
	if not (value is Array):
		return false
	var bounds: Array = value
	if bounds.size() != 4:
		return false
	for component: Variant in bounds:
		if not _is_number(component):
			return false
	var min_m := Vector2(float(bounds[0]), float(bounds[1]))
	var max_m := Vector2(float(bounds[2]), float(bounds[3]))
	if max_m.x < min_m.x or max_m.y < min_m.y:
		return false
	map_bounds_px = Rect2(Units.to_px(min_m), Units.to_px(max_m - min_m))
	return true


## meta.bounds_m as meters; Rect2() when missing or invalid (the caller falls back).
func _meta_bounds_m() -> Rect2:
	var bounds_value: Variant = meta.get("bounds_m")
	if not (bounds_value is Array):
		return Rect2()
	var bounds: Array = bounds_value
	if bounds.size() != 4:
		return Rect2()
	for component: Variant in bounds:
		if not _is_number(component):
			return Rect2()
	var min_m := Vector2(float(bounds[0]), float(bounds[1]))
	var max_m := Vector2(float(bounds[2]), float(bounds[3]))
	if max_m.x <= min_m.x or max_m.y <= min_m.y:
		return Rect2()
	return Rect2(min_m, max_m - min_m)


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _build_layer(features: Array, layer_name: String, category: StringName) -> void:
	var runtime: bool = not Engine.is_editor_hint()
	var layer := Node2D.new()
	layer.name = layer_name
	add_child(layer)
	_layers.append(layer)
	for feature: Variant in features:
		if not (feature is Dictionary):
			continue
		var feature_data: Dictionary = feature
		var osm_id: String = str(feature_data.get("id", ""))
		var kind: String = str(feature_data.get("kind", ""))
		var tags: Dictionary = {}
		var tags_value: Variant = feature_data.get("tags")
		if tags_value is Dictionary:
			tags = tags_value
		if not osm_id.is_empty():
			_seen_osm_ids[osm_id] = true
		var raw_surface: String = str(tags.get("surface", ""))
		var surface: String = MapStyle.normalize_surface(raw_surface)
		var terrain_style: TerrainStyle = _resolve_style(category, osm_id, kind, raw_surface)
		var style_id: String = String(terrain_style.id)
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
			if runtime and category == &"buildings" and not osm_id.is_empty():
				if not _building_rings_m.has(osm_id):
					var ring_m: PackedVector2Array = _line_to_m(outer_ring_value)
					if ring_m.size() >= 3:
						_building_rings_m[osm_id] = ring_m
			var polygon := Polygon2D.new()
			polygon.polygon = points
			_apply_style(polygon, terrain_style)
			polygon.set_meta("osm_id", osm_id)
			polygon.set_meta("category", String(category))
			polygon.set_meta("kind", kind)
			polygon.set_meta("surface", surface)
			polygon.set_meta("style_id", style_id)
			polygon.set_meta("mini_map_color", terrain_style.color)
			if runtime:
				polygon.set_meta("tags", tags)
				polygon.set_meta("bounds_px", _bounds_of(points))
			layer.add_child(polygon)
			_polygon_count += 1
			if runtime:
				_register_mini_map_polygon(polygon, terrain_style.color, _bounds_of(points))
				_index_polygon(osm_id, polygon)
			_expand_computed_bounds(points)
			if terrain != null:
				terrain.add_polygon(
					_points_to_m(points),
					category,
					StringName(kind),
					StringName(surface),
					StringName(style_id),
					osm_id
				)


func _resolve_style(
	category: StringName, osm_id: String, kind: String, raw_surface: String
) -> TerrainStyle:
	var terrain_style: TerrainStyle = null
	if not osm_id.is_empty() and _overrides.has(osm_id):
		var override_id: StringName = StringName(str(_overrides[osm_id]))
		terrain_style = _active_style.get_style_by_id(category, override_id)
		if terrain_style == null:
			_unknown_style_ids[String(override_id)] = true
	if terrain_style == null:
		terrain_style = _active_style.get_style(category, kind, raw_surface)
	return terrain_style


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


func _points_to_m(points_px: PackedVector2Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point: Vector2 in points_px:
		points.append(Vector2(Units.px_to_m(point.x), Units.px_to_m(point.y)))
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


func _bounds_of(points: PackedVector2Array) -> Rect2:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	return bounds


func _expand_computed_bounds(points: PackedVector2Array) -> void:
	for point: Vector2 in points:
		if not _has_computed_bounds:
			_computed_bounds_px = Rect2(point, Vector2.ZERO)
			_has_computed_bounds = true
		else:
			_computed_bounds_px = _computed_bounds_px.expand(point)


func _index_polygon(osm_id: String, polygon: Polygon2D) -> void:
	var polygons: Array[Polygon2D] = []
	if _polygons_by_osm_id.has(osm_id):
		polygons.assign(_polygons_by_osm_id[osm_id])
	polygons.append(polygon)
	_polygons_by_osm_id[osm_id] = polygons


func _register_mini_map_polygon(polygon: Polygon2D, color: Color, bounds_px: Rect2) -> void:
	var bounds_m := Rect2(Units.to_m(bounds_px.position), Units.to_m(bounds_px.size))
	var entry: Dictionary = {
		"polygon": polygon,
		"color": color,
		"bounds_m": bounds_m,
		"order": _mini_map_entries.size(),
	}
	var index: int = _mini_map_entries.size()
	_mini_map_entries.append(entry)
	var min_cell := Vector2i(
		floori(bounds_m.position.x / MINI_MAP_CELL_SIZE_M),
		floori(bounds_m.position.y / MINI_MAP_CELL_SIZE_M)
	)
	var max_cell := Vector2i(
		floori(bounds_m.end.x / MINI_MAP_CELL_SIZE_M),
		floori(bounds_m.end.y / MINI_MAP_CELL_SIZE_M)
	)
	for cell_y: int in range(min_cell.y, max_cell.y + 1):
		for cell_x: int in range(min_cell.x, max_cell.x + 1):
			var key := Vector2i(cell_x, cell_y)
			var indices: Array[int] = []
			var existing_value: Variant = _mini_map_cells.get(key)
			if existing_value is Array:
				indices.assign(existing_value)
			indices.append(index)
			_mini_map_cells[key] = indices


func _picked_info(polygon: Polygon2D) -> Dictionary:
	var tags: Dictionary = {}
	var tags_value: Variant = polygon.get_meta("tags", {})
	if tags_value is Dictionary:
		tags = tags_value
	var world_points := PackedVector2Array()
	for point: Vector2 in polygon.polygon:
		world_points.append(polygon.to_global(point))
	return {
		"id": str(polygon.get_meta("osm_id", "")),
		"category": str(polygon.get_meta("category", "")),
		"kind": str(polygon.get_meta("kind", "")),
		"surface": str(polygon.get_meta("surface", "")),
		"style_id": str(polygon.get_meta("style_id", "")),
		"tags": tags,
		"points": world_points,
	}


func _read_overrides() -> Dictionary:
	if not FileAccess.file_exists(OVERRIDES_PATH):
		return {}
	var file: FileAccess = FileAccess.open(OVERRIDES_PATH, FileAccess.READ)
	if file == null:
		push_warning("MapLoader: could not open %s; ignoring style overrides." % OVERRIDES_PATH)
		return {}
	var json := JSON.new()
	var parse_error: Error = json.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		push_warning("MapLoader: invalid JSON in %s; ignoring style overrides." % OVERRIDES_PATH)
		return {}
	var parsed: Variant = json.data
	if not (parsed is Dictionary):
		push_warning(
			"MapLoader: %s must contain a JSON object; ignoring style overrides." % OVERRIDES_PATH
		)
		return {}
	var data: Dictionary = parsed
	var version_value: Variant = data.get("version")
	if not _is_number(version_value) or int(version_value) != OVERRIDES_VERSION:
		push_warning(
			"MapLoader: unsupported %s version; ignoring style overrides." % OVERRIDES_PATH
		)
		return {}
	var overrides_value: Variant = data.get("overrides")
	if not (overrides_value is Dictionary):
		push_warning(
			(
				"MapLoader: %s is missing an 'overrides' object; ignoring style overrides."
				% OVERRIDES_PATH
			)
		)
		return {}
	var overrides_data: Dictionary = overrides_value
	var result: Dictionary = {}
	for key_value: Variant in overrides_data:
		if not (key_value is String):
			continue
		var value: Variant = overrides_data[key_value]
		if value is String:
			result[String(key_value)] = String(value)
	return result


func _warn_unknown_overrides() -> void:
	var unknown_osm_ids: Array[String] = []
	for key_value: Variant in _overrides:
		var osm_id: String = str(key_value)
		if not _seen_osm_ids.has(osm_id):
			unknown_osm_ids.append(osm_id)
	unknown_osm_ids.sort()
	var unknown_styles: Array[String] = []
	for key_value: Variant in _unknown_style_ids:
		unknown_styles.append(str(key_value))
	unknown_styles.sort()
	if unknown_osm_ids.is_empty() and unknown_styles.is_empty():
		return
	var messages: PackedStringArray = []
	if not unknown_osm_ids.is_empty():
		messages.append("unknown OSM IDs: %s" % ", ".join(PackedStringArray(unknown_osm_ids)))
	if not unknown_styles.is_empty():
		messages.append("unknown style IDs: %s" % ", ".join(PackedStringArray(unknown_styles)))
	push_warning("MapLoader: %s: %s" % [OVERRIDES_PATH, " | ".join(messages)])


func _collect_road_features(features: Array) -> void:
	_road_lines_m.clear()
	_road_features_m.clear()
	for feature_value: Variant in features:
		if not (feature_value is Dictionary):
			continue
		var feature_data: Dictionary = feature_value
		var line_value: Variant = feature_data.get("line")
		if not (line_value is Array):
			continue
		var line: PackedVector2Array = _line_to_m(line_value)
		if line.size() < 2:
			continue
		_road_lines_m.append(line)
		var width_value: Variant = feature_data.get("width")
		var width: float = float(width_value) if _is_number(width_value) else 0.0
		(
			_road_features_m
			. append(
				{
					"id": str(feature_data.get("id", "")),
					"kind": StringName(str(feature_data.get("kind", ""))),
					"width": width,
					"line": line,
				}
			)
		)


func _line_to_m(line: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point_value: Variant in line:
		if not (point_value is Array):
			continue
		var point: Array = point_value
		if point.size() < 2:
			continue
		if not _is_number(point[0]) or not _is_number(point[1]):
			continue
		points.append(Vector2(float(point[0]), float(point[1])))
	return points


func _build_collisions(data: Dictionary) -> void:
	_building_collision = _create_collision_body("BuildingCollision")
	_water_collision = _create_collision_body("WaterCollision")
	_build_collision_shapes(data["buildings"], _building_collision, false)
	_build_collision_shapes(data["landuse"], _water_collision, true)
	if _collision_skip_count > 0:
		push_warning("MapLoader: skipped %d invalid collision polygon(s)." % _collision_skip_count)


func _create_collision_body(body_name: String) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = body_name
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	add_child(body)
	return body


func _build_collision_shapes(features: Array, body: StaticBody2D, water_only: bool) -> void:
	for feature_value: Variant in features:
		if not (feature_value is Dictionary):
			continue
		var feature_data: Dictionary = feature_value
		if water_only:
			var kind := StringName(str(feature_data.get("kind", "")))
			if not TerrainSample.is_water_landuse(&"landuse", kind):
				continue
		var osm_id: String = str(feature_data.get("id", ""))
		for points: PackedVector2Array in _outer_rings_px(feature_data):
			_add_collision_polygon(body, points, osm_id)


func _outer_rings_px(feature_data: Dictionary) -> Array[PackedVector2Array]:
	var rings_px: Array[PackedVector2Array] = []
	var polys_value: Variant = feature_data.get("polys")
	if not (polys_value is Array):
		return rings_px
	var polys: Array = polys_value
	for polygon_rings_value: Variant in polys:
		if not (polygon_rings_value is Array):
			continue
		var rings: Array = polygon_rings_value
		if rings.is_empty():
			continue
		var outer_ring_value: Variant = rings[0]
		if not (outer_ring_value is Array):
			continue
		var points: PackedVector2Array = _ring_to_px(outer_ring_value)
		if points.size() >= 3:
			rings_px.append(points)
	return rings_px


func _add_collision_polygon(
	body: StaticBody2D, points_px: PackedVector2Array, osm_id: String
) -> void:
	if points_px.size() < 3 or Geometry2D.triangulate_polygon(points_px).is_empty():
		_collision_skip_count += 1
		return
	var polygon := CollisionPolygon2D.new()
	polygon.build_mode = CollisionPolygon2D.BUILD_SOLIDS
	polygon.polygon = points_px
	polygon.set_meta("osm_id", osm_id)
	body.add_child(polygon)
	_collision_shape_count += 1


func _clear_generated() -> void:
	for layer: Node2D in _layers:
		if is_instance_valid(layer):
			layer.free()
	_layers.clear()
	_polygons_by_osm_id.clear()
	_computed_bounds_px = Rect2()
	_has_computed_bounds = false
	_seen_osm_ids.clear()
	_unknown_style_ids.clear()
	_road_lines_m.clear()
	_road_features_m.clear()
	_building_rings_m.clear()
	_collision_skip_count = 0
	_polygon_count = 0
	_collision_shape_count = 0
	_mini_map_entries.clear()
	_mini_map_cells.clear()
	if is_instance_valid(_building_collision):
		_building_collision.free()
	_building_collision = null
	if is_instance_valid(_water_collision):
		_water_collision.free()
	_water_collision = null


func frame_full_map_editor() -> void:
	if not Engine.is_editor_hint() or not is_loaded:
		return
	_fit_editor_view(map_bounds_px)


func _frame_editor_view_once() -> bool:
	if not Engine.is_editor_hint():
		return false
	if map_bounds_px.size.x <= 0.0 or map_bounds_px.size.y <= 0.0:
		return false
	var editor_interface: Object = Engine.get_singleton(&"EditorInterface") as Object
	if editor_interface == null:
		return false
	var viewport_value: Variant = editor_interface.call(&"get_editor_viewport_2d")
	var viewport := viewport_value as SubViewport
	if viewport == null:
		return false
	var view_rect: Rect2 = viewport.get_visible_rect()
	if view_rect.size.x <= 0.0 or view_rect.size.y <= 0.0:
		return false
	var target_bounds: Rect2 = map_bounds_px
	if editor_initial_view_m.size.x > 0.0 and editor_initial_view_m.size.y > 0.0:
		target_bounds = Rect2(
			Units.to_px(editor_initial_view_m.position), Units.to_px(editor_initial_view_m.size)
		)
	var visible_world: Rect2 = viewport.global_canvas_transform.affine_inverse() * view_rect
	if visible_world.intersects(target_bounds):
		return true
	_fit_editor_view(target_bounds)
	return true


func _fit_editor_view(bounds_px: Rect2) -> bool:
	if not Engine.is_editor_hint():
		return false
	if bounds_px.size.x <= 0.0 or bounds_px.size.y <= 0.0:
		return false
	var editor_interface: Object = Engine.get_singleton(&"EditorInterface") as Object
	if editor_interface == null:
		return false
	var viewport_value: Variant = editor_interface.call(&"get_editor_viewport_2d")
	var viewport := viewport_value as SubViewport
	if viewport == null:
		return false
	var view_rect: Rect2 = viewport.get_visible_rect()
	if view_rect.size.x <= 0.0 or view_rect.size.y <= 0.0:
		return false
	var fit_zoom_x: float = view_rect.size.x / bounds_px.size.x
	var fit_zoom_y: float = view_rect.size.y / bounds_px.size.y
	var fit_zoom: float = minf(fit_zoom_x, fit_zoom_y) * EDITOR_FRAME_MARGIN
	fit_zoom = clampf(fit_zoom, 0.0001, 64.0)
	var origin: Vector2 = view_rect.size * 0.5 - bounds_px.get_center() * fit_zoom
	viewport.global_canvas_transform = Transform2D(0.0, Vector2(fit_zoom, fit_zoom), 0.0, origin)
	return true
