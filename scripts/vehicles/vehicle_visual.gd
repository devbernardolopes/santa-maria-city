class_name VehicleVisual
extends Node2D
## Draws a vehicle from VehicleData frames, or a flat rectangle when art is missing.
##
## The vehicle node's +X axis is the heading. Sprites that face north are rotated +90°
## on the child sprite, so all physics math stays in the node's local frame.

const NORTH_FACING_ROTATION: float = PI * 0.5

@export var fallback_color: Color = Color(0.82, 0.3, 0.2, 1.0)

var _sprite: AnimatedSprite2D = null
var _data: VehicleData = null
var _lights_enabled: bool = false


func setup(data: VehicleData) -> void:
	_data = data
	_ensure_sprite()
	if _sprite != null:
		_sprite.sprite_frames = _build_frames(data)
		_sprite.rotation = (
			NORTH_FACING_ROTATION if data != null and data.sprite_faces_north else 0.0
		)
		_sprite.scale = _sprite_scale(data)
		_sprite.visible = data != null and not data.frames.is_empty()
	_apply_lights()
	queue_redraw()


func set_lights_enabled(value: bool) -> void:
	_lights_enabled = value
	_apply_lights()


func _ensure_sprite() -> void:
	if _sprite != null:
		return
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	add_child(_sprite)


func _build_frames(data: VehicleData) -> SpriteFrames:
	var result := SpriteFrames.new()
	result.remove_animation(&"default")
	if data == null:
		return result
	var valid: Array[Texture2D] = []
	for texture: Texture2D in data.frames:
		if texture != null:
			valid.append(texture)
	if valid.is_empty():
		return result
	result.add_animation(&"idle")
	result.set_animation_loop(&"idle", false)
	result.add_frame(&"idle", valid[0])
	if valid.size() > 1:
		result.add_animation(&"lights")
		result.set_animation_loop(&"lights", true)
		result.set_animation_speed(&"lights", 1.0 / maxf(0.01, data.frame_time_s))
		for texture: Texture2D in valid:
			result.add_frame(&"lights", texture)
	return result


func _sprite_scale(data: VehicleData) -> Vector2:
	if data == null:
		return Vector2.ONE
	var body_px: float = maxf(data.sprite_length_px, 1.0)
	return Vector2.ONE * (Units.m_to_px(maxf(data.length_m, 0.5)) / body_px)


func _apply_lights() -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		return
	var frames: SpriteFrames = _sprite.sprite_frames
	if _lights_enabled and frames.has_animation(&"lights"):
		_sprite.animation = &"lights"
		_sprite.play()
		return
	_sprite.stop()
	if frames.has_animation(&"idle"):
		_sprite.animation = &"idle"
		_sprite.frame = 0


func _draw() -> void:
	if _data == null or not _data.frames.is_empty():
		return
	var length_px: float = Units.m_to_px(_data.length_m)
	var width_px: float = Units.m_to_px(_data.width_m)
	if length_px <= 0.0 or width_px <= 0.0:
		return
	var body := Rect2(-length_px * 0.5, -width_px * 0.5, length_px, width_px)
	draw_rect(body, fallback_color)
	draw_rect(body, fallback_color.darkened(0.3), false, maxf(1.0, Units.m_to_px(0.05)))
	var windshield := Rect2(length_px * 0.12, -width_px * 0.36, length_px * 0.16, width_px * 0.72)
	draw_rect(windshield, fallback_color.lightened(0.35))
