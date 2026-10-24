class_name EntranceSpawner
extends Node
## Debug fallback for the entrance system.
##
## Entrances are authored as nodes under World/Objects/Entrances, so this spawner only adds
## a few placeholder doors near the player spawn in debug builds when the scene has no
## authored entrance yet. Nothing is written to disk.

const ENTRANCE_SCENE: PackedScene = preload("res://scenes/objects/entrance.tscn")

@export var debug_auto_count: int = 4

var _map: MapLoader = null
var _entrances_root: Node2D = null
var _spawned: Array[Entrance] = []


func _ready() -> void:
	var world: Node = get_parent()
	if world == null:
		return
	_map = world.get_node_or_null("Map") as MapLoader
	_entrances_root = world.get_node_or_null("Objects") as Node2D
	if _map == null or _entrances_root == null:
		push_error("EntranceSpawner: Map or Objects node not found; the debug fallback is disabled.")


## Clears previous debug doors, then places them only when the scene has no authored
## entrance. spawn_point_m only feeds the debug placement.
func spawn_entrances(spawn_point_m: Vector2) -> void:
	_clear_debug_entrances()
	if _map == null or _entrances_root == null:
		return
	if _count_authored() > 0:
		return
	if not OS.is_debug_build() or debug_auto_count <= 0:
		return
	var placed: int = 0
	for candidate: Dictionary in _nearest_buildings(spawn_point_m):
		if placed >= debug_auto_count:
			break
		var entrance: Entrance = _build_debug_entrance(candidate, placed + 1)
		if entrance == null:
			continue
		_entrances_root.add_child(entrance)
		_spawned.append(entrance)
		placed += 1


## Number of entrances authored in the scene; debug doors are not counted.
func _count_authored() -> int:
	var count: int = 0
	for child: Node in _entrances_root.get_children():
		if child is Entrance and not _spawned.has(child):
			count += 1
	return count


func _clear_debug_entrances() -> void:
	for entrance: Entrance in _spawned:
		if is_instance_valid(entrance):
			entrance.free()
	_spawned.clear()


## Every building with a cached ring, nearest center first.
func _nearest_buildings(spawn_point_m: Vector2) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for osm_id: String in _map.get_building_ids():
		var ring: PackedVector2Array = _map.get_building_ring_m(osm_id)
		if ring.size() < 3:
			continue
		var center: Vector2 = _ring_center_m(ring)
		candidates.append(
			{
				"id": osm_id,
				"center": center,
				"distance": spawn_point_m.distance_squared_to(center),
			}
		)
	candidates.sort_custom(_sort_candidates)
	return candidates


## Nearest first, OSM ID as the deterministic tie-break.
func _sort_candidates(a: Dictionary, b: Dictionary) -> bool:
	var distance_a: float = float(a["distance"])
	var distance_b: float = float(b["distance"])
	if distance_a == distance_b:
		return str(a["id"]) < str(b["id"])
	return distance_a < distance_b


## Door on the road-facing edge of the candidate building, or null when it cannot snap.
func _build_debug_entrance(candidate: Dictionary, index: int) -> Entrance:
	var building_id: String = String(candidate["id"])
	var ring: PackedVector2Array = _map.get_building_ring_m(building_id)
	if ring.size() < 3:
		return null
	var center_value: Variant = candidate.get("center")
	if not (center_value is Vector2):
		return null
	var road_point_m: Vector2 = _map.nearest_road_point_m(center_value)
	var snap: Dictionary = BuildingGeometry.snap_to_edge(ring, road_point_m)
	var position_value: Variant = snap.get("position")
	var normal_value: Variant = snap.get("normal")
	if not (position_value is Vector2) or not (normal_value is Vector2):
		return null
	var normal: Vector2 = normal_value
	if normal.length_squared() <= 0.0:
		return null
	var entrance: Entrance = ENTRANCE_SCENE.instantiate() as Entrance
	if entrance == null:
		return null
	var door_position_m: Vector2 = position_value
	entrance.name = "DebugEntrance%d" % index
	entrance.id = "debug_%d" % index
	entrance.building_osm_id = building_id
	entrance.position = Units.to_px(door_position_m)
	entrance.rotation = normal.angle()
	return entrance


func _ring_center_m(ring: PackedVector2Array) -> Vector2:
	var bounds := Rect2(ring[0], Vector2.ZERO)
	for point: Vector2 in ring:
		bounds = bounds.expand(point)
	return bounds.get_center()
