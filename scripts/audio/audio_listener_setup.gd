extends AudioListener2D
func _ready() -> void:
	add_to_group("audio_listener")
	make_current()
