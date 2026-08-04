extends Control

## Interactive editor for a closed TrackSpline (per-point Bezier types).

const HANDLE_HIT_RADIUS := 12.0
const POINT_HIT_RADIUS := 14.0
const CURVE_HIT_RADIUS := 14.0
const MIN_CANVAS_SIZE := 32.0

@onready var _canvas: Control = %Canvas
@onready var _status: Label = %StatusLabel
@onready var _info: Label = %InfoLabel
@onready var _type_option: OptionButton = %TypeOption

var _spline: TrackSpline
var _selected: int = 0
var _drag_mode: String = "" ## "", "point", "out_handle", "in_handle"
var _dirty: bool = false
var _updating_type_ui: bool = false
var _spline_ready: bool = false


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
	# Layout may still report 0-height here — wait for a usable canvas size.
	call_deferred("_try_init_spline")


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
	if _spline == null:
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
	_dirty = false
	_spline_ready = true
	_refresh_status()
	_refresh_info()
	_canvas.queue_redraw()


func _on_reset() -> void:
	_spline_ready = false
	_reset_spline()


func _on_back() -> void:
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")


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
	_status.text = "Courbe fermée · %d points" % _spline.point_count()


func _refresh_info() -> void:
	if _spline == null or _spline.point_count() == 0:
		_info.text = ""
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
	var font := ThemeDB.fallback_font
	# Soft grid
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

	var baked := _spline.baked_points()
	if baked.size() >= 2:
		_canvas.draw_polyline(baked, Color(0.95, 0.55, 0.2, 0.95), 3.0, true)

	# Chord lines between anchors (faint)
	for i in _spline.point_count():
		var a := _spline.get_point(i).position
		var b := _spline.get_point(i + 1).position
		_canvas.draw_line(a, b, Color(1, 1, 1, 0.12), 1.0)

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
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if mb.double_click and _try_cycle_type_at(mb.position):
					pass
				else:
					_begin_left(mb.position)
			else:
				_drag_mode = ""
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_try_remove_at(mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_nudge_tension(0.05)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_nudge_tension(-0.05)
	elif event is InputEventMouseMotion and _drag_mode != "":
		_continue_drag((event as InputEventMouseMotion).position)


func _begin_left(pos: Vector2) -> void:
	# Handles only exist visually for the selection; then point drag, then insert.
	var handle := _hit_editable_handle(_selected, pos)
	if handle != "":
		_drag_mode = handle
		return
	var best := _nearest_point(pos, POINT_HIT_RADIUS)
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
	var best := _nearest_point(pos, POINT_HIT_RADIUS)
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
	match cp.type:
		TrackSpline.PointType.AUTO_SMOOTH:
			return ""
		TrackSpline.PointType.TENSION:
			if pos.distance_to(_spline.out_handle_world(index)) <= HANDLE_HIT_RADIUS:
				return "out_handle"
			if pos.distance_to(_spline.in_handle_world(index)) <= HANDLE_HIT_RADIUS:
				return "out_handle" # mirrored — either side adjusts tension
			return ""
		TrackSpline.PointType.FREE:
			if pos.distance_to(_spline.out_handle_world(index)) <= HANDLE_HIT_RADIUS:
				return "out_handle"
			if pos.distance_to(_spline.in_handle_world(index)) <= HANDLE_HIT_RADIUS:
				return "in_handle"
			return ""
		_:
			return ""


func _try_insert_at(pos: Vector2) -> bool:
	var hit: Dictionary = _spline.closest_on_curve(pos)
	if float(hit.distance) > CURVE_HIT_RADIUS:
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
	var best := _nearest_point(pos, POINT_HIT_RADIUS)
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
