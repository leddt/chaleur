extends Control

## Chooses an existing user:// spline track or starts a new one.

@onready var _list: ItemList = %TrackList
@onready var _empty_label: Label = %EmptyLabel
@onready var _open_button: Button = %OpenButton
@onready var _preview: SplineTrackPreview = %Preview

var _paths: Array[String] = []


func _ready() -> void:
	theme = ThemeBuilder.build()
	_apply_kit_chrome()
	%NewButton.pressed.connect(_on_new_pressed)
	%OpenButton.pressed.connect(_on_open_pressed)
	%BackButton.pressed.connect(_on_back_pressed)
	_list.item_selected.connect(_on_item_selected)
	_list.item_activated.connect(_on_item_activated)
	_preview.set_placeholder("Sélectionne un tracé")
	_refresh_list()


func _apply_kit_chrome() -> void:
	var bg := get_node_or_null("Background") as ColorRect
	if bg != null:
		bg.color = Palette.ASPHALT
	var title := get_node_or_null("%Title") as Label
	if title != null:
		title.theme_type_variation = &"TitleLabel"
	var eyebrow := get_node_or_null("%Eyebrow") as Label
	if eyebrow != null:
		eyebrow.theme_type_variation = &"Eyebrow"
		eyebrow.text = eyebrow.text.to_upper()
	_empty_label.theme_type_variation = &"Caption"
	%NewButton.theme_type_variation = &"Primary"
	%OpenButton.theme_type_variation = &"Primary"
	%BackButton.theme_type_variation = &"Compact"
	var panel := get_node_or_null("%Panel") as PanelContainer
	if panel != null:
		panel.theme_type_variation = &"Instrument"
	for path in [
		"Center/Panel/Margin/VBox/Body/ListCol/ListLabel",
		"Center/Panel/Margin/VBox/Body/PreviewCol/PreviewLabel",
	]:
		var label := get_node_or_null(path) as Label
		if label != null:
			label.theme_type_variation = &"Eyebrow"
			label.text = label.text.to_upper()


func _refresh_list() -> void:
	_list.clear()
	_paths.clear()
	_preview.clear_track()
	var entries := SplineTrackFile.list_entries()
	for entry in entries:
		if not entry is Dictionary:
			continue
		var path := str(entry.get("path", ""))
		var track_name := str(entry.get("name", path))
		if bool(entry.get("builtin", false)):
			track_name = "%s · intégrée" % track_name
		_list.add_item(track_name)
		_paths.append(path)
	var has_tracks := not _paths.is_empty()
	_list.visible = has_tracks
	_empty_label.visible = not has_tracks
	_open_button.disabled = true
	if has_tracks:
		_list.select(0)
		_on_item_selected(0)


func _on_item_selected(index: int) -> void:
	_open_button.disabled = _list.get_selected_items().is_empty()
	_show_preview(index)


func _show_preview(index: int) -> void:
	if index < 0 or index >= _paths.size():
		_preview.clear_track()
		return
	_preview.set_from_path(_paths[index])


func _on_item_activated(index: int) -> void:
	_open_path_at(index)


func _on_open_pressed() -> void:
	var selected := _list.get_selected_items()
	if selected.is_empty():
		return
	_open_path_at(selected[0])


func _open_path_at(index: int) -> void:
	if index < 0 or index >= _paths.size():
		return
	SplineTrackFile.editor_pending_path = _paths[index]
	get_tree().change_scene_to_file("res://view/spline_track_editor.tscn")


func _on_new_pressed() -> void:
	SplineTrackFile.editor_pending_path = ""
	get_tree().change_scene_to_file("res://view/spline_track_editor.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
