class_name TerrainStyle
extends Resource
## Appearance of one map feature kind. A missing texture falls back to a flat color.

@export var id: StringName = &"":
	set(value):
		if id == value:
			return
		id = value
		emit_changed()

@export var kind: StringName = &"":
	set(value):
		if kind == value:
			return
		kind = value
		emit_changed()

@export var surface: StringName = &"":
	set(value):
		if surface == value:
			return
		surface = value
		emit_changed()

@export var color: Color = Color.WHITE
@export var texture: Texture2D = null
@export var meters_per_tile: float = 4.0
@export var tint: Color = Color.WHITE
