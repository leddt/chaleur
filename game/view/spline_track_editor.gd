extends Control

## Interactive editor for a closed TrackSpline (per-point Bezier types).

enum EditMode {
	TRACE, ## Edit control points / spline shape.
	SPACES, ## Inspect / tune space segmentation.
	SECTORS, ## Select stretches between corners (may wrap past start).
}

const CAR_SCENE := preload("res://view/car.tscn")
const HANDLE_HIT_RADIUS := 12.0
const POINT_HIT_RADIUS := 14.0
const CURVE_HIT_RADIUS := 14.0
const MIN_CANVAS_SIZE := 32.0
## Half-width of the asphalt band around the centerline (pixels).
const ROAD_HALF_WIDTH := 28.0
const ASPHALT_COLOR := Color(0.28, 0.29, 0.31, 1.0)
const ASPHALT_EDGE_COLOR := Color(0.18, 0.19, 0.21, 1.0)
## Pale kerb on the race-line side of the asphalt (spot 0).
const RACE_LINE_EDGE_COLOR := Color(0.58, 0.59, 0.62, 1.0)
const RACE_LINE_EDGE_WIDTH := 5.0
const ASPHALT_OUTER_EDGE_WIDTH := 1.5
const CENTERLINE_COLOR := Color(0.95, 0.95, 0.97, 1.0)
const SPACE_EDGE_COLOR := Color(0.05, 0.05, 0.06, 0.95)
const START_LINE_COLOR := Color(0.9, 0.15, 0.12, 1.0)
const CORNER_LINE_COLOR := Color(0.2, 0.85, 0.35, 1.0)
const SPACE_SELECTED_COLOR := Color(1.0, 0.85, 0.2, 0.22)
const SECTOR_SELECTED_COLOR := Color(0.35, 0.7, 1.0, 0.2)
const CORNER_BADGE_RADIUS := 11.0
## Gap from asphalt edge to the badge's natural center.
const CORNER_BADGE_GAP := 18.0
## Spaces immediately behind the start line that form the starting grid.
const START_GRID_SPACES := 5
const START_GRID_MARKER_COLOR := Color(0.95, 0.95, 0.98, 0.6)
## Outer lane sits this far back along the track relative to the inner spot.
const OUTER_SPOT_ALONG_OFFSET := 4.0
const MIN_VIEW_ZOOM := 0.25
const MAX_VIEW_ZOOM := 4.0
const VIEW_ZOOM_STEP := 1.12

@onready var _canvas: Control = %Canvas
@onready var _summary: Label = %SummaryLabel
@onready var _mode_trace: Button = %ModeTrace
@onready var _mode_spaces: Button = %ModeSpaces
@onready var _mode_sectors: Button = %ModeSectors
@onready var _trace_section: Control = %TraceSection
@onready var _spaces_section: Control = %SpacesSection
@onready var _sectors_section: Control = %SectorsSection
@onready var _sector_info_label: Label = %SectorInfoLabel
@onready var _sector_race_line_button: Button = %SectorRaceLineButton
@onready var _type_auto: BaseButton = %TypeAuto
@onready var _type_tension: BaseButton = %TypeTension
@onready var _type_free: BaseButton = %TypeFree
@onready var _algo_center: BaseButton = %AlgoCenter
@onready var _algo_inner: BaseButton = %AlgoInner
@onready var _algo_adaptive: BaseButton = %AlgoAdaptive
@onready var _space_len_slider: HSlider = %SpaceLenSlider
@onready var _space_len_value: Label = %SpaceLenValue
@onready var _hide_space_numbers: CheckBox = %HideSpaceNumbers
@onready var _set_start_button: Button = %SetStartButton
@onready var _corner_speed_spin: SpinBox = %CornerSpeedSpin
@onready var _set_corner_button: Button = %SetCornerButton
@onready var _corner_side_button: Button = %CornerSideButton

var _spline: TrackSpline
var _selected: int = 0
var _drag_mode: String = "" ## "", "point", "out_handle", "in_handle"
var _dirty: bool = false
var _updating_type_ui: bool = false
var _updating_seg_ui: bool = false
var _updating_mode_ui: bool = false
var _updating_corner_ui: bool = false
var _spline_ready: bool = false
var _edit_mode: int = EditMode.TRACE
var _seg_params: TrackSegmenter.Params = TrackSegmenter.Params.new()
var _seg_result: TrackSegmenter.Result
## Index of the start space (display number 1). The red line is its preceding frontier.
var _start_space_index: int = 0
var _selected_space: int = -1
## space_index -> {speed_limit: int, outside: bool, offset: Vector2}
var _corners: Dictionary = {}
## Spaces-mode drag of a corner speed badge (-1 = none).
var _drag_corner_space: int = -1
## World-space grab delta: mouse - badge center at press.
var _drag_corner_grab := Vector2.ZERO
## Index into `_compute_sectors()` (-1 = none).
var _selected_sector: int = -1
## flip_key (corner before sector, or -1 if no corners) -> race line on geometric outside.
var _sector_flip_race_line: Dictionary = {}
var _cars_layer: Node2D
var _preview_cars: Array = [] ## Array[CarToken] — one per spot (inner/outer).
## View transform: screen = world * zoom + pan
var _view_pan := Vector2.ZERO
var _view_zoom := 1.0
var _panning := false


func _ready() -> void:
	_canvas.draw.connect(_on_canvas_draw)
	_canvas.gui_input.connect(_on_canvas_gui_input)
	_canvas.resized.connect(_on_canvas_resized)
	%BackButton.pressed.connect(_on_back)
	%ResetButton.pressed.connect(_on_reset)
	_setup_mode_ui()
	_setup_type_ui()
	_setup_segmentation_ui()
	_set_start_button.pressed.connect(_on_set_start_pressed)
	_setup_corner_ui()
	_setup_sector_ui()
	_apply_edit_mode()
	_ensure_preview_cars()
	# Layout may still report 0-height here — wait for a usable canvas size.
	call_deferred("_try_init_spline")


func _setup_mode_ui() -> void:
	_mode_trace.toggled.connect(_on_mode_trace_toggled)
	_mode_spaces.toggled.connect(_on_mode_spaces_toggled)
	_mode_sectors.toggled.connect(_on_mode_sectors_toggled)
	_sync_mode_buttons()


func _on_mode_trace_toggled(pressed: bool) -> void:
	if _updating_mode_ui or not pressed:
		return
	_set_edit_mode(EditMode.TRACE)


func _on_mode_spaces_toggled(pressed: bool) -> void:
	if _updating_mode_ui or not pressed:
		return
	_set_edit_mode(EditMode.SPACES)


func _on_mode_sectors_toggled(pressed: bool) -> void:
	if _updating_mode_ui or not pressed:
		return
	_set_edit_mode(EditMode.SECTORS)


func _sync_mode_buttons() -> void:
	_updating_mode_ui = true
	_mode_trace.button_pressed = _edit_mode == EditMode.TRACE
	_mode_spaces.button_pressed = _edit_mode == EditMode.SPACES
	_mode_sectors.button_pressed = _edit_mode == EditMode.SECTORS
	_updating_mode_ui = false


func _setup_type_ui() -> void:
	_type_auto.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			_on_type_radio(TrackSpline.PointType.AUTO_SMOOTH)
	)
	_type_tension.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			_on_type_radio(TrackSpline.PointType.TENSION)
	)
	_type_free.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			_on_type_radio(TrackSpline.PointType.FREE)
	)


func _set_edit_mode(mode: int) -> void:
	if _edit_mode == mode:
		return
	_edit_mode = mode
	_drag_mode = ""
	_drag_corner_space = -1
	_sync_mode_buttons()
	_apply_edit_mode()
	_refresh_info()
	_canvas.queue_redraw()


func _apply_edit_mode() -> void:
	_trace_section.visible = _edit_mode == EditMode.TRACE
	_spaces_section.visible = _edit_mode == EditMode.SPACES
	_sectors_section.visible = _edit_mode == EditMode.SECTORS
	_refresh_set_start_button()
	_refresh_corner_ui()
	_refresh_sector_ui()


func _setup_segmentation_ui() -> void:
	_seg_params.road_half_width = ROAD_HALF_WIDTH
	_seg_params.algorithm = TrackSegmenter.Algorithm.INNER_UNIFORM
	_seg_params.car_length = 36.0
	_seg_params.target_space_len = 36.0
	_algo_center.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			_on_algo_radio(TrackSegmenter.Algorithm.CENTER_UNIFORM)
	)
	_algo_inner.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			_on_algo_radio(TrackSegmenter.Algorithm.INNER_UNIFORM)
	)
	_algo_adaptive.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			_on_algo_radio(TrackSegmenter.Algorithm.ADAPTIVE_INNER)
	)
	_space_len_slider.min_value = 20.0
	_space_len_slider.max_value = 80.0
	_space_len_slider.step = 1.0
	_updating_seg_ui = true
	_sync_algo_radios()
	_space_len_slider.value = _seg_params.car_length
	_updating_seg_ui = false
	_space_len_slider.value_changed.connect(_on_space_len_changed)
	_refresh_space_len_label()
	_hide_space_numbers.toggled.connect(func(_pressed: bool) -> void:
		_canvas.queue_redraw()
	)


func _setup_corner_ui() -> void:
	_corner_speed_spin.min_value = 1.0
	_corner_speed_spin.max_value = 8.0
	_corner_speed_spin.step = 1.0
	_corner_speed_spin.rounded = true
	_corner_speed_spin.value = 4.0
	_set_corner_button.pressed.connect(_on_set_corner_pressed)
	_corner_speed_spin.value_changed.connect(_on_corner_speed_changed)
	_corner_side_button.pressed.connect(_on_corner_side_pressed)


func _make_corner_entry(speed_limit: int) -> Dictionary:
	return {
		"speed_limit": speed_limit,
		"outside": true,
		"offset": Vector2.ZERO,
	}


func _corner_speed(space: int) -> int:
	var entry: Variant = _corners.get(space)
	if entry is Dictionary:
		return int(entry.get("speed_limit", 0))
	return int(entry) if entry != null else 0


func _corner_outside(space: int) -> bool:
	var entry: Variant = _corners.get(space)
	if entry is Dictionary:
		return bool(entry.get("outside", true))
	return true


func _corner_offset(space: int) -> Vector2:
	var entry: Variant = _corners.get(space)
	if entry is Dictionary:
		return entry.get("offset", Vector2.ZERO) as Vector2
	return Vector2.ZERO


func _set_corner_speed(space: int, speed_limit: int) -> void:
	if not _corners.has(space):
		return
	var entry: Dictionary = _corners[space]
	entry["speed_limit"] = speed_limit
	_corners[space] = entry


func _set_corner_side(space: int, outside: bool) -> void:
	if not _corners.has(space):
		return
	var entry: Dictionary = _corners[space]
	entry["outside"] = outside
	entry["offset"] = Vector2.ZERO
	_corners[space] = entry


func _set_corner_offset(space: int, offset: Vector2) -> void:
	if not _corners.has(space):
		return
	var entry: Dictionary = _corners[space]
	entry["offset"] = offset
	_corners[space] = entry


func _on_algo_radio(algorithm: int) -> void:
	if _updating_seg_ui:
		return
	if _seg_params.algorithm == algorithm:
		return
	_seg_params.algorithm = algorithm
	_recompute_segmentation()
	_refresh_status()
	_refresh_info()
	_canvas.queue_redraw()


func _sync_algo_radios() -> void:
	var was := _updating_seg_ui
	_updating_seg_ui = true
	match _seg_params.algorithm:
		TrackSegmenter.Algorithm.CENTER_UNIFORM:
			_algo_center.button_pressed = true
		TrackSegmenter.Algorithm.ADAPTIVE_INNER:
			_algo_adaptive.button_pressed = true
		_:
			_algo_inner.button_pressed = true
	_updating_seg_ui = was


func _on_corner_speed_changed(value: float) -> void:
	if _updating_corner_ui:
		return
	if _selected_space < 0 or not _corners.has(_selected_space):
		return
	_set_corner_speed(_selected_space, int(value))
	_dirty = true
	_refresh_info()
	_canvas.queue_redraw()


func _on_corner_side_pressed() -> void:
	if _updating_corner_ui:
		return
	if _selected_space < 0 or not _corners.has(_selected_space):
		return
	_set_corner_side(_selected_space, not _corner_outside(_selected_space))
	_dirty = true
	_refresh_corner_ui()
	_canvas.queue_redraw()


func _on_canvas_resized() -> void:
	_canvas.queue_redraw()
	_try_init_spline()


func _canvas_ready_for_spline() -> bool:
	return _canvas.size.x >= MIN_CANVAS_SIZE and _canvas.size.y >= MIN_CANVAS_SIZE


func _try_init_spline() -> void:
	if _spline_ready or not _canvas_ready_for_spline():
		return
	_reset_spline()


func _unhandled_input(event: InputEvent) -> void:
	if _spline == null or _edit_mode != EditMode.TRACE:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_set_selected_type(TrackSpline.PointType.AUTO_SMOOTH)
				get_viewport().set_input_as_handled()
			KEY_2:
				_set_selected_type(TrackSpline.PointType.TENSION)
				get_viewport().set_input_as_handled()
			KEY_3:
				_set_selected_type(TrackSpline.PointType.FREE)
				get_viewport().set_input_as_handled()


func _reset_spline() -> void:
	if not _canvas_ready_for_spline():
		_spline_ready = false
		_refresh_summary()
		return
	var center := _canvas.size * 0.5
	var radius := mini(center.x, center.y) * 0.55
	_spline = TrackSpline.make_default_triangle(center, radius)
	_selected = 0
	_selected_space = -1
	_start_space_index = 0
	_corners.clear()
	_drag_corner_space = -1
	_selected_sector = -1
	_sector_flip_race_line.clear()
	_dirty = false
	_spline_ready = true
	_recompute_segmentation()
	_refresh_status()
	_refresh_info()
	_refresh_set_start_button()
	_canvas.queue_redraw()


func _on_reset() -> void:
	_spline_ready = false
	_reset_spline()


func _on_back() -> void:
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")


func _on_space_len_changed(value: float) -> void:
	if _updating_seg_ui:
		return
	_seg_params.car_length = value
	_seg_params.target_space_len = value
	_refresh_space_len_label()
	_recompute_segmentation()
	_refresh_status()
	_refresh_info()
	_canvas.queue_redraw()


func _refresh_space_len_label() -> void:
	_space_len_value.text = "%d px" % int(_space_len_slider.value)


func _recompute_segmentation() -> void:
	if _spline == null:
		_seg_result = null
		_refresh_summary()
		return
	_seg_params.road_half_width = ROAD_HALF_WIDTH
	_seg_result = TrackSegmenter.segment(_spline, _seg_params)
	_clamp_space_indices()
	_refresh_summary()


func _clamp_space_indices() -> void:
	if _seg_result == null or _seg_result.space_count() == 0:
		_start_space_index = 0
		_selected_space = -1
		_corners.clear()
		_selected_sector = -1
		return
	var n := _seg_result.space_count()
	_start_space_index = posmod(_start_space_index, n)
	if _selected_space >= n:
		_selected_space = -1
	var kept: Dictionary = {}
	for key in _corners.keys():
		var idx := int(key)
		if idx >= 0 and idx < n:
			var entry: Variant = _corners[key]
			if entry is Dictionary:
				kept[idx] = entry
			else:
				kept[idx] = _make_corner_entry(int(entry))
	_corners = kept
	_prune_sector_flips()
	_clamp_selected_sector()


## Corner spaces in ascending track index (closed-loop order).
func _corners_in_track_order() -> Array[int]:
	var ordered: Array[int] = []
	for key in _corners.keys():
		ordered.append(int(key))
	ordered.sort()
	return ordered


## Sectors = stretches between consecutive corners (may wrap past the start line).
## Each entry: {from: int, to: int} inclusive — from the space after a corner
## through the next corner space.
func _compute_sectors() -> Array:
	var out: Array = []
	if _seg_result == null:
		return out
	var n := _seg_result.space_count()
	if n < 1:
		return out
	var corners := _corners_in_track_order()
	if corners.is_empty():
		out.append({
			"from": _start_space_index,
			"to": posmod(_start_space_index - 1, n),
		})
		return out
	for i in corners.size():
		var prev_corner := corners[i]
		var next_corner := corners[(i + 1) % corners.size()]
		out.append({
			"from": posmod(prev_corner + 1, n),
			"to": next_corner,
		})
	return out


func _sector_space_count(sector: Dictionary) -> int:
	if _seg_result == null:
		return 0
	var n := _seg_result.space_count()
	return posmod(int(sector.to) - int(sector.from), n) + 1


func _space_in_sector(space: int, sector: Dictionary) -> bool:
	if _seg_result == null:
		return false
	var n := _seg_result.space_count()
	return posmod(space - int(sector.from), n) <= posmod(int(sector.to) - int(sector.from), n)


func _sector_index_at_space(space: int) -> int:
	var sectors := _compute_sectors()
	for i in sectors.size():
		if _space_in_sector(space, sectors[i]):
			return i
	return -1


## Stable key for a sector's race-line flip: corner exited into the sector (-1 if none).
func _sector_flip_key(sector: Dictionary) -> int:
	if _corners.is_empty() or _seg_result == null:
		return -1
	var n := _seg_result.space_count()
	return posmod(int(sector.from) - 1, n)


func _sector_race_line_flipped(sector: Dictionary) -> bool:
	return bool(_sector_flip_race_line.get(_sector_flip_key(sector), false))


func _space_race_line_flipped(space: int) -> bool:
	var idx := _sector_index_at_space(space)
	if idx < 0:
		return false
	var sectors := _compute_sectors()
	if idx >= sectors.size():
		return false
	return _sector_race_line_flipped(sectors[idx])


func _prune_sector_flips() -> void:
	var kept: Dictionary = {}
	if _corners.is_empty():
		if _sector_flip_race_line.get(-1, false):
			kept[-1] = true
	else:
		for key in _corners.keys():
			var corner := int(key)
			if _sector_flip_race_line.get(corner, false):
				kept[corner] = true
	_sector_flip_race_line = kept


func _setup_sector_ui() -> void:
	_sector_race_line_button.pressed.connect(_on_sector_race_line_pressed)


func _on_sector_race_line_pressed() -> void:
	var sectors := _compute_sectors()
	if _selected_sector < 0 or _selected_sector >= sectors.size():
		return
	var key := _sector_flip_key(sectors[_selected_sector])
	_sector_flip_race_line[key] = not bool(_sector_flip_race_line.get(key, false))
	if not _sector_flip_race_line[key]:
		_sector_flip_race_line.erase(key)
	_dirty = true
	_refresh_sector_ui()
	_canvas.queue_redraw()


func _refresh_sector_ui() -> void:
	if _sector_info_label == null:
		return
	var sectors := _compute_sectors()
	var has_sel := _selected_sector >= 0 and _selected_sector < sectors.size()
	_sector_race_line_button.disabled = not has_sel
	if not has_sel:
		_sector_info_label.text = (
			"Aucun secteur sélectionné"
			if sectors.is_empty()
			else "%d secteurs — clique une case" % sectors.size()
		)
		_sector_race_line_button.text = "Ligne de course : intérieure"
		return
	var sector: Dictionary = sectors[_selected_sector]
	var count := _sector_space_count(sector)
	var from_disp := _display_space_number(int(sector.from))
	var to_disp := _display_space_number(int(sector.to))
	_sector_info_label.text = "Secteur %d / %d — cases %d→%d (%d)" % [
		_selected_sector + 1,
		sectors.size(),
		from_disp,
		to_disp,
		count,
	]
	var flipped := _sector_race_line_flipped(sector)
	_sector_race_line_button.text = (
		"Ligne de course : extérieure" if flipped else "Ligne de course : intérieure"
	)


func _on_set_start_pressed() -> void:
	if _selected_space < 0 or _seg_result == null:
		return
	_start_space_index = _selected_space
	_dirty = true
	_clamp_selected_sector()
	_refresh_info()
	_refresh_set_start_button()
	_canvas.queue_redraw()


func _refresh_set_start_button() -> void:
	if _set_start_button == null:
		return
	var can_set := (
		_edit_mode == EditMode.SPACES
		and _selected_space >= 0
		and _seg_result != null
		and _selected_space != _start_space_index
	)
	_set_start_button.disabled = not can_set
	if _selected_space >= 0 and _selected_space == _start_space_index:
		_set_start_button.text = "Départ ✓"
	else:
		_set_start_button.text = "Case de départ"


func _on_set_corner_pressed() -> void:
	if _selected_space < 0 or _seg_result == null:
		return
	if _corners.has(_selected_space):
		_corners.erase(_selected_space)
		if _drag_corner_space == _selected_space:
			_drag_corner_space = -1
	else:
		_corners[_selected_space] = _make_corner_entry(int(_corner_speed_spin.value))
	_dirty = true
	_prune_sector_flips()
	_clamp_selected_sector()
	_refresh_info()
	_refresh_corner_ui()
	_canvas.queue_redraw()


func _clamp_selected_sector() -> void:
	var sector_count := _compute_sectors().size()
	if _selected_sector >= sector_count:
		_selected_sector = -1


func _refresh_corner_ui() -> void:
	if _set_corner_button == null:
		return
	var has_sel := (
		_edit_mode == EditMode.SPACES
		and _selected_space >= 0
		and _seg_result != null
	)
	var has_corner := has_sel and _corners.has(_selected_space)
	_set_corner_button.disabled = not has_sel
	_corner_speed_spin.editable = has_sel
	_corner_side_button.disabled = not has_corner
	if has_corner:
		_set_corner_button.text = "Retirer virage"
		_updating_corner_ui = true
		_corner_speed_spin.value = _corner_speed(_selected_space)
		_updating_corner_ui = false
		_corner_side_button.text = (
			"Extérieur" if _corner_outside(_selected_space) else "Intérieur"
		)
	else:
		_set_corner_button.text = "Virage"
		_corner_side_button.text = "Extérieur"


func _on_type_radio(type: int) -> void:
	if _updating_type_ui or _spline == null:
		return
	_set_selected_type(type)


func _set_selected_type(type: int) -> void:
	if _spline == null or _spline.point_count() == 0:
		return
	var cp := _spline.get_point(_selected)
	if cp.type == type:
		_sync_type_radios()
		return
	_spline.set_point_type(_selected, type)
	_dirty = true
	_refresh_status()
	_refresh_info()
	_canvas.queue_redraw()


func _sync_type_radios() -> void:
	if _spline == null or _spline.point_count() == 0:
		return
	_updating_type_ui = true
	match _spline.get_point(_selected).type:
		TrackSpline.PointType.TENSION:
			_type_tension.button_pressed = true
		TrackSpline.PointType.FREE:
			_type_free.button_pressed = true
		_:
			_type_auto.button_pressed = true
	_updating_type_ui = false


func _refresh_summary() -> void:
	var spaces := 0 if _seg_result == null else _seg_result.space_count()
	var sectors := _compute_sectors().size()
	_summary.text = "%d cases · %d virages · %d secteurs" % [spaces, _corners.size(), sectors]


func _refresh_status() -> void:
	_refresh_summary()


func _refresh_info() -> void:
	if _edit_mode == EditMode.SPACES:
		_refresh_set_start_button()
		_refresh_corner_ui()
		_refresh_summary()
		return
	if _edit_mode == EditMode.SECTORS:
		_refresh_sector_ui()
		_refresh_summary()
		return
	if _spline == null or _spline.point_count() == 0:
		_refresh_summary()
		return
	_selected = clampi(_selected, 0, _spline.point_count() - 1)
	_sync_type_radios()
	_refresh_summary()


func _on_canvas_draw() -> void:
	if _spline == null:
		return
	_recompute_segmentation()
	var font := ThemeDB.fallback_font
	# Soft grid stays in screen space.
	var step := 40.0
	var grid_col := Color(1, 1, 1, 0.04)
	var x := 0.0
	while x < _canvas.size.x:
		_canvas.draw_line(Vector2(x, 0), Vector2(x, _canvas.size.y), grid_col, 1.0)
		x += step
	var y := 0.0
	while y < _canvas.size.y:
		_canvas.draw_line(Vector2(0, y), Vector2(_canvas.size.x, y), grid_col, 1.0)
		y += step

	_canvas.draw_set_transform(_view_pan, 0.0, Vector2(_view_zoom, _view_zoom))
	_apply_view_to_cars()

	var baked := _spline.baked_points()
	if baked.size() >= 2:
		_draw_road(baked)
		_draw_spaces()
		_draw_centerline(baked)

	if _edit_mode == EditMode.TRACE:
		_draw_control_points(font)
	_sync_preview_cars()


func _screen_to_world(screen: Vector2) -> Vector2:
	return (screen - _view_pan) / _view_zoom


func _hit_radius(screen_radius: float) -> float:
	return screen_radius / _view_zoom


func _apply_view_to_cars() -> void:
	if _cars_layer == null:
		return
	_cars_layer.position = _view_pan
	_cars_layer.scale = Vector2(_view_zoom, _view_zoom)


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var new_zoom := clampf(_view_zoom * factor, MIN_VIEW_ZOOM, MAX_VIEW_ZOOM)
	if is_equal_approx(new_zoom, _view_zoom):
		return
	_view_pan = screen_pos - (screen_pos - _view_pan) * (new_zoom / _view_zoom)
	_view_zoom = new_zoom
	_apply_view_to_cars()
	_canvas.queue_redraw()


## Shared view navigation (pan / zoom). Returns true if the event was consumed.
func _handle_view_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
			_canvas.accept_event()
			return true
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			if mb.ctrl_pressed:
				_nudge_tension(0.05)
			else:
				_zoom_at(mb.position, VIEW_ZOOM_STEP)
			_canvas.accept_event()
			return true
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			if mb.ctrl_pressed:
				_nudge_tension(-0.05)
			else:
				_zoom_at(mb.position, 1.0 / VIEW_ZOOM_STEP)
			_canvas.accept_event()
			return true
	elif event is InputEventMouseMotion and _panning:
		var mm := event as InputEventMouseMotion
		_view_pan += mm.relative
		_apply_view_to_cars()
		_canvas.queue_redraw()
		_canvas.accept_event()
		return true
	return false


func _ensure_preview_cars() -> void:
	if _cars_layer == null:
		_cars_layer = Node2D.new()
		_cars_layer.name = "PreviewCars"
		_canvas.add_child(_cars_layer)
		_apply_view_to_cars()
	while _preview_cars.size() < 2:
		var car := CAR_SCENE.instantiate() as CarToken
		_cars_layer.add_child(car)
		car.setup(_preview_cars.size())
		_preview_cars.append(car)


func _sync_preview_cars() -> void:
	_ensure_preview_cars()
	var space := -1
	if _seg_result != null and _seg_result.space_count() >= 2:
		if _edit_mode == EditMode.SPACES and _selected_space >= 0:
			space = _selected_space
		elif _edit_mode == EditMode.SECTORS and _selected_sector >= 0:
			var sectors := _compute_sectors()
			if _selected_sector < sectors.size():
				# Mid-sector space so the race-line flip is obvious while editing.
				var sector: Dictionary = sectors[_selected_sector]
				var count := _sector_space_count(sector)
				var n := _seg_result.space_count()
				space = posmod(int(sector.from) + int(count / 2), n)
	var show := space >= 0
	_cars_layer.visible = show
	if not show:
		return
	var poses := _space_slot_poses(space)
	for i in mini(2, poses.size()):
		var car: CarToken = _preview_cars[i]
		var pose: Dictionary = poses[i]
		car.set_pose(pose.pos, pose.heading)
		car.visible = true


## Mid-space poses for spot 0 (race line) and spot 1 (outer).
## Outer is nudged rearward so the two cars don't sit side-by-side flush.
## A flipped sector swaps which geometric side is the race line.
func _space_slot_poses(space_index: int) -> Array:
	if _seg_result == null or _seg_result.space_count() < 2:
		return []
	var poses := _seg_result.space_slot_poses(
		space_index,
		_seg_params.road_half_width,
		_seg_params.spot_inset
	)
	if poses.size() < 2:
		return poses
	var race: Dictionary = (poses[0] as Dictionary).duplicate()
	var outer: Dictionary = (poses[1] as Dictionary).duplicate()
	if _space_race_line_flipped(space_index):
		var tmp_pos: Vector2 = race.pos
		race["pos"] = outer.pos
		outer["pos"] = tmp_pos
	var heading: Vector2 = outer.heading
	if heading.length_squared() > 0.0001:
		outer["pos"] = (outer.pos as Vector2) - heading.normalized() * OUTER_SPOT_ALONG_OFFSET
	return [race, outer]


func _draw_control_points(font: Font) -> void:
	for i in _spline.point_count():
		var cp := _spline.get_point(i)
		var selected := i == _selected
		if selected and cp.type != TrackSpline.PointType.AUTO_SMOOTH:
			var in_h := _spline.in_handle_world(i)
			var out_h := _spline.out_handle_world(i)
			var out_col := Color(0.35, 0.75, 1.0, 0.9)
			var in_col := Color(0.75, 0.45, 1.0, 0.9) if cp.type == TrackSpline.PointType.FREE else out_col
			_canvas.draw_line(cp.position, out_h, out_col, 1.5)
			_canvas.draw_line(cp.position, in_h, in_col, 1.5)
			var in_r := 6.0 if cp.type == TrackSpline.PointType.FREE else 3.5
			_canvas.draw_circle(out_h, 6.0, out_col)
			_canvas.draw_circle(in_h, in_r, in_col)

		var fill := _point_fill_color(cp.type, selected)
		var radius := 10.0 if selected else 8.0
		_canvas.draw_circle(cp.position, radius, fill)
		_canvas.draw_arc(cp.position, radius, 0.0, TAU, 24, Color.WHITE if selected else Color(0, 0, 0, 0.7), 2.0)
		_canvas.draw_string(
			font,
			cp.position + Vector2(12, -8),
			"%d %s" % [i + 1, _type_letter(cp.type)],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			13,
			Color(1, 1, 1, 0.85)
		)


func _draw_spaces() -> void:
	if _seg_result == null or _seg_result.space_count() < 2:
		return
	var font := ThemeDB.fallback_font
	var n := _seg_result.space_count()
	# Selection fill under separators (curved asphalt ribbon, not a flat quad).
	if _edit_mode == EditMode.SPACES and _selected_space >= 0:
		var ribbon := _seg_result.space_ribbon(_selected_space, ROAD_HALF_WIDTH)
		if ribbon.size() >= 3:
			_canvas.draw_colored_polygon(ribbon, SPACE_SELECTED_COLOR)
	elif _edit_mode == EditMode.SECTORS and _selected_sector >= 0:
		_draw_selected_sector_highlight()
	for i in n:
		var a: TrackSegmenter.Frontier = _seg_result.frontiers[i]
		var inner_edge := a.center + a.inside_normal * ROAD_HALF_WIDTH
		var outer_edge := a.center - a.inside_normal * ROAD_HALF_WIDTH
		var is_start_line := i == _start_space_index
		# Line that follows space (i-1): exit of a corner space.
		var space_before := posmod(i - 1, n)
		var is_corner_exit := _corners.has(space_before)
		var col := SPACE_EDGE_COLOR
		var width := 2.0
		if is_start_line:
			col = START_LINE_COLOR
			width = 3.5
		elif is_corner_exit:
			col = CORNER_LINE_COLOR
			width = 3.5
		_canvas.draw_line(inner_edge, outer_edge, col, width)
		if is_corner_exit:
			var badge_c := _corner_badge_center(space_before, a)
			_draw_corner_limit_badge(font, badge_c, _corner_speed(space_before))
		if not _hide_space_numbers.button_pressed:
			# Label the space that begins after this frontier (display number from start).
			var b: TrackSegmenter.Frontier = _seg_result.frontiers[(i + 1) % n]
			var label_pos := a.center.lerp(b.center, 0.35) + a.inside_normal * 10.0
			_canvas.draw_string(
				font,
				label_pos,
				str(_display_space_number(i)),
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				11,
				Color(1, 1, 1, 0.7)
			)
	_draw_start_grid_markers()


func _draw_selected_sector_highlight() -> void:
	var sectors := _compute_sectors()
	if _selected_sector < 0 or _selected_sector >= sectors.size():
		return
	var sector: Dictionary = sectors[_selected_sector]
	var n := _seg_result.space_count()
	var space := int(sector.from)
	while true:
		var ribbon := _seg_result.space_ribbon(space, ROAD_HALF_WIDTH)
		if ribbon.size() >= 3:
			_canvas.draw_colored_polygon(ribbon, SECTOR_SELECTED_COLOR)
		if space == int(sector.to):
			break
		space = posmod(space + 1, n)


## White "]" pads on the five spaces behind the start/finish line (2 spots each).
func _draw_start_grid_markers() -> void:
	if _seg_result == null or _seg_result.space_count() < 2:
		return
	var n := _seg_result.space_count()
	var rows := mini(START_GRID_SPACES, n)
	var lateral := ROAD_HALF_WIDTH * _seg_params.spot_inset
	for row in rows:
		var space := posmod(_start_space_index - 1 - row, n)
		var exit_i := posmod(space + 1, n)
		var fr: TrackSegmenter.Frontier = _seg_result.frontiers[exit_i]
		var fwd := fr.tangent
		if fwd.length_squared() < 0.0001:
			continue
		fwd = fwd.normalized()
		# Behind the exit line = into this space (anti-racing direction).
		# Spot 0 (race line) follows sector flip; spot 1 stays nudged back.
		var flipped := _space_race_line_flipped(space)
		var race_side := fr.inside_normal if not flipped else -fr.inside_normal
		_draw_start_grid_marker(fr.center - fwd * 4.0 + race_side * lateral, fwd)
		_draw_start_grid_marker(
			fr.center - fwd * (4.0 + OUTER_SPOT_ALONG_OFFSET) - race_side * lateral,
			fwd
		)


## Bracket "]" : spine parallel to the start line, short arms rearward.
func _draw_start_grid_marker(center: Vector2, heading: Vector2) -> void:
	var fwd := heading.normalized()
	var right := Vector2(-fwd.y, fwd.x)
	var half_w := 8.5
	var arm := 5.0
	var t := 1.0 # half stroke thickness
	# Non-overlapping quads so alpha stays even at the corners.
	_draw_start_grid_quad(
		center, right, fwd,
		-half_w + t, half_w - t, -t, t
	) # spine (between the arms)
	_draw_start_grid_quad(
		center, right, fwd,
		-half_w - t, -half_w + t, -arm, t
	) # arm A + its corner
	_draw_start_grid_quad(
		center, right, fwd,
		half_w - t, half_w + t, -arm, t
	) # arm B + its corner


func _draw_start_grid_quad(
	origin: Vector2, right: Vector2, fwd: Vector2,
	r0: float, r1: float, f0: float, f1: float
) -> void:
	_canvas.draw_colored_polygon(
		PackedVector2Array([
			origin + right * r0 + fwd * f0,
			origin + right * r1 + fwd * f0,
			origin + right * r1 + fwd * f1,
			origin + right * r0 + fwd * f1,
		]),
		START_GRID_MARKER_COLOR
	)


## Natural badge center on the outside or inside shoulder of the exit frontier.
func _corner_badge_natural(frontier: TrackSegmenter.Frontier, outside: bool) -> Vector2:
	var lateral := ROAD_HALF_WIDTH + CORNER_BADGE_GAP
	if outside:
		return frontier.center - frontier.inside_normal * lateral
	return frontier.center + frontier.inside_normal * lateral


func _corner_badge_center(space: int, frontier: Variant = null) -> Vector2:
	if frontier == null:
		if _seg_result == null or _seg_result.space_count() == 0:
			return Vector2.ZERO
		var exit_i := posmod(space + 1, _seg_result.space_count())
		frontier = _seg_result.frontiers[exit_i]
	return _corner_badge_natural(frontier as TrackSegmenter.Frontier, _corner_outside(space)) + _corner_offset(space)


## Green ring, white fill, black digits — reads as a speed-limit disc beside the exit line.
func _draw_corner_limit_badge(font: Font, center: Vector2, limit: int) -> void:
	var r := CORNER_BADGE_RADIUS
	var font_size := 12
	_canvas.draw_circle(center, r, Color.WHITE)
	_canvas.draw_arc(center, r - 1.5, 0.0, TAU, 28, CORNER_LINE_COLOR, 2.5, true)
	var text := str(limit)
	var extent := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	_canvas.draw_string(
		font,
		center + Vector2(-extent.x * 0.5, extent.y * 0.34),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color.BLACK
	)


func _display_space_number(space_index: int) -> int:
	if _seg_result == null or _seg_result.space_count() == 0:
		return space_index + 1
	var n := _seg_result.space_count()
	return posmod(space_index - _start_space_index, n) + 1


func _draw_road(baked: PackedVector2Array) -> void:
	var pts := _unique_loop_points(baked)
	if pts.size() < 3:
		return
	var loop := PackedVector2Array()
	loop.resize(pts.size() + 1)
	for i in pts.size():
		loop[i] = pts[i]
	loop[pts.size()] = pts[0]

	# Kerbs first (under asphalt): thick pale race-line side, thin dark outer.
	# Asphalt then hides mitre spikes that poke inward at sharp bends / flip joins.
	_draw_asphalt_side_edges()
	_stroke_closed_band(pts, loop, ROAD_HALF_WIDTH, ASPHALT_COLOR)


## Dark thin outer kerb + pale thick race-line kerb (honours per-sector flip).
func _draw_asphalt_side_edges() -> void:
	if _seg_result == null or _seg_result.samples.is_empty():
		return
	var race_half := RACE_LINE_EDGE_WIDTH * 0.5
	var outer_half := ASPHALT_OUTER_EDGE_WIDTH * 0.5
	var race_run := PackedVector2Array()
	var outer_run := PackedVector2Array()
	var prev_flipped := false
	var have_prev := false
	for s in _seg_result.samples:
		var inside: Vector2 = s.inside
		if inside.length_squared() < 0.0001:
			inside = Vector2.UP
		else:
			inside = inside.normalized()
		var space := _seg_result.space_index_at_offset(float(s.cum))
		var flipped := _space_race_line_flipped(space)
		if have_prev and flipped != prev_flipped:
			_stroke_asphalt_edge_run(race_run, RACE_LINE_EDGE_COLOR, RACE_LINE_EDGE_WIDTH)
			_stroke_asphalt_edge_run(outer_run, ASPHALT_EDGE_COLOR, ASPHALT_OUTER_EDGE_WIDTH)
			race_run = PackedVector2Array()
			outer_run = PackedVector2Array()
		have_prev = true
		prev_flipped = flipped
		var race_n := -inside if flipped else inside
		var center: Vector2 = s.pos
		# Centre the stroke on the asphalt lip so half sits outside (visible kerb)
		# and half sits under asphalt (absorbs sharp mitres at corners).
		race_run.append(center + race_n * (ROAD_HALF_WIDTH + race_half))
		outer_run.append(center - race_n * (ROAD_HALF_WIDTH + outer_half))
	_stroke_asphalt_edge_run(race_run, RACE_LINE_EDGE_COLOR, RACE_LINE_EDGE_WIDTH)
	_stroke_asphalt_edge_run(outer_run, ASPHALT_EDGE_COLOR, ASPHALT_OUTER_EDGE_WIDTH)


func _stroke_asphalt_edge_run(pts: PackedVector2Array, color: Color, width: float) -> void:
	if pts.size() < 2:
		return
	var r := width * 0.5
	# Circle stamps give round joins; polyline fills gaps between samples.
	for i in pts.size():
		_canvas.draw_circle(pts[i], r, color)
	_canvas.draw_polyline(pts, color, width, true)


func _draw_centerline(baked: PackedVector2Array) -> void:
	var pts := _unique_loop_points(baked)
	if pts.size() < 3:
		return
	var loop := PackedVector2Array()
	loop.resize(pts.size() + 1)
	for i in pts.size():
		loop[i] = pts[i]
	loop[pts.size()] = pts[0]
	_canvas.draw_polyline(loop, CENTERLINE_COLOR, 2.0, true)


func _stroke_closed_band(pts: PackedVector2Array, loop: PackedVector2Array, radius: float, color: Color) -> void:
	for i in pts.size():
		_canvas.draw_circle(pts[i], radius, color)
	_canvas.draw_polyline(loop, color, radius * 2.0, true)


## Distinct samples of a closed centerline (first point not duplicated at the end).
func _unique_loop_points(baked: PackedVector2Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if baked.is_empty():
		return pts
	pts.append(baked[0])
	for i in range(1, baked.size()):
		if baked[i].distance_squared_to(pts[pts.size() - 1]) > 0.25:
			pts.append(baked[i])
	# Bake often repeats the start at the end — drop it so the loop closure is explicit.
	if pts.size() >= 2 and pts[0].distance_squared_to(pts[pts.size() - 1]) <= 0.25:
		pts.resize(pts.size() - 1)
	return pts


func _point_fill_color(type: int, selected: bool) -> Color:
	match type:
		TrackSpline.PointType.AUTO_SMOOTH:
			return Color(0.45, 0.7, 0.95) if selected else Color(0.55, 0.65, 0.75)
		TrackSpline.PointType.FREE:
			return Color(0.95, 0.55, 0.25) if selected else Color(0.85, 0.7, 0.45)
		_:
			return Color(1.0, 0.35, 0.3) if selected else Color(0.9, 0.9, 0.95)


func _type_letter(type: int) -> String:
	match type:
		TrackSpline.PointType.AUTO_SMOOTH:
			return "A"
		TrackSpline.PointType.FREE:
			return "L"
		_:
			return "T"


func _on_canvas_gui_input(event: InputEvent) -> void:
	if _spline == null:
		return
	if _handle_view_input(event):
		return
	if _edit_mode == EditMode.SPACES:
		_on_spaces_gui_input(event)
		return
	if _edit_mode == EditMode.SECTORS:
		_on_sectors_gui_input(event)
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var world := _screen_to_world(mb.position)
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if mb.double_click and _try_cycle_type_at(world):
					pass
				else:
					_begin_left(world)
			else:
				_drag_mode = ""
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_try_remove_at(world)
	elif event is InputEventMouseMotion and _drag_mode != "":
		_continue_drag(_screen_to_world((event as InputEventMouseMotion).position))


func _on_spaces_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var world := _screen_to_world(mb.position)
		if mb.pressed:
			var badge_space := _badge_hit_at(world)
			if badge_space >= 0:
				_selected_space = badge_space
				_drag_corner_space = badge_space
				_drag_corner_grab = world - _corner_badge_center(badge_space)
				_refresh_info()
				_refresh_set_start_button()
				_refresh_corner_ui()
				_canvas.queue_redraw()
				_canvas.accept_event()
				return
			_drag_corner_space = -1
			_selected_space = _space_index_at(world)
			_refresh_info()
			_refresh_set_start_button()
			_refresh_corner_ui()
			_canvas.queue_redraw()
		elif _drag_corner_space >= 0:
			_drag_corner_space = -1
			_canvas.accept_event()
	elif event is InputEventMouseMotion and _drag_corner_space >= 0:
		if _seg_result == null or _seg_result.space_count() == 0:
			_drag_corner_space = -1
			return
		var world := _screen_to_world((event as InputEventMouseMotion).position)
		var exit_i := posmod(_drag_corner_space + 1, _seg_result.space_count())
		var frontier: TrackSegmenter.Frontier = _seg_result.frontiers[exit_i]
		var natural := _corner_badge_natural(frontier, _corner_outside(_drag_corner_space))
		_set_corner_offset(_drag_corner_space, world - _drag_corner_grab - natural)
		_dirty = true
		_canvas.queue_redraw()
		_canvas.accept_event()


## Closest corner speed badge under `world`, or -1.
func _badge_hit_at(world: Vector2) -> int:
	if _seg_result == null or _corners.is_empty():
		return -1
	var r := _hit_radius(CORNER_BADGE_RADIUS + 2.0)
	var best := -1
	var best_d := r
	for key in _corners.keys():
		var space := int(key)
		var d := world.distance_to(_corner_badge_center(space))
		if d <= best_d:
			best_d = d
			best = space
	return best


func _on_sectors_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
			return
		var space := _space_index_at(_screen_to_world(mb.position))
		if space < 0:
			_selected_sector = -1
		else:
			_selected_sector = _sector_index_at_space(space)
		_refresh_sector_ui()
		_canvas.queue_redraw()
		_canvas.accept_event()


func _space_index_at(pos: Vector2) -> int:
	if _seg_result == null or _seg_result.space_count() < 2:
		return -1
	return _seg_result.space_at_world(pos, ROAD_HALF_WIDTH)


func _begin_left(pos: Vector2) -> void:
	# Handles only exist visually for the selection; then point drag, then insert.
	var handle := _hit_editable_handle(_selected, pos)
	if handle != "":
		_drag_mode = handle
		return
	var best := _nearest_point(pos, _hit_radius(POINT_HIT_RADIUS))
	if best >= 0:
		_selected = best
		_drag_mode = "point"
		_spline.set_point_position(_selected, pos)
		_dirty = true
		_refresh_info()
		_canvas.queue_redraw()
		return
	if _try_insert_at(pos):
		return


func _try_cycle_type_at(pos: Vector2) -> bool:
	var best := _nearest_point(pos, _hit_radius(POINT_HIT_RADIUS))
	if best < 0:
		return false
	_selected = best
	_drag_mode = ""
	var current := _spline.get_point(_selected).type
	var next_type := _next_point_type(current)
	_spline.set_point_type(_selected, next_type)
	_dirty = true
	_refresh_info()
	_canvas.queue_redraw()
	return true


func _next_point_type(type: int) -> int:
	match type:
		TrackSpline.PointType.AUTO_SMOOTH:
			return TrackSpline.PointType.TENSION
		TrackSpline.PointType.TENSION:
			return TrackSpline.PointType.FREE
		_:
			return TrackSpline.PointType.AUTO_SMOOTH


func _hit_editable_handle(index: int, pos: Vector2) -> String:
	var cp := _spline.get_point(index)
	var r := _hit_radius(HANDLE_HIT_RADIUS)
	match cp.type:
		TrackSpline.PointType.AUTO_SMOOTH:
			return ""
		TrackSpline.PointType.TENSION:
			if pos.distance_to(_spline.out_handle_world(index)) <= r:
				return "out_handle"
			if pos.distance_to(_spline.in_handle_world(index)) <= r:
				return "out_handle" # mirrored — either side adjusts tension
			return ""
		TrackSpline.PointType.FREE:
			if pos.distance_to(_spline.out_handle_world(index)) <= r:
				return "out_handle"
			if pos.distance_to(_spline.in_handle_world(index)) <= r:
				return "in_handle"
			return ""
		_:
			return ""


func _try_insert_at(pos: Vector2) -> bool:
	var hit: Dictionary = _spline.closest_on_curve(pos)
	if float(hit.distance) > _hit_radius(CURVE_HIT_RADIUS):
		return false
	var new_index := _spline.insert_point_near(pos)
	if new_index < 0:
		return false
	_selected = new_index
	_drag_mode = "point"
	_dirty = true
	_refresh_status()
	_refresh_info()
	_canvas.queue_redraw()
	return true


func _try_remove_at(pos: Vector2) -> void:
	var best := _nearest_point(pos, _hit_radius(POINT_HIT_RADIUS))
	if best < 0:
		return
	if not _spline.remove_point(best):
		return
	if _selected >= _spline.point_count():
		_selected = _spline.point_count() - 1
	elif _selected > best:
		_selected -= 1
	_dirty = true
	_refresh_status()
	_refresh_info()
	_canvas.queue_redraw()


func _continue_drag(pos: Vector2) -> void:
	var cp := _spline.get_point(_selected)
	match _drag_mode:
		"point":
			_spline.set_point_position(_selected, pos)
			_dirty = true
		"out_handle":
			if cp.type == TrackSpline.PointType.TENSION:
				_spline.set_point_tension(_selected, _spline.tension_from_out_handle(_selected, pos))
			elif cp.type == TrackSpline.PointType.FREE:
				_spline.set_out_handle_world(_selected, pos)
			_dirty = true
		"in_handle":
			if cp.type == TrackSpline.PointType.FREE:
				_spline.set_in_handle_world(_selected, pos)
				_dirty = true
			else:
				return
		_:
			return
	_refresh_info()
	_canvas.queue_redraw()


func _nudge_tension(delta: float) -> void:
	var cp := _spline.get_point(_selected)
	if cp.type != TrackSpline.PointType.TENSION:
		return
	_spline.set_point_tension(_selected, cp.tension + delta)
	_dirty = true
	_refresh_info()
	_canvas.queue_redraw()


func _nearest_point(pos: Vector2, max_dist: float) -> int:
	var best := -1
	var best_d := max_dist * max_dist
	for i in _spline.point_count():
		var d := pos.distance_squared_to(_spline.get_point(i).position)
		if d <= best_d:
			best_d = d
			best = i
	return best
