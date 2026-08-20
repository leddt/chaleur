extends Control

## Local race setup: pick a saved spline track and lap count before the board.

@onready var _list: ItemList = %TrackList
@onready var _empty_label: Label = %EmptyLabel
@onready var _start_button: Button = %StartButton
@onready var _laps_spin: SpinBox = %LapsSpin
@onready var _preview: SplineTrackPreview = %Preview
@onready var _hint: Label = %HintLabel

var _paths: Array[String] = []


func _ready() -> void:
	_apply_kit_chrome()
	%StartButton.pressed.connect(_on_start_pressed)
	%BackButton.pressed.connect(_on_back_pressed)
	_list.item_selected.connect(_on_item_selected)
	_list.item_activated.connect(func(_i: int) -> void: _on_start_pressed())
	_preview.set_placeholder("Sélectionne une piste")
	_laps_spin.min_value = 1
	_laps_spin.max_value = 6
	_laps_spin.value = 1
	_wire_garage_toggles()
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
	_hint.theme_type_variation = &"Caption"
	%StartButton.theme_type_variation = &"Primary"
	%BackButton.theme_type_variation = &"Compact"
	var panel := get_node_or_null("%Panel") as PanelContainer
	if panel != null:
		panel.theme_type_variation = &"Instrument"


func _refresh_list() -> void:
	_list.clear()
	_paths.clear()
	_preview.clear_track()
	for entry in HeatTrack.catalog():
		var path := str(entry.get("id", ""))
		var track_name := str(entry.get("name", path))
		if bool(entry.get("builtin", false)):
			track_name = "%s · intégrée" % track_name
		_list.add_item(track_name)
		_paths.append(path)
	var has_tracks := not _paths.is_empty()
	_list.visible = has_tracks
	_empty_label.visible = not has_tracks
	_start_button.disabled = not has_tracks
	_hint.text = (
		"Choisis une piste et le nombre de tours."
		if has_tracks
		else "Aucune piste enregistrée. Crée-en une dans le créateur de piste."
	)
	if has_tracks:
		_list.select(0)
		_on_item_selected(0)


func _wire_garage_toggles() -> void:
	%GarageCheck.toggled.connect(func(_on: bool) -> void: _sync_garage_enabled())
	_sync_garage_enabled()


func _sync_garage_enabled() -> void:
	var on: bool = %GarageCheck.button_pressed
	%GarageBasicCheck.disabled = not on
	%GarageAdvancedCheck.disabled = not on
	%GarageQuickCheck.disabled = not on


func _race_options() -> RaceOptions:
	var o := RaceOptions.new()
	o.garage_enabled = %GarageCheck.button_pressed
	o.garage_include_basic = %GarageBasicCheck.button_pressed
	o.garage_include_advanced = %GarageAdvancedCheck.button_pressed
	o.garage_quick_start = %GarageQuickCheck.button_pressed
	return o


func _on_item_selected(index: int) -> void:
	_start_button.disabled = _paths.is_empty()
	if index < 0 or index >= _paths.size():
		_preview.clear_track()
		return
	_laps_spin.value = clampf(
		float(SplineTrackFile.default_laps_for_path(_paths[index])),
		_laps_spin.min_value,
		_laps_spin.max_value,
	)
	_preview.set_from_path(_paths[index])


func _on_start_pressed() -> void:
	var selected := _list.get_selected_items()
	if selected.is_empty() or _paths.is_empty():
		return
	var path := _paths[selected[0]]
	if not Game.start_local_race([], int(_laps_spin.value), 0, path, _race_options()):
		_hint.text = "Impossible de charger cette piste."
		return
	get_tree().change_scene_to_file(Game.race_scene_path())


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
