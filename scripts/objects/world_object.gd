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

var data: ObjectData = null
var mutable_state: Dictionary = {}  # health, stack_count, etc.

## --- constructor helpers ---

func new_from_data(new_data: ObjectData) -> WorldObject:
 # scene already has script assigned via ext_resource
 var scene = load("res://scenes/objects/world_object.tscn") as PackedScene
 if scene == null:
  return null
 var instance := scene.instantiate() as WorldObject
 instance.set_data(new_data)
 return instance


func new_from_item_data(new_data: ItemData) -> WorldObject:
 # scene already has script assigned via ext_resource
 var scene = load("res://scenes/objects/world_object.tscn") as PackedScene
 if scene == null:
  return null
 var instance := scene.instantiate() as WorldObject
 instance.set_data(new_data)
 # item-specific defaults
 mutable_state["stack_count"] = 1
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
 # Increments stack_count; if container, adds to inventory.
 if not data.pickable:
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
 mutable_state["stack_count"] = new_count


func use(actor: Entity) -> void:
 ## Called when an entity uses/interacts with this object.
 if data.consumable:
  consume(actor)
 else:
  _interact()


func consume(actor: Entity) -> void:
 ## Consume a consumable item.
 if data.is_consumable:
  if data.health_restore > 0:
   actor.heal(data.health_restore)
  if data.stamina_restore > 0:
   actor.stamina = min(actor.max_stamina, actor.stamina + data.stamina_restore)
  if data.hunger_satisfaction > 0:
   actor.hunger = max(0.0, actor.hunger - data.hunger_satisfaction)
  # remove one from stack
  var count: int = mutable_state.get("stack_count", 1) - 1
  if count <= 0:
   queue_free()
  else:
   mutable_state["stack_count"] = count
  _interact()
 else:
  _interact()


func _interact() -> void:
 ## Generic interact callback.
 pass


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