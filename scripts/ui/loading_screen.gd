# Loading screen scene script
# Shows a progress bar during game/level loading

extends Control

# UI components (set in editor)
@onready var progress_bar: ProgressBar = $ProgressBar
@onready var progress_label: Label = $ProgressLabel
@onready var loading_text: Label = $LoadingText

# Loading state
var _is_loading: bool = false


func _ready() -> void:
	# Initially hide until start_loading is called
	hide()
	progress_bar.value = 0.0
	progress_bar.visible = false
	progress_label.visible = false
	loading_text.visible = false

	# Start loading the map
	start_loading()


func start_loading() -> void:
	_is_loading = true
	show()
	progress_bar.value = 0.0
	progress_bar.visible = true
	progress_label.visible = true
	loading_text.visible = true
	progress_label.text = "Loading..."

	# Load the map resource asynchronously
	load_map_async()


func load_map_async() -> void:
	var map_path: String = "res://data/map.json"

	# Load the map resource
	var map_resource = ResourceLoader.load(map_path)

	if map_resource == null:
		print("Failed to load map: " + map_path)
		_load_complete()
		return

	# Simulate progress update - in a real async implementation
	# this would use ResourceInteractiveLoader for true incremental progress
	# For now, set progress after a short delay
	get_tree().create_timer(0.5).timeout.connect(_on_timer_05)


func _on_timer_05() -> void:
	progress_bar.value = 1.0
	progress_label.text = "100%"
	_load_complete()


func _load_complete() -> void:
	_is_loading = false
	progress_bar.visible = false
	progress_label.visible = false
	loading_text.visible = false

	# Load the world scene after a short delay
	get_tree().create_timer(0.5).timeout.connect(_switch_to_world)


func _switch_to_world() -> void:
	var world_scene_path: String = "res://scenes/world/world.tscn"

	if ResourceLoader.exists(world_scene_path):
		var world_scene = ResourceLoader.load(world_scene_path)
		if world_scene != null:
			var world_instance = world_scene.instantiate()
			if world_instance != null:
				get_tree().root.add_child(world_instance)

	hide()
	progress_bar.value = 1.0
	progress_label.text = "100%"


func stop_loading() -> void:
	_is_loading = false
	hide()
	progress_bar.visible = false
	progress_label.visible = false
	loading_text.visible = false
	progress_bar.value = 0.0
