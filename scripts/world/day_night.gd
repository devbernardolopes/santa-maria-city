class_name DayNight
extends CanvasModulate
## Day/night sky tint driven by the clock and weather. The HUD is a CanvasLayer and stays untinted.

const NIGHT_COLOR: Color = Color("3a4268")
const TWILIGHT_COLOR: Color = Color("f0b48a")
const DAY_COLOR: Color = Color.WHITE
const OVERCAST_COLOR: Color = Color("c9ced8")
const TWILIGHT_WINDOW_HOURS: float = 1.0
const OVERCAST_CLOUD_FACTOR: float = 0.35
const OVERCAST_RAIN_FACTOR: float = 0.15
const TWEEN_DURATION_S: float = 0.5

## Disables the tint entirely (the color stays white).
@export var enabled: bool = true:
	set(value):
		enabled = value
		_apply_target(true)

var _tween: Tween = null


func _ready() -> void:
	color = _target_color()
	GameClock.minute_changed.connect(_on_minute_changed)


func _on_minute_changed() -> void:
	_apply_target(false)


func _apply_target(instant: bool) -> void:
	if not is_inside_tree():
		return
	var target: Color = _target_color()
	if instant:
		_kill_tween()
		color = target
		return
	if color.is_equal_approx(target):
		return
	_kill_tween()
	_tween = create_tween()
	(
		_tween
		. tween_property(self, "color", target, TWEEN_DURATION_S)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_IN_OUT)
	)


func _target_color() -> Color:
	if not enabled:
		return Color.WHITE
	var hour: float = GameClock.get_hour_float()
	var sunrise: float = GameClock.get_sunrise_hour()
	var sunset: float = GameClock.get_sunset_hour()
	var result: Color
	if hour < sunrise - TWILIGHT_WINDOW_HOURS:
		result = NIGHT_COLOR
	elif hour < sunrise:
		result = NIGHT_COLOR.lerp(
			TWILIGHT_COLOR, smoothstep(sunrise - TWILIGHT_WINDOW_HOURS, sunrise, hour)
		)
	elif hour < sunrise + TWILIGHT_WINDOW_HOURS:
		result = TWILIGHT_COLOR.lerp(
			DAY_COLOR, smoothstep(sunrise, sunrise + TWILIGHT_WINDOW_HOURS, hour)
		)
	elif hour < sunset - TWILIGHT_WINDOW_HOURS:
		result = DAY_COLOR
	elif hour < sunset:
		result = DAY_COLOR.lerp(
			TWILIGHT_COLOR, smoothstep(sunset - TWILIGHT_WINDOW_HOURS, sunset, hour)
		)
	elif hour < sunset + TWILIGHT_WINDOW_HOURS:
		result = TWILIGHT_COLOR.lerp(
			NIGHT_COLOR, smoothstep(sunset, sunset + TWILIGHT_WINDOW_HOURS, hour)
		)
	else:
		result = NIGHT_COLOR
	var weather: WeatherSample = GameWeather.current
	if weather != null:
		var overcast: float = (
			weather.cloud_cover * OVERCAST_CLOUD_FACTOR
			+ weather.rain_intensity * OVERCAST_RAIN_FACTOR
		)
		overcast = clampf(overcast * _daylight_weight(hour, sunrise, sunset), 0.0, 1.0)
		result = result.lerp(OVERCAST_COLOR, overcast)
	return result


## 0 at deep night, 1 between sunrise and sunset, ramping across the twilight windows.
func _daylight_weight(hour: float, sunrise: float, sunset: float) -> float:
	if hour < sunrise - TWILIGHT_WINDOW_HOURS or hour >= sunset + TWILIGHT_WINDOW_HOURS:
		return 0.0
	if hour >= sunrise and hour < sunset:
		return 1.0
	if hour < sunrise:
		return smoothstep(sunrise - TWILIGHT_WINDOW_HOURS, sunrise, hour)
	return 1.0 - smoothstep(sunset, sunset + TWILIGHT_WINDOW_HOURS, hour)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
