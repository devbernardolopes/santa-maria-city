class_name TerrainQuery
extends RefCounted
## Point → terrain lookup on a uniform grid. Built once per map load, at runtime only.

const CELL_SIZE_M: float = 32.0
const CATEGORY_RANKS: Dictionary = {
	&"buildings": 0,
	&"roads": 1,
	&"waterways": 2,
	&"landuse": 3,
}
const DEFAULT_RANK: int = 4

## Set by MapLoader after a successful runtime build; null before the map loads.
static var active: TerrainQuery = null

var _points: Array[PackedVector2Array] = []
var _bounds: Array[Rect2] = []
var _samples: Array[TerrainSample] = []
var _ranks: PackedInt32Array = PackedInt32Array()
var _accumulated_bounds: Rect2 = Rect2()
var _has_accumulated_bounds: bool = false
var _origin_m: Vector2 = Vector2.ZERO
var _columns: int = 0
var _rows: int = 0
var _cells: Array = []
var _finalized: bool = false


## Ring points in meters, outer ring only (holes ignored, like drawing and collisions).
func add_polygon(
	points_m: PackedVector2Array,
	category: StringName,
	kind: StringName,
	surface: StringName,
	style_id: StringName,
	osm_id: String
) -> void:
	if points_m.size() < 3:
		return
	var bounds := Rect2(points_m[0], Vector2.ZERO)
	for point: Vector2 in points_m:
		bounds = bounds.expand(point)
	var sample := TerrainSample.new()
	sample.category = category
	sample.kind = kind
	sample.surface = surface
	sample.style_id = style_id
	sample.osm_id = osm_id
	_points.append(points_m)
	_bounds.append(bounds)
	_samples.append(sample)
	_ranks.append(int(CATEGORY_RANKS.get(category, DEFAULT_RANK)))
	if not _has_accumulated_bounds:
		_accumulated_bounds = bounds
		_has_accumulated_bounds = true
	else:
		_accumulated_bounds = _accumulated_bounds.merge(bounds)


## Builds the grid; an empty bounds_m falls back to the accumulated polygon bounds.
func finalize(bounds_m: Rect2) -> void:
	_cells.clear()
	_finalized = false
	var bounds: Rect2 = bounds_m
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		bounds = _accumulated_bounds
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	_origin_m = bounds.position
	_columns = maxi(1, ceili(bounds.size.x / CELL_SIZE_M))
	_rows = maxi(1, ceili(bounds.size.y / CELL_SIZE_M))
	_cells.resize(_columns * _rows)
	for cell_index: int in range(_cells.size()):
		var cell: Array[int] = []
		_cells[cell_index] = cell
	for polygon_index: int in range(_points.size()):
		_index_polygon_in_cells(polygon_index)
	for cell_index: int in range(_cells.size()):
		var cell: Array[int] = _cells[cell_index]
		if cell.size() > 1:
			cell.sort_custom(_compare_entries)
	_finalized = true


## Top-most polygon at the point, by drawing priority; the default sample if none.
func sample(position_m: Vector2) -> TerrainSample:
	if not _finalized or _cells.is_empty():
		return TerrainSample.default_sample()
	var column: int = floori((position_m.x - _origin_m.x) / CELL_SIZE_M)
	var row: int = floori((position_m.y - _origin_m.y) / CELL_SIZE_M)
	if column < 0 or column >= _columns or row < 0 or row >= _rows:
		return TerrainSample.default_sample()
	var cell: Array[int] = _cells[row * _columns + column]
	for polygon_index: int in cell:
		if not _bounds[polygon_index].has_point(position_m):
			continue
		if Geometry2D.is_point_in_polygon(position_m, _points[polygon_index]):
			return _samples[polygon_index]
	return TerrainSample.default_sample()


func kind_at(position_m: Vector2) -> StringName:
	return sample(position_m).kind


func _index_polygon_in_cells(polygon_index: int) -> void:
	var bounds: Rect2 = _bounds[polygon_index]
	var min_column: int = clampi(floori((bounds.position.x - _origin_m.x) / CELL_SIZE_M), 0, _columns - 1)
	var min_row: int = clampi(floori((bounds.position.y - _origin_m.y) / CELL_SIZE_M), 0, _rows - 1)
	var max_column: int = clampi(ceili((bounds.end.x - _origin_m.x) / CELL_SIZE_M), 0, _columns - 1)
	var max_row: int = clampi(ceili((bounds.end.y - _origin_m.y) / CELL_SIZE_M), 0, _rows - 1)
	for row: int in range(min_row, max_row + 1):
		for column: int in range(min_column, max_column + 1):
			var cell: Array[int] = _cells[row * _columns + column]
			cell.append(polygon_index)


## Category priority first (buildings, roads, waterways, landuse), then later features win.
func _compare_entries(a: int, b: int) -> bool:
	if _ranks[a] != _ranks[b]:
		return _ranks[a] < _ranks[b]
	return a > b
