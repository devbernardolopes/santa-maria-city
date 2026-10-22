class_name StreetTreeRule
extends Resource
## Street-tree rule for one road kind: spacing, edge offset, and species mix.

@export var road_kind: StringName = &""
@export var spacing_m: float = 18.0
@export var offset_m: float = 1.8
@export var both_sides: bool = true
## StringName species id -> float weight.
@export var species_weights: Dictionary = {}
