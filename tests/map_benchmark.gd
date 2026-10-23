extends Node
## Headless runtime map benchmark: load time, node counts, and static memory.

const WAIT_MS: int = 120000

var _map: MapLoader = null


func _ready() -> void:
	_map = MapLoader.new()
	_map.map_path = "res://data/map_test.json"
	_map.name = "Map"
	add_child(_map)
	var deadline: int = Time.get_ticks_msec() + WAIT_MS
	while not _map.is_loaded and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not _map.is_loaded:
		push_error("MAP BENCH: map did not load within %d ms" % WAIT_MS)
		get_tree().quit(1)
		return
	print("MAP BENCH: stats=%s" % str(_map.build_stats))
	print("MAP BENCH: size_m=%s bounds_px=%s" % [str(_map.map_size_m), str(_map.map_bounds_px)])
	print(
		"MAP BENCH: nodes=%d static_memory=%d" % [_count_nodes(_map), OS.get_static_memory_usage()]
	)
	get_tree().quit(0)


func _count_nodes(root: Node) -> int:
	var total: int = 1
	for child: Node in root.get_children():
		total += _count_nodes(child)
	return total
