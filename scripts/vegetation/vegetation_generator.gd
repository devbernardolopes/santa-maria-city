class_name VegetationGenerator
extends RefCounted
## Deterministic vegetation placement from the terrain grid and road centerlines.

const CELL_SIZE_M: float = 4.0
const CHUNK_SIZE_M: float = 128.0
const CELLS_PER_CHUNK: int = 32
const BOUNDS_MARGIN_M: float = 8.0
const BLOCKED_CATEGORIES: Array[StringName] = [&"buildings", &"roads", &"waterways"]

var _rules: VegetationRules = null
var _seed: int = 0
var _placement_bounds_m: Rect2 = Rect2()
var _street_road_features: Array[Dictionary] = []
var _street_roads_by_chunk: Dictionary = {}
var _street_roads_generated: Dictionary = {}
var _street_by_chunk: Dictionary = {}
var _street_tree_count: int = 0
var _max_street_clearance_m: float = 0.0


func _init(rules: VegetationRules, seed_value: int, bounds_m: Rect2) -> void:
	_rules = rules
	_seed = seed_value
	_placement_bounds_m = bounds_m.grow(BOUNDS_MARGIN_M)


## Indexes street-tree roads by 128 m chunk. Trees are generated per road on demand.
func prepare_street_tree_index(roads: Array[Dictionary]) -> void:
	_street_road_features.clear()
	_street_roads_by_chunk.clear()
	_street_roads_generated.clear()
	_street_by_chunk.clear()
	_street_tree_count = 0
	_max_street_clearance_m = _find_max_street_clearance()
	if _rules == null or TerrainQuery.active == null:
		return
	for road: Dictionary in roads:
		var kind := StringName(str(road.get("kind", "")))
		var rule: StreetTreeRule = _rules.find_street_rule(kind)
		if rule == null:
			continue
		var line_value: Variant = road.get("line")
		if not (line_value is PackedVector2Array):
			continue
		var line: PackedVector2Array = line_value
		if line.size() < 2:
			continue
		var width_value: Variant = road.get("width")
		var width: float = float(width_value) if _is_number(width_value) else 0.0
		width = maxf(width, 0.0)
		var road_index: int = _street_road_features.size()
		_street_road_features.append(road)
		var margin: float = width * 0.5 + rule.offset_m + _max_street_clearance_m + 2.0
		var bounds: Rect2 = _line_bounds(line).grow(margin)
		var min_chunk: Vector2i = _chunk_of(bounds.position)
		var max_chunk: Vector2i = _chunk_of(bounds.end - Vector2(0.001, 0.001))
		for chunk_y: int in range(min_chunk.y, max_chunk.y + 1):
			for chunk_x: int in range(min_chunk.x, max_chunk.x + 1):
				var chunk := Vector2i(chunk_x, chunk_y)
				var bucket: Array = []
				var bucket_value: Variant = _street_roads_by_chunk.get(chunk)
				if bucket_value is Array:
					bucket = bucket_value
				bucket.append(road_index)
				_street_roads_by_chunk[chunk] = bucket


func _generate_road_street_trees(road: Dictionary, road_index: int) -> void:
	if _rules == null:
		return
	var road_id: String = str(road.get("id", ""))
	var kind := StringName(str(road.get("kind", "")))
	var rule: StreetTreeRule = _rules.find_street_rule(kind)
	if rule == null:
		return
	var line_value: Variant = road.get("line")
	if not (line_value is PackedVector2Array):
		return
	var line: PackedVector2Array = line_value
	if line.size() < 2:
		return
	var width_value: Variant = road.get("width")
	var width: float = float(width_value) if _is_number(width_value) else 0.0
	width = maxf(width, 0.0)
	var spacing: float = maxf(rule.spacing_m, 1.0)
	var start_offset: float = float(_stable_string_hash(road_id) & 1023) / 1024.0 * spacing
	var rng := RandomNumberGenerator.new()
	rng.seed = _mix_seed(_seed, _stable_string_hash(road_id), 0x51EE7)
	var next_distance: float = start_offset
	var cumulative: float = 0.0
	var street_index: int = 0
	var side_count: int = 2 if rule.both_sides else 1
	for segment_index: int in range(line.size() - 1):
		var from: Vector2 = line[segment_index]
		var to: Vector2 = line[segment_index + 1]
		var segment_length: float = from.distance_to(to)
		if segment_length <= 0.0001:
			continue
		var segment_end: float = cumulative + segment_length
		while next_distance <= segment_end + 0.0001:
			var offset_in_segment: float = clampf(
				(next_distance - cumulative) / segment_length,
				0.0,
				1.0
			)
			var point: Vector2 = from.lerp(to, offset_in_segment)
			var tangent: Vector2 = (to - from) / segment_length
			var normal := Vector2(-tangent.y, tangent.x)
			for side_index: int in range(side_count):
				var side: float = 1.0 if side_index == 0 else -1.0
				var candidate: Vector2 = point + normal * (width * 0.5 + rule.offset_m) * side
				var species_index: int = _pick_species_index(rule.species_weights, rng)
				if species_index < 0:
					continue
				var species: VegetationSpecies = _rules.species[species_index]
				if species == null or not _street_position_ok(candidate, species.clearance_m):
					continue
				_add_street_tree(
					candidate,
					species_index,
					species,
					rng,
					"s:%s:%d" % [road_id, street_index],
					road_index,
					street_index
				)
				street_index += 1
			next_distance += spacing
		cumulative = segment_end


func generate_chunk(chunk: Vector2i) -> VegetationChunkData:
	var data := VegetationChunkData.new()
	var query: TerrainQuery = TerrainQuery.active
	if _rules == null or query == null or _rules.species.is_empty():
		return data
	var rng := RandomNumberGenerator.new()
	var base_cx: int = chunk.x * CELLS_PER_CHUNK
	var base_cy: int = chunk.y * CELLS_PER_CHUNK
	for cell_y: int in range(CELLS_PER_CHUNK):
		for cell_x: int in range(CELLS_PER_CHUNK):
			var cx: int = base_cx + cell_x
			var cy: int = base_cy + cell_y
			rng.seed = _mix_seed(_seed, cx, cy)
			var jitter := Vector2(rng.randf(), rng.randf())
			var position_m: Vector2 = (Vector2(float(cx), float(cy)) + jitter) * CELL_SIZE_M
			if not _placement_bounds_m.has_point(position_m):
				continue
			var sample: TerrainSample = query.sample(position_m)
			if _is_blocked_sample(sample):
				continue
			var rule: VegetationRule = _rules.find_rule(sample)
			if rule == null:
				continue
			var acceptance: float = clampf(
				rule.density_per_100m2 * CELL_SIZE_M * CELL_SIZE_M / 100.0,
				0.0,
				1.0
			)
			if rng.randf() > acceptance:
				continue
			var species_index: int = _pick_species_index(rule.species_weights, rng)
			if species_index < 0:
				continue
			var species: VegetationSpecies = _rules.species[species_index]
			if species == null:
				continue
			if not _terrain_position_ok(position_m, sample.category, species.clearance_m, query):
				continue
			data.add(
				position_m,
				species_index,
				_random_radius(species, rng),
				rng.randf() * TAU,
				_random_age(species, rng),
				_cell_key(cx, cy)
			)
	_append_street_trees(data, chunk)
	return data


func _ensure_street_trees_for_chunk(chunk: Vector2i) -> void:
	var roads_value: Variant = _street_roads_by_chunk.get(chunk)
	if not (roads_value is Array):
		return
	var roads: Array = roads_value
	for road_index_value: Variant in roads:
		var road_index: int = int(road_index_value)
		if _street_roads_generated.has(road_index):
			continue
		if road_index < 0 or road_index >= _street_road_features.size():
			continue
		_street_roads_generated[road_index] = true
		_generate_road_street_trees(_street_road_features[road_index], road_index)


func _append_street_trees(data: VegetationChunkData, chunk: Vector2i) -> void:
	_ensure_street_trees_for_chunk(chunk)
	var bucket_value: Variant = _street_by_chunk.get(chunk)
	if not (bucket_value is Array):
		return
	var bucket: Array = bucket_value
	bucket.sort_custom(_sort_street_trees)
	for tree_value: Variant in bucket:
		if not (tree_value is Dictionary):
			continue
		var tree: Dictionary = tree_value
		var position_value: Variant = tree.get("position_m")
		if not (position_value is Vector2):
			continue
		var position_m: Vector2 = position_value
		data.add(
			position_m,
			int(tree.get("species_index", -1)),
			float(tree.get("radius_m", 0.0)),
			float(tree.get("rotation", 0.0)),
			float(tree.get("age_years", 0.0)),
			str(tree.get("key", ""))
		)


func _sort_street_trees(a: Variant, b: Variant) -> bool:
	var a_tree: Dictionary = a
	var b_tree: Dictionary = b
	var a_road: int = int(a_tree.get("road_index", 0))
	var b_road: int = int(b_tree.get("road_index", 0))
	if a_road != b_road:
		return a_road < b_road
	return int(a_tree.get("street_index", 0)) < int(b_tree.get("street_index", 0))


func _add_street_tree(
	position_m: Vector2,
	species_index: int,
	species: VegetationSpecies,
	rng: RandomNumberGenerator,
	key: String,
	road_index: int,
	street_index: int
) -> void:
	var chunk := _chunk_of(position_m)
	var bucket: Array = []
	var bucket_value: Variant = _street_by_chunk.get(chunk)
	if bucket_value is Array:
		bucket = bucket_value
	bucket.append({
		"position_m": position_m,
		"species_index": species_index,
		"radius_m": _random_radius(species, rng),
		"rotation": rng.randf() * TAU,
		"age_years": _random_age(species, rng),
		"key": key,
		"road_index": road_index,
		"street_index": street_index,
	})
	_street_by_chunk[chunk] = bucket
	_street_tree_count += 1


## Number of street trees generated so far; lazy generation grows this as chunks load.
func get_street_tree_count() -> int:
	return _street_tree_count


## Number of roads with street-tree rules in the spatial index.
func get_indexed_street_road_count() -> int:
	return _street_road_features.size()


func _terrain_position_ok(
	position_m: Vector2,
	category: StringName,
	clearance_m: float,
	query: TerrainQuery
) -> bool:
	var clearance: float = maxf(clearance_m, 0.0)
	if clearance <= 0.0:
		return true
	var offsets: Array[Vector2] = [
		Vector2(clearance, 0.0),
		Vector2(-clearance, 0.0),
		Vector2(0.0, clearance),
		Vector2(0.0, -clearance),
	]
	for offset: Vector2 in offsets:
		var point: Vector2 = position_m + offset
		if not _placement_bounds_m.has_point(point):
			return false
		var point_sample: TerrainSample = query.sample(point)
		if point_sample.category != category:
			return false
		if _is_blocked_sample(point_sample):
			return false
	return true


func _street_position_ok(position_m: Vector2, clearance_m: float) -> bool:
	var query: TerrainQuery = TerrainQuery.active
	if query == null or not _placement_bounds_m.has_point(position_m):
		return false
	if _is_blocked_sample(query.sample(position_m)):
		return false
	var clearance: float = maxf(clearance_m, 0.0)
	if clearance <= 0.0:
		return true
	var offsets: Array[Vector2] = [
		Vector2(clearance, 0.0),
		Vector2(-clearance, 0.0),
		Vector2(0.0, clearance),
		Vector2(0.0, -clearance),
	]
	for offset: Vector2 in offsets:
		var point: Vector2 = position_m + offset
		if not _placement_bounds_m.has_point(point):
			return false
		if _is_blocked_sample(query.sample(point)):
			return false
	return true


func _pick_species_index(weights: Dictionary, rng: RandomNumberGenerator) -> int:
	if _rules == null or _rules.species.is_empty():
		return -1
	var total: float = 0.0
	for entry: VegetationSpecies in _rules.species:
		if entry == null:
			continue
		total += _weight(weights, entry.id)
	if total <= 0.0:
		return -1
	var roll: float = rng.randf() * total
	var accumulated: float = 0.0
	var last_index: int = -1
	for index: int in range(_rules.species.size()):
		var entry: VegetationSpecies = _rules.species[index]
		if entry == null:
			continue
		var weight: float = _weight(weights, entry.id)
		if weight <= 0.0:
			continue
		last_index = index
		accumulated += weight
		if roll <= accumulated:
			return index
	return last_index


func _weight(weights: Dictionary, id: StringName) -> float:
	var value: Variant = weights.get(id)
	if value == null:
		value = weights.get(String(id))
	if value is int or value is float:
		return maxf(0.0, float(value))
	return 0.0


func _random_radius(species: VegetationSpecies, rng: RandomNumberGenerator) -> float:
	var minimum: float = maxf(0.0, minf(species.radius_min_m, species.radius_max_m))
	var maximum: float = maxf(minimum, maxf(species.radius_min_m, species.radius_max_m))
	return lerpf(minimum, maximum, rng.randf())


func _random_age(species: VegetationSpecies, rng: RandomNumberGenerator) -> float:
	var properties: ObjectProperties = species.get_properties()
	if properties.max_age_years <= 0.0:
		return 0.0
	return rng.randf() * properties.max_age_years


func _line_bounds(line: PackedVector2Array) -> Rect2:
	var bounds := Rect2(line[0], Vector2.ZERO)
	for index: int in range(1, line.size()):
		bounds = bounds.expand(line[index])
	return bounds


func _find_max_street_clearance() -> float:
	var maximum: float = 0.0
	if _rules == null:
		return maximum
	for species: VegetationSpecies in _rules.species:
		if species != null:
			maximum = maxf(maximum, species.clearance_m)
	return maximum


func _chunk_of(position_m: Vector2) -> Vector2i:
	return Vector2i(
		floori(position_m.x / CHUNK_SIZE_M),
		floori(position_m.y / CHUNK_SIZE_M)
	)


func _cell_key(cx: int, cy: int) -> String:
	return "%d:%d" % [cx, cy]


func _is_blocked_category(category: StringName) -> bool:
	return BLOCKED_CATEGORIES.has(category)


func _is_blocked_sample(sample: TerrainSample) -> bool:
	if _is_blocked_category(sample.category):
		return true
	return TerrainSample.is_water_landuse(sample.category, sample.kind)


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


## Stable integer mix for one global grid cell; never uses hash() or string seeding.
static func _mix_seed(base: int, a: int, b: int) -> int:
	var h: int = (base ^ (a * 0x9E3779B1) ^ (b * 0x85EBCA77)) & 0xFFFFFFFF
	h = (h ^ 61) ^ (h >> 16)
	h = (h + (h << 3)) & 0xFFFFFFFF
	h = h ^ (h >> 4)
	h = (h * 0x27D4EB2D) & 0xFFFFFFFF
	h = h ^ (h >> 15)
	return h


## FNV-1a 32-bit hash for road IDs, stable across runs and platforms.
static func _stable_string_hash(text: String) -> int:
	var h: int = 2166136261
	for index: int in range(text.length()):
		h = h ^ text.unicode_at(index)
		h = (h * 16777619) & 0xFFFFFFFF
	return h
