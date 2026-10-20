extends Node2D
## Root of the playable world. Child layers are kept in fixed draw order.

@onready var _map: MapLoader = $Map
@onready var _camera: DebugCamera = $DebugCamera
@onready var _hud: Hud = $Hud
@onready var _picker: MapPicker = $MapPicker


func _ready() -> void:
	_map.map_loaded.connect(_on_map_loaded)
	_picker.picked.connect(_hud.show_pick)
	if _map.is_loaded:
		var counts: Dictionary = {}
		var counts_value: Variant = _map.meta.get("counts")
		if counts_value is Dictionary:
			counts = counts_value
		_on_map_loaded(counts)


func _on_map_loaded(counts: Dictionary) -> void:
	_camera.on_map_loaded()
	_hud.on_map_loaded(counts)
	_picker.clear_pick()
