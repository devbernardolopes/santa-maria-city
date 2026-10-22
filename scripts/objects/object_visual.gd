class_name ObjectVisual
extends Sprite2D
## Renders the ObjectData's visuals.

var data: ObjectData = null
var animation: StringName = ""


func set_data(new_data: ObjectData) -> void:
	data = new_data
	if data == null:
		queue_free()
		return
	init_sprite_frames()
	if data.sprite_texture != null:
		texture = data.sprite_texture
		modulate = Color.WHITE
	elif data.sprite_frames != null:
		# animation mode
		if data.sprite_frames.get_animation_list().size() > 0:
			animation = data.sprite_frames.get_animation_list()[0]
			# set animation and show first frame
			animation = data.sprite_frames.get_animation_list()[0]
			frame = 0
			modulate = Color.WHITE
		else:
			modulate = data.placeholder_color
			texture = null
	else:
		# placeholder: solid color
		modulate = data.placeholder_color
		texture = null


func init_sprite_frames() -> void:
	# ensure the SpriteFrames are initialized; called from WorldObject
	pass
