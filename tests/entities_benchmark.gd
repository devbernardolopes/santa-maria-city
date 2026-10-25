extends Node
## Headless entity scaling benchmark: spawns debug NPCs through the real DebugSpawner path
## and reports CPU cost, frame pacing, node count, and static memory per npc_count.
##
## The headless loop is paced to the physics tick rate, so wall-clock `loop_ms` stays at
## 1/60 s until the simulation can no longer keep up. Real work is therefore measured as
## process CPU time (Linux/Android `/proc/self/stat`), averaged over the sample frames.
## Godot's Performance.TIME_PHYSICS_PROCESS monitor is not used: it excludes GDScript
## callbacks and reports ~0 for an 8 ms busy-wait inside _physics_process.
##
## Run the full city (slow, realistic collision) or a quick map:
##   ENTITIES_BENCH_MAP=res://data/map_test.json make entities-bench
## Pick the sweep, e.g. one value at a time:
##   ENTITIES_BENCH_SWEEP=100 make entities-bench

const MAP_PATH: String = "res://data/map.json"
const MAP_ENV_VAR: String = "ENTITIES_BENCH_MAP"
const SWEEP_ENV_VAR: String = "ENTITIES_BENCH_SWEEP"
const LOAD_TIMEOUT_MS: int = 120000
## Each value spawns that many NPCs near one road point, measures, then replaces them.
## 0 is the harness baseline used to derive the per-NPC cost.
const SWEEP: Array[int] = [0, 1, 10, 50, 100]
const WARMUP_FRAMES: int = 30
const PREWARM_NPC_COUNT: int = 4
const SAMPLE_FRAMES: int = 300
const SPAWN_RADIUS_M: float = 120.0
const SPAWN_SEED: int = 12345
## Linux USER_HZ: /proc/self/stat CPU ticks per second on Linux and Android.
const PROC_CLOCK_TICKS: float = 100.0

var _harness: Node2D = null
var _map: MapLoader = null
var _objects: Node2D = null
var _spawner: DebugSpawner = null
var _origin_m: Vector2 = Vector2.ZERO
## Sample-frame CPU cost of the empty harness; -1 until a 0-NPC sweep runs.
var _baseline_cpu_ms: float = -1.0


func _ready() -> void:
	_harness = Node2D.new()
	_harness.name = "Harness"
	add_child(_harness)
	_map = MapLoader.new()
	_map.name = "Map"
	var override_path: String = OS.get_environment(MAP_ENV_VAR)
	_map.map_path = MAP_PATH if override_path.is_empty() else override_path
	_harness.add_child(_map)
	var loaded: bool = await _wait_for_map()
	if not loaded:
		return
	_objects = Node2D.new()
	_objects.name = "Objects"
	_objects.y_sort_enabled = true
	_harness.add_child(_objects)
	_spawner = DebugSpawner.new()
	_spawner.name = "DebugSpawner"
	_spawner.spawn_radius_m = SPAWN_RADIUS_M
	_harness.add_child(_spawner)
	_origin_m = _pick_origin_m()
	print(
		(
			"ENTITIES BENCH: map=%s nodes=%d static_memory_kb=%d"
			% [_map.map_path, _count_nodes(_harness), OS.get_static_memory_usage() / 1024]
		)
	)
	await _warm_up()
	var cpu_start_s: float = _process_cpu_s()
	for npc_count: int in _sweep_values():
		await _run_sweep(npc_count)
	var cpu_end_s: float = _process_cpu_s()
	if cpu_start_s >= 0.0 and cpu_end_s >= 0.0:
		print("ENTITIES BENCH: sweeps_cpu_s=%.2f" % (cpu_end_s - cpu_start_s))
	print("ENTITIES BENCH: done")
	get_tree().quit(0)


## Sweep from ENTITIES_BENCH_SWEEP ("0,10,100") when set, otherwise SWEEP.
func _sweep_values() -> Array[int]:
	var raw: String = OS.get_environment(SWEEP_ENV_VAR)
	if raw.is_empty():
		return SWEEP
	var values: Array[int] = []
	for part: String in raw.split(",", false):
		var value: int = int(part.strip_edges())
		if value >= 0:
			values.append(value)
	return values if not values.is_empty() else SWEEP


func _wait_for_map() -> bool:
	var deadline: int = Time.get_ticks_msec() + LOAD_TIMEOUT_MS
	while not _map.is_loaded and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if _map.is_loaded:
		return true
	push_error("ENTITIES BENCH: map did not load within %d ms" % LOAD_TIMEOUT_MS)
	get_tree().quit(1)
	return false


## Road point at the map center, so every sweep measures the same terrain.
func _pick_origin_m() -> Vector2:
	var center_px: Vector2 = _map.map_bounds_px.get_center()
	var center_m := Vector2(Units.px_to_m(center_px.x), Units.px_to_m(center_px.y))
	return _map.nearest_road_point_m(center_m)


## Spawns and frees a small set first, so the first measured sweep does not pay
## one-off costs (terrain index, script caches, physics wake-up).
func _warm_up() -> void:
	_spawn_npcs(PREWARM_NPC_COUNT)
	for _warmup_index: int in range(WARMUP_FRAMES * 2):
		await get_tree().physics_frame
	_spawn_npcs(0)


func _run_sweep(npc_count: int) -> void:
	var memory_before: int = OS.get_static_memory_usage()
	_spawn_npcs(npc_count)
	var spawned: int = _objects.get_child_count()
	for _warmup_index: int in range(WARMUP_FRAMES):
		await get_tree().physics_frame
	var cpu_before_s: float = _process_cpu_s()
	var start_usec: int = Time.get_ticks_usec()
	for _sample_index: int in range(SAMPLE_FRAMES):
		await get_tree().physics_frame
	var elapsed_usec: int = Time.get_ticks_usec() - start_usec
	var cpu_after_s: float = _process_cpu_s()
	var memory_used: int = OS.get_static_memory_usage() - memory_before
	var samples: float = float(SAMPLE_FRAMES)
	var cpu_ms: float = -1.0
	if cpu_before_s >= 0.0 and cpu_after_s >= 0.0:
		cpu_ms = (cpu_after_s - cpu_before_s) * 1000.0 / samples
	if npc_count == 0:
		_baseline_cpu_ms = cpu_ms
	var per_npc_us: float = -1.0
	if npc_count > 0 and _baseline_cpu_ms >= 0.0 and cpu_ms >= 0.0:
		per_npc_us = (cpu_ms - _baseline_cpu_ms) * 1000.0 / float(npc_count)
	var format: String = (
		"ENTITIES BENCH: npc_count=%d spawned=%d cpu_ms=%.3f per_npc_us=%.1f "
		+ "loop_ms=%.3f nodes=%d sweep_memory_kb=%d per_npc_kb=%d static_memory_kb=%d"
	)
	print(
		format
		% [
			npc_count,
			spawned,
			cpu_ms,
			per_npc_us,
			float(elapsed_usec) / 1000.0 / samples,
			_count_nodes(_harness),
			memory_used / 1024,
			(memory_used / 1024) / maxi(npc_count, 1),
			OS.get_static_memory_usage() / 1024,
		]
	)


func _spawn_npcs(npc_count: int) -> void:
	_spawner.npc_count = npc_count
	_spawner.spawn_npcs(SPAWN_SEED, _origin_m)


## Process CPU seconds from /proc/self/stat, or -1 where the file is unavailable.
func _process_cpu_s() -> float:
	var file: FileAccess = FileAccess.open("/proc/self/stat", FileAccess.READ)
	if file == null:
		return -1.0
	# procfs files report length 0, so read a line instead of the whole text.
	var text: String = file.get_line()
	file.close()
	var close_index: int = text.rfind(")")
	if close_index < 0:
		return -1.0
	# Fields after "(comm)": state=0, so utime=11 and stime=12.
	var fields: PackedStringArray = text.substr(close_index + 1).strip_edges().split(" ", false)
	if fields.size() < 13:
		return -1.0
	var ticks: int = int(fields[11]) + int(fields[12])
	return float(ticks) / PROC_CLOCK_TICKS


func _count_nodes(root: Node) -> int:
	var total: int = 1
	for child: Node in root.get_children():
		total += _count_nodes(child)
	return total
