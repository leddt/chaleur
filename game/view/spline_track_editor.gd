extends Control

## Interactive editor for a closed TrackSpline (per-point Bezier types).

enum EditMode {
	TRACE, ## Edit control points / spline shape.
	SPACES, ## Inspect / tune space segmentation.
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
const CENTERLINE_COLOR := Color(0.95, 0.95, 0.97, 1.0)
const SPACE_EDGE_COLOR := Color(0.05, 0.05, 0.06, 0.95)
const START_LINE_COLOR := Color(0.9, 0.15, 0.12, 1.0)
const CORNER_LINE_COLOR := Color(0.2, 0.85, 0.35, 1.0)
const SPACE_SELECTED_COLOR := Color(1.0, 0.85, 0.2, 0.22)
const MIN_VIEW_ZOOM := 0.25
const MAX_VIEW_ZOOM := 4.0
const VIEW_ZOOM_STEP := 1.12

@onready var _canvas: Control = %Canvas
@onready var _status: Label = %StatusLabel
@onready var _info: Label = %InfoLabel
@onready var _hint: Label = %Hint
@onready var _mode_option: OptionButton = %ModeOption
@onready var _type_label: Label = %TypeLabel
@onready var _type_option: OptionButton = %TypeOption
@onready var _algo_label: Label = %AlgoLabel
@onready var _algo_option: OptionButton = %AlgoOption
@onready var _len_label: Label = %LenLabel
@onready var _space_len_slider: HSlider = %SpaceLenSlider
@onready var _space_len_value: Label = %SpaceLenValue
@onready var _set_start_button: Button = %SetStartButton
@onready var _corner_speed_label: Label = %CornerSpeedLabel
@onready var _corner_speed_spin: SpinBox = %CornerSpeedSpin
@onready var _set_corner_button: Button = %SetCornerButton

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
## space_index -> speed_limit (HeatCorner.from_space semantics).
var _corners: Dictionary = {}
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
	_type_option.clear()
	_type_option.add_item("Auto", TrackSpline.PointType.AUTO_SMOOTH)
	_type_option.add_item("Tension", TrackSpline.PointType.TENSION)
	_type_option.add_item("Libre", TrackSpline.PointType.FREE)
	_type_option.item_selected.connect(_on_type_option_selected)
	_setup_mode_ui()
	_setup_segmentation_ui()
	_set_start_button.pressed.connect(_on_set_start_pressed)
	_setup_corner_ui()
	_apply_edit_mode()
	_ensure_preview_cars()
	# Layout may still report 0-height here — wait for a usable canvas size.
	call_deferred("_try_init_spline")


func _setup_mode_ui() -> void:
	_mode_option.clear()
	_mode_option.add_item("Tracé", EditMode.TRACE)
	_mode_option.add_item("Cases", EditMode.SPACES)
	_updating_mode_ui = true
	_mode_option.select(_mode_option.get_item_index(_edit_mode))
	_updating_mode_ui = false
	_mode_option.item_selected.connect(_on_mode_selected)


func _on_mode_selected(item_index: int) -> void:
	if _updating_mode_ui:
		return
	_set_edit_mode(_mode_option.get_item_id(item_index))


func _set_edit_mode(mode: int) -> void:
	if _edit_mode == mode:
		return
	_edit_mode = mode
	_drag_mode = ""
	_apply_edit_mode()
	_refresh_info()
	_canvas.queue_redraw()


func _apply_edit_mode() -> void:
	var trace := _edit_mode == EditMode.TRACE
	_type_label.visible = trace
	_type_option.visible = trace
	# Segmentation controls stay available in both modes for now.
	_algo_label.visible = true
	_algo_option.visible = true
	_len_label.visible = true
	_space_len_slider.visible = true
	_space_len_value.visible = true
	_set_start_button.visible = not trace
	_corner_speed_label.visible = not trace
	_corner_speed_spin.visible = not trace
	_set_corner_button.visible = not trace
	_refresh_set_start_button()
	_refresh_corner_ui()
	if trace:
		_hint.text = "Mode tracé — clic près de la courbe : ajouter. Clic droit : supprimer. Double-clic : type. Touches 1/2/3 : type. Molette : zoom. Molette milieu : pan. Ctrl+molette : tension."
	else:
		_hint.text = "Mode cases — sélectionner une case. Départ (ligne rouge précédente). Virage + vitesse max (ligne verte suivante). Molette : zoom. Molette milieu : pan."


func _setup_segmentation_ui() -> void:
	_seg_params.road_half_width = ROAD_HALF_WIDTH
	_seg_params.algorithm = TrackSegmenter.Algorithm.INNER_UNIFORM
	_seg_params.car_length = 36.0
	_seg_params.target_space_len = 36.0
	_algo_option.clear()
	_algo_option.add_item(
		TrackSegmenter.algorithm_name(TrackSegmenter.Algorithm.CENTER_UNIFORM),
		TrackSegmenter.Algorithm.CENTER_UNIFORM
	)
	_algo_option.add_item(
		TrackSegmenter.algorithm_name(TrackSegmenter.Algorithm.INNER_UNIFORM),
		TrackSegmenter.Algorithm.INNER_UNIFORM
	)
	_algo_option.add_item(
		TrackSegmenter.algorithm_name(TrackSegmenter.Algorithm.ADAPTIVE_INNER),
		TrackSegmenter.Algorithm.ADAPTIVE_INNER
	)
	_updating_seg_ui = true
	_algo_option.select(_algo_option.get_item_index(_seg_params.algorithm))
	_space_len_slider.min_value = 20.0
	_space_len_slider.max_value = 80.0
	_space_len_slider.step = 1.0
	_space_len_slider.value = _seg_params.car_length
	_updating_seg_ui = false
	_algo_option.item_selected.connect(_on_algo_selected)
	_space_len_slider.value_changed.connect(_on_space_len_changed)
	_refresh_space_len_label()


func _setup_corner_ui() -> void:
	_corner_speed_spin.min_value = 1.0
	_corner_speed_spin.max_value = 8.0
	_corner_speed_spin.step = 1.0
	_corner_speed_spin.rounded = true
	_corner_speed_spin.value = 4.0
	_set_corner_button.pressed.connect(_on_set_corner_pressed)
	_corner_speed_spin.value_changed.connect(_on_corner_speed_changed)


func _on_corner_speed_changed(value: float) -> void:
	if _updating_corner_ui:
		return
	if _selected_space < 0 or not _corners.has(_selected_space):
		return
	_corners[_selected_space] = int(value)
	_dirty = true
	_refresh_info()
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
		_status.text = "En attente du canvas…"
		return
	var center := _canvas.size * 0.5
	var radius := mini(center.x, center.y) * 0.55
	_spline = TrackSpline.make_default_triangle(center, radius)
	_selected = 0
	_selected_space = -1
	_start_space_index = 0
	_corners.clear()
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


func _on_algo_selected(item_index: int) -> void:
	if _updating_seg_ui:
		return
	_seg_params.algorithm = _algo_option.get_item_id(item_index)
	_recompute_segmentation()
	_refresh_status()
	_refresh_info()
	_canvas.queue_redraw()


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
		return
	_seg_params.road_half_width = ROAD_HALF_WIDTH
	_seg_result = TrackSegmenter.segment(_spline, _seg_params)
	_clamp_space_indices()


func _clamp_space_indices() -> void:
	if _seg_result == null or _seg_result.space_count() == 0:
		_start_space_index = 0
		_selected_space = -1
		_corners.clear()
		return
	var n := _seg_result.space_count()
	_start_space_index = posmod(_start_space_index, n)
	if _selected_space >= n:
		_selected_space = -1
	var kept: Dictionary = {}
	for key in _corners.keys():
		var idx := int(key)
		if idx >= 0 and idx < n:
			kept[idx] = int(_corners[key])
	_corners = kept


func _on_set_start_pressed() -> void:
	if _selected_space < 0 or _seg_result == null:
		return
	_start_space_index = _selected_space
	_dirty = true
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
	else:
		_corners[_selected_space] = int(_corner_speed_spin.value)
	_dirty = true
	_refresh_info()
	_refresh_corner_ui()
	_canvas.queue_redraw()


func _refresh_corner_ui() -> void:
	if _set_corner_button == null:
		return
	var has_sel := (
		_edit_mode == EditMode.SPACES
		and _selected_space >= 0
		and _seg_result != null
	)
	_set_corner_button.disabled = not has_sel
	_corner_speed_spin.editable = has_sel
	if has_sel and _corners.has(_selected_space):
		_set_corner_button.text = "Retirer virage"
		_updating_corner_ui = true
		_corner_speed_spin.value = int(_corners[_selected_space])
		_updating_corner_ui = false
	else:
		_set_corner_button.text = "Virage"


func _on_type_option_selected(item_index: int) -> void:
	if _updating_type_ui or _spline == null:
		return
	_set_selected_type(_type_option.get_item_id(item_index))


func _set_selected_type(type: int) -> void:
	if _spline == null or _spline.point_count() == 0:
		return
	var cp := _spline.get_point(_selected)
	if cp.type == type:
		_sync_type_option()
		return
	_spline.set_point_type(_selected, type)
	_dirty = true
	_refresh_status()
	_refresh_info()
	_canvas.queue_redraw()


func _sync_type_option() -> void:
	if _spline == null or _spline.point_count() == 0:
		return
	_updating_type_ui = true
	var type := _spline.get_point(_selected).type
	var idx := _type_option.get_item_index(type)
	if idx >= 0:
		_type_option.select(idx)
	_updating_type_ui = false


func _refresh_status() -> void:
	if _spline == null:
		_status.text = ""
		return
	var spaces := 0 if _seg_result == null else _seg_result.space_count()
	var algo := "" if _seg_result == null else TrackSegmenter.algorithm_name(_seg_result.algorithm)
	_status.text = "Courbe fermée · %d points · %d cases (%s)" % [
		_spline.point_count(), spaces, algo
	]


func _refresh_info() -> void:
	if _spline == null or _spline.point_count() == 0:
		_info.text = ""
		return
	if _edit_mode == EditMode.SPACES:
		var spaces := 0 if _seg_result == null else _seg_result.space_count()
		var sel_txt := "aucune"
		if _selected_space >= 0 and spaces > 0:
			sel_txt = "#%d" % _display_space_number(_selected_space)
			if _selected_space == _start_space_index:
				sel_txt += " (départ)"
			if _corners.has(_selected_space):
				sel_txt += " (virage <%d)" % int(_corners[_selected_space])
		_info.text = "Mode cases · %d cases · %d virages · sélection %s · %s · longueur %.0f px" % [
			spaces,
			_corners.size(),
			sel_txt,
			TrackSegmenter.algorithm_name(_seg_params.algorithm),
			_seg_params.car_length,
		]
		_refresh_set_start_button()
		_refresh_corner_ui()
		return
	_selected = clampi(_selected, 0, _spline.point_count() - 1)
	var cp := _spline.get_point(_selected)
	var dirty := " *" if _dirty else ""
	var extra := ""
	if cp.type == TrackSpline.PointType.TENSION:
		extra = "  tension %.2f" % cp.tension
	_info.text = "Point %d/%d%s  %s  pos (%.0f, %.0f)%s" % [
		_selected + 1,
		_spline.point_count(),
		dirty,
		TrackSpline.type_name(cp.type),
		cp.position.x,
		cp.position.y,
		extra,
	]
	_sync_type_option()


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
	var show := (
		_edit_mode == EditMode.SPACES
		and _selected_space >= 0
		and _seg_result != null
		and _seg_result.space_count() >= 2
	)
	_cars_layer.visible = show
	if not show:
		return
	var poses := _space_slot_poses(_selected_space)
	for i in mini(2, poses.size()):
		var car: CarToken = _preview_cars[i]
		var pose: Dictionary = poses[i]
		car.set_pose(pose.pos, pose.heading)
		car.visible = true


## Mid-space poses for spot 0 (inner) and spot 1 (outer), as in-game.
func _space_slot_poses(space_index: int) -> Array:
	if _seg_result == null or _seg_result.space_count() < 2:
		return []
	return _seg_result.space_slot_poses(
		space_index,
		_seg_params.road_half_width,
		_seg_params.spot_inset
	)


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
	if _selected_space >= 0 and _edit_mode == EditMode.SPACES:
		var ribbon := _seg_result.space_ribbon(_selected_space, ROAD_HALF_WIDTH)
		if ribbon.size() >= 3:
			_canvas.draw_colored_polygon(ribbon, SPACE_SELECTED_COLOR)
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
			var limit := int(_corners[space_before])
			# Outside the asphalt, near the green exit line.
			var label_pos := outer_edge - a.inside_normal * 16.0
			_canvas.draw_string(
				font,
				label_pos,
				"<%d" % limit,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				12,
				CORNER_LINE_COLOR
			)
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

	# Dark shoulder underlay, then asphalt. Circles seal the closed join and sharp bends
	# so we never depend on an offset polygon (those tear at the seam / fold in hairpins).
	var edge_r := ROAD_HALF_WIDTH + 1.5
	_stroke_closed_band(pts, loop, edge_r, ASPHALT_EDGE_COLOR)
	_stroke_closed_band(pts, loop, ROAD_HALF_WIDTH, ASPHALT_COLOR)


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
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var idx := _space_index_at(_screen_to_world(mb.position))
			_selected_space = idx
			_refresh_info()
			_refresh_set_start_button()
			_refresh_corner_ui()
			_canvas.queue_redraw()


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
		_status.text = "Minimum %d points" % TrackSpline.MIN_POINTS
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
