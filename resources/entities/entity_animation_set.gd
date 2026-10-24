@tool
class_name EntityAnimationSet
extends Resource
## Sprite animation and locomotion clip mapping for one entity look.
##
## Art is authored in a SpriteFrames resource (editor: "Add frames from sprite sheet").
## The set only adds what the entity needs on top: world scale in meters, the facing
## offset for north-facing art, and which clip belongs to each locomotion state.

@export var sprite_frames: SpriteFrames = null:
	set(value):
		sprite_frames = value
		_frame_width_px = 0.0
## Width the whole frame is drawn at, in meters; drives the world scale of the art.
@export_range(0.1, 5.0, 0.01, "suffix:m") var sprite_width_m: float = 0.8
## North-facing art needs +90° so its face points along the entity's +X heading.
@export_range(-180.0, 180.0, 1.0, "suffix:°") var sprite_facing_offset_deg: float = 90.0
## Sprite offset in the entity's facing frame (X forward, Y right), in meters.
@export var sprite_offset_m: Vector2 = Vector2.ZERO
## Per-state clip definitions; missing states fall back (run -> walk).
@export var states: Array[EntityAnimationState] = []

var _frame_width_px: float = 0.0


## True when there is at least one animation to play.
func is_playable() -> bool:
	return sprite_frames != null and not sprite_frames.get_animation_names().is_empty()


## Definition actually used for a state, following the run -> walk fallback.
func get_definition(state: EntityAnimationState.State) -> EntityAnimationState:
	var definition: EntityAnimationState = _playable_definition(state)
	if definition != null:
		return definition
	if state == EntityAnimationState.State.RUN:
		return _playable_definition(EntityAnimationState.State.WALK)
	return null


## Clip name for a state, or an empty name when the state has nothing to play.
func get_clip(state: EntityAnimationState.State) -> StringName:
	var definition: EntityAnimationState = get_definition(state)
	return &"" if definition == null else definition.clip


## World scale that draws one frame at sprite_width_m.
func get_sprite_scale() -> float:
	var width_px: float = get_frame_width_px()
	if width_px <= 0.0:
		return 1.0
	return Units.m_to_px(sprite_width_m) / width_px


func get_frame_width_px() -> float:
	if _frame_width_px <= 0.0:
		_frame_width_px = _measure_frame_width_px()
	return _frame_width_px


func _measure_frame_width_px() -> float:
	if sprite_frames == null:
		return 0.0
	for definition: EntityAnimationState in states:
		if definition == null or definition.clip == &"":
			continue
		if not _has_frames(definition.clip):
			continue
		var texture: Texture2D = sprite_frames.get_frame_texture(definition.clip, 0)
		if texture != null:
			return texture.get_size().x
	return 0.0


func _playable_definition(state: EntityAnimationState.State) -> EntityAnimationState:
	for definition: EntityAnimationState in states:
		if definition == null or definition.state != state:
			continue
		if definition.clip == &"" or not _has_frames(definition.clip):
			return null
		return definition
	return null


func _has_frames(clip: StringName) -> bool:
	if sprite_frames == null or not sprite_frames.has_animation(clip):
		return false
	return sprite_frames.get_frame_count(clip) > 0
