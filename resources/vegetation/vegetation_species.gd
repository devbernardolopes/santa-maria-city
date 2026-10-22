class_name VegetationSpecies
extends Resource
## One placeable plant or rock: size, look, placement, and shared physical properties.

enum Kind { TREE, BUSH, ROCK }

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var kind: Kind = Kind.TREE
@export var trunk_radius_m: float = 0.0
@export var radius_min_m: float = 0.5
@export var radius_max_m: float = 1.0
@export var collides: bool = false
@export var clearance_m: float = 0.5
@export var ground_color: Color = Color(0.4, 0.35, 0.25, 1.0)
@export var canopy_color: Color = Color(0.25, 0.5, 0.2, 1.0)
@export_range(0.0, 1.0) var canopy_alpha: float = 0.8
@export var ground_texture: Texture2D = null
@export var canopy_texture: Texture2D = null
@export var properties: ObjectProperties = null


## Shared properties for this species; lazily creates the fallback instance.
func get_properties() -> ObjectProperties:
	if properties == null:
		properties = ObjectProperties.new()
	return properties
