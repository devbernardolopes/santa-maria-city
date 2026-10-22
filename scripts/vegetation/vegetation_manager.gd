class_name VegetationManager
extends Node
## Streams deterministic vegetation chunks around the active camera and focus entity.

signal inspected(text: String)

const STREAM_INTERVAL_S: float = 0.25
const CAMERA_MOVE_STREAM_M: float = 8.0
const VIEW_MARGIN_M: float = 32.0
const ANCHOR_STREAM_RADIUS_M: float = 30.0
const COLLISION_RADIUS_M: float = 30.0
const INTERACTION_RADIUS_M: float = 3.0
const COLLISION_REFRESH_M: float = 2.0
const INTERACTION_REFRESH_M: float = 0.5
const MAX_COLLIDERS: int = 48
const MAX_INTERACTABLES: int = 6
const MAX_CACHED_CHUNKS: int = 64
const INTERACTABLE_MIN_RADIUS_M: float = 0.6
const INTERACTABLE_MAX_RADIUS_M: float = 1.2

@export var rules: VegetationRules = null
@export var vegetation_seed: int = 20261020
@export var enabled: bool = true
@export var max_view_radius_m: float = 300.0

var _map: MapLoader = null
var _active_rules: VegetationRules = null
var _generator: VegetationGenerator = null
var _anchor: Node2D = null
var _running: bool = false

var _decals: Node2D = null
var _canopy_layer: Node2D = null
var _chunk_data: Dictionary = {}
var _ground_views: Dictionary = {}
var _canopy_views: Dictionary = {}
var _pending_chunks: Array[Vector2i] = []
var _area_dirty: bool = true
var _stream_timer: float = 0.0
var _last_camera_center_m: Vector2 = Vector2(INF, INF)
var _last_camera_zoom: Vector2 = Vector2.ZERO
var _focus_outside: bool = false

var _collider_root: Node2D = null
var _colliders: Array[StaticBody2D] = []
var _collider_shapes: Array[CollisionShape2D] = []
var _collider_count: int = 0
var _interactable_root: Node2D = null
var _interactables: Array[Interactable] = []
var _interactable_data: Array[VegetationChunkData] = []
var _interactable_indices: PackedInt32Array = PackedInt32Array()
var _interactable_count: int = 0
var _last_collision_anchor_m: Vector2 = Vector2(INF, INF)
var _last_interaction_anchor_m: Vector2 = Vector2(INF, INF)
var _collision_dirty: bool = true
var _interaction_dirty: bool = true


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var world: Node = get_parent()
	_decals = world.get_node_or_null("Decals") as Node2D
	_canopy_layer = world.get_node_or_null("Canopy") as Node2D
	if _decals == null or _canopy_layer == null:
		push_error("VegetationManager: Decals or Canopy node not found; vegetation is disabled.")
		return
	_ensure_pools()
	set_process(false)


## Rebuilds everything for a newly loaded map; safe to call after MapLoader.rebuild().
func start(map: MapLoader) -> void:
	if Engine.is_editor_hint():
		return
	if _decals == null or _canopy_layer == null:
		return
	_map = map
	_active_rules = rules if rules != null else VegetationRules.shared_default()
	_clear_all()
	if not enabled or _map == null or TerrainQuery.active == null or _active_rules == null:
		_running = false
		set_process(false)
		return
	if _active_rules.species.is_empty():
		push_warning("VegetationManager: the rules have no species; vegetation is disabled.")
		_running = false
		set_process(false)
		return
	var bounds: Rect2 = _map_bounds_m()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		push_warning("VegetationManager: the map has no valid bounds_m; vegetation is disabled.")
		_running = false
		set_process(false)
		return
	_generator = VegetationGenerator.new(_active_rules, vegetation_seed, bounds)
	var street_start_usec: int = Time.get_ticks_usec()
	_generator.prepare_street_trees(_map.get_road_features_m())
	if OS.is_debug_build():
		var street_ms: int = int(round(float(Time.get_ticks_usec() - street_start_usec) / 1000.0))
		print(
			"VegetationManager: prepared %d street trees in %d ms."
			% [_generator.get_street_tree_count(), street_ms]
		)
	_running = true
	_area_dirty = true
	_stream_timer = 0.0
	_last_camera_center_m = Vector2(INF, INF)
	_last_camera_zoom = Vector2.ZERO
	_focus_outside = false
	set_process(true)


## The single focus point for collisions and interactions (player now, vehicle later).
func set_collision_anchor(anchor: Node2D) -> void:
	if _anchor == anchor:
		return
	_anchor = anchor
	_last_collision_anchor_m = Vector2(INF, INF)
	_last_interaction_anchor_m = Vector2(INF, INF)
	_collision_dirty = true
	_interaction_dirty = true
	if _anchor == null or not is_instance_valid(_anchor):
		_disable_pools()
	elif _running:
		set_process(true)


func get_stats() -> Dictionary:
	var instances: int = 0
	var chunks: Array = _ground_views.keys()
	for chunk_value: Variant in chunks:
		var chunk: Vector2i = chunk_value
		var data_value: Variant = _chunk_data.get(chunk)
		if data_value is VegetationChunkData:
			var data: VegetationChunkData = data_value
			instances += data.count()
	return {
		"chunks": _ground_views.size(),
		"instances": instances,
		"colliders": _collider_count,
		"interactables": _interactable_count,
	}


func _process(delta: float) -> void:
	if not _running:
		return
	_stream_timer += delta
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return
	var camera_center_m: Vector2 = _to_m(camera.get_screen_center_position())
	var moved: bool = _last_camera_center_m.distance_to(camera_center_m) >= CAMERA_MOVE_STREAM_M
	var zoom_changed: bool = not camera.zoom.is_equal_approx(_last_camera_zoom)
	if _stream_timer >= STREAM_INTERVAL_S or moved or zoom_changed or _area_dirty:
		_stream_timer = 0.0
		_last_camera_center_m = camera_center_m
		_last_camera_zoom = camera.zoom
		_update_needed_area(camera, camera_center_m)
		_area_dirty = false
	_pump_pending_chunk()
	_update_anchor_work()


func _update_needed_area(camera: Camera2D, center_m: Vector2) -> void:
	var bounds: Rect2 = _map_bounds_m()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		_clear_views()
		_pending_chunks.clear()
		_disable_pools()
		return
	if not bounds.has_point(center_m):
		_focus_outside = true
		_clear_views()
		_pending_chunks.clear()
		_disable_pools()
		return
	if _anchor != null and is_instance_valid(_anchor) and not bounds.has_point(_anchor_position_m()):
		_focus_outside = true
		_clear_views()
		_pending_chunks.clear()
		_disable_pools()
		return
	_focus_outside = false
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var zoom: Vector2 = camera.zoom
	var visible_size_m := Vector2(
		Units.px_to_m(viewport_size.x / maxf(zoom.x, 0.0001)),
		Units.px_to_m(viewport_size.y / maxf(zoom.y, 0.0001))
	)
	var area := Rect2(center_m - visible_size_m * 0.5, visible_size_m).grow(VIEW_MARGIN_M)
	var cap_radius: float = maxf(max_view_radius_m, 0.0)
	if cap_radius > 0.0:
		var cap := Rect2(
			center_m - Vector2(cap_radius, cap_radius),
			Vector2(cap_radius, cap_radius) * 2.0
		)
		area = area.intersection(cap)
	if _anchor != null and is_instance_valid(_anchor):
		var anchor_m: Vector2 = _anchor_position_m()
		if bounds.has_point(anchor_m):
			var anchor_area := Rect2(
				anchor_m - Vector2(ANCHOR_STREAM_RADIUS_M, ANCHOR_STREAM_RADIUS_M),
				Vector2(ANCHOR_STREAM_RADIUS_M, ANCHOR_STREAM_RADIUS_M) * 2.0
			)
			area = area.merge(anchor_area)
	_free_views_outside(area)
	_evict_cache()
	_queue_missing_views(area, bounds)


func _queue_missing_views(area: Rect2, bounds: Rect2) -> void:
	var needed: Array[Vector2i] = []
	var min_chunk: Vector2i = _chunk_of(area.position)
	var max_chunk: Vector2i = _chunk_of(area.end - Vector2(0.001, 0.001))
	for chunk_y: int in range(min_chunk.y, max_chunk.y + 1):
		for chunk_x: int in range(min_chunk.x, max_chunk.x + 1):
			var chunk := Vector2i(chunk_x, chunk_y)
			if not _chunk_intersects_map(chunk, bounds):
				continue
			if _ground_views.has(chunk):
				continue
			needed.append(chunk)
	needed.sort_custom(_sort_chunks)
	_pending_chunks = needed


func _pump_pending_chunk() -> void:
	if _pending_chunks.is_empty():
		return
	var chunk: Vector2i = _pending_chunks[0]
	_pending_chunks.remove_at(0)
	if _ground_views.has(chunk):
		return
	if not _chunk_intersects_map(chunk, _map_bounds_m()):
		return
	_create_view(chunk)
	_collision_dirty = true
	_interaction_dirty = true
	_evict_cache()


func _create_view(chunk: Vector2i) -> void:
	var data: VegetationChunkData = _get_chunk_data(chunk)
	if data == null:
		return
	var origin_m := Vector2(float(chunk.x), float(chunk.y)) * VegetationGenerator.CHUNK_SIZE_M
	var ground := VegetationBatch.new()
	ground.name = "Ground_%d_%d" % [chunk.x, chunk.y]
	ground.configure(data, _active_rules, origin_m, VegetationBatch.Mode.GROUND)
	ground.position = Units.to_px(origin_m)
	_decals.add_child(ground)
	_ground_views[chunk] = ground
	var canopy := VegetationBatch.new()
	canopy.name = "Canopy_%d_%d" % [chunk.x, chunk.y]
	canopy.configure(data, _active_rules, origin_m, VegetationBatch.Mode.CANOPY)
	canopy.position = Units.to_px(origin_m)
	_canopy_layer.add_child(canopy)
	_canopy_views[chunk] = canopy


func _get_chunk_data(chunk: Vector2i) -> VegetationChunkData:
	var existing: Variant = _chunk_data.get(chunk)
	if existing is VegetationChunkData:
		return existing
	if _generator == null:
		return null
	var data: VegetationChunkData = _generator.generate_chunk(chunk)
	_chunk_data[chunk] = data
	return data


func _free_view(chunk: Vector2i) -> void:
	var ground_value: Variant = _ground_views.get(chunk)
	if ground_value is VegetationBatch:
		var ground: VegetationBatch = ground_value
		if is_instance_valid(ground):
			ground.free()
	_ground_views.erase(chunk)
	var canopy_value: Variant = _canopy_views.get(chunk)
	if canopy_value is VegetationBatch:
		var canopy: VegetationBatch = canopy_value
		if is_instance_valid(canopy):
			canopy.free()
	_canopy_views.erase(chunk)


func _clear_views() -> void:
	var chunks: Array = _ground_views.keys()
	for chunk_value: Variant in chunks:
		var chunk: Vector2i = chunk_value
		_free_view(chunk)
	var canopy_chunks: Array = _canopy_views.keys()
	for chunk_value: Variant in canopy_chunks:
		var chunk: Vector2i = chunk_value
		_free_view(chunk)


func _free_views_outside(area: Rect2) -> void:
	var keep_area: Rect2 = area.grow(VegetationGenerator.CHUNK_SIZE_M)
	var chunks: Array = _ground_views.keys()
	for chunk_value: Variant in chunks:
		var chunk: Vector2i = chunk_value
		if not keep_area.intersects(_chunk_rect(chunk)):
			_free_view(chunk)


func _evict_cache() -> void:
	if _chunk_data.size() <= MAX_CACHED_CHUNKS:
		return
	var candidates: Array[Vector2i] = []
	var chunks: Array = _chunk_data.keys()
	for chunk_value: Variant in chunks:
		var chunk: Vector2i = chunk_value
		if _ground_views.has(chunk) or _pending_chunks.has(chunk):
			continue
		candidates.append(chunk)
	candidates.sort_custom(_sort_far_chunks)
	var remove_count: int = _chunk_data.size() - MAX_CACHED_CHUNKS
	for index: int in range(mini(remove_count, candidates.size())):
		_chunk_data.erase(candidates[index])


func _update_anchor_work() -> void:
	if _anchor == null or not is_instance_valid(_anchor):
		_disable_pools()
		return
	var anchor_m: Vector2 = _anchor_position_m()
	var bounds: Rect2 = _map_bounds_m()
	if _focus_outside or not bounds.has_point(anchor_m):
		_disable_pools()
		return
	if _collision_dirty or _last_collision_anchor_m.distance_to(anchor_m) >= COLLISION_REFRESH_M:
		_refresh_colliders(anchor_m)
		_last_collision_anchor_m = anchor_m
		_collision_dirty = false
	if _interaction_dirty or _last_interaction_anchor_m.distance_to(anchor_m) >= INTERACTION_REFRESH_M:
		_refresh_interactables(anchor_m)
		_last_interaction_anchor_m = anchor_m
		_interaction_dirty = false


func _refresh_colliders(anchor_m: Vector2) -> void:
	_ensure_pools()
	var candidates: Array[Dictionary] = []
	var min_chunk: Vector2i = _chunk_of(anchor_m - Vector2(COLLISION_RADIUS_M, COLLISION_RADIUS_M))
	var max_chunk: Vector2i = _chunk_of(anchor_m + Vector2(COLLISION_RADIUS_M, COLLISION_RADIUS_M))
	for chunk_y: int in range(min_chunk.y, max_chunk.y + 1):
		for chunk_x: int in range(min_chunk.x, max_chunk.x + 1):
			var chunk := Vector2i(chunk_x, chunk_y)
			var data_value: Variant = _chunk_data.get(chunk)
			if not (data_value is VegetationChunkData):
				continue
			var data: VegetationChunkData = data_value
			for index: int in range(data.count()):
				var species: VegetationSpecies = _species_at(data, index)
				if species == null or not species.collides:
					continue
				var position_m: Vector2 = data.positions_m[index]
				var distance: float = position_m.distance_to(anchor_m)
				if distance > COLLISION_RADIUS_M:
					continue
				var radius_m: float = species.trunk_radius_m
				if species.kind != VegetationSpecies.Kind.TREE:
					radius_m = data.radii_m[index]
				if radius_m <= 0.0:
					continue
				candidates.append({
					"position_m": position_m,
					"radius_m": radius_m,
					"distance": distance,
					"key": data.keys[index],
				})
	candidates.sort_custom(_sort_candidates)
	for index: int in range(_colliders.size()):
		if index < candidates.size():
			var candidate: Dictionary = candidates[index]
			var position_value: Variant = candidate.get("position_m")
			if position_value is Vector2:
				var position_m: Vector2 = position_value
				_colliders[index].position = Units.to_px(position_m)
			var shape: CollisionShape2D = _collider_shapes[index]
			var circle := shape.shape as CircleShape2D
			if circle != null:
				circle.radius = Units.m_to_px(float(candidate.get("radius_m", 0.0)))
			_set_collider_enabled(index, true)
		else:
			_set_collider_enabled(index, false)
	_collider_count = mini(candidates.size(), _colliders.size())


func _refresh_interactables(anchor_m: Vector2) -> void:
	if not (_anchor is Entity):
		_disable_interactables()
		return
	_ensure_pools()
	var candidates: Array[Dictionary] = []
	var min_chunk: Vector2i = _chunk_of(anchor_m - Vector2(INTERACTION_RADIUS_M, INTERACTION_RADIUS_M))
	var max_chunk: Vector2i = _chunk_of(anchor_m + Vector2(INTERACTION_RADIUS_M, INTERACTION_RADIUS_M))
	for chunk_y: int in range(min_chunk.y, max_chunk.y + 1):
		for chunk_x: int in range(min_chunk.x, max_chunk.x + 1):
			var chunk := Vector2i(chunk_x, chunk_y)
			var data_value: Variant = _chunk_data.get(chunk)
			if not (data_value is VegetationChunkData):
				continue
			var data: VegetationChunkData = data_value
			for index: int in range(data.count()):
				var species: VegetationSpecies = _species_at(data, index)
				if species == null:
					continue
				var position_m: Vector2 = data.positions_m[index]
				var distance: float = position_m.distance_to(anchor_m)
				if distance > INTERACTION_RADIUS_M:
					continue
				candidates.append({
					"data": data,
					"index": index,
					"distance": distance,
					"key": data.keys[index],
				})
	candidates.sort_custom(_sort_candidates)
	for slot: int in range(_interactables.size()):
		if slot < candidates.size():
			var candidate: Dictionary = candidates[slot]
			var data_value: Variant = candidate.get("data")
			if not (data_value is VegetationChunkData):
				_disable_interactable(slot)
				continue
			var data: VegetationChunkData = data_value
			var index: int = int(candidate.get("index", -1))
			var species: VegetationSpecies = _species_at(data, index)
			if species == null:
				_disable_interactable(slot)
				continue
			var interactable: Interactable = _interactables[slot]
			interactable.position = Units.to_px(data.positions_m[index])
			interactable.set_radius_m(clampf(
				data.radii_m[index],
				INTERACTABLE_MIN_RADIUS_M,
				INTERACTABLE_MAX_RADIUS_M
			))
			interactable.prompt_text = "Inspect %s" % _display_name(species)
			interactable.set_available(true)
			_set_interactable_enabled(slot, true)
			_interactable_data[slot] = data
			_interactable_indices[slot] = index
		else:
			_disable_interactable(slot)
	_interactable_count = mini(candidates.size(), _interactables.size())


func _disable_interactable(slot: int) -> void:
	_set_interactable_enabled(slot, false)
	if slot < _interactable_data.size():
		_interactable_data[slot] = null
	if slot < _interactable_indices.size():
		_interactable_indices[slot] = -1


func _disable_interactables() -> void:
	for slot: int in range(_interactables.size()):
		_disable_interactable(slot)
	_interactable_count = 0


func _on_pool_interacted(_actor: Entity, slot: int) -> void:
	if slot < 0 or slot >= _interactable_data.size():
		return
	var data: VegetationChunkData = _interactable_data[slot]
	if data == null:
		return
	var index: int = _interactable_indices[slot]
	if index < 0 or index >= data.count():
		return
	var species: VegetationSpecies = _species_at(data, index)
	if species == null:
		return
	var lines: PackedStringArray = [
		"%s · %.1f m" % [_display_name(species), data.radii_m[index]],
	]
	if not species.description.is_empty():
		lines.append(species.description)
	var properties: ObjectProperties = species.get_properties()
	var properties_text: String = properties.describe()
	if not properties_text.is_empty():
		lines.append(properties_text)
	var age_years: float = data.ages_years[index]
	if age_years >= 0.1:
		lines.append("age %.1f y" % age_years)
	inspected.emit("\n".join(lines))


func _ensure_pools() -> void:
	if _collider_root == null:
		_collider_root = Node2D.new()
		_collider_root.name = "VegetationColliders"
		add_child(_collider_root)
		for index: int in range(MAX_COLLIDERS):
			var body := StaticBody2D.new()
			body.name = "Collider_%d" % index
			body.collision_layer = 0
			body.collision_mask = 0
			var shape_node := CollisionShape2D.new()
			var circle := CircleShape2D.new()
			shape_node.shape = circle
			shape_node.disabled = true
			body.add_child(shape_node)
			_collider_root.add_child(body)
			_colliders.append(body)
			_collider_shapes.append(shape_node)
	if _interactable_root == null:
		_interactable_root = Node2D.new()
		_interactable_root.name = "VegetationInteractables"
		add_child(_interactable_root)
		for slot: int in range(MAX_INTERACTABLES):
			var interactable := Interactable.new()
			interactable.name = "Inspect_%d" % slot
			interactable.prompt_text = ""
			interactable.interacted.connect(_on_pool_interacted.bind(slot))
			_interactable_root.add_child(interactable)
			_interactables.append(interactable)
			_interactable_data.append(null)
			_interactable_indices.append(-1)
			_set_interactable_enabled(slot, false)


func _set_collider_enabled(index: int, enabled: bool) -> void:
	if index < 0 or index >= _colliders.size():
		return
	var body: StaticBody2D = _colliders[index]
	body.collision_layer = PhysicsLayers.WORLD if enabled else 0
	body.collision_mask = 0
	var shape: CollisionShape2D = _collider_shapes[index]
	if shape != null:
		shape.disabled = not enabled


func _disable_colliders() -> void:
	for index: int in range(_colliders.size()):
		_set_collider_enabled(index, false)
	_collider_count = 0


func _set_interactable_enabled(slot: int, enabled: bool) -> void:
	if slot < 0 or slot >= _interactables.size():
		return
	var interactable: Interactable = _interactables[slot]
	interactable.collision_layer = PhysicsLayers.INTERACTABLES if enabled else 0
	interactable.collision_mask = 0
	interactable.monitorable = enabled
	if not enabled:
		interactable.prompt_text = ""


func _disable_pools() -> void:
	_disable_colliders()
	_disable_interactables()
	_collision_dirty = true
	_interaction_dirty = true


func _clear_all() -> void:
	_clear_views()
	_chunk_data.clear()
	_pending_chunks.clear()
	_area_dirty = true
	_collision_dirty = true
	_interaction_dirty = true
	_last_collision_anchor_m = Vector2(INF, INF)
	_last_interaction_anchor_m = Vector2(INF, INF)
	_ensure_pools()
	_disable_pools()


func _species_at(data: VegetationChunkData, index: int) -> VegetationSpecies:
	if data == null or _active_rules == null:
		return null
	if index < 0 or index >= data.count():
		return null
	var species_index: int = data.species_index[index]
	if species_index < 0 or species_index >= _active_rules.species.size():
		return null
	return _active_rules.species[species_index]


func _display_name(species: VegetationSpecies) -> String:
	return species.display_name if not species.display_name.is_empty() else "Vegetation"


func _anchor_position_m() -> Vector2:
	if _anchor == null or not is_instance_valid(_anchor):
		return Vector2(INF, INF)
	return _to_m(_anchor.global_position)


func _to_m(point_px: Vector2) -> Vector2:
	return Vector2(Units.px_to_m(point_px.x), Units.px_to_m(point_px.y))


func _chunk_of(position_m: Vector2) -> Vector2i:
	return Vector2i(
		floori(position_m.x / VegetationGenerator.CHUNK_SIZE_M),
		floori(position_m.y / VegetationGenerator.CHUNK_SIZE_M)
	)


func _chunk_rect(chunk: Vector2i) -> Rect2:
	var origin := Vector2(float(chunk.x), float(chunk.y)) * VegetationGenerator.CHUNK_SIZE_M
	return Rect2(origin, Vector2.ONE * VegetationGenerator.CHUNK_SIZE_M)


func _chunk_center_m(chunk: Vector2i) -> Vector2:
	return _chunk_rect(chunk).get_center()


func _chunk_intersects_map(chunk: Vector2i, bounds: Rect2) -> bool:
	return _chunk_rect(chunk).intersects(bounds.grow(VegetationGenerator.BOUNDS_MARGIN_M))


func _sort_chunks(a: Vector2i, b: Vector2i) -> bool:
	var distance_a: float = _chunk_center_m(a).distance_squared_to(_last_camera_center_m)
	var distance_b: float = _chunk_center_m(b).distance_squared_to(_last_camera_center_m)
	if is_equal_approx(distance_a, distance_b):
		if a.x == b.x:
			return a.y < b.y
		return a.x < b.x
	return distance_a < distance_b


func _sort_far_chunks(a: Vector2i, b: Vector2i) -> bool:
	var distance_a: float = _chunk_center_m(a).distance_squared_to(_last_camera_center_m)
	var distance_b: float = _chunk_center_m(b).distance_squared_to(_last_camera_center_m)
	if is_equal_approx(distance_a, distance_b):
		if a.x == b.x:
			return a.y < b.y
		return a.x < b.x
	return distance_a > distance_b


func _sort_candidates(a: Dictionary, b: Dictionary) -> bool:
	var distance_a: float = float(a.get("distance", INF))
	var distance_b: float = float(b.get("distance", INF))
	if is_equal_approx(distance_a, distance_b):
		return str(a.get("key", "")) < str(b.get("key", ""))
	return distance_a < distance_b


func _map_bounds_m() -> Rect2:
	if _map == null:
		return Rect2()
	var value: Variant = _map.meta.get("bounds_m")
	if value is Array:
		var bounds: Array = value
		if bounds.size() == 4:
			var valid: bool = true
			for component: Variant in bounds:
				if not _is_number(component):
					valid = false
					break
			if valid:
				var min_m := Vector2(float(bounds[0]), float(bounds[1]))
				var max_m := Vector2(float(bounds[2]), float(bounds[3]))
				if max_m.x > min_m.x and max_m.y > min_m.y:
					return Rect2(min_m, max_m - min_m)
	if _map.map_bounds_px.size.x > 0.0 and _map.map_bounds_px.size.y > 0.0:
		return Rect2(
			Vector2(
				Units.px_to_m(_map.map_bounds_px.position.x),
				Units.px_to_m(_map.map_bounds_px.position.y)
			),
			Vector2(
				Units.px_to_m(_map.map_bounds_px.size.x),
				Units.px_to_m(_map.map_bounds_px.size.y)
			)
		)
	return Rect2()


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
