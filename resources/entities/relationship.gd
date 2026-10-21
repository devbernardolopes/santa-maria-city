class_name Relationship
extends Resource
## One directed relationship edge. It stores IDs, never EntityData references.

enum Social { STRANGER, ACQUAINTANCE, FRIEND, ENEMY, COUPLE }
enum Kin {
	NONE,
	PARENT,
	CHILD,
	SIBLING,
	SPOUSE,
	GRANDPARENT,
	GRANDCHILD,
	AUNT_UNCLE,
	NIECE_NEPHEW,
	COUSIN,
	IN_LAW,
	STEP_RELATIVE,
}
enum BasisKind { NONE, CONSANGUINITY, AFFINITY, ADOPTION }

@export var from_id: StringName = &""
@export var to_id: StringName = &""
@export var social: Social = Social.STRANGER
@export var kin: Kin = Kin.NONE
@export var basis: BasisKind = BasisKind.NONE
