class_name GameCalendar
extends RefCounted
## Proleptic Gregorian calendar rules and the Santa Maria sun model. All static.

enum Weekday { MONDAY, TUESDAY, WEDNESDAY, THURSDAY, FRIDAY, SATURDAY, SUNDAY }

const SECONDS_PER_MINUTE: float = 60.0
const SECONDS_PER_HOUR: float = 3600.0
const SECONDS_PER_DAY: float = 86400.0

const DAYS_PER_ERA: int = 146097
const EPOCH_SHIFT_DAYS: int = 719468
const EPOCH_WEEKDAY_OFFSET: int = 3

const SOLAR_NOON_HOUR: float = 12.5
const DAY_LENGTH_BASE_HOURS: float = 12.1
const DAY_LENGTH_AMPLITUDE_HOURS: float = 1.9
const DAY_LENGTH_PEAK_DOY: int = 355

const DAYS_IN_MONTH: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const WEEKDAY_NAMES: Array[String] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
const MONTH_NAMES: Array[String] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


static func is_leap_year(year: int) -> bool:
	return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)


static func days_in_month(year: int, month: int) -> int:
	if month < 1 or month > 12:
		push_warning("GameCalendar: days_in_month expects month 1-12, got %d." % month)
		return 0
	if month == 2 and is_leap_year(year):
		return 29
	return DAYS_IN_MONTH[month - 1]


## Days since 1970-01-01 (negative before the epoch).
static func days_from_civil(year: int, month: int, day: int) -> int:
	var shifted_year: int = year
	if month <= 2:
		shifted_year -= 1
	var era: int = _floor_div(shifted_year, 400)
	var year_of_era: int = shifted_year - era * 400
	var day_of_year: int = _floor_div(153 * (month + (9 if month > 2 else -3)) + 2, 5) + day - 1
	var day_of_era: int = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year
	return era * DAYS_PER_ERA + day_of_era - EPOCH_SHIFT_DAYS


## Inverse of days_from_civil: x = year, y = month, z = day.
static func civil_from_days(days: int) -> Vector3i:
	var shifted_days: int = days + EPOCH_SHIFT_DAYS
	var era: int = _floor_div(shifted_days, DAYS_PER_ERA)
	var day_of_era: int = shifted_days - era * DAYS_PER_ERA
	var year_of_era: int = (day_of_era - day_of_era / 1460 + day_of_era / 36524 - day_of_era / 146096) / 365
	var year: int = year_of_era + era * 400
	var day_of_year: int = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100)
	var month_prime: int = _floor_div(5 * day_of_year + 2, 153)
	var day: int = day_of_year - _floor_div(153 * month_prime + 2, 5) + 1
	var month: int = month_prime + 3 if month_prime < 10 else month_prime - 9
	if month <= 2:
		year += 1
	return Vector3i(year, month, day)


## 0 = Monday … 6 = Sunday.
static func weekday_of_days(days: int) -> int:
	return posmod(days + EPOCH_WEEKDAY_OFFSET, 7)


static func weekday_name(weekday: int) -> String:
	return WEEKDAY_NAMES[clampi(weekday, 0, WEEKDAY_NAMES.size() - 1)]


static func month_name(month: int) -> String:
	return MONTH_NAMES[clampi(month - 1, 0, MONTH_NAMES.size() - 1)]


## 1-based day of the year.
static func day_of_year(year: int, month: int, day: int) -> int:
	return days_from_civil(year, month, day) - days_from_civil(year, 1, 1) + 1


## Hours (0–24) of sunrise on the given day of year, for Santa Maria (UTC−3).
static func sunrise_hour(day_of_year: int) -> float:
	return SOLAR_NOON_HOUR - day_length_hours(day_of_year) * 0.5


## Hours (0–24) of sunset on the given day of year, for Santa Maria (UTC−3).
static func sunset_hour(day_of_year: int) -> float:
	return SOLAR_NOON_HOUR + day_length_hours(day_of_year) * 0.5


static func day_length_hours(day_of_year: int) -> float:
	return (
		DAY_LENGTH_BASE_HOURS
		+ DAY_LENGTH_AMPLITUDE_HOURS * cos(TAU * (day_of_year - DAY_LENGTH_PEAK_DOY) / 365.0)
	)


## Floor division; GDScript integer division truncates toward zero.
static func _floor_div(dividend: int, divisor: int) -> int:
	var quotient: int = dividend / divisor
	if dividend % divisor != 0 and (dividend < 0) != (divisor < 0):
		quotient -= 1
	return quotient
