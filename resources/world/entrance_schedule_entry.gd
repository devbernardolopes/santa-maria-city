@tool
class_name EntranceScheduleEntry
extends Resource
## One weekly opening interval for an entrance.
##
## Weekdays start on Monday (GameClock weekday 0 = Monday). The listed day is the day the
## interval starts, so an interval from 22:00 to 02:00 on Friday also covers early Saturday.

@export_group("Days")
@export var monday: bool = true
@export var tuesday: bool = true
@export var wednesday: bool = true
@export var thursday: bool = true
@export var friday: bool = true
@export var saturday: bool = true
@export var sunday: bool = true

@export_group("Hours")
@export_range(0.0, 24.0, 0.25, "suffix:h") var from_hour: float = 0.0
@export_range(0.0, 24.0, 0.25, "suffix:h") var to_hour: float = 24.0


## True when the interval starts on `weekday` (0 = Monday).
func starts_on(weekday: int) -> bool:
	match weekday:
		0:
			return monday
		1:
			return tuesday
		2:
			return wednesday
		3:
			return thursday
		4:
			return friday
		5:
			return saturday
		6:
			return sunday
	return false


## True when `hour` on `weekday` falls inside this interval; to < from wraps past midnight.
func covers(weekday: int, hour: float) -> bool:
	if from_hour < to_hour:
		return starts_on(weekday) and hour >= from_hour and hour < to_hour
	if from_hour > to_hour:
		if starts_on(weekday) and hour >= from_hour:
			return true
		return starts_on(wrapi(weekday - 1, 0, 7)) and hour < to_hour
	return false


## Hours from `weekday`/`hour` until this interval next starts, or INF when it never does.
func next_opening_after(weekday: int, hour: float) -> float:
	var best: float = INF
	for offset: int in range(7):
		if not starts_on(wrapi(weekday + offset, 0, 7)):
			continue
		if offset == 0 and from_hour <= hour:
			continue
		best = minf(best, float(offset) * 24.0 + from_hour)
	return best
