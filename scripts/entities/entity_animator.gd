@tool
class_name EntityAnimator
extends RefCounted
## Pure locomotion animation state machine. No nodes and no resources.
##
## EntityVisual feeds it the body's speed and intent, and applies the returned state
## to the sprite. Presentation only: nothing here can gate movement.

## Speed below which the entity counts as standing still, in m/s.
const MOVING_SPEED_MPS: float = 0.1

var state: EntityAnimationState.State = EntityAnimationState.State.IDLE


## Resolves the state for the current body snapshot. Seated entities stay idle
## (the body is hidden while riding).
func resolve(speed_mps: float, wants_run: bool, seated: bool) -> EntityAnimationState.State:
	var next: EntityAnimationState.State = EntityAnimationState.State.IDLE
	if not seated and speed_mps >= MOVING_SPEED_MPS:
		next = (EntityAnimationState.State.RUN if wants_run else EntityAnimationState.State.WALK)
	state = next
	return state


func reset() -> void:
	state = EntityAnimationState.State.IDLE
