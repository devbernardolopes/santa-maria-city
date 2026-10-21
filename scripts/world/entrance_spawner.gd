class_name EntranceSpawner
extends Node
## Spawns Entrance nodes from res://data/overlays/entrances.json, snapped to footprints.

const ENTRANCES_PATH: String = "res://data/overlays/entrances.json"
const ENTRANCES_VERSION: int = 1
const ENTRANCE_SCENE: PackedScene = preload("res://scenes/objects/entrance.tscn")
const ENTRANCE_SCRIPT: Script = preload("res://scripts/objects/entrance.gd")
const ENTRANCE_DATA_SCRIPT: Script = preload("res://resources/world/entrance_data.gd")
const BUILDING_GEOMETRY: Script = preload("res://scripts/world/building_geometry.gd")

@export var debug_auto_count: int = 4

var _map: MapLoader = null
var _objects: Node2D = null
var _entrances: Array[Entrance] = []
var _report_invalid: int = 0
var _report_duplicates: Array[String] = []
var _report_unknown: Array[String] = []


func _ready() -> void:
	_map = get_parent().get_node_or_null("Map") as MapLoader
	_objects = get_parent().get_node_or_null("Objects") as Node2D
	if _map == null or _objects == null:
		push_error("EntranceSpawner: Map or Objects node not found; entrance spawning is disabled.")


## Clears previous entrances, then spawns every valid file entry (or debug auto entrances
## when the file has zero entries). spawn_point_m only feeds the auto placement.
func spawn_entrances(spawn_point_m: Vector2) -> void:
	_clear_entrances()
	if _map == null or _objects == null:
		return
	var sources: Array = _read_sources()
	if sources.is_empty() and OS.is_debug_build() and debug_auto_count > 0:
		sources = _auto_sources(spawn_point_m)
	for source in sources:
		_spawn(source)
	_warn_spawn_problems()


func _clear_entrances() -> void:
	for entrance: Entrance in _entrances:
		if is_instance_valid(entrance):
			entrance.free()
	_entrances.clear()
	_report_invalid = 0
	_report_duplicates.clear()
	_report_unknown.clear()


## Valid entries in file order; problems are aggregated and reported after spawning.
func _read_sources() -> Array:
	var sources: Array = []
	var data: Dictionary = _read_file()
	if data.is_empty():
		return sources
	var entries_value: Variant = data.get("entrances")
	if not (entries_value is Array):
		push_warning("EntranceSpawner: '%s' has no 'entrances' array; no file entrances spawned." % ENTRANCES_PATH)
		return sources
	var entries: Array = entries_value
	var seen_ids: Dictionary = {}
	for index: int in range(entries.size()):
		if not (entries[index] is Dictionary):
			_report_invalid += 1
			continue
		var source: Resource = ENTRANCE_DATA_SCRIPT.new().from_dict(entries[index]) if ENTRANCE_DATA_SCRIPT != null else null
		if source == null:
			# try global class if available
			source = EntranceData.from_dict(entries[index])
		if source == null:
			_report_invalid += 1
			continue
		if seen_ids.has(source.id):
			_report_duplicates.append(source.id)
			continue
		seen_ids[source.id] = true
		sources.append(source)
	return sources


## Readable + version-checked file data; empty when missing or broken (with one warning).
func _read_file() -> Dictionary:
	if not FileAccess.file_exists(ENTRANCES_PATH):
		return {}
	var file: FileAccess = FileAccess.open(ENTRANCES_PATH, FileAccess.READ)
	if file == null:
		push_warning("EntranceSpawner: could not open %s; no file entrances spawned." % ENTRANCES_PATH)
		return {}
	var json := JSON.new()
	var parse_error: Error = json.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		push_warning("EntranceSpawner: invalid JSON in %s at line %d; no file entrances spawned." % [
			ENTRANCES_PATH, json.get_error_line(),
		])
		return {}
	var parsed: Variant = json.data
	if not (parsed is Dictionary):
		push_warning("EntranceSpawner: %s must contain a JSON object; no file entrances spawned." % ENTRANCES_PATH)
		return {}
	var data: Dictionary = parsed
	var version_value: Variant = data.get("version")
	if not _is_number(version_value) or int(version_value) != ENTRANCES_VERSION:
		push_warning("EntranceSpawner: unsupported %s version; no file entrances spawned." % ENTRANCES_PATH)
		return {}
	return data


## Debug fallback: the buildings closest to the spawn point, door on the road-facing edge.
func _auto_sources(spawn_point_m: Vector2) -> Array:
	var candidates: Array[Dictionary] = []
	for osm_id: String in _map.get_building_ids():
		var ring: PackedVector2Array = _map.get_building_ring_m(osm_id)
		if ring.size() < 3:
			continue
		var center: Vector2 = _ring_center_m(ring)
		candidates.append({
			"id": osm_id,
			"center": center,
			"distance": spawn_point_m.distance_squared_to(center),
		})
	candidates.sort_custom(_sort_candidates)
	var sources: Array[EntranceData] = []
	for index: int in range(mini(debug_auto_count, candidates.size())):
		var candidate: Dictionary = candidates[index]
		var source := EntranceData.new()
		source.id = "auto_%d" % (index + 1)
		source.building_osm_id = str(candidate["id"])
		var center_value: Variant = candidate["center"]
		if center_value is Vector2:
			source.position_m = _map.nearest_road_point_m(center_value)
		sources.append(source)
	return sources


## Nearest first, OSM ID as the deterministic tie-break.
func _sort_candidates(a: Dictionary, b: Dictionary) -> bool:
	var distance_a: float = float(a["distance"])
	var distance_b: float = float(b["distance"])
	if distance_a == distance_b:
		return str(a["id"]) < str(b["id"])
	return distance_a < distance_b


func _spawn(source: Resource) -> void:
	var ring: PackedVector2Array = _map.get_building_ring_m(source.building_osm_id)
	if ring.size() < 3:
		_report_unknown.append(source.building_osm_id)
		return
	var snap: Dictionary = {}
	var geom := BuildingGeometry
	snap = geom.snap_to_edge(ring, source.position_m)
	var position_value: Variant = snap.get("position")
	var normal_value: Variant = snap.get("normal")
	if not (position_value is Vector2) or not (normal_value is Vector2):
		_report_invalid += 1
		return
	var normal: Vector2 = normal_value
	if normal.length_squared() <= 0.0:
		_report_invalid += 1
		return
	source.position_m = position_value
	source.normal = normal
	var entrance := ENTRANCE_SCENE.instantiate() as Node
	if entrance == null:
		push_warning("EntranceSpawner: could not instantiate %s; skipped '%s'." % [ENTRANCE_SCENE.resource_path, source.id])
		return
	entrance.set("data", source)
	entrance.position = Units.to_px(source.get("position_m"))
	_objects.add_child(entrance)
	_entrances.append(entrance)


func _warn_spawn_problems() -> void:
	if _report_invalid == 0 and _report_duplicates.is_empty() and _report_unknown.is_empty():
		return
	var messages: PackedStringArray = []
	if _report_invalid > 0:
		messages.append("invalid entries: %d" % _report_invalid)
	if not _report_duplicates.is_empty():
		_report_duplicates.sort()
		messages.append("duplicate ids: %s" % ", ".join(PackedStringArray(_report_duplicates)))
	if not _report_unknown.is_empty():
		_report_unknown.sort()
		messages.append("unknown building IDs: %s" % ", ".join(PackedStringArray(_report_unknown)))
	push_warning("EntranceSpawner: %s: %s" % [ENTRANCES_PATH, " | ".join(messages)])


func _ring_center_m(ring: PackedVector2Array) -> Vector2:
	var bounds := Rect2(ring[0], Vector2.ZERO)
	for point: Vector2 in ring:
		bounds = bounds.expand(point)
	return bounds.get_center()


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
