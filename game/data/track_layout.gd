class_name TrackLayout
extends RefCounted

const TRACK1_JSON := "res://data/track1_layout.json"

## Visual layout for a track: background texture + normalized spot positions.

var id: String = ""
var source_path: String = ""
var texture: Texture2D
var image_size: Vector2 = Vector2.ZERO
## spaces[i] = Array of Vector2 in 0..1 image UV (spot 0 = race line / inner).
var spaces: Array = []
## Parallel to HeatCorner: {from_space, speed_limit, id}
var corners: Array[Dictionary] = []
## Extra JSON keys preserved on save (sectors, start, …).
var extra: Dictionary = {}


static func for_track_id(track_id: String) -> TrackLayout:
	match track_id:
		"track1":
			return load_json(TRACK1_JSON)
		_:
			return null


static func load_json(path: String) -> TrackLayout:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("TrackLayout: cannot open %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("TrackLayout: invalid JSON %s" % path)
		return null
	var data: Dictionary = parsed
	var layout := TrackLayout.new()
	layout.source_path = path
	layout.id = str(data.get("id", ""))
	var img_path := str(data.get("image", ""))
	if not img_path.is_empty() and ResourceLoader.exists(img_path):
		layout.texture = load(img_path) as Texture2D
	var isize: Array = data.get("image_size", [0, 0])
	if isize.size() >= 2:
		layout.image_size = Vector2(float(isize[0]), float(isize[1]))
	layout.spaces.clear()
	for space_data in data.get("spaces", []):
		var spots: Array[Vector2] = []
		for spot in space_data.get("spots", []):
			if spot is Array and spot.size() >= 2:
				spots.append(Vector2(float(spot[0]), float(spot[1])))
		layout.spaces.append(spots)
	layout.corners.clear()
	for c in data.get("corners", []):
		layout.corners.append({
			"from_space": int(c.get("from_space", 0)),
			"speed_limit": int(c.get("speed_limit", 0)),
			"id": str(c.get("id", "")),
		})
	layout.extra.clear()
	for key in data.keys():
		if key in ["id", "image", "image_size", "space_count", "spaces", "corners"]:
			continue
		layout.extra[key] = data[key]
	return layout


func set_spot_uv(space: int, spot: int, uv: Vector2) -> void:
	if space < 0 or space >= spaces.size():
		return
	var spots: Array = spaces[space]
	uv = uv.clamp(Vector2.ZERO, Vector2.ONE)
	while spots.size() <= spot:
		spots.append(uv)
	spots[spot] = uv
	spaces[space] = spots


func save_json(path: String = "") -> Error:
	var out_path := path if not path.is_empty() else source_path
	if out_path.is_empty():
		out_path = TRACK1_JSON
	var spaces_data: Array = []
	for spots in spaces:
		var spot_arr: Array = []
		for uv in spots:
			var v: Vector2 = uv
			spot_arr.append([v.x, v.y])
		spaces_data.append({"spots": spot_arr})
	var corners_data: Array = []
	for c in corners:
		corners_data.append({
			"from_space": int(c.get("from_space", 0)),
			"speed_limit": int(c.get("speed_limit", 0)),
			"id": str(c.get("id", "")),
		})
	var data: Dictionary = {
		"id": id,
		"image": "res://assets/track1.jpg" if id == "track1" else "",
		"image_size": [int(image_size.x), int(image_size.y)],
		"space_count": spaces.size(),
		"spaces": spaces_data,
		"corners": corners_data,
	}
	for key in extra.keys():
		data[key] = extra[key]
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		push_error("TrackLayout: cannot write %s (%s)" % [out_path, FileAccess.get_open_error()])
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	source_path = out_path
	return OK


func space_count() -> int:
	return spaces.size()


func spot_count(space: int) -> int:
	if space < 0 or space >= spaces.size():
		return 1
	var spots: Array = spaces[space]
	return maxi(1, spots.size())


func spot_uv(space: int, spot: int) -> Vector2:
	if spaces.is_empty():
		return Vector2(0.5, 0.5)
	var idx := posmod(space, spaces.size())
	var spots: Array = spaces[idx]
	if spots.is_empty():
		return Vector2(0.5, 0.5)
	if spot < spots.size():
		return spots[spot]
	# Extrapolate past last defined spot along the lane axis.
	if spots.size() == 1:
		return spots[0]
	var a: Vector2 = spots[spots.size() - 2]
	var b: Vector2 = spots[spots.size() - 1]
	var step := b - a
	return b + step * float(spot - (spots.size() - 1))


## Letterboxed rect that fits the track image inside `view_size`.
func fitted_rect(view_size: Vector2) -> Rect2:
	if texture == null:
		return Rect2(Vector2.ZERO, view_size)
	var tex_size := texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return Rect2(Vector2.ZERO, view_size)
	var scale := minf(view_size.x / tex_size.x, view_size.y / tex_size.y)
	var drawn := tex_size * scale
	var origin := (view_size - drawn) * 0.5
	return Rect2(origin, drawn)


func uv_to_view(uv: Vector2, view_size: Vector2) -> Vector2:
	var rect := fitted_rect(view_size)
	return rect.position + Vector2(uv.x * rect.size.x, uv.y * rect.size.y)


func to_heat_track(laps: int = 1) -> HeatTrack:
	var track := HeatTrack.new()
	track.id = id
	track.space_count = space_count()
	track.laps = laps
	track.start_heat = 6
	track.start_stress = 3
	track.start_behind_finish_line = true
	track.start_max_per_space = 2
	track.spots.clear()
	for i in track.space_count:
		# Entire track1 is two-wide; ignore any legacy 6-spot start on space 0.
		track.spots.append(mini(2, spot_count(i)) if id == "track1" else spot_count(i))
	track.corners.clear()
	for c in corners:
		track.corners.append(HeatCorner.new(
			int(c.get("from_space", 0)),
			int(c.get("speed_limit", 0)),
			str(c.get("id", ""))
		))
	return track
