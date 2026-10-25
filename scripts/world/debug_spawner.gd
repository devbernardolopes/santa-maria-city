class_name DebugSpawner
extends Node
## Spawns debug NPCs on road centerlines near the player.
##
## npc_count is meant to measure what the player can actually see, so the default
## radius keeps every NPC inside the camera view. A radius of 0 or less disables
## the filter and spawns across the whole imported map, like the old behaviour.

const NPC_SCENE: PackedScene = preload("res://scenes/entities/entity.tscn")

@export var npc_count: int = 8
## Shared look for the debug NPCs; null leaves them as placeholder bodies.
@export var npc_animation_set: EntityAnimationSet = null
## Road segments within this distance of the player are valid spawn spots.
@export var spawn_radius_m: float = 120.0

var _map: MapLoader = null
var _objects: Node2D = null
var _npcs: Array[Entity] = []


func _ready() -> void:
	_map = get_parent().get_node_or_null("Map") as MapLoader
	_objects = get_parent().get_node_or_null("Objects") as Node2D
	if _map == null or _objects == null:
		push_error("DebugSpawner: Map or Objects node not found; NPC spawning is disabled.")


func spawn_npcs(seed_value: int, origin_m: Vector2) -> void:
	_clear_npcs()
	if _map == null or _objects == null or npc_count <= 0:
		return
	var segments: Array[PackedVector2Array] = _collect_segments_m(origin_m)
	if segments.is_empty():
		segments.append(PackedVector2Array([_map.nearest_road_point_m(origin_m)]))
		push_warning(
			(
				"DebugSpawner: no road within %d m of the player; using the nearest road."
				% roundi(spawn_radius_m)
			)
		)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for _npc_index: int in range(npc_count):
		var segment: PackedVector2Array = segments[rng.randi_range(0, segments.size() - 1)]
		var point_m: Vector2 = segment[0]
		if segment.size() > 1:
			point_m = segment[0].lerp(segment[1], rng.randf())
		var npc := NPC_SCENE.instantiate() as Entity
		if npc == null:
			continue
		npc.data = EntityData.create_random(rng)
		npc.data.animation_set = npc_animation_set
		var controller := WanderController.new()
		controller.random_seed = rng.randi()
		npc.set_controller(controller)
		npc.position = Units.to_px(point_m)
		_objects.add_child(npc)
		_npcs.append(npc)


## Road segments in meters whose midpoint lies within spawn_radius_m of origin_m.
## A non-positive radius keeps every segment.
func _collect_segments_m(origin_m: Vector2) -> Array[PackedVector2Array]:
	var segments: Array[PackedVector2Array] = []
	if _map == null:
		return segments
	var radius_squared_m: float = spawn_radius_m * spawn_radius_m
	var filter_by_radius: bool = spawn_radius_m > 0.0
	for line: PackedVector2Array in _map.get_road_lines_m():
		if line.size() < 2:
			continue
		for index: int in range(line.size() - 1):
			var start_m: Vector2 = line[index]
			var end_m: Vector2 = line[index + 1]
			if filter_by_radius:
				var midpoint_m: Vector2 = (start_m + end_m) * 0.5
				if midpoint_m.distance_squared_to(origin_m) > radius_squared_m:
					continue
			segments.append(PackedVector2Array([start_m, end_m]))
	return segments


func _clear_npcs() -> void:
	for npc: Entity in _npcs:
		if is_instance_valid(npc):
			npc.free()
	_npcs.clear()
