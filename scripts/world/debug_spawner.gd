class_name DebugSpawner
extends Node
## Spawns debug NPCs on random road centerlines.

const NPC_SCENE: PackedScene = preload("res://scenes/entities/entity.tscn")

@export var npc_count: int = 8
## Shared look for the debug NPCs; null leaves them as placeholder bodies.
@export var npc_animation_set: EntityAnimationSet = null

var _map: MapLoader = null
var _objects: Node2D = null
var _npcs: Array[Entity] = []


func _ready() -> void:
	_map = get_parent().get_node_or_null("Map") as MapLoader
	_objects = get_parent().get_node_or_null("Objects") as Node2D
	if _map == null or _objects == null:
		push_error("DebugSpawner: Map or Objects node not found; NPC spawning is disabled.")


func spawn_npcs(seed_value: int) -> void:
	_clear_npcs()
	if _map == null or _objects == null or npc_count <= 0:
		return
	var lines: Array[PackedVector2Array] = _map.get_road_lines_m()
	if lines.is_empty():
		push_warning("DebugSpawner: no road centerlines available; no NPCs spawned.")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for _npc_index: int in range(npc_count):
		var line: PackedVector2Array = lines[rng.randi_range(0, lines.size() - 1)]
		if line.size() < 2:
			continue
		var segment_index: int = rng.randi_range(0, line.size() - 2)
		var point_m: Vector2 = line[segment_index].lerp(line[segment_index + 1], rng.randf())
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


func _clear_npcs() -> void:
	for npc: Entity in _npcs:
		if is_instance_valid(npc):
			npc.free()
	_npcs.clear()
