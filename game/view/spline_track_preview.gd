class_name SplineTrackPreview
extends Control

## Auto-fitting canvas that paints a saved track via SplineTrackPainter.

const PLACEHOLDER_COLOR := Color(0.35, 0.36, 0.38, 0.55)

var _spline: TrackSpline
var _baked: PackedVector2Array = PackedVector2Array()
var _ctx: SplineTrackPainter.Context = SplineTrackPainter.Context.new()
var _opts: SplineTrackPainter.Options = SplineTrackPainter.preview_options()
var _placeholder := "Sélectionne une piste"
var _ground: ColorRect
var _ground_theme := TrackGround.DEFAULT_THEME
## flip_key -> true (same storage as the editor document).
var _sector_flip_race_line: Dictionary = {}
var _corners: Dictionary = {}
var _kerbs: Dictionary = {}
var _decorations: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	_ground = TrackGround.attach(self, _ground_theme)
	_ctx.font = ThemeDB.fallback_font
	_ctx.race_line_flipped = _space_race_line_flipped


func set_placeholder(text: String) -> void:
	_placeholder = text
	queue_redraw()


func clear_track() -> void:
	_spline = null
	_baked = PackedVector2Array()
	_ctx.seg = null
	_corners.clear()
	_kerbs.clear()
	_decorations.clear()
	_sector_flip_race_line.clear()
	_set_ground_theme(TrackGround.DEFAULT_THEME)
	queue_redraw()


func set_from_document(data: Dictionary) -> void:
	if not SplineTrackFile.is_valid_document(data):
		clear_track()
		return
	var spline_data: Variant = data.get("spline", {})
	if not spline_data is Dictionary:
		clear_track()
		return
	_set_ground_theme(TrackGround.from_document(data))
	_spline = TrackSpline.from_dict(spline_data)
	_baked = SplineTrackPainter.bake_spline(_spline)
	var params := TrackSegmenter.Params.new()
	params.road_half_width = SplineTrackPainter.HALF_WIDTH
	var seg: Variant = data.get("segmentation", {})
	if seg is Dictionary:
		params.algorithm = int(seg.get("algorithm", TrackSegmenter.Algorithm.INNER_UNIFORM))
		params.car_length = float(seg.get("car_length", 36.0))
		params.target_space_len = float(seg.get("target_space_len", params.car_length))
	_ctx.half_width = SplineTrackPainter.HALF_WIDTH
	_ctx.spot_inset = params.spot_inset
	_ctx.seg = TrackSegmenter.segment(_spline, params)
	_ctx.start_space = int(data.get("start_space", 0))
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
	_ctx.corners = _corners
	_kerbs.clear()
	var kerbs_data: Variant = data.get("kerbs", [])
	if kerbs_data is Array:
		for k_item in kerbs_data:
			if not k_item is Dictionary:
				continue
			var k_entry: Dictionary = k_item
			var k_space := int(k_entry.get("space", -1))
			if k_space < 0:
				continue
			var want_in := bool(k_entry.get("inside", false))
			var want_out := bool(k_entry.get("outside", false))
			if not want_in and not want_out:
				continue
			_kerbs[k_space] = {"inside": want_in, "outside": want_out}
	_ctx.kerbs = _kerbs
	_sector_flip_race_line.clear()
	var flips_data: Variant = data.get("sector_flip_race_line", [])
	if flips_data is Array:
		for item2 in flips_data:
			if item2 is Dictionary:
				_sector_flip_race_line[int(item2.get("key", -1))] = true
			elif item2 != null:
				_sector_flip_race_line[int(item2)] = true
	_decorations = TrackDecor.from_document(data)
	queue_redraw()


func set_from_path(path: String) -> void:
	if path.is_empty():
		clear_track()
		return
	set_from_document(SplineTrackFile.load_document(path))


func has_track() -> bool:
	return _baked.size() >= 3


func _space_race_line_flipped(space: int) -> bool:
	if _ctx.seg == null or _corners.is_empty():
		return bool(_sector_flip_race_line.get(-1, false))
	# Flip key = corner exited into the sector containing this space.
	var n := _ctx.seg.space_count()
	if n == 0:
		return false
	var corners: Array[int] = []
	for key in _corners.keys():
		corners.append(int(key))
	corners.sort()
	if corners.is_empty():
		return false
	# Sector after the last corner before `space` (track order).
	var key := corners[corners.size() - 1]
	for i in corners.size():
		var c := corners[i]
		var next_c := corners[(i + 1) % corners.size()]
		var from := posmod(c + 1, n)
		var to := next_c
		if posmod(space - from, n) <= posmod(to - from, n):
			key = c
			break
	return bool(_sector_flip_race_line.get(key, false))


func _draw() -> void:
	var bg := Rect2(Vector2.ZERO, size)
	if not has_track():
		_draw_placeholder()
		return
	var world := SplineTrackPainter.bounds(_baked, _ctx.half_width)
	var xform := SplineTrackPainter.fit_transform(world, bg, 18.0)
	SplineTrackPainter.draw(self, _baked, _ctx, _opts, xform)
	TrackDecor.draw(self, _decorations, xform)


func _set_ground_theme(theme_id: String) -> void:
	_ground_theme = TrackGround.normalize(theme_id)
	if _ground == null:
		_ground = TrackGround.attach(self, _ground_theme)
		return
	var mat := _ground.material as ShaderMaterial
	if mat == null:
		_ground.material = TrackGround.make_material(_ground_theme)
	else:
		TrackGround.apply(mat, _ground_theme)


func _draw_placeholder() -> void:
	var font := ThemeDB.fallback_font
	var font_size := 14
	var text_size := font.get_string_size(_placeholder, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pos := (size - text_size) * 0.5 + Vector2(0, text_size.y)
	draw_string(font, pos, _placeholder, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, PLACEHOLDER_COLOR)
