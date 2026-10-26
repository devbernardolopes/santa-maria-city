@tool
class_name UniqueVehicle
extends AnimatedSprite2D

#const NORTH_FACING_ROTATION: float = PI * 0.5

@export var vehicle_data: VehicleData = null
@export var vehicle_id: StringName = &""
@export var lights_enabled: bool = false
@export var fallback_color: Color = Color(0.82, 0.3, 0.2, 1.0)
@export var vehicle_scale: float = 1.0
@export_range(0.00, 360.00) var heading_deg: float = 0.00

var _lights_enabled: bool = lights_enabled
var _heading_deg: float = heading_deg
var _vehicle_scale: float = vehicle_scale


func setup(data: VehicleData) -> void:
	if vehicle_data == null:
		return
	
	data = vehicle_data
	
	sprite_frames = _build_frames(vehicle_data)
	#rotation = (NORTH_FACING_ROTATION if vehicle_data != null and vehicle_data.sprite_faces_north else 0.0)
	#scale = _sprite_scale(vehicle_data)
	visible = vehicle_data != null and not vehicle_data.frames.is_empty()
	_apply_lights()
	queue_redraw()


func _ready() -> void:
	setup(vehicle_data)


func _process(delta: float) -> void:
	if vehicle_data == null:
		return
	if sprite_frames != null:
		if _lights_enabled != lights_enabled:
			_lights_enabled = lights_enabled
			_apply_lights()
		if _heading_deg != heading_deg:
			_heading_deg = heading_deg
			rotation = deg_to_rad(heading_deg)
		if _vehicle_scale != vehicle_scale:
			_vehicle_scale = vehicle_scale
			scale = _sprite_scale(vehicle_data) * vehicle_scale
		return
	setup(vehicle_data)


func _build_frames(data: VehicleData) -> SpriteFrames:
	var result := SpriteFrames.new()
	#result.remove_animation(&"default")
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
	if sprite_frames == null:
		return
	var frames: SpriteFrames = sprite_frames
	if lights_enabled and frames.has_animation(&"lights"):
		animation = &"lights"
		play()
		return
	stop()
	if frames.has_animation(&"idle"):
		animation = &"idle"
		frame = 0


func _draw() -> void:
	if vehicle_data == null or not vehicle_data.frames.is_empty():
		return
	var length_px: float = Units.m_to_px(vehicle_data.length_m)
	var width_px: float = Units.m_to_px(vehicle_data.width_m)
	if length_px <= 0.0 or width_px <= 0.0:
		return
	var body := Rect2(-length_px * 0.5, -width_px * 0.5, length_px, width_px)
	draw_rect(body, fallback_color)
	draw_rect(body, fallback_color.darkened(0.3), false, maxf(1.0, Units.m_to_px(0.05)))
	var windshield := Rect2(length_px * 0.12, -width_px * 0.36, length_px * 0.16, width_px * 0.72)
	draw_rect(windshield, fallback_color.lightened(0.35))
