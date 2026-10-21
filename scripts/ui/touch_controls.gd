class_name TouchControls
extends Control
## Shows and lays out the virtual joystick and run button.

const SHORT_SIDE_RATIO: float = 0.22
const MIN_SIDE_PX: float = 56.0
const MARGIN_RATIO: float = 0.12
const MIN_MARGIN_PX: float = 12.0

@export var force_visible: bool = false:
	set(value):
		force_visible = value
		if is_node_ready():
			_update_visibility()

@onready var _joystick: TouchJoystick = $VirtualJoystick
@onready var _run_button: TouchRunButton = $RunButton


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)
	get_viewport().size_changed.connect(_layout)
	get_window().focus_exited.connect(_release_all)
	_update_visibility()
	_layout()


func _exit_tree() -> void:
	_release_all()


func _notification(what: int) -> void:
	if what == CanvasItem.NOTIFICATION_VISIBILITY_CHANGED and not visible:
		_release_all()


func _update_visibility() -> void:
	var should_show: bool = force_visible or DisplayServer.is_touchscreen_available()
	visible = should_show
	if should_show:
		_layout()
	else:
		_release_all()


func _layout() -> void:
	if _joystick == null or _run_button == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var side: float = maxf(MIN_SIDE_PX, minf(viewport_size.x, viewport_size.y) * SHORT_SIDE_RATIO)
	var margin: float = maxf(MIN_MARGIN_PX, side * MARGIN_RATIO)
	_joystick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_joystick.offset_left = margin
	_joystick.offset_top = -side - margin
	_joystick.offset_right = margin + side
	_joystick.offset_bottom = -margin
	_run_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_run_button.offset_left = -side - margin
	_run_button.offset_top = -side - margin
	_run_button.offset_right = -margin
	_run_button.offset_bottom = -margin
	_joystick.queue_redraw()
	_run_button.queue_redraw()


func _release_all() -> void:
	if _joystick != null:
		_joystick.release_all()
	if _run_button != null:
		_run_button.release_all()
