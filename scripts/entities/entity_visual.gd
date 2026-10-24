@tool
class_name EntityVisual
extends Node2D
## Entity appearance: a SpriteFrames animation when an EntityAnimationSet is assigned,
## or the flat placeholder body otherwise.
##
## The entity node's +X axis is the heading, so north-facing art gets a fixed child
## rotation from the animation set. The sprite child is created at runtime (and as an
## internal node in the editor preview), never saved into scenes.

const TURN_RATE: float = 12.0
## Playback speed clamp, so wading through mud or a speed boost still reads as walking.
const MIN_PLAYBACK_SCALE: float = 0.5
const MAX_PLAYBACK_SCALE: float = 2.0

const BODY_RADIUS_M: float = 0.35
const FACING_LENGTH_M: float = 0.22
const FACING_HALF_WIDTH_M: float = 0.09

@export var body_color: Color = Color("d9822b"):
	set(value):
		body_color = value
		queue_redraw()

@export var animation_set: EntityAnimationSet = null:
	set(value):
		animation_set = value
		_apply_animation_set()

## Body this visual presents; bound by Entity or resolved from the parent.
var entity: Entity = null
## Heading the visual is turned toward, kept as a Vector2 so the sprite can rotate freely.
var facing: Vector2 = Vector2.DOWN

var _sprite: AnimatedSprite2D = null
var _animator := EntityAnimator.new()
var _applied_state: EntityAnimationState.State = EntityAnimationState.State.IDLE
var _applied_clip: StringName = &""


func _ready() -> void:
	if entity == null:
		var parent: Node = get_parent()
		if parent is Entity:
			entity = parent as Entity
			if animation_set == null and entity.data != null:
				animation_set = entity.data.animation_set
	_apply_animation_set()


## Attaches a body and picks up its data's animation set when none is assigned here.
func bind(target: Entity) -> void:
	entity = target
	if animation_set == null and entity != null and entity.data != null:
		animation_set = entity.data.animation_set
	_apply_animation_set()


func set_facing(direction: Vector2) -> void:
	if direction.is_zero_approx():
		return
	facing = direction.normalized()
	rotation = facing.angle()


func look_toward(direction: Vector2, delta: float) -> void:
	if direction.is_zero_approx():
		return
	facing = direction.normalized()
	rotation = lerp_angle(rotation, facing.angle(), minf(1.0, delta * TURN_RATE))


## Current locomotion state, for tests and the debug HUD.
func get_current_state() -> EntityAnimationState.State:
	return _applied_state


## Clip currently playing, or an empty name while the placeholder body is drawn.
func get_current_clip() -> StringName:
	return _applied_clip


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or entity == null or _sprite == null:
		return
	var next: EntityAnimationState.State = _animator.resolve(
		entity.get_speed_mps(), entity.wants_run(), entity.riding
	)
	if next != _applied_state:
		_apply_state(next)
	_update_playback_scale()


func _apply_animation_set() -> void:
	if not is_node_ready():
		return
	if animation_set == null or not animation_set.is_playable():
		_clear_sprite()
		queue_redraw()
		return
	_ensure_sprite()
	_sprite.sprite_frames = animation_set.sprite_frames
	_sprite.scale = Vector2.ONE * animation_set.get_sprite_scale()
	_sprite.position = Units.to_px(animation_set.sprite_offset_m)
	_sprite.rotation = deg_to_rad(animation_set.sprite_facing_offset_deg)
	_sprite.visible = true
	_animator.reset()
	_applied_clip = &""
	_apply_state(EntityAnimationState.State.IDLE)
	queue_redraw()


func _apply_state(state: EntityAnimationState.State) -> void:
	_applied_state = state
	if animation_set == null:
		return
	var definition: EntityAnimationState = animation_set.get_definition(state)
	if definition == null:
		if _sprite != null:
			_sprite.stop()
		_applied_clip = &""
		return
	if definition.clip == _applied_clip:
		return
	_applied_clip = definition.clip
	_sprite.animation = definition.clip
	_sprite.play()


## Ties the clip rate to ground speed so feet do not slide; authored fps when unset.
func _update_playback_scale() -> void:
	if animation_set == null or _sprite == null or _applied_clip == &"":
		return
	var definition: EntityAnimationState = animation_set.get_definition(_applied_state)
	if definition == null or definition.meters_per_cycle <= 0.0:
		_sprite.speed_scale = 1.0
		return
	var frames: SpriteFrames = _sprite.sprite_frames
	if frames == null or not frames.has_animation(_applied_clip):
		return
	var fps: float = maxf(frames.get_animation_speed(_applied_clip), 0.01)
	var cycle_s: float = frames.get_frame_count(_applied_clip) / fps
	var speed_mps: float = entity.get_speed_mps()
	_sprite.speed_scale = clampf(
		speed_mps * cycle_s / definition.meters_per_cycle, MIN_PLAYBACK_SCALE, MAX_PLAYBACK_SCALE
	)


func _ensure_sprite() -> void:
	if _sprite != null:
		return
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_sprite, false, Node.INTERNAL_MODE_FRONT)


func _clear_sprite() -> void:
	_applied_state = EntityAnimationState.State.IDLE
	_applied_clip = &""
	_animator.reset()
	if _sprite == null:
		return
	_sprite.stop()
	_sprite.visible = false


func _draw() -> void:
	if _sprite != null and _sprite.visible:
		return
	var radius: float = Units.m_to_px(BODY_RADIUS_M)
	if radius <= 0.0:
		return
	draw_circle(Vector2.ZERO, radius, body_color)
	draw_arc(
		Vector2.ZERO,
		radius,
		0.0,
		TAU,
		32,
		body_color.darkened(0.35),
		maxf(1.0, radius * 0.12),
		true
	)
	var tip := Vector2(radius + Units.m_to_px(FACING_LENGTH_M), 0.0)
	var half_width: float = Units.m_to_px(FACING_HALF_WIDTH_M)
	var base_x: float = radius * 0.55
	var triangle := PackedVector2Array(
		[
			tip,
			Vector2(base_x, -half_width),
			Vector2(base_x, half_width),
		]
	)
	draw_colored_polygon(triangle, body_color.lightened(0.18))
