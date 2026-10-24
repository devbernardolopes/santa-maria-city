class_name AudioManager
extends Node
## Spatial audio manager: sets listener at player, pools AudioStreamPlayer2D nodes,
## and plays events near the listener only. Uses Godot's 2D spatialization (position,
## distance attenuation, left/right panning) automatically.

const MAX_POOL_SIZE: int = 32
const RANGE_M: float = 60.0

var _pool: Array[AudioStreamPlayer2D] = []
var _listener_target: Node2D = null

func _ready() -> void:
	# Pre-create pool of 2D audio players; no owner so they don't save into scenes.
	for _i: int in range(MAX_POOL_SIZE):
		var p := AudioStreamPlayer2D.new()
		p.name = "AudioPool_%d" % _i
		add_child(p)
		_pool.append(p)


func set_listener_target(node: Node2D) -> void:
	_listener_target = node


func play_at(world_m: Vector2, stream: AudioStream, loop: bool = false) -> AudioStreamPlayer2D:
	if stream == null:
		return null
	if _listener_target == null:
		return null
	var listener_m := Vector2.ZERO
	if _listener_target != null:
		listener_m = Vector2(
			_listener_target.global_position.x / Units.PX_PER_METER,
			_listener_target.global_position.y / Units.PX_PER_METER
		)
	var dist_m: float = world_m.distance_to(listener_m)
	if dist_m > RANGE_M:
		return null
	var p := _find_available()
	if p == null:
		return null
	p.global_position = Vector2(world_m.x * Units.PX_PER_METER, world_m.y * Units.PX_PER_METER)
	p.stream = stream
	p.loop = loop
	p.play()
	return p


func update_listener() -> void:
	# Listener is handled by an AudioListener2D node near the player; this manager
	# only updates pool positions when sources move.
	pass


func _find_available() -> AudioStreamPlayer2D:
	for p: AudioStreamPlayer2D in _pool:
		if not p.playing:
			return p
	# Fallback: steal oldest playing one-shot; loop nodes stay.
	for p: AudioStreamPlayer2D in _pool:
		if not p.loop and p.playing:
			p.stop()
			return p
	return null
