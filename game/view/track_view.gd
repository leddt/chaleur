class_name TrackView
extends Control

const PLAYER_COLORS := CarToken.PLAYER_COLORS
const CAR_SCENE := preload("res://view/car.tscn")
const MOVE_DURATION := 0.5

var engine: HeatGameEngine
var highlight_spaces: Array[int] = []
var show_space_debug: bool = false

## Visual progress/spot (lags behind engine while animating).
var _viz_progress: Dictionary = {} # player_id -> float
var _viz_spot: Dictionary = {} # player_id -> int
var _anim_from: Dictionary = {} # player_id -> float
var _anim_to: Dictionary = {} # player_id -> float
var _anim_elapsed: Dictionary = {} # player_id -> float
var _anim_duration: Dictionary = {} # player_id -> float
var _layout: TrackLayout

var _cars_layer: Node2D
var _cars: Dictionary = {} # player_id -> CarToken


func _ready() -> void:
	set_process(true)
	_cars_layer = Node2D.new()
	_cars_layer.name = "Cars"
	add_child(_cars_layer)


func set_engine(p_engine: HeatGameEngine, snap: bool = false) -> void:
	engine = p_engine
	_layout = null
	if engine != null and engine.track != null:
		_layout = TrackLayout.for_track_id(engine.track.id)
	if engine == null:
		_clear_viz()
		_clear_cars()
		queue_redraw()
		return
	if snap or _viz_progress.is_empty():
		_snap_all()
	else:
		_ensure_viz_keys()
	_sync_cars()
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
		_viz_progress[player_id] = lerpf(from_p, to_p, u)
		if t >= 1.0:
			_viz_progress[player_id] = to_p
			finished.append(int(player_id))
	for player_id in finished:
		_anim_from.erase(player_id)
		_anim_to.erase(player_id)
		_anim_elapsed.erase(player_id)
		_anim_duration.erase(player_id)
	_sync_cars()
	queue_redraw()


func _draw() -> void:
	if engine == null or engine.track == null:
		return
	if _layout != null and _layout.texture != null:
		_draw_layout_track()
	else:
		_draw_oval_track()


func _draw_layout_track() -> void:
	var rect := _layout.fitted_rect(size)
	draw_texture_rect(_layout.texture, rect, false)
	if show_space_debug:
		for space in engine.track.space_count:
			var uv := _layout.spot_uv(space, 0)
			var pos := _layout.uv_to_view(uv, size)
			var col := Color(1, 1, 0, 0.55)
			if engine.track.corner_after(space) != null:
				col = Color(0.2, 1, 0.3, 0.8)
			if space == 0:
				col = Color(1, 0.3, 0.3, 0.8)
			draw_circle(pos, 4.0, col)
			if space % 3 == 0:
				draw_string(ThemeDB.fallback_font, pos + Vector2(4, -4), str(space), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)


func _draw_oval_track() -> void:
	var track := engine.track
	var center := size * 0.5
	var rx := size.x * 0.42
	var ry := size.y * 0.38
	for space in track.space_count:
		var pos := _oval_space_pos(space, center, rx, ry)
		var is_corner := track.corner_after(space) != null
		var is_finish := space == 0
		var color := Color(0.75, 0.45, 0.2) if is_corner else Color(0.35, 0.38, 0.42)
		if is_finish:
			color = Color(0.85, 0.85, 0.9)
		if space in highlight_spaces:
			color = Color(0.95, 0.9, 0.35)
		draw_circle(pos, 14.0, color)
		draw_arc(pos, 14.0, 0, TAU, 24, Color(0.1, 0.1, 0.1), 2.0)
		var label := "F" if is_finish else str(space)
		var corner := track.corner_after(space)
		if corner:
			label = "%d<%d" % [space, corner.speed_limit]
		draw_string(ThemeDB.fallback_font, pos + Vector2(-10, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)


func _sync_cars() -> void:
	if engine == null:
		_clear_cars()
		return
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
		var spot := int(_viz_spot.get(p.id, p.spot))
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
	if _anim_to.has(p.id):
		return float(_viz_progress.get(p.id, p.progress))
	var prog := float(p.progress)
	_viz_progress[p.id] = prog
	_viz_spot[p.id] = p.spot
	return prog


func _clear_viz() -> void:
	_anim_from.clear()
	_anim_to.clear()
	_anim_elapsed.clear()
	_anim_duration.clear()
	_viz_progress.clear()
	_viz_spot.clear()


func _ensure_viz_keys() -> void:
	for p in engine.players:
		if not _viz_progress.has(p.id):
			_viz_progress[p.id] = float(p.progress)
			_viz_spot[p.id] = p.spot


func _snap_all() -> void:
	_anim_from.clear()
	_anim_to.clear()
	_anim_elapsed.clear()
	_anim_duration.clear()
	_viz_progress.clear()
	_viz_spot.clear()
	for p in engine.players:
		_viz_progress[p.id] = float(p.progress)
		_viz_spot[p.id] = p.spot


func _start_animations() -> void:
	for p in engine.players:
		var from_prog := float(_viz_progress.get(p.id, p.progress))
		var to_prog := float(p.progress)
		_viz_spot[p.id] = p.spot
		if absf(from_prog - to_prog) < 0.01:
			_viz_progress[p.id] = to_prog
			_anim_from.erase(p.id)
			_anim_to.erase(p.id)
			_anim_elapsed.erase(p.id)
			_anim_duration.erase(p.id)
			continue
		if _anim_to.has(p.id) and absf(float(_anim_to[p.id]) - to_prog) < 0.01:
			continue
		var steps := maxf(1.0, absf(to_prog - from_prog))
		_anim_from[p.id] = from_prog
		_anim_to[p.id] = to_prog
		_anim_elapsed[p.id] = 0.0
		_anim_duration[p.id] = clampf(MOVE_DURATION * (steps / 3.0), 0.35, 1.1)
		_viz_progress[p.id] = from_prog


func _car_sample(progress: float, spot: int) -> Dictionary:
	if _layout != null and _layout.texture != null:
		return _car_sample_layout(progress, spot)
	var center := size * 0.5
	return _car_sample_oval(progress, spot, center, size.x * 0.42, size.y * 0.38)


func _car_sample_layout(progress: float, spot: int) -> Dictionary:
	var track := engine.track
	var p0 := int(floor(progress))
	var frac := progress - float(p0)
	var s0 := track.space_of_progress(p0)
	var s1 := track.space_of_progress(p0 + 1)
	var a := _layout.uv_to_view(_layout.spot_uv(s0, spot), size)
	var b := _layout.uv_to_view(_layout.spot_uv(s1, spot), size)
	var pos := a.lerp(b, frac)
	var heading := b - a
	if heading.length_squared() < 0.0001:
		var s2 := track.space_of_progress(p0 + 2)
		var c := _layout.uv_to_view(_layout.spot_uv(s2, spot), size)
		heading = c - a
	return {"pos": pos, "heading": heading}


func _car_sample_oval(progress: float, spot: int, center: Vector2, rx: float, ry: float) -> Dictionary:
	var track := engine.track
	var p0 := int(floor(progress))
	var frac := progress - float(p0)
	var s0 := track.space_of_progress(p0)
	var s1 := track.space_of_progress(p0 + 1)
	var a := _oval_space_pos(s0, center, rx, ry)
	var b := _oval_space_pos(s1, center, rx, ry)
	var base := a.lerp(b, frac)
	var tangential := b - a
	if tangential.length_squared() < 0.0001:
		var nxt := _oval_space_pos((s0 + 1) % track.space_count, center, rx, ry)
		tangential = nxt - a
	tangential = tangential.normalized()
	var normal := Vector2(-tangential.y, tangential.x)
	var pos := base + normal * (float(spot) - 0.5) * 12.0
	return {"pos": pos, "heading": tangential}


func _oval_space_pos(space: int, center: Vector2, rx: float, ry: float) -> Vector2:
	var t := float(space) / float(engine.track.space_count) * TAU - PI * 0.5
	return center + Vector2(cos(t) * rx, sin(t) * ry)
