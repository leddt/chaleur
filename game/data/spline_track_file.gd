class_name SplineTrackFile
extends RefCounted

## JSON documents for spline tracks stored under user://tracks/.

const VERSION := 1
const USER_DIR := "user://tracks"

## Path to open in the spline editor next scene change. Empty = new track.
static var editor_pending_path: String = ""


static func ensure_user_dir() -> Error:
	if DirAccess.dir_exists_absolute(USER_DIR):
		return OK
	return DirAccess.make_dir_recursive_absolute(USER_DIR)


static func slugify(track_name: String) -> String:
	var raw := track_name.strip_edges().to_lower()
	var out := ""
	for i in raw.length():
		var ch := raw[i]
		var code := ch.unicode_at(0)
		var is_alnum := (
			(code >= 97 and code <= 122)
			or (code >= 48 and code <= 57)
		)
		if is_alnum:
			out += ch
		elif ch == " " or ch == "-" or ch == "_":
			if out.is_empty() or out[out.length() - 1] != "_":
				out += "_"
	out = out.strip_edges().trim_prefix("_").trim_suffix("_")
	if out.is_empty():
		out = "trace_%d" % int(Time.get_unix_time_from_system())
	return out


static func path_for_name(track_name: String) -> String:
	return "%s/%s.json" % [USER_DIR, slugify(track_name)]


static func save_document(path: String, data: Dictionary) -> Error:
	var dir_err := ensure_user_dir()
	if dir_err != OK:
		push_error("SplineTrackFile: cannot create %s (%s)" % [USER_DIR, dir_err])
		return dir_err
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var err := FileAccess.get_open_error()
		push_error("SplineTrackFile: cannot write %s (%s)" % [path, err])
		return err
	file.store_string(JSON.stringify(data, "\t"))
	return OK


static func load_document(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SplineTrackFile: cannot read %s (%s)" % [path, FileAccess.get_open_error()])
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	push_error("SplineTrackFile: invalid JSON in %s" % path)
	return {}


static func delete_document(path: String) -> Error:
	if path.is_empty() or not FileAccess.file_exists(path):
		return OK
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		push_error("SplineTrackFile: cannot delete %s (%s)" % [path, err])
	return err


## True for documents written by this editor (ignores other JSON leftover in USER_DIR).
static func is_valid_document(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	if int(data.get("version", 0)) < 1:
		return false
	var spline: Variant = data.get("spline", null)
	if not spline is Dictionary:
		return false
	var points: Variant = spline.get("points", null)
	return points is Array and not points.is_empty()


## [{path: String, name: String, modified: int}] sorted by name.
static func list_entries() -> Array:
	ensure_user_dir()
	var entries: Array = []
	var dir := DirAccess.open(USER_DIR)
	if dir == null:
		return entries
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var path := "%s/%s" % [USER_DIR, file_name]
			var data := load_document(path)
			if not is_valid_document(data):
				file_name = dir.get_next()
				continue
			var display_name := str(data.get("name", "")).strip_edges()
			if display_name.is_empty():
				display_name = file_name.get_basename()
			entries.append({
				"path": path,
				"name": display_name,
				"modified": int(FileAccess.get_modified_time(path)),
			})
		file_name = dir.get_next()
	dir.list_dir_end()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")).to_lower() < str(b.get("name", "")).to_lower()
	)
	return entries
