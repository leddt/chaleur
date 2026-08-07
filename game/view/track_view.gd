class_name TrackView
extends Control

const CAR_SCENE := preload("res://view/car.tscn")
const RESET_VIEW_ICON := preload("res://ui/kit/icons/recadrer.png")
const MOVE_DURATION := 0.5
const MIN_VIEW_ZOOM := 0.15
const MAX_VIEW_ZOOM := 8.0
const VIEW_ZOOM_STEP := 1.12
const FIT_MARGIN := 24.0


var engine: HeatGameEngine
var highlight_spaces: Array[int] = []
var show_space_debug: bool = false

## Visual progress/spot (lags behind engine while animating).
var _viz_progress: Dictionary = {} # player_id -> float
var _viz_spot: Dictionary = {} # player_id -> float
var _anim_from: Dictionary = {} # player_id -> float
var _anim_to: Dictionary = {} # player_id -> float
var _anim_from_spot: Dictionary = {} # player_id -> float
var _anim_to_spot: Dictionary = {} # player_id -> float
var _anim_elapsed: Dictionary = {} # player_id -> float
var _anim_duration: Dictionary = {} # player_id -> float

var _cars_layer: Node2D
var _cars: Dictionary = {} # player_id -> CarToken
var _view_xform := Transform2D.IDENTITY

## Fit framing (default). User pan/zoom overrides until reset.
var _fit_pan := Vector2.ZERO
var _fit_zoom := 1.0
var _view_pan := Vector2.ZERO
var _view_zoom := 1.0
var _view_dirty_fit := true
var _panning := false
var _fit_size := Vector2.ZERO
var _fit_bind: SplineTrackBind = null
var _reset_btn: Button


func _ready() -> void:
	set_process(true)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_cars_layer = Node2D.new()
	_cars_layer.name = "Cars"
	add_child(_cars_layer)
	_reset_btn = Button.new()
	_reset_btn.name = "ResetView"
	_reset_btn.text = ""
	_reset_btn.icon = RESET_VIEW_ICON
	_reset_btn.expand_icon = true
	_reset_btn.theme_type_variation = &"Compact"
	_reset_btn.focus_mode = Control.FOCUS_NONE
	_reset_btn.visible = false
	_reset_btn.tooltip_text = "Recadrer"
	_reset_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_reset_btn.offset_left = -48.0
	_reset_btn.offset_top = 8.0
	_reset_btn.offset_right = -8.0
	_reset_btn.offset_bottom = 48.0
	_reset_btn.custom_minimum_size = Vector2(40, 40)
	_reset_btn.pressed.connect(reset_view)
	add_child(_reset_btn)
	_reset_btn.add_theme_constant_override("icon_max_width", 28)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := _reset_btn.get_theme_stylebox(state)
		if sb is StyleBoxFlat:
			var tight := (sb as StyleBoxFlat).duplicate() as StyleBoxFlat
			tight.content_margin_left = 6
			tight.content_margin_right = 6
			tight.content_margin_top = 6
			tight.content_margin_bottom = 6
			_reset_btn.add_theme_stylebox_override(state, tight)


func set_engine(p_engine: HeatGameEngine, snap: bool = false) -> void:
	var track_changed := engine != p_engine
	engine = p_engine
	if engine == null:
		_clear_viz()
		_clear_cars()
		_view_dirty_fit = true
		_update_reset_btn()
		queue_redraw()
		return
	if track_changed:
		_view_dirty_fit = true
		_reset_to_fit_values()
	if snap or _viz_progress.is_empty():
		_snap_all()
		_sync_cars()
	else:
		_ensure_viz_keys()
	queue_redraw()


func refresh(animate: bool = true) -> void:
	if engine == null:
		return
	_ensure_viz_keys()
	if animate:
		_start_animations()
	else:
		_snap_all()
	_sync_cars()
	queue_redraw()


func reset_view() -> void:
	_view_pan = _fit_pan
	_view_zoom = _fit_zoom
	_compose_view_xform()
	_apply_view_to_cars()
	_update_reset_btn()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_view_dirty_fit = true
		_sync_cars()
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if _handle_view_input(event):
		accept_event()


func _process(delta: float) -> void:
	if _anim_to.is_empty():
		return
	var finished: Array[int] = []
	for player_id in _anim_to.keys():
		var elapsed := float(_anim_elapsed.get(player_id, 0.0)) + delta
		_anim_elapsed[player_id] = elapsed
		var duration: float = maxf(float(_anim_duration.get(player_id, MOVE_DURATION)), 0.01)
		var t := clampf(elapsed / duration, 0.0, 1.0)
		var u := t * t * (3.0 - 2.0 * t)
		var from_p: float = float(_anim_from[player_id])
		var to_p: float = float(_anim_to[player_id])
		var from_s: float = float(_anim_from_spot.get(player_id, _viz_spot.get(player_id, 0.0)))
		var to_s: float = float(_anim_to_spot.get(player_id, from_s))
		_viz_progress[player_id] = lerpf(from_p, to_p, u)
		_viz_spot[player_id] = lerpf(from_s, to_s, u)
		if t >= 1.0:
			_viz_progress[player_id] = to_p
			_viz_spot[player_id] = to_s
			finished.append(int(player_id))
	for player_id in finished:
		_anim_from.erase(player_id)
		_anim_to.erase(player_id)
		_anim_from_spot.erase(player_id)
		_anim_to_spot.erase(player_id)
		_anim_elapsed.erase(player_id)
		_anim_duration.erase(player_id)
	_sync_cars()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.INK)
	if engine == null or engine.track == null:
		return
	var bind := engine.track.spline_bind
	if bind == null:
		return
	_ensure_fit(bind)
	var opts := SplineTrackPainter.game_options()
	SplineTrackPainter.draw(self, bind.baked_points(), bind.paint_context(), opts, _view_xform)
	if show_space_debug:
		_draw_space_debug(bind)


func _ensure_fit(bind: SplineTrackBind) -> void:
	var need := _view_dirty_fit or bind != _fit_bind or size != _fit_size
	if not need:
		_compose_view_xform()
		_apply_view_to_cars()
		return
	var baked := bind.baked_points()
	var world := SplineTrackPainter.bounds(baked, bind.half_width)
	var fit := SplineTrackPainter.fit_transform(world, Rect2(Vector2.ZERO, size), FIT_MARGIN)
	var was_default := _is_default_view()
	_fit_pan = fit.origin
	_fit_zoom = absf(fit.get_scale().x)
	_fit_bind = bind
	_fit_size = size
	_view_dirty_fit = false
	if was_default or not _has_valid_view():
		_view_pan = _fit_pan
		_view_zoom = _fit_zoom
	_compose_view_xform()
	_apply_view_to_cars()
	_update_reset_btn()


func _has_valid_view() -> bool:
	return _view_zoom > 0.0 and is_finite(_view_zoom)


func _is_default_view() -> bool:
	if not _has_valid_view():
		return true
	return is_equal_approx(_view_zoom, _fit_zoom) and _view_pan.is_equal_approx(_fit_pan)


func _reset_to_fit_values() -> void:
	_view_pan = _fit_pan
	_view_zoom = _fit_zoom
	_update_reset_btn()


func _compose_view_xform() -> void:
	_view_xform = Transform2D(0.0, Vector2(_view_zoom, _view_zoom), 0.0, _view_pan)


func _apply_view_to_cars() -> void:
	if _cars_layer == null:
		return
	# Same pattern as the spline editor: cars live in world space under the view transform
	# so CAR_LENGTH stays proportional to road width when the track is fitted.
	_cars_layer.position = _view_pan
	_cars_layer.scale = Vector2(_view_zoom, _view_zoom)


func _update_reset_btn() -> void:
	if _reset_btn == null:
		return
	_reset_btn.visible = not _is_default_view() and engine != null


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var new_zoom := clampf(_view_zoom * factor, MIN_VIEW_ZOOM, MAX_VIEW_ZOOM)
	if is_equal_approx(new_zoom, _view_zoom):
		return
	_view_pan = screen_pos - (screen_pos - _view_pan) * (new_zoom / _view_zoom)
	_view_zoom = new_zoom
	_compose_view_xform()
	_apply_view_to_cars()
	_update_reset_btn()
	queue_redraw()


func _handle_view_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
			return true
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, VIEW_ZOOM_STEP)
			return true
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / VIEW_ZOOM_STEP)
			return true
	elif event is InputEventMouseMotion and _panning:
		var mm := event as InputEventMouseMotion
		_view_pan += mm.relative
		_compose_view_xform()
		_apply_view_to_cars()
		_update_reset_btn()
		queue_redraw()
		return true
	return false


func _draw_space_debug(bind: SplineTrackBind) -> void:
	for space in engine.track.space_count:
		var poses := bind.space_slot_poses(space)
		if poses.is_empty():
			continue
		var world: Vector2 = poses[0].pos
		var pos: Vector2 = _view_xform * world
		var col := Color(1, 1, 0, 0.55)
		if engine.track.corner_after(space) != null:
			col = Color(0.2, 1, 0.3, 0.8)
		if space == 0:
			col = Color(1, 0.3, 0.3, 0.8)
		draw_circle(pos, 4.0, col)


func _sync_cars() -> void:
	if engine == null:
		_clear_cars()
		return
	if engine.track != null and engine.track.spline_bind != null:
		_ensure_fit(engine.track.spline_bind)
	var alive: Dictionary = {}
	for p in engine.players:
		alive[p.id] = true
		var car: CarToken = _cars.get(p.id) as CarToken
		if car == null:
			car = CAR_SCENE.instantiate() as CarToken
			_cars_layer.add_child(car)
			car.setup(p.id)
			_cars[p.id] = car
		var prog := _display_progress(p)
		var spot := float(_viz_spot.get(p.id, float(p.spot)))
		var sample := _car_sample(prog, spot)
		car.set_pose(sample.pos, sample.heading)
		car.set_finished(p.finished)
	var stale: Array[int] = []
	for player_id in _cars.keys():
		if not alive.has(player_id):
			stale.append(int(player_id))
	for player_id in stale:
		var car: CarToken = _cars[player_id]
		_cars.erase(player_id)
		if is_instance_valid(car):
			car.queue_free()


func _clear_cars() -> void:
	for player_id in _cars.keys():
		var car: CarToken = _cars[player_id]
		if is_instance_valid(car):
			car.queue_free()
	_cars.clear()


func _display_progress(p: PlayerState) -> float:
	if _viz_progress.has(p.id):
		return float(_viz_progress[p.id])
	var prog := float(p.progress)
	_viz_progress[p.id] = prog
	_viz_spot[p.id] = p.spot
	return prog


func _ensure_viz_keys() -> void:
	for p in engine.players:
		if not _viz_progress.has(p.id):
			_viz_progress[p.id] = float(p.progress)
			_viz_spot[p.id] = float(p.spot)


func _snap_all() -> void:
	_clear_viz()
	for p in engine.players:
		_viz_progress[p.id] = float(p.progress)
		_viz_spot[p.id] = float(p.spot)


func _clear_viz() -> void:
	_viz_progress.clear()
	_viz_spot.clear()
	_anim_from.clear()
	_anim_to.clear()
	_anim_from_spot.clear()
	_anim_to_spot.clear()
	_anim_elapsed.clear()
	_anim_duration.clear()


func _start_animations() -> void:
	for p in engine.players:
		var from_p := float(_viz_progress.get(p.id, float(p.progress)))
		var to_p := float(p.progress)
		var from_s := float(_viz_spot.get(p.id, float(p.spot)))
		var to_s := float(p.spot)
		if is_equal_approx(from_p, to_p) and is_equal_approx(from_s, to_s):
			_viz_progress[p.id] = to_p
			_viz_spot[p.id] = to_s
			continue
		_anim_from[p.id] = from_p
		_anim_to[p.id] = to_p
		_anim_from_spot[p.id] = from_s
		_anim_to_spot[p.id] = to_s
		_anim_elapsed[p.id] = 0.0
		var dist := absf(to_p - from_p) + absf(to_s - from_s) * 0.35
		_anim_duration[p.id] = MOVE_DURATION * clampf(dist / 4.0, 0.55, 1.6)


func _car_sample(progress: float, spot: float) -> Dictionary:
	var bind := engine.track.spline_bind if engine != null and engine.track != null else null
	if bind == null:
		return {"pos": Vector2.ZERO, "heading": Vector2.RIGHT}
	return bind.sample_at(progress, spot)
