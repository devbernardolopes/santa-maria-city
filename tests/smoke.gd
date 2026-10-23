extends Node2D
## Headless vegetation smoke test: map load, streaming, pools, and inspection.

const PLAYER_SCENE: PackedScene = preload("res://scenes/entities/player.tscn")
const MAP_WAIT_MS: int = 15000
const STREAM_WAIT_MS: int = 5000
const POOL_WAIT_MS: int = 5000
const SEARCH_STEP_M: float = 16.0

var _map: MapLoader = null
var _manager: VegetationManager = null
var _player: Entity = null
var _camera: Camera2D = null
var _inspected_text: String = ""
var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	await _run()
	if _failures.is_empty():
		print("VEGETATION SMOKE OK")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		print("VEGETATION SMOKE FAIL: %s" % failure)
	get_tree().quit(1)


func _run() -> void:
	_map = MapLoader.new()
	_map.map_path = "res://data/map_test.json"
	_map.name = "Map"
	add_child(_map)
	if not await _wait_for_map():
		return
	if not _validate_lazy_street_trees():
		return

	var decals := Node2D.new()
	decals.name = "Decals"
	add_child(decals)
	var canopy := Node2D.new()
	canopy.name = "Canopy"
	add_child(canopy)

	_manager = VegetationManager.new()
	_manager.name = "VegetationManager"
	add_child(_manager)

	var rules: VegetationRules = _manager.rules
	if rules == null:
		rules = VegetationRules.shared_default()
	var focus_px: Vector2 = _find_vegetated_position_px(rules)
	if focus_px.x == INF:
		focus_px = _map.map_bounds_px.get_center()

	_player = PLAYER_SCENE.instantiate() as Entity
	if _player == null:
		_fail("could not instantiate the player scene")
		return
	_player.name = "Focus"
	_player.position = focus_px
	add_child(_player)

	_camera = Camera2D.new()
	_camera.name = "Camera"
	_camera.position = focus_px
	add_child(_camera)
	_camera.make_current()

	_manager.set_collision_anchor(_player)
	_manager.inspected.connect(_on_inspected)
	_manager.start(_map)

	if not await _wait_for_instances():
		return
	var colliding_position: Vector2 = _find_plant_position(true)
	var any_position: Vector2 = _find_plant_position(false)
	var target: Vector2 = colliding_position if colliding_position.x != INF else any_position
	if target.x == INF:
		_fail("no generated plants found in cached chunks")
		return
	_player.global_position = Units.to_px(target)
	_camera.position = _player.global_position
	_camera.reset_smoothing()
	_manager.set_collision_anchor(null)
	_manager.set_collision_anchor(_player)
	if not await _wait_for_interactables():
		return
	_validate_stats(colliding_position.x != INF)
	if not _inspect_first_enabled():
		_fail("could not inspect a pooled plant")
	elif _inspected_text.is_empty():
		_fail("inspection text was empty")
	elif not _inspected_text.contains("kg"):
		_fail("inspection text has no physical property summary")
	else:
		print("VEGETATION SMOKE inspect: %s" % _inspected_text.replace("\n", " | "))


func _wait_for_map() -> bool:
	var deadline: int = Time.get_ticks_msec() + MAP_WAIT_MS
	while not _map.is_loaded and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not _map.is_loaded:
		_fail("map did not load within %d ms" % MAP_WAIT_MS)
		return false
	return true


func _validate_lazy_street_trees() -> bool:
	var rules: VegetationRules = VegetationRules.shared_default()
	var bounds_px: Rect2 = _map.map_bounds_px
	var bounds_m := Rect2(
		Vector2(Units.px_to_m(bounds_px.position.x), Units.px_to_m(bounds_px.position.y)),
		Vector2(Units.px_to_m(bounds_px.size.x), Units.px_to_m(bounds_px.size.y))
	)
	var roads: Array[Dictionary] = _map.get_road_features_m()
	var generator := VegetationGenerator.new(rules, 20261020, bounds_m)
	generator.prepare_street_tree_index(roads)
	var checked: int = 0
	for road: Dictionary in roads:
		if checked >= 8:
			break
		var kind := StringName(str(road.get("kind", "")))
		if rules.find_street_rule(kind) == null:
			continue
		var line_value: Variant = road.get("line")
		if not (line_value is PackedVector2Array):
			continue
		var line: PackedVector2Array = line_value
		if line.size() < 2:
			continue
		checked += 1
		var midpoint: Vector2 = line[line.size() / 2]
		var chunk := Vector2i(
			floori(midpoint.x / VegetationGenerator.CHUNK_SIZE_M),
			floori(midpoint.y / VegetationGenerator.CHUNK_SIZE_M)
		)
		var data: VegetationChunkData = generator.generate_chunk(chunk)
		var street_count: int = 0
		for key: String in data.keys:
			if key.begins_with("s:"):
				street_count += 1
		if street_count > 0:
			print(
				(
					"VEGETATION SMOKE lazy street trees: %d in chunk %s (road %s)"
					% [street_count, str(chunk), str(road.get("id", ""))]
				)
			)
			return true
	_fail("lazy street-tree generation produced no trees")
	return false


func _wait_for_instances() -> bool:
	var deadline: int = Time.get_ticks_msec() + STREAM_WAIT_MS
	while Time.get_ticks_msec() < deadline:
		if int(_manager.get_stats().get("instances", 0)) > 0:
			return true
		await get_tree().create_timer(0.1).timeout
	_fail("no vegetation instances appeared within %d ms" % STREAM_WAIT_MS)
	return false


func _wait_for_interactables() -> bool:
	var deadline: int = Time.get_ticks_msec() + POOL_WAIT_MS
	while Time.get_ticks_msec() < deadline:
		if int(_manager.get_stats().get("interactables", 0)) > 0:
			return true
		await get_tree().create_timer(0.1).timeout
	_fail("no pooled interactables appeared within %d ms" % POOL_WAIT_MS)
	return false


func _find_vegetated_position_px(rules: VegetationRules) -> Vector2:
	if rules == null or TerrainQuery.active == null:
		return Vector2(INF, INF)
	var bounds_px: Rect2 = _map.map_bounds_px
	if bounds_px.size.x <= 0.0 or bounds_px.size.y <= 0.0:
		return Vector2(INF, INF)
	var step_px: float = Units.m_to_px(SEARCH_STEP_M)
	var y: float = bounds_px.position.y + step_px * 0.5
	while y < bounds_px.end.y:
		var x: float = bounds_px.position.x + step_px * 0.5
		while x < bounds_px.end.x:
			var point_px := Vector2(x, y)
			var point_m := Vector2(Units.px_to_m(x), Units.px_to_m(y))
			if rules.find_rule(TerrainQuery.active.sample(point_m)) != null:
				return point_px
			x += step_px
		y += step_px
	return Vector2(INF, INF)


func _find_plant_position(colliding_only: bool) -> Vector2:
	if _manager == null or _manager._active_rules == null:
		return Vector2(INF, INF)
	var rules: VegetationRules = _manager._active_rules
	for data_value: Variant in _manager._chunk_data.values():
		if not (data_value is VegetationChunkData):
			continue
		var data: VegetationChunkData = data_value
		for index: int in range(data.count()):
			var species_index: int = data.species_index[index]
			if species_index < 0 or species_index >= rules.species.size():
				continue
			var species: VegetationSpecies = rules.species[species_index]
			if species == null:
				continue
			if colliding_only and not species.collides:
				continue
			return data.positions_m[index]
	return Vector2(INF, INF)


func _validate_stats(expect_colliders: bool) -> void:
	var stats: Dictionary = _manager.get_stats()
	print("VEGETATION SMOKE stats: %s" % str(stats))
	if int(stats.get("chunks", 0)) <= 0:
		_fail("no loaded vegetation chunks")
	if int(stats.get("instances", 0)) <= 0:
		_fail("no generated vegetation instances")
	if int(stats.get("interactables", 0)) <= 0:
		_fail("no pooled interactables near the focus plant")
	if expect_colliders and int(stats.get("colliders", 0)) <= 0:
		_fail("no pooled colliders near the focus plant")


func _inspect_first_enabled() -> bool:
	for slot: Interactable in _manager._interactables:
		if slot.collision_layer == 0:
			continue
		if slot.interact(_player):
			return true
	return false


func _on_inspected(text: String) -> void:
	_inspected_text = text


func _fail(message: String) -> void:
	_failures.append(message)
