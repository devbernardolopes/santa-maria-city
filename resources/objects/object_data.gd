class_name ObjectData
extends Resource
## Static definition for a world object (furniture, item, wall, etc).

## Human-readable identity
@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""

## Visuals
@export var kind: String = ""  # "wall", "chair", "rug", "table", "lamp", "container", "consumable", etc.
@export var sprite_frames: SpriteFrames = null
@export var sprite_texture: Texture2D = null
@export var sprite_scale: float = 1.0
@export var sprite_offset_m: Vector2 = Vector2.ZERO
@export var placeholder_color: Color = Color(0.8, 0.8, 0.8)

## Placement
@export var size_m: Vector2 = Vector2.ONE
@export var collision_size_m: Vector2 = Vector2.ONE
@export var collision_offset_m: Vector2 = Vector2.ZERO

## Physical properties; reuse the existing system
@export var properties: ObjectProperties = ObjectProperties.new()

## Behavior flags
@export var obstacle: bool = true
@export var movable: bool = true
@export var pickable: bool = false
@export var interactable: bool = false
@export var consumable: bool = false
@export var container_capacity: int = 0


func init_sprite_frames() -> void:
	# ensure sprite_frames are ready; called from WorldObject
	pass
