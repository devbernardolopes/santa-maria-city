class_name Interactable
extends Area2D
## Composition component: marks an object as usable. Behavior lives in the owning object.

signal interacted(actor: Entity)
signal rejected(actor: Entity, text: String)

## Prompt shown while this object is the current interaction target.
@export var prompt_text: String = ""
## Radius of the interaction circle, in meters (shape built in code from Units).
@export var radius_m: float = 0.9
## False blocks interaction and shows unavailable_text instead.
@export var available: bool = true
## Shown while unavailable, for example "Locked" or "Closed · opens 08:00".
@export var unavailable_text: String = ""


func _ready() -> void:
	collision_layer = PhysicsLayers.INTERACTABLES
	collision_mask = 0
	monitoring = false
	var shape_node := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = Units.m_to_px(radius_m)
	shape_node.shape = circle
	add_child(shape_node)


## Emits interacted when available, rejected otherwise; returns whether it ran.
func interact(actor: Entity) -> bool:
	if available:
		interacted.emit(actor)
		return true
	rejected.emit(actor, unavailable_text)
	return false


func get_prompt() -> String:
	return prompt_text if available else unavailable_text


func set_available(value: bool, new_unavailable_text: String = "") -> void:
	available = value
	if not new_unavailable_text.is_empty():
		unavailable_text = new_unavailable_text
