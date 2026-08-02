extends Control

## In-game editor for track layout spot positions (UV on the background image).

const JSON_PATH := TrackLayout.TRACK1_JSON

@onready var _canvas: Control = %Canvas
@onready var _status: Label = %StatusLabel
@onready var _space_spin: SpinBox = %SpaceSpin
@onready var _spot_spin: SpinBox = %SpotSpin
@onready var _info: Label = %InfoLabel

var _layout: TrackLayout
var _space: int = 0
var _spot: int = 0
var _dragging: bool = false
var _dirty: bool = false


func _ready() -> void:
	if not OS.is_debug_build():
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")
		return
	_canvas.draw.connect(_on_canvas_draw)
	_canvas.gui_input.connect(_on_canvas_gui_input)
	_canvas.resized.connect(func() -> void: _canvas.queue_redraw())
	%PrevSpaceButton.pressed.connect(func() -> void: _select_space(_space - 1))
	%NextSpaceButton.pressed.connect(func() -> void: _select_space(_space + 1))
	%SaveButton.pressed.connect(_on_save)
	%ReloadButton.pressed.connect(_on_reload)
	%BackButton.pressed.connect(_on_back)
	_space_spin.value_changed.connect(func(v: float) -> void: _select_space(int(v)))
	_spot_spin.value_changed.connect(func(v: float) -> void: _select_spot(int(v)))
	_load_layout()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_LEFT, KEY_A:
				_select_space(_space - 1)
				get_viewport().set_input_as_handled()
			KEY_RIGHT, KEY_D:
				_select_space(_space + 1)
				get_viewport().set_input_as_handled()
			KEY_1:
				_select_spot(0)
				get_viewport().set_input_as_handled()
			KEY_2:
				_select_spot(1)
				get_viewport().set_input_as_handled()
			KEY_S:
				if event.ctrl_pressed or event.meta_pressed:
					_on_save()
					get_viewport().set_input_as_handled()
			KEY_R:
				if event.ctrl_pressed or event.meta_pressed:
					_on_reload()
					get_viewport().set_input_as_handled()


func _load_layout() -> void:
	_layout = TrackLayout.load_json(JSON_PATH)
	_dirty = false
	if _layout == null:
		_status.text = "Impossible de charger %s" % JSON_PATH
		return
	_space_spin.max_value = maxi(_layout.space_count() - 1, 0)
	_space_spin.value = mini(_space, _space_spin.max_value)
	_select_space(int(_space_spin.value))
	_status.text = "Chargé: %s (%d cases)" % [_layout.id, _layout.space_count()]
	_canvas.queue_redraw()


func _select_space(index: int) -> void:
	if _layout == null or _layout.space_count() == 0:
		return
	_space = posmod(index, _layout.space_count())
	_space_spin.set_value_no_signal(_space)
	var cap := _layout.spot_count(_space)
	_spot_spin.max_value = maxi(cap - 1, 0)
	_spot = clampi(_spot, 0, int(_spot_spin.max_value))
	_spot_spin.set_value_no_signal(_spot)
	_refresh_info()
	_canvas.queue_redraw()


func _select_spot(index: int) -> void:
	if _layout == null:
		return
	_spot = clampi(index, 0, int(_spot_spin.max_value))
	_spot_spin.set_value_no_signal(_spot)
	_refresh_info()
	_canvas.queue_redraw()


func _refresh_info() -> void:
	if _layout == null:
		_info.text = ""
		return
	var uv := _layout.spot_uv(_space, _spot)
	var corner_txt := ""
	for c in _layout.corners:
		if int(c.get("from_space", -1)) == _space:
			corner_txt = "  |  virage <%s (%s)" % [str(c.get("speed_limit", "?")), str(c.get("id", ""))]
			break
	var dirty := " *" if _dirty else ""
	_info.text = "Case %d / spot %d%s  UV (%.4f, %.4f)%s" % [
		_space, _spot, dirty, uv.x, uv.y, corner_txt
	]


func _on_save() -> void:
	if _layout == null:
		return
	var err := _layout.save_json(JSON_PATH)
	if err != OK:
		_status.text = "Échec sauvegarde (%s)" % error_string(err)
		return
	_dirty = false
	_status.text = "Sauvé → %s" % JSON_PATH
	_refresh_info()


func _on_reload() -> void:
	_load_layout()


func _on_back() -> void:
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")


func _on_canvas_draw() -> void:
	if _layout == null or _layout.texture == null:
		_canvas.draw_string(ThemeDB.fallback_font, Vector2(20, 40), "Pas de layout / texture", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		return
	var rect := _layout.fitted_rect(_canvas.size)
	_canvas.draw_texture_rect(_layout.texture, rect, false)
	# All spaces (faint)
	for i in _layout.space_count():
		var uv0 := _layout.spot_uv(i, 0)
		var p0 := _uv_to_canvas(uv0, rect)
		var col := Color(1, 1, 0, 0.35)
		if _is_corner_space(i):
			col = Color(0.2, 1, 0.35, 0.55)
		_canvas.draw_circle(p0, 3.0, col)
		if i % 5 == 0 or i == _space:
			_canvas.draw_string(
				ThemeDB.fallback_font,
				p0 + Vector2(5, -4),
				str(i),
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				10,
				Color(1, 1, 1, 0.7) if i != _space else Color.WHITE
			)
	# Selected space spots
	var spot_n := _layout.spot_count(_space)
	for s in spot_n:
		var uv := _layout.spot_uv(_space, s)
		var pos := _uv_to_canvas(uv, rect)
		var fill := Color(1, 0.25, 0.25) if s == 0 else Color(0.25, 0.45, 1)
		var radius := 9.0 if s == _spot else 6.0
		_canvas.draw_circle(pos, radius, fill)
		_canvas.draw_arc(pos, radius, 0, TAU, 24, Color.WHITE if s == _spot else Color(0, 0, 0), 2.0)
		_canvas.draw_string(
			ThemeDB.fallback_font,
			pos + Vector2(-3, 4),
			str(s),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			11,
			Color.WHITE
		)
	# Link spots of selected space
	if spot_n >= 2:
		var a := _uv_to_canvas(_layout.spot_uv(_space, 0), rect)
		var b := _uv_to_canvas(_layout.spot_uv(_space, 1), rect)
		_canvas.draw_line(a, b, Color(1, 1, 1, 0.5), 1.5)


func _is_corner_space(space: int) -> bool:
	for c in _layout.corners:
		if int(c.get("from_space", -1)) == space:
			return true
	return false


func _uv_to_canvas(uv: Vector2, rect: Rect2) -> Vector2:
	return rect.position + Vector2(uv.x * rect.size.x, uv.y * rect.size.y)


func _canvas_to_uv(pos: Vector2, rect: Rect2) -> Vector2:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return Vector2.ZERO
	return Vector2(
		clampf((pos.x - rect.position.x) / rect.size.x, 0.0, 1.0),
		clampf((pos.y - rect.position.y) / rect.size.y, 0.0, 1.0)
	)


func _on_canvas_gui_input(event: InputEvent) -> void:
	if _layout == null or _layout.texture == null:
		return
	var rect := _layout.fitted_rect(_canvas.size)
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_handle_click(mb.position, rect)
			else:
				_dragging = false
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_select_space(_space - 1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_select_space(_space + 1)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		if rect.has_point(mm.position):
			_layout.set_spot_uv(_space, _spot, _canvas_to_uv(mm.position, rect))
			_dirty = true
			_refresh_info()
			_canvas.queue_redraw()


func _handle_click(pos: Vector2, rect: Rect2) -> void:
	# Prefer grabbing a spot of the selected space; else select nearest space.
	var best_spot := -1
	var best_d := 14.0 * 14.0
	for s in _layout.spot_count(_space):
		var p := _uv_to_canvas(_layout.spot_uv(_space, s), rect)
		var d := pos.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best_spot = s
	if best_spot >= 0:
		_select_spot(best_spot)
		_dragging = true
		_layout.set_spot_uv(_space, _spot, _canvas_to_uv(pos, rect))
		_dirty = true
		_refresh_info()
		_canvas.queue_redraw()
		return
	# Click elsewhere: select nearest space (by spot 0), then start dragging its active spot
	var nearest := 0
	var nearest_d := INF
	for i in _layout.space_count():
		var p := _uv_to_canvas(_layout.spot_uv(i, 0), rect)
		var d := pos.distance_squared_to(p)
		if d < nearest_d:
			nearest_d = d
			nearest = i
	_select_space(nearest)
	_dragging = true
	_layout.set_spot_uv(_space, _spot, _canvas_to_uv(pos, rect))
	_dirty = true
	_refresh_info()
	_canvas.queue_redraw()
