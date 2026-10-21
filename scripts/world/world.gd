extends Node2D
## Root of the playable world. Child layers are kept in fixed draw order.

const PLAYER_SCENE: PackedScene = preload("res://scenes/entities/player.tscn")
const SPAWNS_PATH: String = "res://data/overlays/spawns.json"
const SPAWNS_VERSION: int = 1

@export var debug_seed: int = 1

@onready var _map: MapLoader = $Map
@onready var _objects: Node2D = $Objects
@onready var _follow_camera: FollowCamera = $FollowCamera
@onready var _debug_camera: DebugCamera = $DebugCamera
@onready var _debug_spawner: DebugSpawner = $DebugSpawner
@onready var _hud: Hud = $Hud
@onready var _picker: MapPicker = $MapPicker

var _player: Entity = null


func _ready() -> void:
	_map.map_loaded.connect(_on_map_loaded)
	_picker.picked.connect(_hud.show_pick)
	if _map.is_loaded:
		var counts: Dictionary = {}
		var counts_value: Variant = _map.meta.get("counts")
		if counts_value is Dictionary:
			counts = counts_value
		_on_map_loaded(counts)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("debug_camera"):
		return
	if get_viewport().get_camera_2d() == _debug_camera:
		_follow_camera.make_current()
	else:
		_debug_camera.global_position = _follow_camera.get_screen_center_position()
		_debug_camera.zoom = _follow_camera.zoom
		_debug_camera.make_current()
	get_viewport().set_input_as_handled()


func _on_map_loaded(counts: Dictionary) -> void:
	_debug_camera.on_map_loaded()
	_hud.on_map_loaded(counts)
	_picker.clear_pick()
	_spawn_player()
	_debug_spawner.spawn_npcs(debug_seed + 1)


func _spawn_player() -> void:
	if _player != null and is_instance_valid(_player):
		_follow_camera.target = null
		_hud.set_player(null)
		_player.free()
	_player = null
	var rng := RandomNumberGenerator.new()
	rng.seed = debug_seed
	var data: EntityData = EntityData.create_random(rng)
	var player := PLAYER_SCENE.instantiate() as Entity
	if player == null:
		push_error("World: could not instantiate the player scene.")
		return
	player.data = data
	player.position = Units.to_px(_player_spawn_point_m())
	_objects.add_child(player)
	_player = player
	_follow_camera.target = player
	_follow_camera.snap_to_target()
	_follow_camera.make_current()
	_hud.set_player(player)


func _player_spawn_point_m() -> Vector2:
	var override: Variant = _read_spawn_override()
	if override is Vector2:
		return override
	return _map.nearest_road_point_m(_map_center_m())


func _read_spawn_override() -> Variant:
	if not FileAccess.file_exists(SPAWNS_PATH):
		return null
	var file: FileAccess = FileAccess.open(SPAWNS_PATH, FileAccess.READ)
	if file == null:
		push_warning("World: could not open %s; using the map center." % SPAWNS_PATH)
		return null
	var json := JSON.new()
	var parse_error: Error = json.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		push_warning("World: invalid JSON in %s; using the map center." % SPAWNS_PATH)
		return null
	var parsed: Variant = json.data
	if not (parsed is Dictionary):
		push_warning("World: %s must contain a JSON object; using the map center." % SPAWNS_PATH)
		return null
	var data: Dictionary = parsed
	var version_value: Variant = data.get("version")
	if not _is_number(version_value) or int(version_value) != SPAWNS_VERSION:
		push_warning("World: unsupported %s version; using the map center." % SPAWNS_PATH)
		return null
	var player_value: Variant = data.get("player")
	if player_value == null:
		return null
	if not (player_value is Array):
		push_warning("World: '%s.player' must be null or [x_m, y_m]; using the map center." % SPAWNS_PATH)
		return null
	var player_array: Array = player_value
	if player_array.size() != 2:
		push_warning("World: '%s.player' must contain two numbers; using the map center." % SPAWNS_PATH)
		return null
	if not _is_number(player_array[0]) or not _is_number(player_array[1]):
		push_warning("World: '%s.player' must contain two numbers; using the map center." % SPAWNS_PATH)
		return null
	return Vector2(float(player_array[0]), float(player_array[1]))


func _map_center_m() -> Vector2:
	var bounds_value: Variant = _map.meta.get("bounds_m")
	if bounds_value is Array:
		var bounds: Array = bounds_value
		if bounds.size() == 4 and _is_number(bounds[0]) and _is_number(bounds[1]) and _is_number(bounds[2]) and _is_number(bounds[3]):
			var min_m := Vector2(float(bounds[0]), float(bounds[1]))
			var max_m := Vector2(float(bounds[2]), float(bounds[3]))
			return (min_m + max_m) * 0.5
	var center_px: Vector2 = _map.map_bounds_px.get_center()
	return Vector2(Units.px_to_m(center_px.x), Units.px_to_m(center_px.y))


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
