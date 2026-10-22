class_name VegetationRule
extends Resource
## Terrain rule: expected plants per 100 m² for one category/kind/surface combination.

@export var category: StringName = &"landuse"
@export var kind: StringName = &""
@export var surface: StringName = &""
@export var density_per_100m2: float = 0.0
## StringName species id -> float weight.
@export var species_weights: Dictionary = {}
