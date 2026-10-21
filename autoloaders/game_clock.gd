extends Node
## In-game calendar and clock. total_seconds since 1970-01-01 00:00 is the single source of truth.

signal minute_changed()
signal hour_changed(hour: int)
signal day_changed(year: int, month: int, day: int)
signal period_changed(period: int)
signal time_scale_changed(value: float)
signal paused_changed(value: bool)

enum Period { NIGHT, DAWN, MORNING, AFTERNOON, DUSK, EVENING }

const MIN_TIME_SCALE: float = 0.0
const MAX_TIME_SCALE: float = 7200.0
const SECONDS_PER_MINUTE: float = GameCalendar.SECONDS_PER_MINUTE
const SECONDS_PER_HOUR: float = GameCalendar.SECONDS_PER_HOUR
const SECONDS_PER_DAY: float = GameCalendar.SECONDS_PER_DAY
const TWILIGHT_WINDOW_HOURS: float = 1.0
const NOON_HOUR: float = 12.0
const EVENING_END_HOUR: float = 22.0
const KNOWN_STATE_KEYS: Array[String] = ["total_seconds", "time_scale", "paused"]

@export var start_year: int = 2026
@export var start_month: int = 10
@export var start_day: int = 20
@export var start_hour: float = 8.0

## Game seconds per real second.
@export var time_scale: float = 60.0:
	set(value):
		var clamped: float = clampf(value, MIN_TIME_SCALE, MAX_TIME_SCALE)
		if is_equal_approx(time_scale, clamped):
			return
		time_scale = clamped
		time_scale_changed.emit(clamped)

@export var paused: bool = false:
	set(value):
		if paused == value:
			return
		paused = value
		paused_changed.emit(value)

var total_seconds: float = 0.0

var _last_minute_index: int = 0
var _last_hour_index: int = 0
var _last_day_index: int = 0
var _last_period: Period = Period.NIGHT


func _ready() -> void:
	total_seconds = (
		float(GameCalendar.days_from_civil(start_year, start_month, start_day)) * SECONDS_PER_DAY
		+ clampf(start_hour, 0.0, 24.0) * SECONDS_PER_HOUR
	)
	_sync_boundaries()


func _process(delta: float) -> void:
	if paused:
		return
	total_seconds += delta * time_scale
	_emit_boundaries()


func get_days() -> int:
	return floori(total_seconds / SECONDS_PER_DAY)


func get_year() -> int:
	return GameCalendar.civil_from_days(get_days()).x


func get_month() -> int:
	return GameCalendar.civil_from_days(get_days()).y


func get_day() -> int:
	return GameCalendar.civil_from_days(get_days()).z


func get_hour() -> int:
	return int(get_hour_float())


func get_minute() -> int:
	return int(fposmod(total_seconds, SECONDS_PER_HOUR) / SECONDS_PER_MINUTE)


## Hour of the day as a float in [0, 24).
func get_hour_float() -> float:
	return fposmod(total_seconds, SECONDS_PER_DAY) / SECONDS_PER_HOUR


## 0 = Monday … 6 = Sunday (GameCalendar.Weekday).
func get_weekday() -> int:
	return GameCalendar.weekday_of_days(get_days())


## 1-based day of the year.
func get_day_of_year() -> int:
	var civil: Vector3i = GameCalendar.civil_from_days(get_days())
	return GameCalendar.day_of_year(civil.x, civil.y, civil.z)


func get_sunrise_hour() -> float:
	return GameCalendar.sunrise_hour(get_day_of_year())


func get_sunset_hour() -> float:
	return GameCalendar.sunset_hour(get_day_of_year())


func is_daytime() -> bool:
	var hour: float = get_hour_float()
	return hour >= get_sunrise_hour() and hour < get_sunset_hour()


## The six periods always partition the whole day, relative to today's sunrise/sunset.
func get_period() -> Period:
	var hour: float = get_hour_float()
	var sunrise: float = get_sunrise_hour()
	var sunset: float = get_sunset_hour()
	if hour < sunrise - TWILIGHT_WINDOW_HOURS:
		return Period.NIGHT
	if hour < sunrise + TWILIGHT_WINDOW_HOURS:
		return Period.DAWN
	if hour < NOON_HOUR:
		return Period.MORNING
	if hour < sunset - TWILIGHT_WINDOW_HOURS:
		return Period.AFTERNOON
	if hour < sunset + TWILIGHT_WINDOW_HOURS:
		return Period.DUSK
	if hour < EVENING_END_HOUR:
		return Period.EVENING
	return Period.NIGHT


func format_time() -> String:
	return "%02d:%02d" % [get_hour(), get_minute()]


## English, for example "Tue 20 Oct 2026".
func format_date() -> String:
	var days: int = get_days()
	var civil: Vector3i = GameCalendar.civil_from_days(days)
	return "%s %d %s %d" % [
		GameCalendar.weekday_name(GameCalendar.weekday_of_days(days)),
		civil.z,
		GameCalendar.month_name(civil.y),
		civil.x,
	]


func set_time_scale(value: float) -> void:
	time_scale = value


func set_paused(value: bool) -> void:
	paused = value


## Jumps the clock; every skipped boundary signal is emitted once with the final state.
func advance_hours(hours: float) -> void:
	total_seconds += hours * SECONDS_PER_HOUR
	_emit_boundaries()


func set_datetime(year: int, month: int, day: int, hour: float) -> void:
	if month < 1 or month > 12:
		push_warning("GameClock: set_datetime month %d out of range (1-12); ignored." % month)
		return
	var max_day: int = GameCalendar.days_in_month(year, month)
	if day < 1 or day > max_day:
		push_warning("GameClock: set_datetime day %d out of range (1-%d); ignored." % [day, max_day])
		return
	if hour < 0.0 or hour > 24.0:
		push_warning("GameClock: set_datetime hour %.2f out of range (0-24); ignored." % hour)
		return
	total_seconds = (
		float(GameCalendar.days_from_civil(year, month, day)) * SECONDS_PER_DAY
		+ hour * SECONDS_PER_HOUR
	)
	_emit_boundaries()


func get_state() -> Dictionary:
	return {
		"total_seconds": total_seconds,
		"time_scale": time_scale,
		"paused": paused,
	}


## Unknown or invalid input leaves the clock unchanged and warns.
func load_state(state: Dictionary) -> void:
	for key: Variant in state:
		if not (key is String) or not KNOWN_STATE_KEYS.has(key):
			push_warning("GameClock: load_state ignored; unknown key '%s'." % str(key))
			return
	if not state.has("total_seconds"):
		push_warning("GameClock: load_state ignored; missing 'total_seconds'.")
		return
	var seconds_value: Variant = state["total_seconds"]
	if not _is_number(seconds_value):
		push_warning("GameClock: load_state ignored; 'total_seconds' must be a number.")
		return
	var scale_value: Variant = state.get("time_scale", time_scale)
	if not _is_number(scale_value):
		push_warning("GameClock: load_state ignored; 'time_scale' must be a number.")
		return
	var paused_value: Variant = state.get("paused", paused)
	if not (paused_value is bool):
		push_warning("GameClock: load_state ignored; 'paused' must be a bool.")
		return
	total_seconds = float(seconds_value)
	time_scale = float(scale_value)
	paused = bool(paused_value)
	_emit_boundaries()


func _sync_boundaries() -> void:
	_last_minute_index = _minute_index()
	_last_hour_index = _hour_index()
	_last_day_index = _day_index()
	_last_period = get_period()


## Emits each crossed boundary at most once per call, with the final state.
func _emit_boundaries() -> void:
	var minute_index: int = _minute_index()
	var hour_index: int = _hour_index()
	var day_index: int = _day_index()
	var period: Period = get_period()
	if minute_index != _last_minute_index:
		_last_minute_index = minute_index
		minute_changed.emit()
	if hour_index != _last_hour_index:
		_last_hour_index = hour_index
		hour_changed.emit(get_hour())
	if day_index != _last_day_index:
		_last_day_index = day_index
		day_changed.emit(get_year(), get_month(), get_day())
	if period != _last_period:
		_last_period = period
		period_changed.emit(period)


func _minute_index() -> int:
	return floori(total_seconds / SECONDS_PER_MINUTE)


func _hour_index() -> int:
	return floori(total_seconds / SECONDS_PER_HOUR)


func _day_index() -> int:
	return floori(total_seconds / SECONDS_PER_DAY)


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
