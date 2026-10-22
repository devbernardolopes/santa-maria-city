extends Node
## Deterministic weather: a pure function of the seed and GameClock time, recomputed each minute.

signal weather_changed(sample: WeatherSample)

const FEATURE_SCALE_HOURS: float = 18.0
const DAY_OFFSET_SCALE_DAYS: float = 5.0
const OFFSET_NOISE_SALT: int = 1
const RAIN_THRESHOLD: float = 0.45
const CLOUDY_THRESHOLD: float = 0.1
const RAIN_RANGE: float = 0.55
const CLOUD_OFFSET: float = 0.3
const CLOUD_RANGE: float = 1.3
const SEASONAL_BASE_C: float = 19.0
const SEASONAL_AMPLITUDE_C: float = 6.5
const SEASONAL_PEAK_DOY: int = 20
const DIURNAL_AMPLITUDE_C: float = 5.0
const DIURNAL_PEAK_HOUR: float = 15.0
const DIURNAL_PERIOD_HOURS: float = 24.0
const DAY_OFFSET_AMPLITUDE_C: float = 3.0
const CLOUD_COOLING_C: float = 2.0
const RAIN_COOLING_C: float = 2.0
const EMIT_TEMPERATURE_DELTA_C: float = 0.5

@export var weather_seed: int = 20261020

var current: WeatherSample = null

var _last_emitted: WeatherSample = null


func _ready() -> void:
	current = compute(weather_seed, GameClock.total_seconds)
	_last_emitted = current
	GameClock.minute_changed.connect(_on_minute_changed)


## Weather for an arbitrary time, with no hidden state: jumping the clock stays consistent.
static func compute(seed_value: int, total_seconds: float) -> WeatherSample:
	var t_hours: float = total_seconds / GameCalendar.SECONDS_PER_HOUR
	var n: float = _noise_1d(seed_value, t_hours / FEATURE_SCALE_HOURS)
	var sample := WeatherSample.new()
	sample.cloud_cover = clampf((n + CLOUD_OFFSET) / CLOUD_RANGE, 0.0, 1.0)
	if n > RAIN_THRESHOLD:
		sample.condition = WeatherSample.Condition.RAIN
		sample.rain_intensity = clampf((n - RAIN_THRESHOLD) / RAIN_RANGE, 0.0, 1.0)
	elif n > CLOUDY_THRESHOLD:
		sample.condition = WeatherSample.Condition.CLOUDY
	else:
		sample.condition = WeatherSample.Condition.CLEAR
	sample.temperature_c = _temperature_c(seed_value, total_seconds, sample.cloud_cover, sample.is_raining())
	return sample


func get_state() -> Dictionary:
	return {"weather_seed": weather_seed}


## Unknown or invalid input leaves the seed unchanged and warns.
func load_state(state: Dictionary) -> void:
	for key: Variant in state:
		if not (key is String) or String(key) != "weather_seed":
			push_warning("GameWeather: load_state ignored; unknown key '%s'." % str(key))
			return
	if not state.has("weather_seed"):
		push_warning("GameWeather: load_state ignored; missing 'weather_seed'.")
		return
	var seed_value: Variant = state["weather_seed"]
	if not (seed_value is int):
		push_warning("GameWeather: load_state ignored; 'weather_seed' must be an int.")
		return
	weather_seed = seed_value
	current = compute(weather_seed, GameClock.total_seconds)
	_publish()


func _on_minute_changed() -> void:
	current = compute(weather_seed, GameClock.total_seconds)
	_publish()


## Emits only when the condition changes or the temperature moved at least 0.5 °C.
func _publish() -> void:
	if _last_emitted == null:
		_last_emitted = current
		return
	var condition_changed: bool = current.condition != _last_emitted.condition
	var temperature_delta: float = absf(current.temperature_c - _last_emitted.temperature_c)
	_last_emitted = current
	if condition_changed or temperature_delta >= EMIT_TEMPERATURE_DELTA_C:
		weather_changed.emit(current)


static func _temperature_c(seed_value: int, total_seconds: float, cloud_cover: float, raining: bool) -> float:
	var t_days: float = total_seconds / GameCalendar.SECONDS_PER_DAY
	var days: int = floori(t_days)
	var civil: Vector3i = GameCalendar.civil_from_days(days)
	var doy: int = GameCalendar.day_of_year(civil.x, civil.y, civil.z)
	var hour: float = fposmod(total_seconds, GameCalendar.SECONDS_PER_DAY) / GameCalendar.SECONDS_PER_HOUR
	var seasonal: float = SEASONAL_BASE_C + SEASONAL_AMPLITUDE_C * cos(TAU * (doy - SEASONAL_PEAK_DOY) / 365.0)
	var diurnal: float = DIURNAL_AMPLITUDE_C * cos(TAU * (hour - DIURNAL_PEAK_HOUR) / DIURNAL_PERIOD_HOURS)
	var day_offset: float = (
		DAY_OFFSET_AMPLITUDE_C
		* _noise_1d(seed_value + OFFSET_NOISE_SALT, t_days / DAY_OFFSET_SCALE_DAYS)
	)
	var total: float = seasonal + diurnal + day_offset
	if hour >= GameCalendar.sunrise_hour(doy) and hour < GameCalendar.sunset_hour(doy):
		total -= CLOUD_COOLING_C * cloud_cover
	if raining:
		total -= RAIN_COOLING_C
	return total


static func _noise_1d(seed_value: int, position: float) -> float:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	noise.frequency = 1.0
	return noise.get_noise_1d(position)
