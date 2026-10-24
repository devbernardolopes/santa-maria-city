class_name EntitySoundSet
extends Resource
## Set of AudioStreams for one entity, referenced by EntityData.sound_set.
## Event names (e.g. footstep, idle, action) are played by gameplay nodes; null = silent.

@export var footstep_stream: AudioStream = null
@export var idle_stream: AudioStream = null
@export var action_stream: AudioStream = null
