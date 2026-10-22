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
@onready var _picker: MapPicker = $MapPicker
@onready var _touch_controls: TouchControls = $Hud/TouchControls
@onready var _entrance_spawner: EntranceSpawner = $EntranceSpawner
@onready var _interior_manager: InteriorManager = $InteriorManager
@onready var _vegetation: VegetationManager = $VegetationManager
var _spawn_point_m: Vector2 = Vector2.ZERO


func _ready() -> void:
	_map.map_loaded.connect(_on_map_loaded)
	var hud0: Hud = get_node_or_null("Hud") as Hud
	if hud0 != null:
		_picker.picked.connect(hud0.show_pick)
		if _vegetation != null and not _vegetation.inspected.is_connected(hud0.show_message):
			_vegetation.inspected.connect(hud0.show_message)
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
	var hud: Hud = get_node_or_null("Hud") as Hud
	if hud != null:
		hud.on_map_loaded(counts)
	_picker.clear_pick()
	_spawn_player()
	if _vegetation != null:
		_vegetation.start(_map)
	if _entrance_spawner != null:
		_entrance_spawner.spawn_entrances(_spawn_point_m)
	if _debug_spawner != null:
		_debug_spawner.spawn_npcs(debug_seed + 1)


func _spawn_player() -> void:
	var hud_r: Hud = get_node_or_null("Hud") as Hud
	if hud_r != null:
		hud_r.set_player(null)
		hud_r.set_interaction_prompt("")
	var tc_r: TouchControls = get_node_or_null("Hud/TouchControls") as TouchControls
	if tc_r != null:
		tc_r.set_interact_available(false)
	var player_ref: Entity = _player
	if player_ref != null and is_instance_valid(player_ref):
		if _vegetation != null:
			_vegetation.set_collision_anchor(null)
		player_ref.free()
	_player = null
	var rng := RandomNumberGenerator.new()
	rng.seed = debug_seed
	var data: EntityData = EntityData.create_random(rng)
	var player := PLAYER_SCENE.instantiate() as Entity
	if player == null:
		push_error("World: could not instantiate the player scene.")
		return
	player.data = data
	_spawn_point_m = _player_spawn_point_m()
	player.position = Units.to_px(_spawn_point_m)
	_objects.add_child(player)
	_player = player
	_set_focus_entity(player)
	var hud_p: Hud = get_node_or_null("Hud") as Hud
	if hud_p != null:
		hud_p.set_player(player)
	_wire_player_interaction(player)
	if hud_p != null:
		hud_p.set_interaction_prompt("")
	var tc_p: TouchControls = get_node_or_null("Hud/TouchControls") as TouchControls
	if tc_p != null:
		tc_p.set_interact_available(false)


## Single focus point for the camera and vegetation; a future vehicle can replace the node.
func _set_focus_entity(node: Node2D) -> void:
	_follow_camera.target = node
	_follow_camera.snap_to_target()
	_follow_camera.make_current()
	if _vegetation != null:
		_vegetation.set_collision_anchor(node)


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
		if (
			bounds.size() == 4
			and _is_number(bounds[0])
			and _is_number(bounds[1])
			and _is_number(bounds[2])
			and _is_number(bounds[3])
		):
			var min_m := Vector2(float(bounds[0]), float(bounds[1]))
			var max_m := Vector2(float(bounds[2]), float(bounds[3]))
			return (min_m + max_m) * 0.5
	var center_px: Vector2 = _map.map_bounds_px.get_center()
	return Vector2(Units.px_to_m(center_px.x), Units.px_to_m(center_px.y))


func _wire_player_interaction(player: Entity) -> void:
	var hud: Hud = get_node_or_null("Hud") as Hud
	if hud == null:
		return
	var interaction := player.get_node_or_null("PlayerInteraction") as PlayerInteraction
	if interaction == null:
		return
	if interaction.target_changed.is_connected(_on_player_target_changed):
		return
	interaction.target_changed.connect(_on_player_target_changed)
	if not interaction.message.is_connected(hud.show_message):
		interaction.message.connect(hud.show_message)


func _on_player_target_changed(target: Interactable) -> void:
	var hud: Hud = get_node_or_null("Hud") as Hud
	if hud == null:
		return
	var text: String = ""
	if target != null and is_instance_valid(target):
		text = target.get_prompt()
	hud.set_interaction_prompt(text)
	var tc: TouchControls = get_node_or_null("Hud/TouchControls") as TouchControls
	if tc != null:
		tc.set_interact_available(not text.is_empty())

func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT

var _player: Entity = null
