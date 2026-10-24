@tool
class_name EntityAnimationState
extends Resource
## One locomotion animation state: which SpriteFrames clip plays and how fast.

enum State {
	IDLE,
	WALK,
	RUN,
}

## State this definition drives.
@export var state: State = State.IDLE
## Clip name inside the animation set's SpriteFrames. Empty disables the state.
@export var clip: StringName = &""
## Ground distance covered by one full clip cycle, in meters. Zero keeps the authored fps.
@export_range(0.0, 10.0, 0.05, "suffix:m") var meters_per_cycle: float = 0.0
