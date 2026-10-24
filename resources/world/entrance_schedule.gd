class_name EntranceSchedule
extends RefCounted
## Pure helpers over an entrance's weekly schedule; no clock dependency.


## No entries means always open. Otherwise any covering interval opens the entrance.
static func is_open(entries: Array[EntranceScheduleEntry], weekday: int, hour: float) -> bool:
	if entries.is_empty():
		return true
	for entry: EntranceScheduleEntry in entries:
		if entry != null and entry.covers(weekday, hour):
			return true
	return false


## "HH:MM" of the next opening at or after now, searching seven days ahead.
static func next_opening_text(
	entries: Array[EntranceScheduleEntry], weekday: int, hour: float
) -> String:
	var best: float = INF
	for entry: EntranceScheduleEntry in entries:
		if entry != null:
			best = minf(best, entry.next_opening_after(weekday, hour))
	if best == INF:
		return "00:00"
	var total_minutes: int = int(round(fposmod(best, 24.0) * 60.0)) % (24 * 60)
	return "%02d:%02d" % [total_minutes / 60, total_minutes % 60]
