class_name ItemData
extends ObjectData
## Runtime definition for pickable / consumable items.

@export var stack_max: int = 1
@export var is_consumable: bool = false
@export var health_restore: float = 0.0
@export var stamina_restore: float = 0.0
@export var hunger_satisfaction: float = 0.0
@export var duration_seconds: float = 0.0  # for timed effects

## Runtime state lives on WorldObject, not here.
