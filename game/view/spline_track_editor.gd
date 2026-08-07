extends Control

## Interactive editor for a closed TrackSpline (per-point Bezier types).

enum EditMode {
	TRACE, ## Edit control points / spline shape.
	SPACES, ## Inspect / tune space segmentation.
	SECTORS, ## Select stretches between corners (may wrap past start).
}

const CAR_SCENE := preload("res://view/car.tscn")
const RESET_VIEW_ICON := preload("res://ui/kit/icons/recadrer.png")
const HANDLE_HIT_RADIUS := 12.0
const POINT_HIT_RADIUS := 14.0
const CURVE_HIT_RADIUS := 14.0
const MIN_CANVAS_SIZE := 32.0
## Half-width of the asphalt band around the centerline (pixels).
const ROAD_HALF_WIDTH := SplineTrackPainter.HALF_WIDTH
const CORNER_BADGE_RADIUS := SplineTrackPainter.CORNER_BADGE_RADIUS
## Gap from asphalt edge to the badge's natural center.
const CORNER_BADGE_GAP := SplineTrackPainter.CORNER_BADGE_GAP
## Spaces immediately behind the start line that form the starting grid.
const START_GRID_SPACES := SplineTrackPainter.START_GRID_SPACES
const START_GRID_MARKER_COLOR := SplineTrackPainter.START_GRID_MARKER_COLOR
## Outer lane sits this far back along the track relative to the inner spot.
const OUTER_SPOT_ALONG_OFFSET := SplineTrackPainter.OUTER_SPOT_ALONG_OFFSET
const SPACE_SELECTED_COLOR := Color(1.0, 0.85, 0.2, 0.1)
const SECTOR_SELECTED_COLOR := Color(0.5, 0.78, 1.0, 0.1)
const START_LINE_COLOR := SplineTrackPainter.START_LINE_COLOR
const CORNER_LINE_COLOR := SplineTrackPainter.CORNER_LINE_COLOR
const MIN_VIEW_ZOOM := 0.25
const MAX_VIEW_ZOOM := 4.0
const VIEW_ZOOM_STEP := 1.12
const FIT_MARGIN := 24.0

@onready var _canvas: Control = %Canvas
@onready var _summary: Label = %SummaryLabel
@onready var _track_name_edit: LineEdit = %TrackNameEdit
@onready var _builtin_check: CheckBox = %BuiltinCheck
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
@onready var _seg_mode_auto: Button = %SegModeAuto
@onready var _seg_mode_fixed: Button = %SegModeFixed
@onready var _len_row: Control = %LenRow
@onready var _count_row: Control = %CountRow
@onready var _space_len_slider: HSlider = %SpaceLenSlider
@onready var _space_len_value: Label = %SpaceLenValue
@onready var _space_count_spin: SpinBox = %SpaceCountSpin
@onready var _hide_space_numbers: CheckBox = %HideSpaceNumbers
@onready var _set_start_button: Button = %SetStartButton
@onready var _corner_speed_spin: SpinBox = %CornerSpeedSpin
@onready var _set_corner_button: Button = %SetCornerButton
@onready var _corner_side_button: Button = %CornerSideButton
@onready var _corner_details: Control = %CornerDetails

var _spline: TrackSpline
var _track_name: String = ""
## user:// path when editing an existing document; empty for a new track.
var _file_path: String = ""
var _selected: int = 0
var _drag_mode: String = "" ## "", "point", "out_handle", "in_handle"
var _dirty: bool = false
var _updating_type_ui: bool = false
var _updating_seg_ui: bool = false
var _updating_mode_ui: bool = false
var _updating_corner_ui: bool = false
var _updating_name_ui: bool = false
var _spline_ready: bool = false
var _edit_mode: int = EditMode.TRACE
var _seg_params: TrackSegmenter.Params = TrackSegmenter.Params.new()
var _seg_result: TrackSegmenter.Result
## Index of the start space (display number 1). The red line is its preceding frontier
## (exit of the previous space). Set-start places that line after the selection.
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
var _fit_pan := Vector2.ZERO
var _fit_zoom := 1.0
var _panning := false
var _reset_view_btn: Button


func _ready() -> void:
	theme = ThemeBuilder.build()
	_apply_kit_chrome()
	_setup_name_ui()
	_canvas.clip_contents = true
	_setup_reset_view_btn()
	_canvas.draw.connect(_on_canvas_draw)
	_canvas.gui_input.connect(_on_canvas_gui_input)
	_canvas.resized.connect(_on_canvas_resized)
	%BackButton.pressed.connect(_on_back)
	%SaveButton.pressed.connect(_on_save)
	_setup_mode_ui()
	_setup_type_ui()
	_setup_segmentation_ui()
	_set_start_button.pressed.connect(_on_set_start_pressed)
	_setup_corner_ui()
	_setup_sector_ui()
	_apply_edit_mode()
	_ensure_preview_cars()
	if _reset_view_btn != null:
		_canvas.move_child(_reset_view_btn, -1)
	# Layout may still report 0-height here — wait for a usable canvas size.
	call_deferred("_try_init_spline")


func _apply_kit_chrome() -> void:
	var bg := get_node_or_null("Background") as ColorRect
	if bg != null:
		bg.color = Palette.ASPHALT
	var title := get_node_or_null("Root/TopBar/Title") as Label
	if title != null:
		title.theme_type_variation = &"TitleLabel"
		title.remove_theme_font_size_override("font_size")
	%BackButton.theme_type_variation = &"Compact"
	%SaveButton.theme_type_variation = &"Primary"
	_builtin_check.visible = SplineTrackFile.can_write_builtin()
	_builtin_check.disabled = not SplineTrackFile.can_write_builtin()
	_seg_mode_auto.theme_type_variation = &"Compact"
	_seg_mode_fixed.theme_type_variation = &"Compact"
	_mode_trace.theme_type_variation = &"Compact"
	_mode_spaces.theme_type_variation = &"Compact"
	_mode_sectors.theme_type_variation = &"Compact"
	_set_start_button.theme_type_variation = &"Compact"
	_set_corner_button.theme_type_variation = &"Compact"
	_corner_side_button.theme_type_variation = &"Compact"
	_sector_race_line_button.theme_type_variation = &"Compact"
	var side := get_node_or_null("Root/MainRow/SidePanel") as PanelContainer
	if side != null:
		side.theme_type_variation = &"Instrument"
	for path in [
		"Root/MainRow/SidePanel/Margin/PanelVBox/NameSection/NameTitle",
		"Root/MainRow/SidePanel/Margin/PanelVBox/PrioSection/PrioTitle",
		"Root/MainRow/SidePanel/Margin/PanelVBox/EditSection/EditTitle",
	]:
		var section := get_node_or_null(path) as Label
		if section != null:
			section.theme_type_variation = &"Eyebrow"
			section.remove_theme_font_size_override("font_size")
			section.text = section.text.to_upper()
	for path2 in [
		"Root/MainRow/SidePanel/Margin/PanelVBox/SectorsSection/SectorHint",
		"Root/MainRow/SidePanel/Margin/PanelVBox/SummaryLabel",
	]:
		var caption := get_node_or_null(path2) as Label
		if caption != null:
			caption.theme_type_variation = &"Caption"
			caption.remove_theme_color_override("font_color")
			caption.remove_theme_font_size_override("font_size")
	_sector_info_label.theme_type_variation = &"Caption"


func _setup_name_ui() -> void:
	_track_name_edit.text_changed.connect(_on_track_name_changed)
	_builtin_check.toggled.connect(_on_builtin_toggled)
	_sync_track_name_field()
	_sync_builtin_check()


func _on_track_name_changed(value: String) -> void:
	if _updating_name_ui:
		return
	_track_name = value.strip_edges()
	_dirty = true
	_refresh_window_title()


func _on_builtin_toggled(_pressed: bool) -> void:
	if not SplineTrackFile.can_write_builtin():
		return
	_dirty = true


func _sync_builtin_check() -> void:
	_builtin_check.set_pressed_no_signal(
		SplineTrackFile.can_write_builtin() and SplineTrackFile.is_builtin_path(_file_path)
	)


func _wants_builtin_save() -> bool:
	return SplineTrackFile.can_write_builtin() and _builtin_check.button_pressed


func _sync_track_name_field() -> void:
	_updating_name_ui = true
	_track_name_edit.text = _track_name
	_updating_name_ui = false
	_refresh_window_title()


func _display_track_name() -> String:
	return _track_name if not _track_name.is_empty() else "Nouveau tracé"


func _refresh_window_title() -> void:
	var title := get_node_or_null("Root/TopBar/Title") as Label
	if title != null:
		title.text = _display_track_name()


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
	_seg_params.forced_space_count = 0
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
	_seg_mode_auto.toggled.connect(_on_seg_mode_auto_toggled)
	_seg_mode_fixed.toggled.connect(_on_seg_mode_fixed_toggled)
	_space_len_slider.min_value = 20.0
	_space_len_slider.max_value = 80.0
	_space_len_slider.step = 1.0
	_space_count_spin.min_value = float(_seg_params.min_spaces)
	_space_count_spin.max_value = float(_seg_params.max_spaces)
	_space_count_spin.step = 1.0
	_space_count_spin.rounded = true
	_updating_seg_ui = true
	_sync_algo_radios()
	_space_len_slider.value = _seg_params.car_length
	_space_count_spin.value = 24.0
	_seg_mode_auto.button_pressed = true
	_updating_seg_ui = false
	_space_len_slider.value_changed.connect(_on_space_len_changed)
	_space_count_spin.value_changed.connect(_on_space_count_changed)
	_refresh_space_len_label()
	_refresh_seg_mode_ui()
	_hide_space_numbers.toggled.connect(func(_pressed: bool) -> void:
		_canvas.queue_redraw()
	)


func _is_seg_mode_fixed() -> bool:
	return _seg_mode_fixed.button_pressed


func _on_seg_mode_auto_toggled(pressed: bool) -> void:
	if _updating_seg_ui or not pressed:
		return
	_seg_params.forced_space_count = 0
	_refresh_seg_mode_ui()
	_recompute_segmentation()
	_refresh_status()
	_refresh_info()
	_canvas.queue_redraw()


func _on_seg_mode_fixed_toggled(pressed: bool) -> void:
	if _updating_seg_ui or not pressed:
		return
	var count := int(_space_count_spin.value)
	if _seg_result != null and _seg_result.space_count() >= _seg_params.min_spaces:
		count = _seg_result.space_count()
		_updating_seg_ui = true
		_space_count_spin.set_value_no_signal(float(count))
		_updating_seg_ui = false
	_seg_params.forced_space_count = clampi(count, _seg_params.min_spaces, _seg_params.max_spaces)
	_refresh_seg_mode_ui()
	_recompute_segmentation()
	_refresh_status()
	_refresh_info()
	_canvas.queue_redraw()


func _on_space_count_changed(value: float) -> void:
	if _updating_seg_ui or not _is_seg_mode_fixed():
		return
	_seg_params.forced_space_count = clampi(
		int(value), _seg_params.min_spaces, _seg_params.max_spaces
	)
	_recompute_segmentation()
	_refresh_status()
	_refresh_info()
	_canvas.queue_redraw()


func _refresh_seg_mode_ui() -> void:
	var fixed := _is_seg_mode_fixed()
	_len_row.visible = not fixed
	_count_row.visible = fixed


func _sync_seg_mode_buttons() -> void:
	var fixed := _seg_params.forced_space_count > 0
	_seg_mode_fixed.button_pressed = fixed
	_seg_mode_auto.button_pressed = not fixed
	if fixed:
		_space_count_spin.set_value_no_signal(float(_seg_params.forced_space_count))


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
	_refresh_fit(false)
	_canvas.queue_redraw()
	_try_init_spline()


func _canvas_ready_for_spline() -> bool:
	return _canvas.size.x >= MIN_CANVAS_SIZE and _canvas.size.y >= MIN_CANVAS_SIZE


func _try_init_spline() -> void:
	if _spline_ready or not _canvas_ready_for_spline():
		return
	var path := SplineTrackFile.editor_pending_path
	SplineTrackFile.editor_pending_path = ""
	if path.is_empty():
		_reset_spline()
		return
	if SplineTrackFile.is_builtin_path(path) and not SplineTrackFile.can_write_builtin():
		_summary.text = "Les circuits intégrés ne sont éditables qu'en debug"
		_reset_spline()
		return
	if not _load_from_path(path):
		_reset_spline()
		_summary.text = "Impossible de charger %s" % path


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_S and (event.ctrl_pressed or event.meta_pressed):
			_on_save()
			get_viewport().set_input_as_handled()
			return
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


func _on_save() -> void:
	if _spline == null:
		_summary.text = "Rien à enregistrer"
		return
	var wants_builtin := _wants_builtin_save()
	if wants_builtin and not SplineTrackFile.can_write_builtin():
		_summary.text = "Les tracés built-in ne sont éditables qu'en debug"
		return
	var path := _resolve_save_path(wants_builtin)
	var err := SplineTrackFile.save_document(path, _build_save_document())
	if err != OK:
		_summary.text = "Échec de l'enregistrement"
		return
	_file_path = path
	_dirty = false
	_sync_builtin_check()
	_summary.text = "Enregistré : %s" % path


func _resolve_save_path(wants_builtin: bool) -> String:
	if not _file_path.is_empty():
		var path_is_builtin := SplineTrackFile.is_builtin_path(_file_path)
		if path_is_builtin == wants_builtin:
			return _file_path
	return SplineTrackFile.path_for_name(_display_track_name(), wants_builtin)


func _build_save_document() -> Dictionary:
	var corners_data: Array = []
	for key in _corners.keys():
		var space := int(key)
		var entry: Variant = _corners[key]
		if not entry is Dictionary:
			entry = _make_corner_entry(int(entry))
		var corner: Dictionary = entry
		var offset: Vector2 = corner.get("offset", Vector2.ZERO)
		corners_data.append({
			"space": space,
			"speed_limit": int(corner.get("speed_limit", 0)),
			"outside": bool(corner.get("outside", false)),
			"offset": [offset.x, offset.y],
		})
	corners_data.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("space", 0)) < int(b.get("space", 0))
	)
	var flips_data: Array = []
	for key in _sector_flip_race_line.keys():
		if bool(_sector_flip_race_line.get(key, false)):
			flips_data.append({"key": int(key)})
	flips_data.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("key", 0)) < int(b.get("key", 0))
	)
	return {
		"version": SplineTrackFile.VERSION,
		"name": _track_name,
		"spline": _spline.to_dict(),
		"segmentation": {
			"algorithm": int(_seg_params.algorithm),
			"car_length": _seg_params.car_length,
			"target_space_len": _seg_params.target_space_len,
			"forced_space_count": int(_seg_params.forced_space_count),
		},
		"start_space": _start_space_index,
		"corners": corners_data,
		"sector_flip_race_line": flips_data,
	}


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
	_track_name = ""
	_file_path = ""
	_seg_params.forced_space_count = 0
	_sync_track_name_field()
	_sync_builtin_check()
	_dirty = false
	_spline_ready = true
	_recompute_segmentation()
	_refresh_status()
	_refresh_info()
	_refresh_set_start_button()
	_sync_algo_radios()
	_updating_seg_ui = true
	_space_len_slider.value = _seg_params.car_length
	_sync_seg_mode_buttons()
	_updating_seg_ui = false
	_refresh_space_len_label()
	_refresh_seg_mode_ui()
	_fit_view()
	_canvas.queue_redraw()


func _load_from_path(path: String) -> bool:
	var data := SplineTrackFile.load_document(path)
	if data.is_empty():
		return false
	var spline_data: Variant = data.get("spline", {})
	if not spline_data is Dictionary:
		return false
	var spline := TrackSpline.from_dict(spline_data)
	if spline.point_count() < TrackSpline.MIN_POINTS:
		return false
	_spline = spline
	_file_path = path
	_track_name = str(data.get("name", "")).strip_edges()
	_sync_track_name_field()
	_sync_builtin_check()
	var seg: Variant = data.get("segmentation", {})
	if seg is Dictionary:
		_seg_params.algorithm = int(seg.get("algorithm", TrackSegmenter.Algorithm.INNER_UNIFORM))
		_seg_params.car_length = float(seg.get("car_length", 36.0))
		_seg_params.target_space_len = float(seg.get("target_space_len", _seg_params.car_length))
		_seg_params.forced_space_count = int(seg.get("forced_space_count", 0))
	_start_space_index = int(data.get("start_space", 0))
	_selected = 0
	_selected_space = -1
	_drag_corner_space = -1
	_selected_sector = -1
	_corners.clear()
	var corners_data: Variant = data.get("corners", [])
	if corners_data is Array:
		for item in corners_data:
			if not item is Dictionary:
				continue
			var entry: Dictionary = item
			var space := int(entry.get("space", -1))
			if space < 0:
				continue
			var offset := Vector2.ZERO
			var off_v: Variant = entry.get("offset", [0.0, 0.0])
			if off_v is Array and off_v.size() >= 2:
				offset = Vector2(float(off_v[0]), float(off_v[1]))
			elif off_v is Vector2:
				offset = off_v
			_corners[space] = {
				"speed_limit": int(entry.get("speed_limit", 0)),
				"outside": bool(entry.get("outside", true)),
				"offset": offset,
			}
	_sector_flip_race_line.clear()
	var flips_data: Variant = data.get("sector_flip_race_line", [])
	if flips_data is Array:
		for item2 in flips_data:
			if item2 is Dictionary:
				_sector_flip_race_line[int(item2.get("key", -1))] = true
			elif item2 != null:
				_sector_flip_race_line[int(item2)] = true
	_dirty = false
	_spline_ready = true
	_recompute_segmentation()
	_refresh_status()
	_refresh_info()
	_refresh_set_start_button()
	_sync_algo_radios()
	_updating_seg_ui = true
	_space_len_slider.value = _seg_params.car_length
	_sync_seg_mode_buttons()
	_updating_seg_ui = false
	_refresh_space_len_label()
	_refresh_seg_mode_ui()
	_fit_view()
	_canvas.queue_redraw()
	return true


func _on_back() -> void:
	get_tree().change_scene_to_file("res://ui/spline_track_picker.tscn")


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
	if _selected_space < 0 or _seg_result == null or _seg_result.space_count() == 0:
		return
	# Start line sits on the exit of the selected space; display #1 is the next space.
	_start_space_index = posmod(_selected_space + 1, _seg_result.space_count())
	_dirty = true
	_clamp_selected_sector()
	_refresh_info()
	_refresh_set_start_button()
	_canvas.queue_redraw()


func _refresh_set_start_button() -> void:
	if _set_start_button == null:
		return
	var line_after_selected := (
		_selected_space >= 0
		and _seg_result != null
		and _seg_result.space_count() > 0
		and _start_space_index == posmod(_selected_space + 1, _seg_result.space_count())
	)
	var can_set := (
		_edit_mode == EditMode.SPACES
		and _selected_space >= 0
		and _seg_result != null
		and not line_after_selected
	)
	_set_start_button.disabled = not can_set
	if line_after_selected:
		_set_start_button.text = "Départ ✓"
	else:
		_set_start_button.text = "Définir comme case départ"


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
	_corner_details.visible = has_corner
	_corner_speed_spin.editable = has_corner
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
		_set_corner_button.text = "Ajouter virage"
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
		_draw_track(baked, font)

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


func _setup_reset_view_btn() -> void:
	_reset_view_btn = Button.new()
	_reset_view_btn.name = "ResetView"
	_reset_view_btn.text = ""
	_reset_view_btn.icon = RESET_VIEW_ICON
	_reset_view_btn.expand_icon = true
	_reset_view_btn.theme_type_variation = &"Compact"
	_reset_view_btn.focus_mode = Control.FOCUS_NONE
	_reset_view_btn.visible = false
	_reset_view_btn.tooltip_text = "Recadrer"
	_reset_view_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_reset_view_btn.offset_left = -48.0
	_reset_view_btn.offset_top = 8.0
	_reset_view_btn.offset_right = -8.0
	_reset_view_btn.offset_bottom = 48.0
	_reset_view_btn.custom_minimum_size = Vector2(40, 40)
	_reset_view_btn.z_index = 10
	_reset_view_btn.pressed.connect(reset_view)
	_canvas.add_child(_reset_view_btn)
	_reset_view_btn.add_theme_constant_override("icon_max_width", 28)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := _reset_view_btn.get_theme_stylebox(state)
		if sb is StyleBoxFlat:
			var tight := (sb as StyleBoxFlat).duplicate() as StyleBoxFlat
			tight.content_margin_left = 6
			tight.content_margin_right = 6
			tight.content_margin_top = 6
			tight.content_margin_bottom = 6
			_reset_view_btn.add_theme_stylebox_override(state, tight)


func reset_view() -> void:
	_fit_view()
	_canvas.queue_redraw()


func _fit_view() -> void:
	_refresh_fit(true)


## Update stored fit framing. If `force` or the view was already at fit, apply it.
func _refresh_fit(force: bool) -> void:
	if _spline == null or not _canvas_ready_for_spline():
		_update_reset_view_btn()
		return
	var baked := _spline.baked_points()
	if baked.size() < 2:
		_update_reset_view_btn()
		return
	var world := SplineTrackPainter.bounds(baked, ROAD_HALF_WIDTH)
	var fit := SplineTrackPainter.fit_transform(world, Rect2(Vector2.ZERO, _canvas.size), FIT_MARGIN)
	var was_default := _is_default_view()
	_fit_pan = fit.origin
	_fit_zoom = absf(fit.get_scale().x)
	if force or was_default or not _has_valid_view():
		_view_pan = _fit_pan
		_view_zoom = _fit_zoom
		_apply_view_to_cars()
	_update_reset_view_btn()


func _has_valid_view() -> bool:
	return _view_zoom > 0.0 and is_finite(_view_zoom)


func _is_default_view() -> bool:
	if not _has_valid_view():
		return true
	return is_equal_approx(_view_zoom, _fit_zoom) and _view_pan.is_equal_approx(_fit_pan)


func _update_reset_view_btn() -> void:
	if _reset_view_btn == null:
		return
	_reset_view_btn.visible = _spline != null and not _is_default_view()


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var new_zoom := clampf(_view_zoom * factor, MIN_VIEW_ZOOM, MAX_VIEW_ZOOM)
	if is_equal_approx(new_zoom, _view_zoom):
		return
	_view_pan = screen_pos - (screen_pos - _view_pan) * (new_zoom / _view_zoom)
	_view_zoom = new_zoom
	_apply_view_to_cars()
	_update_reset_view_btn()
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
		_update_reset_view_btn()
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
		if _reset_view_btn != null:
			_canvas.move_child(_reset_view_btn, -1)
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
	# Temporary play-index identity: editor works in geometric indices.
	var bind := SplineTrackBind.new()
	bind.seg = _seg_result
	bind.seg_params = _seg_params
	bind.half_width = ROAD_HALF_WIDTH
	bind.spot_inset = _seg_params.spot_inset
	bind.start_space = 0
	bind.corners = _corners
	bind.sector_flip_race_line = _sector_flip_race_line
	return bind.space_slot_poses(space_index)


func _paint_context(font: Font) -> SplineTrackPainter.Context:
	var ctx := SplineTrackPainter.Context.new()
	ctx.half_width = ROAD_HALF_WIDTH
	ctx.spot_inset = _seg_params.spot_inset
	ctx.seg = _seg_result
	ctx.start_space = _start_space_index
	ctx.corners = _corners
	ctx.race_line_flipped = _space_race_line_flipped
	ctx.font = font
	return ctx


func _draw_track(baked: PackedVector2Array, font: Font) -> void:
	var ctx := _paint_context(font)
	var body := SplineTrackPainter.Options.new()
	body.asphalt = true
	body.race_line = true
	body.centerline = true
	SplineTrackPainter.draw(_canvas, baked, ctx, body)
	_draw_selection_fills()
	var overlays := SplineTrackPainter.editor_roadmap_options(_hide_space_numbers.button_pressed)
	overlays.asphalt = false
	overlays.race_line = false
	overlays.centerline = false
	SplineTrackPainter.draw(_canvas, baked, ctx, overlays)


func _draw_selection_fills() -> void:
	if _seg_result == null or _seg_result.space_count() < 2:
		return
	if _edit_mode == EditMode.SPACES and _selected_space >= 0:
		_draw_space_fill(_selected_space, SPACE_SELECTED_COLOR)
	elif _edit_mode == EditMode.SECTORS and _selected_sector >= 0:
		_draw_selected_sector_highlight()


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


func _draw_selected_sector_highlight() -> void:
	var sectors := _compute_sectors()
	if _selected_sector < 0 or _selected_sector >= sectors.size():
		return
	var sector: Dictionary = sectors[_selected_sector]
	var n := _seg_result.space_count()
	var space := int(sector.from)
	while true:
		_draw_space_fill(space, SECTOR_SELECTED_COLOR)
		if space == int(sector.to):
			break
		space = posmod(space + 1, n)


## Fills one space with triangles clamped to its frontiers (no round-cap bleed).
func _draw_space_fill(space: int, color: Color) -> void:
	var quads: Array = _seg_result.space_fill_quads(space, ROAD_HALF_WIDTH)
	for q in quads:
		var p: PackedVector2Array = q
		if p.size() < 4:
			continue
		_draw_fill_tri(p[0], p[1], p[2], color)
		_draw_fill_tri(p[0], p[2], p[3], color)


func _draw_fill_tri(a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	# Skip collapsed slivers that Godot may refuse to fill.
	var area2 := absf((b - a).cross(c - a))
	if area2 < 0.05:
		return
	_canvas.draw_colored_polygon(PackedVector2Array([a, b, c]), color)


func _corner_badge_natural(frontier: TrackSegmenter.Frontier, outside: bool) -> Vector2:
	return SplineTrackPainter.corner_badge_natural(frontier, outside, ROAD_HALF_WIDTH)


func _corner_badge_center(space: int, frontier: Variant = null) -> Vector2:
	return SplineTrackPainter.corner_badge_center(_paint_context(ThemeDB.fallback_font), space, frontier)


func _display_space_number(space_index: int) -> int:
	return SplineTrackPainter.display_space_number(_paint_context(ThemeDB.fallback_font), space_index)


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
