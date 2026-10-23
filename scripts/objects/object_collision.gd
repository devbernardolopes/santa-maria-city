class_name ObjectCollision
extends Area2D
## Runtime collision for a WorldObject; built from ObjectData.
## When obstacle=true it blocks entity movement; otherwise it's loose (items).

var data: ObjectData = null


func set_data(new_data: ObjectData) -> void:
	data = new_data
	if data == null:
		return
	collision_layer = PhysicsLayers.WORLD
	collision_mask = 0
	monitoring = false
	var radius: float = maxf(0.0, data.collision_size_m.x / 2.0)
	if radius > 0.0:
		var circle := CircleShape2D.new()
		circle.radius = Units.m_to_px(radius)
		var shape := CollisionShape2D.new()
		# set offset before shape, as Godot may validate differently
		shape.position = Vector2(
			Units.m_to_px(data.collision_offset_m.x), Units.m_to_px(data.collision_offset_m.y)
		)
		shape.shape = circle
		add_child(shape)
	else:
		# no collision when size is zero
		queue_free()


func _ready() -> void:
	collision_layer = PhysicsLayers.WORLD
	collision_mask = PhysicsLayers.ENTITIES
	monitoring = false
	# set up initial data if any
	queue_free()
