class_name ScreenFader
extends CanvasLayer
## Full-screen black fade for screen transitions. Lives on layer 100, above the HUD.

const BLACK: Color = Color(0.0, 0.0, 0.0, 0.0)

var _rect: ColorRect = null
var _tween: Tween = null


func _ready() -> void:
	_rect = ColorRect.new()
	_rect.name = "FadeRect"
	_rect.color = BLACK
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


## Fades to full black; await to continue after the screen is covered.
func fade_out(duration: float) -> void:
	await _fade_to(1.0, duration)


## Fades back to transparent; await to continue after the screen is clear.
func fade_in(duration: float) -> void:
	await _fade_to(0.0, duration)


func _fade_to(alpha: float, duration: float) -> void:
	if _rect == null:
		return
	_kill_tween()
	if duration <= 0.0:
		_rect.color = Color(0.0, 0.0, 0.0, alpha)
		return
	_tween = create_tween()
	_tween.tween_property(_rect, "color:a", alpha, duration)
	await _tween.finished
	_tween = null


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
