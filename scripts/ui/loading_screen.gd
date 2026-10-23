extends Control
## Loads the World scene in the background while keeping a visible progress surface.

const WORLD_SCENE_PATH: String = "res://scenes/world/world.tscn"
const WORLD_SCENE_PROGRESS_MAX: float = 0.85
const MAP_PROGRESS: float = 0.95
const COMPLETE_PROGRESS: float = 1.0
const MAX_WAIT_S: float = 120.0

@onready var progress_bar: ProgressBar = $ProgressBar
@onready var progress_label: Label = $ProgressLabel
@onready var loading_text: Label = $LoadingText

var _is_loading: bool = false
var _world: Node = null
var _elapsed_s: float = 0.0
var _world_load_started: bool = false


func _ready() -> void:
	progress_bar.value = 0.0
	progress_label.text = "0%"
	loading_text.text = "Initializing game..."
	start_loading.call_deferred()


func _process(delta: float) -> void:
	if not _is_loading:
		return
	_elapsed_s += delta
	if _elapsed_s > MAX_WAIT_S:
		_fail_loading("Loading timed out. Check the map data and project output for errors.")
		return

func start_loading() -> void:
	if _is_loading:
		return
	_is_loading = true
	_elapsed_s = 0.0
	_set_progress(0.0, "Loading world scene...")
	call_deferred("_load_world_scene")


func _load_world_scene() -> void:
	if not _is_loading or _world_load_started:
		return
	_world_load_started = true
	_set_progress(0.1, "Loading world scene...")
	await get_tree().process_frame
	var world_scene: PackedScene = ResourceLoader.load(WORLD_SCENE_PATH, "PackedScene") as PackedScene
	if world_scene == null:
		_fail_loading("Could not load the world scene.")
		return
	if _world != null:
		return
	_world = world_scene.instantiate()
	if _world == null:
		_fail_loading("The world scene could not be instantiated.")
		return
	_set_progress(WORLD_SCENE_PROGRESS_MAX, "Building map...")
	await get_tree().process_frame
	get_tree().root.add_child(_world)
	var map: MapLoader = _world.get_node_or_null("Map") as MapLoader
	if map == null:
		_fail_loading("The world scene has no Map node.")
		return
	if not map.map_loaded.is_connected(_on_map_loaded):
		map.map_loaded.connect(_on_map_loaded, CONNECT_ONE_SHOT)
	if map.has_signal("map_load_failed") and not map.map_load_failed.is_connected(_on_map_load_failed):
		map.map_load_failed.connect(_on_map_load_failed, CONNECT_ONE_SHOT)
	if map.is_loaded:
		_on_map_loaded({})


func _on_map_loaded(_counts: Dictionary) -> void:
	if not _is_loading:
		return
	_set_progress(MAP_PROGRESS, "Finalizing world...")
	await get_tree().process_frame
	_set_progress(COMPLETE_PROGRESS, "Ready")
	_is_loading = false
	await get_tree().process_frame
	queue_free()


func _on_map_load_failed(message: String) -> void:
	_fail_loading(message)


func _fail_loading(message: String) -> void:
	_is_loading = false
	_world_load_started = false
	loading_text.text = message
	progress_label.text = "Unable to load"
	progress_bar.value = 0.0
	push_error("LoadingScreen: %s" % message)


func _set_progress(value: float, message: String) -> void:
	var clamped_value: float = clampf(value, 0.0, COMPLETE_PROGRESS)
	progress_bar.value = clamped_value * 100.0
	progress_label.text = "%d%%" % roundi(clamped_value * 100.0)
	loading_text.text = message
