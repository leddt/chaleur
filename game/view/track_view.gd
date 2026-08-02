class_name TrackView
extends Control

const PLAYER_COLORS: Array[Color] = [
	Color(0.9, 0.25, 0.25),
	Color(0.25, 0.55, 0.95),
	Color(0.25, 0.8, 0.4),
	Color(0.95, 0.8, 0.2),
	Color(0.95, 0.55, 0.15),
	Color(0.7, 0.35, 0.9),
]

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


func _ready() -> void:
	set_process(true)


func set_engine(p_engine: HeatGameEngine, snap: bool = false) -> void:
	engine = p_engine
	_layout = null
	if engine != null and engine.track != null:
		_layout = TrackLayout.for_track_id(engine.track.id)
	if engine == null:
		_clear_viz()
		queue_redraw()
		return
	if snap or _viz_progress.is_empty():
		_snap_all()
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
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
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
	for p in engine.players:
		var prog := _display_progress(p)
		var spot := int(_viz_spot.get(p.id, p.spot))
		var car_pos := _car_pos_layout(prog, spot)
		_draw_car(car_pos, p)


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
	for p in engine.players:
		var prog := _display_progress(p)
		var spot := int(_viz_spot.get(p.id, p.spot))
		var car_pos := _car_pos_oval(prog, spot, center, rx, ry)
		_draw_car(car_pos, p)


func _draw_car(car_pos: Vector2, p: PlayerState) -> void:
	var col := PLAYER_COLORS[p.id % PLAYER_COLORS.size()]
	draw_circle(car_pos, 9.0, col)
	var ring := Color(1, 1, 1) if p.finished else Color(0, 0, 0)
	draw_arc(car_pos, 9.0, 0, TAU, 20, ring, 2.5 if p.finished else 2.0)
	var tag := "F" if p.finished else str(p.id + 1)
	draw_string(
		ThemeDB.fallback_font,
		car_pos + Vector2(-4, 4),
		tag,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		11,
		Color.WHITE
	)


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


func _car_pos_layout(progress: float, spot: int) -> Vector2:
	var track := engine.track
	var p0 := int(floor(progress))
	var frac := progress - float(p0)
	var s0 := track.space_of_progress(p0)
	var s1 := track.space_of_progress(p0 + 1)
	var a := _layout.uv_to_view(_layout.spot_uv(s0, spot), size)
	var b := _layout.uv_to_view(_layout.spot_uv(s1, spot), size)
	return a.lerp(b, frac)


func _car_pos_oval(progress: float, spot: int, center: Vector2, rx: float, ry: float) -> Vector2:
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
		tangential = (nxt - a).normalized()
	else:
		tangential = tangential.normalized()
	var normal := Vector2(-tangential.y, tangential.x)
	return base + normal * (float(spot) - 0.5) * 12.0


func _oval_space_pos(space: int, center: Vector2, rx: float, ry: float) -> Vector2:
	var t := float(space) / float(engine.track.space_count) * TAU - PI * 0.5
	return center + Vector2(cos(t) * rx, sin(t) * ry)
