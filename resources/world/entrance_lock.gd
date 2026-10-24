@tool
class_name EntranceLock
extends Resource
## One physical lock on an entrance.
##
## An entrance can carry several locks; a key only opens the locks whose key item id it
## matches, and each lock has its own ability check for picking. Nothing consumes these
## fields yet: the item and strike systems ship later.

@export_group("Identity")
## Flavor name shown by future inspection, for example "front" or "deadbolt".
@export var name: String = ""
## Item id that opens this lock; empty means no key fits.
@export var required_key_item_id: StringName = &""

@export_group("Lockpicking")
## Ability rolled to pick this lock; the item and action systems are future work.
@export var pick_ability: EntityData.Ability = EntityData.Ability.DEXTERITY
@export_range(1, 30, 1) var pick_dc: int = 10
## False makes the lock unpickable; only a matching key opens it.
@export var pickable: bool = true
