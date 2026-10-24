class_name VehicleSoundSet
extends Resource
## Set of AudioStreams for one vehicle, referenced by VehicleData.sound_set.
## Driving events use cross-faded bands: idle (0-2 m/s), slow (2-12 m/s), fast (>12 m/s).

@export var door_open_stream: AudioStream = null
@export var door_close_stream: AudioStream = null
@export var engine_start_stream: AudioStream = null
@export var drive_idle_stream: AudioStream = null
@export var drive_slow_stream: AudioStream = null
@export var drive_fast_stream: AudioStream = null
