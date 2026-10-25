@tool
class_name LineDecal
extends Path2D

@export var bake_interval: float = 8.0:
	set(v):
		bake_interval = v
		_rebuild()

@export var texture: Texture2D:
	set(v):
		texture = v
		_apply_style()

@export_enum("None:0", "Tile:1", "Stretch:2") var texture_mode: int = 1:
	set(v):
		texture_mode = v
		_apply_style()

@export var width: float = 2.5:
	set(v):
		width = v
		_apply_style()

@export var pixel_art: bool = false:
	set(v):
		pixel_art = v
		_apply_style()

var line: Line2D
var _connected_curve: Curve2D
var _rebuilding: bool = false


func _ready() -> void:
	line = Line2D.new()
	line.name = "Line"
	# Internal child: hidden from the Scene dock and not saved into the .tscn
	add_child(line, false, Node.INTERNAL_MODE_FRONT)
	_apply_style()
	_rebuild()


func _process(_delta: float) -> void:
	# Reconnect if the Curve resource was created/replaced in the Inspector
	if curve != _connected_curve:
		if _connected_curve and _connected_curve.changed.is_connected(_rebuild):
			_connected_curve.changed.disconnect(_rebuild)
		_connected_curve = curve
		if curve:
			curve.changed.connect(_rebuild)
		_rebuild()


func _apply_style() -> void:
	if line == null:
		return
	line.texture = texture
	line.texture_mode = texture_mode
	line.width = width
	line.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	line.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if pixel_art else CanvasItem.TEXTURE_FILTER_PARENT_NODE
	line.begin_cap_mode = Line2D.LINE_CAP_NONE
	line.end_cap_mode = Line2D.LINE_CAP_NONE


func _rebuild() -> void:
	if _rebuilding or line == null or curve == null:
		return
	_rebuilding = true
	if not is_equal_approx(curve.bake_interval, bake_interval):
		curve.bake_interval = bake_interval
	line.points = curve.get_baked_points()
	_rebuilding = false
