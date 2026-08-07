class_name TrackView
extends Control

const CAR_SCENE := preload("res://view/car.tscn")
const MOVE_DURATION := 0.5

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


func _ready() -> void:
	set_process(true)
	_cars_layer = Node2D.new()
	_cars_layer.name = "Cars"
	add_child(_cars_layer)


func set_engine(p_engine: HeatGameEngine, snap: bool = false) -> void:
	engine = p_engine
	if engine == null:
		_clear_viz()
		_clear_cars()
		queue_redraw()
		return
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


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_sync_cars()
		queue_redraw()


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
	_rebuild_view_xform(bind)
	var opts := SplineTrackPainter.game_options()
	SplineTrackPainter.draw(self, bind.baked_points(), bind.paint_context(), opts, _view_xform)
	if show_space_debug:
		_draw_space_debug(bind)


func _rebuild_view_xform(bind: SplineTrackBind) -> void:
	var baked := bind.baked_points()
	var world := SplineTrackPainter.bounds(baked, bind.half_width)
	_view_xform = SplineTrackPainter.fit_transform(world, Rect2(Vector2.ZERO, size), 24.0)
	_apply_view_to_cars()


func _apply_view_to_cars() -> void:
	if _cars_layer == null:
		return
	# Same pattern as the spline editor: cars live in world space under the view transform
	# so CAR_LENGTH stays proportional to road width when the track is fitted.
	var s := absf(_view_xform.get_scale().x)
	_cars_layer.position = _view_xform.origin
	_cars_layer.scale = Vector2(s, s)


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
		_rebuild_view_xform(engine.track.spline_bind)
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
