class_name VehicleSpawner
extends Node
## Spawns vehicles from data/overlays/vehicles.json, with a debug fallback near the player.

signal vehicle_spawned(vehicle: Vehicle)

const VEHICLE_SCENE: PackedScene = preload("res://scenes/vehicles/vehicle.tscn")
const DEFAULT_OVERLAY_PATH: String = "res://data/overlays/vehicles.json"
const DEFAULT_DEBUG_DATA_PATH: String = "res://resources/vehicles/car.tres"
const OVERLAY_VERSION: int = 1

@export var overlay_path: String = DEFAULT_OVERLAY_PATH
## Debug builds spawn this many cars on the nearest road when the overlay is empty.
@export_range(0, 8) var debug_fallback_count: int = 2
@export var debug_fallback_spacing_m: float = 12.0
## Data used by the debug spawn action; change it in the inspector to test another car.
@export var debug_vehicle_data: VehicleData = null

var _vehicles: Array[Vehicle] = []
var _map: MapLoader = null
var _objects: Node2D = null


func _ready() -> void:
	_map = get_parent().get_node_or_null("Map") as MapLoader
	_objects = get_parent().get_node_or_null("Objects") as Node2D
	if _objects == null:
		push_error("VehicleSpawner: Objects node not found; vehicles are disabled.")


func spawn_vehicles(spawn_point_m: Vector2) -> void:
	_clear_vehicles()
	if _objects == null:
		return
	var entries: Array[Dictionary] = _read_overlay()
	if entries.is_empty() and OS.is_debug_build() and debug_fallback_count > 0:
		entries = _debug_entries(spawn_point_m)
	for entry: Dictionary in entries:
		_spawn_entry(entry)


## Debug helper: spawns a car a few metres in front of the actor, facing the same way.
func spawn_in_front_of(actor: Entity, data: VehicleData = null) -> Vehicle:
	if actor == null or not is_instance_valid(actor):
		return null
	var vehicle_data: VehicleData = data
	if vehicle_data == null:
		vehicle_data = debug_vehicle_data
	if vehicle_data == null:
		vehicle_data = load(DEFAULT_DEBUG_DATA_PATH) as VehicleData
	if vehicle_data == null:
		push_warning("VehicleSpawner: no debug vehicle data available.")
		return null
	var forward: Vector2 = actor.facing
	if forward.length_squared() <= 0.001:
		forward = Vector2.DOWN
	forward = forward.normalized()
	var heading: float = forward.angle()
	var origin_m: Vector2 = Units.to_m(actor.global_position)
	var base_distance_m: float = vehicle_data.length_m * 0.5 + 1.0
	for extra_m: float in [0.0, 3.0, 6.0]:
		var point_m: Vector2 = origin_m + forward * (base_distance_m + extra_m)
		if _is_clear(point_m, heading, vehicle_data):
			return _spawn(vehicle_data, point_m, heading, StringName("debug/%d" % Time.get_ticks_msec()), false)
	return null


func get_vehicles() -> Array[Vehicle]:
	return _vehicles.duplicate()


func _read_overlay() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not FileAccess.file_exists(overlay_path):
		return result
	var file: FileAccess = FileAccess.open(overlay_path, FileAccess.READ)
	if file == null:
		push_warning("VehicleSpawner: could not open %s; no vehicles spawned." % overlay_path)
		return result
	var json := JSON.new()
	var parse_error: Error = json.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		push_warning("VehicleSpawner: invalid JSON in %s; no vehicles spawned." % overlay_path)
		return result
	var parsed: Variant = json.data
	if not (parsed is Dictionary):
		push_warning("VehicleSpawner: %s must contain a JSON object." % overlay_path)
		return result
	var data: Dictionary = parsed
	var version_value: Variant = data.get("version")
	if not _is_number(version_value) or int(version_value) != OVERLAY_VERSION:
		push_warning("VehicleSpawner: unsupported %s version; no vehicles spawned." % overlay_path)
		return result
	var entries_value: Variant = data.get("vehicles")
	if not (entries_value is Array):
		push_warning("VehicleSpawner: '%s.vehicles' must be an array." % overlay_path)
		return result
	var entries: Array = entries_value
	var skipped: int = 0
	for index: int in range(entries.size()):
		var entry_value: Variant = entries[index]
		if not (entry_value is Dictionary):
			skipped += 1
			continue
		var entry: Dictionary = entry_value
		var data_path: String = str(entry.get("data", ""))
		if data_path.is_empty():
			skipped += 1
			continue
		var position_value: Variant = entry.get("position")
		var position_m: Variant = _read_position(position_value)
		if position_m == null:
			skipped += 1
			continue
		var heading_deg: float = 0.0
		var heading_value: Variant = entry.get("heading_deg")
		if _is_number(heading_value):
			heading_deg = float(heading_value)
		var entry_id: String = str(entry.get("id", ""))
		if entry_id.is_empty():
			entry_id = "v_%04d" % index
		var lights_value: Variant = entry.get("lights")
		var lights: bool = lights_value is bool and bool(lights_value)
		result.append({
			"id": entry_id,
			"data": data_path,
			"position": position_m,
			"heading_rad": deg_to_rad(heading_deg),
			"lights": lights,
		})
	if skipped > 0:
		push_warning("VehicleSpawner: skipped %d invalid entries in %s." % [skipped, overlay_path])
	return result


func _spawn_entry(entry: Dictionary) -> void:
	var data_value: Variant = entry.get("data")
	var vehicle_data: VehicleData = null
	if data_value is VehicleData:
		vehicle_data = data_value
	elif data_value is String:
		vehicle_data = load(String(data_value)) as VehicleData
	if vehicle_data == null:
		push_warning("VehicleSpawner: could not load VehicleData '%s'; skipped." % str(data_value))
		return
	var position_value: Variant = entry.get("position")
	var position_m: Vector2 = position_value if position_value is Vector2 else Vector2.ZERO
	var heading_value: Variant = entry.get("heading_rad")
	var heading_rad: float = float(heading_value) if _is_number(heading_value) else 0.0
	var lights_value: Variant = entry.get("lights")
	var lights: bool = lights_value is bool and bool(lights_value)
	var entry_id: String = str(entry.get("id", ""))
	if not _is_clear(position_m, heading_rad, vehicle_data):
		push_warning("VehicleSpawner: spawn point for '%s' is blocked; skipped." % entry_id)
		return
	var vehicle := _spawn(vehicle_data, position_m, heading_rad, StringName(entry_id), lights)
	if vehicle == null:
		push_warning("VehicleSpawner: could not instantiate vehicle '%s'." % entry_id)


func _spawn(
	vehicle_data: VehicleData,
	position_m: Vector2,
	heading_rad: float,
	entry_id: StringName,
	lights: bool
) -> Vehicle:
	if _objects == null:
		return null
	var vehicle := VEHICLE_SCENE.instantiate() as Vehicle
	if vehicle == null:
		return null
	vehicle.data = vehicle_data
	vehicle.vehicle_id = entry_id
	vehicle.position = Units.to_px(position_m)
	vehicle.rotation = wrapf(heading_rad, -PI, PI)
	vehicle.lights_enabled = lights or vehicle_data.default_lights_enabled
	_objects.add_child(vehicle)
	_vehicles.append(vehicle)
	vehicle_spawned.emit(vehicle)
	return vehicle


func _debug_entries(spawn_point_m: Vector2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _map == null or debug_fallback_count <= 0:
		return result
	var vehicle_data: VehicleData = debug_vehicle_data
	if vehicle_data == null:
		vehicle_data = load(DEFAULT_DEBUG_DATA_PATH) as VehicleData
	if vehicle_data == null:
		return result
	var frame: Dictionary = _nearest_road_frame(spawn_point_m)
	var point_value: Variant = frame.get("point", spawn_point_m)
	var direction_value: Variant = frame.get("direction", Vector2.RIGHT)
	var point_m: Vector2 = point_value if point_value is Vector2 else spawn_point_m
	var direction: Vector2 = direction_value if direction_value is Vector2 else Vector2.RIGHT
	var heading_rad: float = direction.angle()
	var first: float = -float(debug_fallback_count - 1) * 0.5
	for index: int in range(debug_fallback_count):
		var offset_m: float = (first + float(index)) * debug_fallback_spacing_m
		result.append({
			"id": "debug/%d" % index,
			"data": vehicle_data,
			"position": point_m + direction * offset_m,
			"heading_rad": heading_rad,
			"lights": false,
		})
	return result


## Nearest road centerline point plus its direction, used for the debug fallback only.
func _nearest_road_frame(from_m: Vector2) -> Dictionary:
	var result: Dictionary = {"point": from_m, "direction": Vector2.RIGHT}
	if _map == null:
		return result
	var best: float = INF
	for line: PackedVector2Array in _map.get_road_lines_m():
		if line.size() < 2:
			continue
		for index: int in range(line.size() - 1):
			var candidate: Vector2 = Geometry2D.get_closest_point_to_segment(
				from_m,
				line[index],
				line[index + 1]
			)
			var distance: float = from_m.distance_squared_to(candidate)
			if distance >= best:
				continue
			best = distance
			var direction: Vector2 = (line[index + 1] - line[index]).normalized()
			if direction.length_squared() <= 0.001:
				direction = Vector2.RIGHT
			result = {"point": candidate, "direction": direction}
	return result


func _is_clear(point_m: Vector2, heading_rad: float, vehicle_data: VehicleData) -> bool:
	var query: TerrainQuery = TerrainQuery.active
	if query != null:
		var sample: TerrainSample = query.sample(point_m)
		if TerrainSample.is_water_landuse(sample.category, sample.kind):
			return false
	var viewport: Viewport = get_viewport()
	if viewport == null or viewport.world_2d == null:
		return true
	var space: PhysicsDirectSpaceState2D = viewport.world_2d.direct_space_state
	var params := PhysicsShapeQueryParameters2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = maxf(1.0, Units.m_to_px(vehicle_data.width_m) * 0.5)
	capsule.height = maxf(Units.m_to_px(vehicle_data.length_m), capsule.radius * 2.0)
	params.shape = capsule
	params.transform = Transform2D(heading_rad + PI * 0.5, Units.to_px(point_m))
	params.collision_mask = PhysicsLayers.WORLD | PhysicsLayers.VEHICLES
	params.collide_with_areas = false
	params.collide_with_bodies = true
	return space.intersect_shape(params, 1).is_empty()


func _read_position(value: Variant) -> Variant:
	if not (value is Array):
		return null
	var values: Array = value
	if values.size() != 2:
		return null
	if not _is_number(values[0]) or not _is_number(values[1]):
		return null
	return Vector2(float(values[0]), float(values[1]))


func _clear_vehicles() -> void:
	for vehicle: Vehicle in _vehicles:
		if not is_instance_valid(vehicle):
			continue
		var actors: Array[Entity] = vehicle.occupants.duplicate()
		for actor: Entity in actors:
			if is_instance_valid(actor):
				vehicle.exit(actor)
		vehicle.free()
	_vehicles.clear()


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
