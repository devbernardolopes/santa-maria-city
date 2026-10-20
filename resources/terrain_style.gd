class_name TerrainStyle
extends Resource
## Appearance of one map feature kind. A missing texture falls back to a flat color.

@export var kind: StringName = &""
@export var color: Color = Color.WHITE
@export var texture: Texture2D = null
@export var meters_per_tile: float = 4.0
@export var tint: Color = Color.WHITE
