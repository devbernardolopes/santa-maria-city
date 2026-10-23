# Object Placement Demo Script
# Demonstrates placing ObjectData resources as WorldObject instances
# inside building interiors (Phase 2/3 functionality)

extends Node2D

# The interior's Objects node (assign in inspector or drag $Objects in scene)
@onready var _objects_node: Node2D = $Objects

# The rug resource to place (assign oriental_rug.tres in inspector)
@export var rug_resource: String = "res://resources/objects/oriental_rug.tres"

# Position to place the object (meters, local to interior)
@export var place_position_m: Vector2 = Vector2(3.0, 2.0)


func _ready() -> void:
	# Load the ObjectData resource
	var rug_data := load(rug_resource) as ObjectData
	if rug_data == null:
		push_error("Failed to load rug resource: %s" % rug_resource)
		return

	# Create WorldObject instance from the data
	var rug := WorldObject.new_from_data(rug_data)
	if rug == null:
		push_error("Failed to create WorldObject from rug resource")
		return

	# Convert position to pixels (1 meter = 16 pixels = Units.PX_PER_METER)
	var position_px: Vector2 = place_position_m * 16.0
	rug.global_position = position_px

	# Add to the interior's Objects node
	if _objects_node != null:
		_objects_node.add_child(rug)
		print("[Phase3] Oriental rug placed at %d, %d pixels" % [position_px.x, position_px.y])
	else:
		# Add directly to this scene (World root)
		add_child(rug)
		print("[Phase3] Oriental rug placed at %d, %d pixels" % [position_px.x, position_px.y])


func _print(text: String) -> void:
	print("[Phase3] " + text)
