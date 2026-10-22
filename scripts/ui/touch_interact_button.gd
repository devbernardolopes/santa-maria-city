class_name TouchInteractButton
extends Control
## Multitouch interact button that holds the interact action while pressed.

const BASE_COLOR: Color = Color(0.08, 0.08, 0.08, 0.32)
const RING_COLOR: Color = Color(1.0, 1.0, 1.0, 0.65)
const PRESSED_COLOR: Color = Color(0.2, 0.7, 0.4, 0.55)
const LABEL_COLOR: Color = Color(1.0, 1.0, 1.0, 0.85)
const RING_WIDTH_RATIO: float = 0.035
const ACTION: StringName = &"interact"
const LABEL_TEXT: String = "USE"

var _touch_index: int = -1
var _pressed: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _exit_tree() -> void:
	release_all()


func _notification(what: int) -> void:
	if what == CanvasItem.NOTIFICATION_VISIBILITY_CHANGED and not visible:
		release_all()


func _input(event: InputEvent) -> void:
	if not visible or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _touch_index == -1 and get_global_rect().has_point(touch.position):
			_touch_index = touch.index
			_set_pressed(true)
		elif not touch.pressed and touch.index == _touch_index:
			release_all()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_index:
			_set_pressed(get_global_rect().has_point(drag.position))


func release_all() -> void:
	_touch_index = -1
	_set_pressed(false)


func _set_pressed(value: bool) -> void:
	if _pressed == value:
		return
	_pressed = value
	if _pressed:
		Input.action_press(ACTION)
	else:
		Input.action_release(ACTION)
	queue_redraw()


func _draw() -> void:
	var radius: float = size.x * 0.5 - 1.0
	if radius <= 0.0:
		return
	var center: Vector2 = size * 0.5
	draw_circle(center, radius, PRESSED_COLOR if _pressed else BASE_COLOR)
	draw_arc(center, radius, 0.0, TAU, 64, RING_COLOR, maxf(1.0, radius * RING_WIDTH_RATIO), true)
	var font: Font = ThemeDB.fallback_font
	var font_size: int = maxi(12, int(size.x * 0.18))
	var text_size: Vector2 = font.get_string_size(
		LABEL_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
	)
	draw_string(
		font,
		center + Vector2(-text_size.x * 0.5, text_size.y * 0.35),
		LABEL_TEXT,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		LABEL_COLOR
	)
