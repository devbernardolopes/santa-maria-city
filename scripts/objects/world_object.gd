class_name WorldObject
extends Node2D
## Runtime instance of an ObjectData (or ItemData) in the world.
## Holds mutable state: health, stack count, contents, durability.

## Children added in _ready:
##   - Visual (ObjectVisual)
##   - Collision (ObjectCollision)
##   - Interactable (optional Area2D for prompts)

@onready var _visual: ObjectVisual = $Visual
@onready var _collision: ObjectCollision = $Collision
@onready var _interactable: Interactable = $Interactable

@export var data: ObjectData = null
var mutable_state: Dictionary = {}  # health, stack_count, etc.

## Inventory system
var inventory: Dictionary = {}  # item_id -> stack_count
var is_container: bool = false
var container_title: String = ""

## --- constructor helpers ---


static func new_from_data(new_data: ObjectData) -> WorldObject:
	# scene already has script assigned via ext_resource
	var scene = load("res://scripts/objects/world_object.tscn") as PackedScene
	if scene == null:
		return null
	var instance := scene.instantiate() as WorldObject
	instance.set_data(new_data)
	return instance


func new_from_item_data(new_data: ItemData) -> WorldObject:
	# scene already has script assigned via ext_resource
	var scene = load("res://scripts/objects/world_object.tscn") as PackedScene
	if scene == null:
		return null
	var instance := scene.instantiate() as WorldObject
	instance.set_data(new_data)
	# item-specific defaults
	mutable_state["stack_count"] = 1
	# determine if this is a container
	if new_data.kind == "container":
		is_container = true
		container_title = new_data.display_name
	return instance


## --- data flow ---


func set_data(new_data: ObjectData) -> void:
	data = new_data
	if data == null:
		queue_free()
		return
	mutable_state = {}
	_visual.set_data(data)
	_collision.set_data(data)
	_update_interactable()


func _update_interactable() -> void:
	if _interactable == null:
		return
	if data.pickable:
		_interactable.prompt_text = "Take"
		_interactable.available = true
	elif data.interactable:
		_interactable.prompt_text = "Use"
		_interactable.available = true
	else:
		_interactable.available = false
		_interactable.prompt_text = ""


func take() -> bool:
	## Called when an entity tries to take this object.
	## For items: increments stack_count and gives to player inventory.
	## For containers: returns false (containers are opened, not taken).
	if not data.pickable:
		return false
	if is_container:
		return false
	var count: int = mutable_state.get("stack_count", 1) + 1
	var max_count: int = (data as ItemData).stack_max
	if max_count > 0 and count > max_count:
		count = max_count
	mutable_state["stack_count"] = count
	_take_callback(count)
	return true


func _take_callback(new_count: int) -> void:
	## Override in subclass or hook from World to give the item to the player.
	# Default: update mutable state and free the object
	mutable_state["stack_count"] = new_count
	if new_count <= 0:
		queue_free()


func use(giver: Entity) -> void:
	## Called when an entity uses/interacts with this object.
	if data.consumable:
		consume(giver, 1.0)
	else:
		_interact()


func consume(giver: Entity, amount: float) -> void:
	## Consume a consumable item.
	# giver: the entity consuming (usually the player)
	# amount: number of stack items to consume (default 1.0)
	if not data.is_consumable:
		return
	var stacks_to_consume: int = max(0, int(amount))
	var current_stack_count: int = mutable_state.get("stack_count", 1)
	var consumed: int = 0
	while consumed < stacks_to_consume and current_stack_count > 0:
		if data.health_restore > 0:
			giver.heal(data.health_restore)
		if data.stamina_restore > 0:
			giver.stamina = min(giver.max_stamina, giver.stamina + data.stamina_restore)
		if data.hunger_satisfaction > 0:
			giver.hunger = max(0.0, giver.hunger - data.hunger_satisfaction)
		consumed += 1
		current_stack_count -= 1
	mutable_state["stack_count"] = max(0, current_stack_count)
	if current_stack_count <= 0:
		queue_free()
	_interact()


func _interact() -> void:
	## Generic interact callback.
	# If this is a container, open it; otherwise do nothing default
	if is_container:
		_open_container()


func _open_container() -> void:
	## Open the container interface.
	# TODO: Connect to game's inventory/ui system
	push_warning("Interactor: container '%s' opened (no UI yet)" % container_title)


## --- health / breakability ---


func damage(amount: float) -> void:
	## Reduce health; if breakable, free the object.
	mutable_state["health"] = max(0.0, mutable_state.get("health", 1.0) - amount)
	if data.breakable and mutable_state["health"] <= 0.0:
		queue_free()
	else:
		queue_redraw()


## --- physics interactions ---


func _physics_process(_delta: float) -> void:
	## Handle movement if movable; items can be picked up, walls cannot move.
	if not data.movable:
		return


# bodies that are not obstacles just pass through; nothing to do here


func _ready() -> void:
	_update_interactable()
	# ensure we have a valid collision setup
	if _collision == null:
		var col := ObjectCollision.new()
		add_child(col)
		col.set_data(data)
	if _visual == null:
		var vis := ObjectVisual.new()
		add_child(vis)
		vis.set_data(data)
	if _interactable == null:
		var inter := Interactable.new()
		add_child(inter)
		_interactable = inter
		_update_interactable()
