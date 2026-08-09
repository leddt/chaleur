extends Control

## Interactive editor for a closed TrackSpline (per-point Bezier types).

enum EditMode {
	TRACE, ## Edit control points / spline shape.
	SPACES, ## Inspect / tune space segmentation.
	SECTORS, ## Select stretches between corners (may wrap past start).
	DECOR, ## Track backdrop and scenery.
}

const CAR_SCENE := preload("res://view/car.tscn")
const RESET_VIEW_ICON := preload("res://ui/kit/icons/recadrer.png")
const DECOR_SELECT_ICON := preload("res://ui/kit/icons/selection.png")
const HANDLE_HIT_RADIUS := 12.0
const POINT_HIT_RADIUS := 14.0
const CURVE_HIT_RADIUS := 14.0
const MIN_CANVAS_SIZE := 32.0
## Half-width of the asphalt band around the centerline (pixels).
const ROAD_HALF_WIDTH := SplineTrackPainter.HALF_WIDTH
const CORNER_BADGE_RADIUS := SplineTrackPainter.CORNER_BADGE_RADIUS
## Gap from asphalt edge to the badge's natural center.
const CORNER_BADGE_GAP := SplineTrackPainter.CORNER_BADGE_GAP
## Spaces immediately behind the start line that form the starting grid.
const START_GRID_SPACES := SplineTrackPainter.START_GRID_SPACES
const START_GRID_MARKER_COLOR := SplineTrackPainter.START_GRID_MARKER_COLOR
## Outer lane sits this far back along the track relative to the inner spot.
const OUTER_SPOT_ALONG_OFFSET := SplineTrackPainter.OUTER_SPOT_ALONG_OFFSET
const SPACE_SELECTED_COLOR := Color(1.0, 0.85, 0.2, 0.1)
const SECTOR_SELECTED_COLOR := Color(0.5, 0.78, 1.0, 0.1)
const START_LINE_COLOR := SplineTrackPainter.START_LINE_COLOR
const CORNER_LINE_COLOR := SplineTrackPainter.CORNER_LINE_COLOR
const MIN_VIEW_ZOOM := 0.25
const MAX_VIEW_ZOOM := 4.0
const VIEW_ZOOM_STEP := 1.12
const FIT_MARGIN := 24.0

@onready var _canvas: Control = %Canvas
@onready var _summary: Label = %SummaryLabel
@onready var _track_name_edit: LineEdit = %TrackNameEdit
@onready var _ground_theme_option: OptionButton = %GroundThemeOption
@onready var _decor_select: Button = %DecorSelect
@onready var _decor_tree: Button = %DecorTree
@onready var _decor_rock: Button = %DecorRock
@onready var _decor_bleachers: Button = %DecorBleachers
@onready var _builtin_check: CheckBox = %BuiltinCheck
@onready var _mode_trace: Button = %ModeTrace
@onready var _mode_spaces: Button = %ModeSpaces
@onready var _mode_sectors: Button = %ModeSectors
@onready var _mode_decor: Button = %ModeDecor
@onready var _trace_section: Control = %TraceSection
@onready var _spaces_section: Control = %SpacesSection
@onready var _sectors_section: Control = %SectorsSection
@onready var _decor_section: Control = %DecorSection
@onready var _sector_info_label: Label = %SectorInfoLabel
@onready var _sector_race_line_button: Button = %SectorRaceLineButton
@onready var _type_auto: BaseButton = %TypeAuto
@onready var _type_tension: BaseButton = %TypeTension
@onready var _type_free: BaseButton = %TypeFree
@onready var _algo_center: BaseButton = %AlgoCenter
@onready var _algo_inner: BaseButton = %AlgoInner
@onready var _algo_adaptive: BaseButton = %AlgoAdaptive
@onready var _seg_mode_auto: Button = %SegModeAuto
@onready var _seg_mode_fixed: Button = %SegModeFixed
@onready var _len_row: Control = %LenRow
@onready var _count_row: Control = %CountRow
@onready var _space_len_slider: HSlider = %SpaceLenSlider
@onready var _space_len_value: Label = %SpaceLenValue
@onready var _space_count_spin: SpinBox = %SpaceCountSpin
@onready var _hide_space_numbers: CheckBox = %HideSpaceNumbers
@onready var _set_start_button: Button = %SetStartButton
@onready var _corner_speed_spin: SpinBox = %CornerSpeedSpin
@onready var _set_corner_button: Button = %SetCornerButton
@onready var _corner_side_button: Button = %CornerSideButton
@onready var _corner_details: Control = %CornerDetails
@onready var _kerb_details: Control = %KerbDetails
@onready var _kerb_inside_check: CheckBox = %KerbInsideCheck
@onready var _kerb_outside_check: CheckBox = %KerbOutsideCheck

var _spline: TrackSpline
var _track_name: String = ""
## Temporary draw target for paint layers (decor / handles).
var _draw_target: CanvasItem
var _ground_theme: String = TrackGround.DEFAULT_THEME
## Placeable scenery items: Array[{type, position:Vector2, seed}].
var _decorations: Array = []
var _decor_brush: String = TrackDecor.TOOL_SELECT
## Selected decoration indices in Decor+Select tool.
var _selected_decors: Array = []
## Next place preview: stable seed until the item is committed.
var _decor_ghost_seed: int = 1
var _decor_ghost_pos := Vector2.ZERO
var _decor_ghost_active: bool = false
## Pending place seed per tool (tree/rock) — matches palette icon.
var _decor_place_seeds: Dictionary = {
	TrackDecor.TYPE_TREE: 1,
	TrackDecor.TYPE_ROCK: 1,
	TrackDecor.TYPE_BLEACHERS: 1,
}
## user:// path when editing an existing document; empty for a new track.
var _file_path: String = ""
var _selected: int = 0
var _drag_mode: String = "" ## "", "point", "out_handle", "in_handle"
var _dirty: bool = false
var _updating_type_ui: bool = false
var _updating_seg_ui: bool = false
var _updating_mode_ui: bool = false
var _updating_name_ui: bool = false
var _updating_decor_ui: bool = false
var _ground: ColorRect
var _updating_corner_ui: bool = false
var _updating_kerb_ui: bool = false
var _spline_ready: bool = false
var _edit_mode: int = EditMode.TRACE
var _seg_params: TrackSegmenter.Params = TrackSegmenter.Params.new()
var _seg_result: TrackSegmenter.Result
## Index of the start space (display number 1). The red line is its preceding frontier
## (exit of the previous space). Set-start places that line after the selection.
var _start_space_index: int = 0
var _selected_space: int = -1
## space_index -> {speed_limit: int, outside: bool, offset: Vector2}
var _corners: Dictionary = {}
## space_index -> {inside: bool, outside: bool} (geometric loop sides)
var _kerbs: Dictionary = {}
## Spaces-mode drag of a corner speed badge (-1 = none).
var _drag_corner_space: int = -1
## World-space grab delta: mouse - badge center at press.
var _drag_corner_grab := Vector2.ZERO
## "", "move", "scale", "resize", "rotate", "marquee"
var _drag_decor_mode: String = ""
var _drag_decor_start_mouse := Vector2.ZERO
var _drag_decor_pivot := Vector2.ZERO
var _drag_decor_start_dist: float = 1.0
var _drag_decor_start_angle: float = 0.0
## Poignée de resize libre: "nw"|"n"|"ne"|"e"|"se"|"s"|"sw"|"w"
var _drag_decor_handle: String = ""
## Snapshots at drag start: Array[{index:int, item:Dictionary}].
var _drag_decor_snapshots: Array = []
var _decor_marquee_start := Vector2.ZERO
var _decor_marquee_end := Vector2.ZERO
var _decor_marquee_additive: bool = false
## Index into `_compute_sectors()` (-1 = none).
var _selected_sector: int = -1
## flip_key (corner before sector, or -1 if no corners) -> race line on geometric outside.
var _sector_flip_race_line: Dictionary = {}
var _cars_layer: Node2D
var _preview_cars: Array = [] ## Array[CarToken] — one per spot (inner/outer).
## View transform: screen = world * zoom + pan
var _view_pan := Vector2.ZERO
var _view_zoom := 1.0
var _fit_pan := Vector2.ZERO
var _fit_zoom := 1.0
var _panning := false
var _reset_view_btn: Button

func _ready() -> void:
	theme = ThemeBuilder.build()
	_apply_kit_chrome()
	_setup_name_ui()
	_setup_decor_palette()
	_canvas.clip_contents = true
	_ground = TrackGround.attach(_canvas, _ground_theme)
	_setup_reset_view_btn()
	_canvas.draw.connect(_on_canvas_draw)
	_canvas.gui_input.connect(_on_canvas_gui_input)
	_canvas.resized.connect(_on_canvas_resized)
	_canvas.mouse_exited.connect(_on_canvas_mouse_exited)
	%BackButton.pressed.connect(_on_back)
	%SaveButton.pressed.connect(_on_save)
	_setup_mode_ui()
	_setup_type_ui()
	_setup_segmentation_ui()
	_set_start_button.pressed.connect(_on_set_start_pressed)
	_setup_corner_ui()
	_setup_kerb_ui()
	_setup_sector_ui()
	_apply_edit_mode()
	_ensure_preview_cars()
	if _reset_view_btn != null:
		_canvas.move_child(_reset_view_btn, -1)
	# Layout may still report 0-height here — wait for a usable canvas size.
	call_deferred("_try_init_spline")


func _apply_kit_chrome() -> void:
	var bg := get_node_or_null("Background") as ColorRect
	if bg != null:
		bg.color = Palette.ASPHALT
	var title := get_node_or_null("Root/TopBar/Title") as Label
	if title != null:
		title.theme_type_variation = &"TitleLabel"
		title.remove_theme_font_size_override("font_size")
	%BackButton.theme_type_variation = &"Compact"
	%SaveButton.theme_type_variation = &"Primary"
	_builtin_check.visible = SplineTrackFile.can_write_builtin()
	_builtin_check.disabled = not SplineTrackFile.can_write_builtin()
	_ground_theme_option.theme_type_variation = &"Compact"
	_seg_mode_auto.theme_type_variation = &"Compact"
	_seg_mode_fixed.theme_type_variation = &"Compact"
	_mode_trace.theme_type_variation = &"Compact"
	_mode_spaces.theme_type_variation = &"Compact"
	_mode_sectors.theme_type_variation = &"Compact"
	_mode_decor.theme_type_variation = &"Compact"
	_style_decor_palette_button(_decor_select)
	_style_decor_palette_button(_decor_tree)
	_style_decor_palette_button(_decor_rock)
	_style_decor_palette_button(_decor_bleachers)
	_set_start_button.theme_type_variation = &"Compact"
	_set_corner_button.theme_type_variation = &"Compact"
	_corner_side_button.theme_type_variation = &"Compact"
	_sector_race_line_button.theme_type_variation = &"Compact"
	var side := get_node_or_null("Root/MainRow/SidePanel") as PanelContainer
	if side != null:
		side.theme_type_variation = &"Instrument"
	for path in [
		"Root/MainRow/SidePanel/Margin/PanelVBox/NameSection/NameTitle",
		"Root/MainRow/SidePanel/Margin/PanelVBox/DecorSection/GroundTitle",
		"Root/MainRow/SidePanel/Margin/PanelVBox/DecorSection/DecorItemsTitle",
		"Root/MainRow/SidePanel/Margin/PanelVBox/PrioSection/PrioTitle",
		"Root/MainRow/SidePanel/Margin/PanelVBox/EditSection/EditTitle",
	]:
		var section := get_node_or_null(path) as Label
		if section != null:
			section.theme_type_variation = &"Eyebrow"
			section.remove_theme_font_size_override("font_size")
			section.text = section.text.to_upper()
	for path2 in [
		"Root/MainRow/SidePanel/Margin/PanelVBox/SectorsSection/SectorHint",
		"Root/MainRow/SidePanel/Margin/PanelVBox/SummaryLabel",
	]:
		var caption := get_node_or_null(path2) as Label
		if caption != null:
			caption.theme_type_variation = &"Caption"
			caption.remove_theme_color_override("font_color")
			caption.remove_theme_font_size_override("font_size")
	_sector_info_label.theme_type_variation = &"Caption"


func _setup_name_ui() -> void:
	_track_name_edit.text_changed.connect(_on_track_name_changed)
	_builtin_check.toggled.connect(_on_builtin_toggled)
	_ground_theme_option.clear()
	for theme_id in TrackGround.theme_ids():
		_ground_theme_option.add_item(TrackGround.display_name(theme_id))
		_ground_theme_option.set_item_metadata(_ground_theme_option.item_count - 1, theme_id)
	_ground_theme_option.item_selected.connect(_on_ground_theme_selected)
	_sync_track_name_field()
	_sync_ground_theme_field()
	_sync_builtin_check()


func _on_track_name_changed(value: String) -> void:
	if _updating_name_ui:
		return
	_track_name = value.strip_edges()
	_dirty = true
	_refresh_window_title()


func _on_ground_theme_selected(index: int) -> void:
	if _updating_name_ui:
		return
	var theme_id := TrackGround.normalize(str(_ground_theme_option.get_item_metadata(index)))
	if theme_id == _ground_theme:
		return
	_ground_theme = theme_id
	_apply_ground_theme()
	_dirty = true


func _on_builtin_toggled(_pressed: bool) -> void:
	if not SplineTrackFile.can_write_builtin():
		return
	_dirty = true


func _sync_builtin_check() -> void:
	_builtin_check.set_pressed_no_signal(
		SplineTrackFile.can_write_builtin() and SplineTrackFile.is_builtin_path(_file_path)
	)


func _wants_builtin_save() -> bool:
	return SplineTrackFile.can_write_builtin() and _builtin_check.button_pressed


func _sync_track_name_field() -> void:
	_updating_name_ui = true
	_track_name_edit.text = _track_name
	_updating_name_ui = false


func _sync_ground_theme_field() -> void:
	_updating_name_ui = true
	var want := TrackGround.normalize(_ground_theme)
	var selected := 0
	for i in _ground_theme_option.item_count:
		if str(_ground_theme_option.get_item_metadata(i)) == want:
			selected = i
			break
	_ground_theme_option.select(selected)
	_updating_name_ui = false
	_apply_ground_theme()


func _apply_ground_theme() -> void:
	_ground_theme = TrackGround.normalize(_ground_theme)
	if _ground == null:
		_ground = TrackGround.attach(_canvas, _ground_theme)
		return
	var mat := _ground.material as ShaderMaterial
	if mat == null:
		_ground.material = TrackGround.make_material(_ground_theme)
	else:
		TrackGround.apply(mat, _ground_theme)
	_refresh_window_title()


func _style_decor_palette_button(btn: Button) -> void:
	## Sélection = bordure moutarde seulement (pas de fond rempli).
	btn.theme_type_variation = &"Compact"
	var empty := Color(0, 0, 0, 0)
	btn.add_theme_stylebox_override("normal", _decor_swatch_box(empty, Palette.SMOKE))
	btn.add_theme_stylebox_override("hover", _decor_swatch_box(empty, Palette.MUSTARD))
	btn.add_theme_stylebox_override("pressed", _decor_swatch_box(empty, Palette.MUSTARD))
	btn.add_theme_stylebox_override("hover_pressed", _decor_swatch_box(empty, Palette.MUSTARD))
	btn.add_theme_stylebox_override("focus", _decor_swatch_box(empty, Palette.MUSTARD))
	btn.add_theme_color_override("icon_normal_color", Palette.CARDBOARD)
	btn.add_theme_color_override("icon_hover_color", Palette.CARDBOARD)
	btn.add_theme_color_override("icon_pressed_color", Palette.CARDBOARD)


func _decor_swatch_box(fill: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _setup_decor_palette() -> void:
	_decor_select.icon = DECOR_SELECT_ICON
	_decor_select.text = ""
	_decor_tree.text = ""
	_decor_rock.text = ""
	_decor_bleachers.text = ""
	_decor_select.add_theme_constant_override("icon_max_width", 36)
	_decor_tree.add_theme_constant_override("icon_max_width", 36)
	_decor_rock.add_theme_constant_override("icon_max_width", 36)
	_decor_bleachers.add_theme_constant_override("icon_max_width", 36)
	_roll_decor_place_seed(TrackDecor.TYPE_TREE)
	_roll_decor_place_seed(TrackDecor.TYPE_ROCK)
	_roll_decor_place_seed(TrackDecor.TYPE_BLEACHERS)
	_decor_select.pressed.connect(_on_decor_select_pressed)
	_decor_tree.pressed.connect(_on_decor_tree_pressed)
	_decor_rock.pressed.connect(_on_decor_rock_pressed)
	_decor_bleachers.pressed.connect(_on_decor_bleachers_pressed)
	_sync_decor_palette()


func _on_decor_select_pressed() -> void:
	if _updating_decor_ui:
		return
	_set_decor_brush(TrackDecor.TOOL_SELECT)


func _on_decor_tree_pressed() -> void:
	if _updating_decor_ui:
		return
	_activate_decor_place_tool(TrackDecor.TYPE_TREE)


func _on_decor_rock_pressed() -> void:
	if _updating_decor_ui:
		return
	_activate_decor_place_tool(TrackDecor.TYPE_ROCK)


func _on_decor_bleachers_pressed() -> void:
	if _updating_decor_ui:
		return
	_activate_decor_place_tool(TrackDecor.TYPE_BLEACHERS)


func _activate_decor_place_tool(type_id: String) -> void:
	## Premier clic : place le seed déjà affiché sur l'icône.
	## Reclic sur l'outil actif : tire un nouveau seed (icône + fantôme).
	var id := TrackDecor.normalize(type_id)
	var already_active := TrackDecor.normalize_brush(_decor_brush) == id
	_decor_brush = id
	_clear_decor_drag()
	_selected_decors.clear()
	if already_active:
		_roll_decor_place_seed(id)
	else:
		_decor_ghost_seed = int(_decor_place_seeds.get(id, 1))
	_sync_decor_palette()
	_canvas.queue_redraw()


func _set_decor_brush(brush_id: String) -> void:
	_decor_brush = TrackDecor.normalize_brush(brush_id)
	_clear_decor_drag()
	if TrackDecor.is_place_brush(_decor_brush):
		_selected_decors.clear()
		_decor_ghost_seed = int(_decor_place_seeds.get(_decor_brush, 1))
	else:
		_decor_ghost_active = false
	_sync_decor_palette()
	_canvas.queue_redraw()


func _roll_decor_place_seed(type_id: String) -> void:
	var id := TrackDecor.normalize(type_id)
	var seed_v := maxi(1, int(randi()))
	_decor_place_seeds[id] = seed_v
	if TrackDecor.normalize_brush(_decor_brush) == id:
		_decor_ghost_seed = seed_v
	_refresh_decor_place_icon(id)


func _roll_decor_ghost_seed() -> void:
	## Roll the currently active place tool (after pose / mode enter).
	if TrackDecor.is_place_brush(_decor_brush):
		_roll_decor_place_seed(_decor_brush)
	else:
		_decor_ghost_seed = maxi(1, int(randi()))


func _refresh_decor_place_icon(type_id: String) -> void:
	var id := TrackDecor.normalize(type_id)
	var seed_v := int(_decor_place_seeds.get(id, 1))
	var tex := TrackDecor.preview_texture(id, 40, seed_v)
	match id:
		TrackDecor.TYPE_ROCK:
			_decor_rock.icon = tex
		TrackDecor.TYPE_BLEACHERS:
			_decor_bleachers.icon = tex
		_:
			_decor_tree.icon = tex


func _on_canvas_mouse_exited() -> void:
	if not _decor_ghost_active:
		return
	_decor_ghost_active = false
	_canvas.queue_redraw()


func _sync_decor_palette() -> void:
	_updating_decor_ui = true
	_decor_brush = TrackDecor.normalize_brush(_decor_brush)
	_decor_select.set_pressed_no_signal(_decor_brush == TrackDecor.TOOL_SELECT)
	_decor_tree.set_pressed_no_signal(_decor_brush == TrackDecor.TYPE_TREE)
	_decor_rock.set_pressed_no_signal(_decor_brush == TrackDecor.TYPE_ROCK)
	_decor_bleachers.set_pressed_no_signal(_decor_brush == TrackDecor.TYPE_BLEACHERS)
	_updating_decor_ui = false
	if TrackDecor.is_place_brush(_decor_brush):
		_decor_ghost_seed = int(_decor_place_seeds.get(_decor_brush, 1))


func _display_track_name() -> String:
	return _track_name if not _track_name.is_empty() else "Nouvelle piste"


func _refresh_window_title() -> void:
	var title := get_node_or_null("Root/TopBar/Title") as Label
	if title != null:
		title.text = _display_track_name()


func _setup_mode_ui() -> void:
	_mode_trace.toggled.connect(_on_mode_trace_toggled)
	_mode_spaces.toggled.connect(_on_mode_spaces_toggled)
	_mode_sectors.toggled.connect(_on_mode_sectors_toggled)
	_mode_decor.toggled.connect(_on_mode_decor_toggled)
	_sync_mode_buttons()


func _on_mode_trace_toggled(pressed: bool) -> void:
	if _updating_mode_ui or not pressed:
		return
	_set_edit_mode(EditMode.TRACE)


func _on_mode_spaces_toggled(pressed: bool) -> void:
	if _updating_mode_ui or not pressed:
		return
	_set_edit_mode(EditMode.SPACES)


func _on_mode_sectors_toggled(pressed: bool) -> void:
	if _updating_mode_ui or not pressed:
		return
	_set_edit_mode(EditMode.SECTORS)


func _on_mode_decor_toggled(pressed: bool) -> void:
	if _updating_mode_ui or not pressed:
		return
	_set_edit_mode(EditMode.DECOR)


func _sync_mode_buttons() -> void:
	_updating_mode_ui = true
	_mode_trace.button_pressed = _edit_mode == EditMode.TRACE
	_mode_spaces.button_pressed = _edit_mode == EditMode.SPACES
	_mode_sectors.button_pressed = _edit_mode == EditMode.SECTORS
	_mode_decor.button_pressed = _edit_mode == EditMode.DECOR
	_updating_mode_ui = false


func _setup_type_ui() -> void:
	_type_auto.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			_on_type_radio(TrackSpline.PointType.AUTO_SMOOTH)
	)
	_type_tension.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			_on_type_radio(TrackSpline.PointType.TENSION)
	)
	_type_free.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			_on_type_radio(TrackSpline.PointType.FREE)
	)


func _set_edit_mode(mode: int) -> void:
	if _edit_mode == mode:
		return
	_edit_mode = mode
	_drag_mode = ""
	_drag_corner_space = -1
	_clear_decor_drag()
	if mode != EditMode.DECOR:
		_selected_decors.clear()
		_decor_ghost_active = false
	elif TrackDecor.is_place_brush(_decor_brush):
		_decor_ghost_seed = int(_decor_place_seeds.get(_decor_brush, 1))
	_sync_mode_buttons()
	_apply_edit_mode()
	_refresh_info()
	_canvas.queue_redraw()


func _apply_edit_mode() -> void:
	_trace_section.visible = _edit_mode == EditMode.TRACE
	_spaces_section.visible = _edit_mode == EditMode.SPACES
	_sectors_section.visible = _edit_mode == EditMode.SECTORS
	_decor_section.visible = _edit_mode == EditMode.DECOR
	_refresh_set_start_button()
	_refresh_corner_ui()
	_refresh_kerb_ui()
	_refresh_sector_ui()


func _setup_segmentation_ui() -> void:
	_seg_params.road_half_width = ROAD_HALF_WIDTH
	_seg_params.algorithm = TrackSegmenter.Algorithm.INNER_UNIFORM
	_seg_params.car_length = 36.0
	_seg_params.target_space_len = 36.0
	_seg_params.forced_space_count = 0
	_algo_center.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			_on_algo_radio(TrackSegmenter.Algorithm.CENTER_UNIFORM)
	)
	_algo_inner.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			_on_algo_radio(TrackSegmenter.Algorithm.INNER_UNIFORM)
	)
	_algo_adaptive.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			_on_algo_radio(TrackSegmenter.Algorithm.ADAPTIVE_INNER)
	)
	_seg_mode_auto.toggled.connect(_on_seg_mode_auto_toggled)
	_seg_mode_fixed.toggled.connect(_on_seg_mode_fixed_toggled)
	_space_len_slider.min_value = 20.0
	_space_len_slider.max_value = 80.0
	_space_len_slider.step = 1.0
	_space_count_spin.min_value = float(_seg_params.min_spaces)
	_space_count_spin.max_value = float(_seg_params.max_spaces)
	_space_count_spin.step = 1.0
	_space_count_spin.rounded = true
	_updating_seg_ui = true
	_sync_algo_radios()
	_space_len_slider.value = _seg_params.car_length
	_space_count_spin.value = 24.0
	_seg_mode_auto.button_pressed = true
	_updating_seg_ui = false
	_space_len_slider.value_changed.connect(_on_space_len_changed)
	_space_count_spin.value_changed.connect(_on_space_count_changed)
	_refresh_space_len_label()
	_refresh_seg_mode_ui()
	_hide_space_numbers.toggled.connect(func(_pressed: bool) -> void:
		_canvas.queue_redraw()
	)


func _is_seg_mode_fixed() -> bool:
	return _seg_mode_fixed.button_pressed


func _on_seg_mode_auto_toggled(pressed: bool) -> void:
	if _updating_seg_ui or not pressed:
		return
	_seg_params.forced_space_count = 0
	_refresh_seg_mode_ui()
	_recompute_segmentation()
	_refresh_status()
	_refresh_info()
	_canvas.queue_redraw()


func _on_seg_mode_fixed_toggled(pressed: bool) -> void:
	if _updating_seg_ui or not pressed:
		return
	var count := int(_space_count_spin.value)
	if _seg_result != null and _seg_result.space_count() >= _seg_params.min_spaces:
		count = _seg_result.space_count()
		_updating_seg_ui = true
		_space_count_spin.set_value_no_signal(float(count))
		_updating_seg_ui = false
	_seg_params.forced_space_count = clampi(count, _seg_params.min_spaces, _seg_params.max_spaces)
	_refresh_seg_mode_ui()
	_recompute_segmentation()
	_refresh_status()
	_refresh_info()
	_canvas.queue_redraw()


func _on_space_count_changed(value: float) -> void:
	if _updating_seg_ui or not _is_seg_mode_fixed():
		return
	_seg_params.forced_space_count = clampi(
		int(value), _seg_params.min_spaces, _seg_params.max_spaces
	)
	_recompute_segmentation()
	_refresh_status()
	_refresh_info()
	_canvas.queue_redraw()


func _refresh_seg_mode_ui() -> void:
	var fixed := _is_seg_mode_fixed()
	_len_row.visible = not fixed
	_count_row.visible = fixed


func _sync_seg_mode_buttons() -> void:
	var fixed := _seg_params.forced_space_count > 0
	_seg_mode_fixed.button_pressed = fixed
	_seg_mode_auto.button_pressed = not fixed
	if fixed:
		_space_count_spin.set_value_no_signal(float(_seg_params.forced_space_count))


func _setup_corner_ui() -> void:
	_corner_speed_spin.min_value = 1.0
	_corner_speed_spin.max_value = 8.0
	_corner_speed_spin.step = 1.0
	_corner_speed_spin.rounded = true
	_corner_speed_spin.value = 4.0
	_set_corner_button.pressed.connect(_on_set_corner_pressed)
	_corner_speed_spin.value_changed.connect(_on_corner_speed_changed)
	_corner_side_button.pressed.connect(_on_corner_side_pressed)


func _setup_kerb_ui() -> void:
	_kerb_inside_check.toggled.connect(_on_kerb_inside_toggled)
	_kerb_outside_check.toggled.connect(_on_kerb_outside_toggled)


func _make_corner_entry(speed_limit: int) -> Dictionary:
	return {
		"speed_limit": speed_limit,
		"outside": true,
		"offset": Vector2.ZERO,
	}


func _corner_speed(space: int) -> int:
	var entry: Variant = _corners.get(space)
	if entry is Dictionary:
		return int(entry.get("speed_limit", 0))
	return int(entry) if entry != null else 0


func _corner_outside(space: int) -> bool:
	var entry: Variant = _corners.get(space)
	if entry is Dictionary:
		return bool(entry.get("outside", true))
	return true


func _corner_offset(space: int) -> Vector2:
	var entry: Variant = _corners.get(space)
	if entry is Dictionary:
		return entry.get("offset", Vector2.ZERO) as Vector2
	return Vector2.ZERO


func _set_corner_speed(space: int, speed_limit: int) -> void:
	if not _corners.has(space):
		return
	var entry: Dictionary = _corners[space]
	entry["speed_limit"] = speed_limit
	_corners[space] = entry


func _set_corner_side(space: int, outside: bool) -> void:
	if not _corners.has(space):
		return
	var entry: Dictionary = _corners[space]
	entry["outside"] = outside
	entry["offset"] = Vector2.ZERO
	_corners[space] = entry


func _set_corner_offset(space: int, offset: Vector2) -> void:
	if not _corners.has(space):
		return
	var entry: Dictionary = _corners[space]
	entry["offset"] = offset
	_corners[space] = entry


func _on_algo_radio(algorithm: int) -> void:
	if _updating_seg_ui:
		return
	if _seg_params.algorithm == algorithm:
		return
	_seg_params.algorithm = algorithm
	_recompute_segmentation()
	_refresh_status()
	_refresh_info()
	_canvas.queue_redraw()


func _sync_algo_radios() -> void:
	var was := _updating_seg_ui
	_updating_seg_ui = true
	match _seg_params.algorithm:
		TrackSegmenter.Algorithm.CENTER_UNIFORM:
			_algo_center.button_pressed = true
		TrackSegmenter.Algorithm.ADAPTIVE_INNER:
			_algo_adaptive.button_pressed = true
		_:
			_algo_inner.button_pressed = true
	_updating_seg_ui = was


func _on_corner_speed_changed(value: float) -> void:
	if _updating_corner_ui:
		return
	if _selected_space < 0 or not _corners.has(_selected_space):
		return
	_set_corner_speed(_selected_space, int(value))
	_dirty = true
	_refresh_info()
	_canvas.queue_redraw()


func _on_corner_side_pressed() -> void:
	if _updating_corner_ui:
		return
	if _selected_space < 0 or not _corners.has(_selected_space):
		return
	_set_corner_side(_selected_space, not _corner_outside(_selected_space))
	_dirty = true
	_refresh_corner_ui()
	_canvas.queue_redraw()


func _space_kerb_inside(space: int) -> bool:
	var entry: Variant = _kerbs.get(space)
	if entry is Dictionary:
		return bool(entry.get("inside", false))
	return false


func _space_kerb_outside(space: int) -> bool:
	var entry: Variant = _kerbs.get(space)
	if entry is Dictionary:
		return bool(entry.get("outside", false))
	return false


func _set_space_kerb(space: int, inside: bool, outside: bool) -> void:
	if space < 0:
		return
	if not inside and not outside:
		_kerbs.erase(space)
		return
	_kerbs[space] = {"inside": inside, "outside": outside}


func _on_kerb_inside_toggled(pressed: bool) -> void:
	if _updating_kerb_ui:
		return
	if _selected_space < 0:
		return
	_set_space_kerb(_selected_space, pressed, _space_kerb_outside(_selected_space))
	_dirty = true
	_canvas.queue_redraw()


func _on_kerb_outside_toggled(pressed: bool) -> void:
	if _updating_kerb_ui:
		return
	if _selected_space < 0:
		return
	_set_space_kerb(_selected_space, _space_kerb_inside(_selected_space), pressed)
	_dirty = true
	_canvas.queue_redraw()


func _refresh_kerb_ui() -> void:
	if _kerb_details == null:
		return
	var has_sel := (
		_edit_mode == EditMode.SPACES
		and _selected_space >= 0
		and _seg_result != null
	)
	_kerb_details.visible = has_sel
	_updating_kerb_ui = true
	_kerb_inside_check.disabled = not has_sel
	_kerb_outside_check.disabled = not has_sel
	_kerb_inside_check.button_pressed = has_sel and _space_kerb_inside(_selected_space)
	_kerb_outside_check.button_pressed = has_sel and _space_kerb_outside(_selected_space)
	_updating_kerb_ui = false


func _on_canvas_resized() -> void:
	_refresh_fit(false)
	_canvas.queue_redraw()
	_try_init_spline()


func _canvas_ready_for_spline() -> bool:
	return _canvas.size.x >= MIN_CANVAS_SIZE and _canvas.size.y >= MIN_CANVAS_SIZE


func _try_init_spline() -> void:
	if _spline_ready or not _canvas_ready_for_spline():
		return
	var path := SplineTrackFile.editor_pending_path
	SplineTrackFile.editor_pending_path = ""
	if path.is_empty():
		_reset_spline()
		return
	if SplineTrackFile.is_builtin_path(path) and not SplineTrackFile.can_write_builtin():
		_summary.text = "Les pistes intégrées ne sont éditables qu'en debug"
		_reset_spline()
		return
	if not _load_from_path(path):
		_reset_spline()
		_summary.text = "Impossible de charger %s" % path


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_S and (event.ctrl_pressed or event.meta_pressed):
			_on_save()
			get_viewport().set_input_as_handled()
			return
		if (
			_edit_mode == EditMode.DECOR
			and (event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE)
			and _remove_selected_decorations()
		):
			get_viewport().set_input_as_handled()
			return
	if _spline == null or _edit_mode != EditMode.TRACE:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_set_selected_type(TrackSpline.PointType.AUTO_SMOOTH)
				get_viewport().set_input_as_handled()
			KEY_2:
				_set_selected_type(TrackSpline.PointType.TENSION)
				get_viewport().set_input_as_handled()
			KEY_3:
				_set_selected_type(TrackSpline.PointType.FREE)
				get_viewport().set_input_as_handled()


func _on_save() -> void:
	if _spline == null:
		_summary.text = "Rien à enregistrer"
		return
	var wants_builtin := _wants_builtin_save()
	if wants_builtin and not SplineTrackFile.can_write_builtin():
		_summary.text = "Les pistes intégrées ne sont éditables qu'en debug"
		return
	var path := _resolve_save_path(wants_builtin)
	var err := SplineTrackFile.save_document(path, _build_save_document())
	if err != OK:
		_summary.text = "Échec de l'enregistrement"
		return
	_file_path = path
	_dirty = false
	_sync_builtin_check()
	_summary.text = "Enregistré : %s" % path


func _resolve_save_path(wants_builtin: bool) -> String:
	if not _file_path.is_empty():
		var path_is_builtin := SplineTrackFile.is_builtin_path(_file_path)
		if path_is_builtin == wants_builtin:
			return _file_path
	return SplineTrackFile.path_for_name(_display_track_name(), wants_builtin)


func _build_save_document() -> Dictionary:
	var corners_data: Array = []
	for key in _corners.keys():
		var space := int(key)
		var entry: Variant = _corners[key]
		if not entry is Dictionary:
			entry = _make_corner_entry(int(entry))
		var corner: Dictionary = entry
		var offset: Vector2 = corner.get("offset", Vector2.ZERO)
		corners_data.append({
			"space": space,
			"speed_limit": int(corner.get("speed_limit", 0)),
			"outside": bool(corner.get("outside", false)),
			"offset": [offset.x, offset.y],
		})
	corners_data.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("space", 0)) < int(b.get("space", 0))
	)
	var flips_data: Array = []
	for key in _sector_flip_race_line.keys():
		if bool(_sector_flip_race_line.get(key, false)):
			flips_data.append({"key": int(key)})
	flips_data.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("key", 0)) < int(b.get("key", 0))
	)
	var kerbs_data: Array = []
	for key in _kerbs.keys():
		var space := int(key)
		var entry: Variant = _kerbs[key]
		if not entry is Dictionary:
			continue
		var kerb: Dictionary = entry
		var want_in := bool(kerb.get("inside", false))
		var want_out := bool(kerb.get("outside", false))
		if not want_in and not want_out:
			continue
		kerbs_data.append({
			"space": space,
			"inside": want_in,
			"outside": want_out,
		})
	kerbs_data.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("space", 0)) < int(b.get("space", 0))
	)
	return {
		"version": SplineTrackFile.VERSION,
		"name": _track_name,
		"ground_theme": TrackGround.normalize(_ground_theme),
		"spline": _spline.to_dict(),
		"segmentation": {
			"algorithm": int(_seg_params.algorithm),
			"car_length": _seg_params.car_length,
			"target_space_len": _seg_params.target_space_len,
			"forced_space_count": int(_seg_params.forced_space_count),
		},
		"start_space": _start_space_index,
		"corners": corners_data,
		"kerbs": kerbs_data,
		"sector_flip_race_line": flips_data,
		"decorations": TrackDecor.to_document(_decorations),
	}


func _reset_spline() -> void:
	if not _canvas_ready_for_spline():
		_spline_ready = false
		_refresh_summary()
		return
	var center := _canvas.size * 0.5
	var radius := mini(center.x, center.y) * 0.55
	_spline = TrackSpline.make_default_triangle(center, radius)
	_selected = 0
	_selected_space = -1
	_start_space_index = 0
	_corners.clear()
	_kerbs.clear()
	_decorations.clear()
	_selected_decors.clear()
	_clear_decor_drag()
	_drag_corner_space = -1
	_selected_sector = -1
	_sector_flip_race_line.clear()
	_track_name = ""
	_ground_theme = TrackGround.DEFAULT_THEME
	_decor_brush = TrackDecor.TOOL_SELECT
	_file_path = ""
	_seg_params.forced_space_count = 0
	_sync_track_name_field()
	_sync_ground_theme_field()
	_sync_builtin_check()
	_sync_decor_palette()
	_dirty = false
	_spline_ready = true
	_recompute_segmentation()
	_refresh_status()
	_refresh_info()
	_refresh_set_start_button()
	_sync_algo_radios()
	_updating_seg_ui = true
	_space_len_slider.value = _seg_params.car_length
	_sync_seg_mode_buttons()
	_updating_seg_ui = false
	_refresh_space_len_label()
	_refresh_seg_mode_ui()
	_fit_view()
	_canvas.queue_redraw()


func _load_from_path(path: String) -> bool:
	var data := SplineTrackFile.load_document(path)
	if data.is_empty():
		return false
	var spline_data: Variant = data.get("spline", {})
	if not spline_data is Dictionary:
		return false
	var spline := TrackSpline.from_dict(spline_data)
	if spline.point_count() < TrackSpline.MIN_POINTS:
		return false
	_spline = spline
	_file_path = path
	_track_name = str(data.get("name", "")).strip_edges()
	_ground_theme = TrackGround.from_document(data)
	_sync_track_name_field()
	_sync_ground_theme_field()
	_sync_builtin_check()
	var seg: Variant = data.get("segmentation", {})
	if seg is Dictionary:
		_seg_params.algorithm = int(seg.get("algorithm", TrackSegmenter.Algorithm.INNER_UNIFORM))
		_seg_params.car_length = float(seg.get("car_length", 36.0))
		_seg_params.target_space_len = float(seg.get("target_space_len", _seg_params.car_length))
		_seg_params.forced_space_count = int(seg.get("forced_space_count", 0))
	_start_space_index = int(data.get("start_space", 0))
	_selected = 0
	_selected_space = -1
	_drag_corner_space = -1
	_selected_sector = -1
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
	_sector_flip_race_line.clear()
	var flips_data: Variant = data.get("sector_flip_race_line", [])
	if flips_data is Array:
		for item2 in flips_data:
			if item2 is Dictionary:
				_sector_flip_race_line[int(item2.get("key", -1))] = true
			elif item2 != null:
				_sector_flip_race_line[int(item2)] = true
	_decorations = TrackDecor.from_document(data)
	_selected_decors.clear()
	_clear_decor_drag()
	_dirty = false
	_spline_ready = true
	_recompute_segmentation()
	_refresh_status()
	_refresh_info()
	_refresh_set_start_button()
	_sync_algo_radios()
	_updating_seg_ui = true
	_space_len_slider.value = _seg_params.car_length
	_sync_seg_mode_buttons()
	_updating_seg_ui = false
	_refresh_space_len_label()
	_refresh_seg_mode_ui()
	_sync_decor_palette()
	_fit_view()
	_canvas.queue_redraw()
	return true


func _on_back() -> void:
	get_tree().change_scene_to_file("res://ui/spline_track_picker.tscn")


func _on_space_len_changed(value: float) -> void:
	if _updating_seg_ui:
		return
	_seg_params.car_length = value
	_seg_params.target_space_len = value
	_refresh_space_len_label()
	_recompute_segmentation()
	_refresh_status()
	_refresh_info()
	_canvas.queue_redraw()


func _refresh_space_len_label() -> void:
	_space_len_value.text = "%d px" % int(_space_len_slider.value)


func _recompute_segmentation() -> void:
	if _spline == null:
		_seg_result = null
		_refresh_summary()
		return
	_seg_params.road_half_width = ROAD_HALF_WIDTH
	_seg_result = TrackSegmenter.segment(_spline, _seg_params)
	_clamp_space_indices()
	_refresh_summary()


func _clamp_space_indices() -> void:
	if _seg_result == null or _seg_result.space_count() == 0:
		_start_space_index = 0
		_selected_space = -1
		_corners.clear()
		_kerbs.clear()
		_selected_sector = -1
		return
	var n := _seg_result.space_count()
	_start_space_index = posmod(_start_space_index, n)
	if _selected_space >= n:
		_selected_space = -1
	var kept: Dictionary = {}
	for key in _corners.keys():
		var idx := int(key)
		if idx >= 0 and idx < n:
			var entry: Variant = _corners[key]
			if entry is Dictionary:
				kept[idx] = entry
			else:
				kept[idx] = _make_corner_entry(int(entry))
	_corners = kept
	var kept_kerbs: Dictionary = {}
	for k_key in _kerbs.keys():
		var k_idx := int(k_key)
		if k_idx < 0 or k_idx >= n:
			continue
		var k_entry: Variant = _kerbs[k_key]
		if not k_entry is Dictionary:
			continue
		var want_in := bool(k_entry.get("inside", false))
		var want_out := bool(k_entry.get("outside", false))
		if want_in or want_out:
			kept_kerbs[k_idx] = {"inside": want_in, "outside": want_out}
	_kerbs = kept_kerbs
	_prune_sector_flips()
	_clamp_selected_sector()


## Corner spaces in ascending track index (closed-loop order).
func _corners_in_track_order() -> Array[int]:
	var ordered: Array[int] = []
	for key in _corners.keys():
		ordered.append(int(key))
	ordered.sort()
	return ordered


## Sectors = stretches between consecutive corners (may wrap past the start line).
## Each entry: {from: int, to: int} inclusive — from the space after a corner
## through the next corner space.
func _compute_sectors() -> Array:
	var out: Array = []
	if _seg_result == null:
		return out
	var n := _seg_result.space_count()
	if n < 1:
		return out
	var corners := _corners_in_track_order()
	if corners.is_empty():
		out.append({
			"from": _start_space_index,
			"to": posmod(_start_space_index - 1, n),
		})
		return out
	for i in corners.size():
		var prev_corner := corners[i]
		var next_corner := corners[(i + 1) % corners.size()]
		out.append({
			"from": posmod(prev_corner + 1, n),
			"to": next_corner,
		})
	return out


func _sector_space_count(sector: Dictionary) -> int:
	if _seg_result == null:
		return 0
	var n := _seg_result.space_count()
	return posmod(int(sector.to) - int(sector.from), n) + 1


func _space_in_sector(space: int, sector: Dictionary) -> bool:
	if _seg_result == null:
		return false
	var n := _seg_result.space_count()
	return posmod(space - int(sector.from), n) <= posmod(int(sector.to) - int(sector.from), n)


func _sector_index_at_space(space: int) -> int:
	var sectors := _compute_sectors()
	for i in sectors.size():
		if _space_in_sector(space, sectors[i]):
			return i
	return -1


## Stable key for a sector's race-line flip: corner exited into the sector (-1 if none).
func _sector_flip_key(sector: Dictionary) -> int:
	if _corners.is_empty() or _seg_result == null:
		return -1
	var n := _seg_result.space_count()
	return posmod(int(sector.from) - 1, n)


func _sector_race_line_flipped(sector: Dictionary) -> bool:
	return bool(_sector_flip_race_line.get(_sector_flip_key(sector), false))


func _space_race_line_flipped(space: int) -> bool:
	var idx := _sector_index_at_space(space)
	if idx < 0:
		return false
	var sectors := _compute_sectors()
	if idx >= sectors.size():
		return false
	return _sector_race_line_flipped(sectors[idx])


func _prune_sector_flips() -> void:
	var kept: Dictionary = {}
	if _corners.is_empty():
		if _sector_flip_race_line.get(-1, false):
			kept[-1] = true
	else:
		for key in _corners.keys():
			var corner := int(key)
			if _sector_flip_race_line.get(corner, false):
				kept[corner] = true
	_sector_flip_race_line = kept


func _setup_sector_ui() -> void:
	_sector_race_line_button.pressed.connect(_on_sector_race_line_pressed)


func _on_sector_race_line_pressed() -> void:
	var sectors := _compute_sectors()
	if _selected_sector < 0 or _selected_sector >= sectors.size():
		return
	var key := _sector_flip_key(sectors[_selected_sector])
	_sector_flip_race_line[key] = not bool(_sector_flip_race_line.get(key, false))
	if not _sector_flip_race_line[key]:
		_sector_flip_race_line.erase(key)
	_dirty = true
	_refresh_sector_ui()
	_canvas.queue_redraw()


func _refresh_sector_ui() -> void:
	if _sector_info_label == null:
		return
	var sectors := _compute_sectors()
	var has_sel := _selected_sector >= 0 and _selected_sector < sectors.size()
	_sector_race_line_button.disabled = not has_sel
	if not has_sel:
		_sector_info_label.text = (
			"Aucun secteur sélectionné"
			if sectors.is_empty()
			else "%d secteurs — clique une case" % sectors.size()
		)
		_sector_race_line_button.text = "Ligne de course : intérieure"
		return
	var sector: Dictionary = sectors[_selected_sector]
	var count := _sector_space_count(sector)
	var from_disp := _display_space_number(int(sector.from))
	var to_disp := _display_space_number(int(sector.to))
	_sector_info_label.text = "Secteur %d / %d — cases %d→%d (%d)" % [
		_selected_sector + 1,
		sectors.size(),
		from_disp,
		to_disp,
		count,
	]
	var flipped := _sector_race_line_flipped(sector)
	_sector_race_line_button.text = (
		"Ligne de course : extérieure" if flipped else "Ligne de course : intérieure"
	)


func _on_set_start_pressed() -> void:
	if _selected_space < 0 or _seg_result == null or _seg_result.space_count() == 0:
		return
	# Start line sits on the exit of the selected space; display #1 is the next space.
	_start_space_index = posmod(_selected_space + 1, _seg_result.space_count())
	_dirty = true
	_clamp_selected_sector()
	_refresh_info()
	_refresh_set_start_button()
	_canvas.queue_redraw()


func _refresh_set_start_button() -> void:
	if _set_start_button == null:
		return
	var line_after_selected := (
		_selected_space >= 0
		and _seg_result != null
		and _seg_result.space_count() > 0
		and _start_space_index == posmod(_selected_space + 1, _seg_result.space_count())
	)
	var can_set := (
		_edit_mode == EditMode.SPACES
		and _selected_space >= 0
		and _seg_result != null
		and not line_after_selected
	)
	_set_start_button.disabled = not can_set
	if line_after_selected:
		_set_start_button.text = "Départ ✓"
	else:
		_set_start_button.text = "Définir comme case départ"


func _on_set_corner_pressed() -> void:
	if _selected_space < 0 or _seg_result == null:
		return
	if _corners.has(_selected_space):
		_corners.erase(_selected_space)
		if _drag_corner_space == _selected_space:
			_drag_corner_space = -1
	else:
		_corners[_selected_space] = _make_corner_entry(int(_corner_speed_spin.value))
	_dirty = true
	_prune_sector_flips()
	_clamp_selected_sector()
	_refresh_info()
	_refresh_corner_ui()
	_canvas.queue_redraw()


func _clamp_selected_sector() -> void:
	var sector_count := _compute_sectors().size()
	if _selected_sector >= sector_count:
		_selected_sector = -1


func _refresh_corner_ui() -> void:
	if _set_corner_button == null:
		return
	var has_sel := (
		_edit_mode == EditMode.SPACES
		and _selected_space >= 0
		and _seg_result != null
	)
	var has_corner := has_sel and _corners.has(_selected_space)
	_set_corner_button.disabled = not has_sel
	_corner_details.visible = has_corner
	_corner_speed_spin.editable = has_corner
	_corner_side_button.disabled = not has_corner
	if has_corner:
		_set_corner_button.text = "Retirer virage"
		_updating_corner_ui = true
		_corner_speed_spin.value = _corner_speed(_selected_space)
		_updating_corner_ui = false
		_corner_side_button.text = (
			"Extérieur" if _corner_outside(_selected_space) else "Intérieur"
		)
	else:
		_set_corner_button.text = "Ajouter virage"
		_corner_side_button.text = "Extérieur"


func _on_type_radio(type: int) -> void:
	if _updating_type_ui or _spline == null:
		return
	_set_selected_type(type)


func _set_selected_type(type: int) -> void:
	if _spline == null or _spline.point_count() == 0:
		return
	var cp := _spline.get_point(_selected)
	if cp.type == type:
		_sync_type_radios()
		return
	_spline.set_point_type(_selected, type)
	_dirty = true
	_refresh_status()
	_refresh_info()
	_canvas.queue_redraw()


func _sync_type_radios() -> void:
	if _spline == null or _spline.point_count() == 0:
		return
	_updating_type_ui = true
	match _spline.get_point(_selected).type:
		TrackSpline.PointType.TENSION:
			_type_tension.button_pressed = true
		TrackSpline.PointType.FREE:
			_type_free.button_pressed = true
		_:
			_type_auto.button_pressed = true
	_updating_type_ui = false


func _refresh_summary() -> void:
	var spaces := 0 if _seg_result == null else _seg_result.space_count()
	var sectors := _compute_sectors().size()
	_summary.text = "%d cases · %d virages · %d secteurs" % [spaces, _corners.size(), sectors]


func _refresh_status() -> void:
	_refresh_summary()


func _refresh_info() -> void:
	if _edit_mode == EditMode.SPACES:
		_refresh_set_start_button()
		_refresh_corner_ui()
		_refresh_kerb_ui()
		_refresh_summary()
		return
	if _edit_mode == EditMode.SECTORS:
		_refresh_sector_ui()
		_refresh_summary()
		return
	if _edit_mode == EditMode.DECOR:
		_refresh_summary()
		return
	if _spline == null or _spline.point_count() == 0:
		_refresh_summary()
		return
	_selected = clampi(_selected, 0, _spline.point_count() - 1)
	_sync_type_radios()
	_refresh_summary()


func _ink() -> CanvasItem:
	return _draw_target if _draw_target != null else _canvas


func _on_canvas_draw() -> void:
	if _spline == null:
		return
	_recompute_segmentation()
	var font := ThemeDB.fallback_font

	_apply_view_to_cars()
	# Transform points in the painter (screen space), don't scale the canvas:
	# canvas scale also stretches AA feathers and makes strokes soft when zoomed.
	var xform := _compose_view_xform()

	var baked := _spline.baked_points()
	if baked.size() >= 2:
		_draw_track(baked, font, xform)
	elif _edit_mode == EditMode.TRACE:
		_draw_control_points(font, xform)


func _compose_view_xform() -> Transform2D:
	TrackGround.set_view(_canvas, _view_pan, _view_zoom)
	return Transform2D(0.0, Vector2(_view_zoom, _view_zoom), 0.0, _view_pan)


func _screen_to_world(screen: Vector2) -> Vector2:
	return (screen - _view_pan) / _view_zoom


func _hit_radius(screen_radius: float) -> float:
	return screen_radius / _view_zoom


func _apply_view_to_cars() -> void:
	if _cars_layer == null:
		return
	_cars_layer.position = _view_pan
	_cars_layer.scale = Vector2(_view_zoom, _view_zoom)


func _setup_reset_view_btn() -> void:
	_reset_view_btn = Button.new()
	_reset_view_btn.name = "ResetView"
	_reset_view_btn.text = ""
	_reset_view_btn.icon = RESET_VIEW_ICON
	_reset_view_btn.expand_icon = true
	_reset_view_btn.theme_type_variation = &"Compact"
	_reset_view_btn.focus_mode = Control.FOCUS_NONE
	_reset_view_btn.visible = false
	_reset_view_btn.tooltip_text = "Recadrer"
	_reset_view_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_reset_view_btn.offset_left = -48.0
	_reset_view_btn.offset_top = 8.0
	_reset_view_btn.offset_right = -8.0
	_reset_view_btn.offset_bottom = 48.0
	_reset_view_btn.custom_minimum_size = Vector2(40, 40)
	_reset_view_btn.z_index = TrackGround.VIEW_UI_Z
	_reset_view_btn.pressed.connect(reset_view)
	_canvas.add_child(_reset_view_btn)
	_reset_view_btn.add_theme_constant_override("icon_max_width", 28)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := _reset_view_btn.get_theme_stylebox(state)
		if sb is StyleBoxFlat:
			var tight := (sb as StyleBoxFlat).duplicate() as StyleBoxFlat
			tight.content_margin_left = 6
			tight.content_margin_right = 6
			tight.content_margin_top = 6
			tight.content_margin_bottom = 6
			_reset_view_btn.add_theme_stylebox_override(state, tight)


func reset_view() -> void:
	_fit_view()
	_apply_view_to_cars()
	_canvas.queue_redraw()


func _fit_view() -> void:
	_refresh_fit(true)


## Update stored fit framing. If `force` or the view was already at fit, apply it.
func _refresh_fit(force: bool) -> void:
	if _spline == null or not _canvas_ready_for_spline():
		_update_reset_view_btn()
		return
	var baked := _spline.baked_points()
	if baked.size() < 2:
		_update_reset_view_btn()
		return
	var world := SplineTrackPainter.bounds(baked, ROAD_HALF_WIDTH)
	var fit := SplineTrackPainter.fit_transform(world, Rect2(Vector2.ZERO, _canvas.size), FIT_MARGIN)
	var was_default := _is_default_view()
	_fit_pan = fit.origin
	_fit_zoom = absf(fit.get_scale().x)
	if force or was_default or not _has_valid_view():
		_view_pan = _fit_pan
		_view_zoom = _fit_zoom
		_apply_view_to_cars()
	_update_reset_view_btn()


func _has_valid_view() -> bool:
	return _view_zoom > 0.0 and is_finite(_view_zoom)


func _is_default_view() -> bool:
	if not _has_valid_view():
		return true
	return is_equal_approx(_view_zoom, _fit_zoom) and _view_pan.is_equal_approx(_fit_pan)


func _update_reset_view_btn() -> void:
	if _reset_view_btn == null:
		return
	_reset_view_btn.visible = _spline != null and not _is_default_view()


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var new_zoom := clampf(_view_zoom * factor, MIN_VIEW_ZOOM, MAX_VIEW_ZOOM)
	if is_equal_approx(new_zoom, _view_zoom):
		return
	_view_pan = screen_pos - (screen_pos - _view_pan) * (new_zoom / _view_zoom)
	_view_zoom = new_zoom
	_apply_view_to_cars()
	TrackGround.set_view(_canvas, _view_pan, _view_zoom)
	_update_reset_view_btn()
	_canvas.queue_redraw()


## Shared view navigation (pan / zoom). Returns true if the event was consumed.
func _handle_view_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
			_canvas.accept_event()
			return true
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			if mb.ctrl_pressed:
				_nudge_tension(0.05)
			else:
				_zoom_at(mb.position, VIEW_ZOOM_STEP)
			_canvas.accept_event()
			return true
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			if mb.ctrl_pressed:
				_nudge_tension(-0.05)
			else:
				_zoom_at(mb.position, 1.0 / VIEW_ZOOM_STEP)
			_canvas.accept_event()
			return true
	elif event is InputEventMouseMotion and _panning:
		var mm := event as InputEventMouseMotion
		_view_pan += mm.relative
		_apply_view_to_cars()
		_update_reset_view_btn()
		SplineTrackPainter.set_view_pan(_canvas, _view_pan)
		TrackGround.set_view(_canvas, _view_pan, _view_zoom)
		_canvas.accept_event()
		return true
	return false


func _ensure_preview_cars() -> void:
	if _cars_layer == null:
		_cars_layer = Node2D.new()
		_cars_layer.name = "PreviewCars"
		_cars_layer.z_index = 10
		_canvas.add_child(_cars_layer)
		_apply_view_to_cars()
		if _reset_view_btn != null:
			_canvas.move_child(_reset_view_btn, -1)
	while _preview_cars.size() < 2:
		var car := CAR_SCENE.instantiate() as CarToken
		_cars_layer.add_child(car)
		car.setup(_preview_cars.size())
		_preview_cars.append(car)


func _sync_preview_cars() -> void:
	_ensure_preview_cars()
	var space := -1
	if _seg_result != null and _seg_result.space_count() >= 2:
		if _edit_mode == EditMode.SPACES and _selected_space >= 0:
			space = _selected_space
		elif _edit_mode == EditMode.SECTORS and _selected_sector >= 0:
			var sectors := _compute_sectors()
			if _selected_sector < sectors.size():
				# Mid-sector space so the race-line flip is obvious while editing.
				var sector: Dictionary = sectors[_selected_sector]
				var count := _sector_space_count(sector)
				var n := _seg_result.space_count()
				space = posmod(int(sector.from) + int(count / 2), n)
	var show := space >= 0
	_cars_layer.visible = show
	if not show:
		return
	var poses := _space_slot_poses(space)
	for i in mini(2, poses.size()):
		var car: CarToken = _preview_cars[i]
		var pose: Dictionary = poses[i]
		car.set_pose(pose.pos, pose.heading)
		car.visible = true


## Mid-space poses for spot 0 (race line) and spot 1 (outer).
## Outer is nudged rearward so the two cars don't sit side-by-side flush.
## A flipped sector swaps which geometric side is the race line.
func _space_slot_poses(space_index: int) -> Array:
	# Temporary play-index identity: editor works in geometric indices.
	var bind := SplineTrackBind.new()
	bind.seg = _seg_result
	bind.seg_params = _seg_params
	bind.half_width = ROAD_HALF_WIDTH
	bind.spot_inset = _seg_params.spot_inset
	bind.start_space = 0
	bind.corners = _corners
	bind.sector_flip_race_line = _sector_flip_race_line
	return bind.space_slot_poses(space_index)


func _paint_context(font: Font) -> SplineTrackPainter.Context:
	var ctx := SplineTrackPainter.Context.new()
	ctx.half_width = ROAD_HALF_WIDTH
	ctx.spot_inset = _seg_params.spot_inset
	ctx.seg = _seg_result
	ctx.start_space = _start_space_index
	ctx.corners = _corners
	ctx.kerbs = _kerbs
	ctx.race_line_flipped = _space_race_line_flipped
	ctx.font = font
	return ctx


func _draw_track(baked: PackedVector2Array, font: Font, xform: Transform2D) -> void:
	var ctx := _paint_context(font)
	var opts := SplineTrackPainter.editor_roadmap_options(_hide_space_numbers.button_pressed)
	var zoom_xform := Transform2D(0.0, Vector2(_view_zoom, _view_zoom), 0.0, Vector2.ZERO)
	var after_asphalt := func(c: CanvasItem) -> void:
		_draw_target = c
		_draw_selection_fills(zoom_xform)
		_draw_target = null
	var after_road := func(c: CanvasItem) -> void:
		_draw_target = c
		TrackDecor.draw(c, _decorations, zoom_xform)
		_draw_decor_ghost(zoom_xform)
		_draw_decor_selection(zoom_xform)
		if _edit_mode == EditMode.TRACE:
			_draw_control_points(font, zoom_xform)
		_draw_target = null
	SplineTrackPainter.draw(_canvas, baked, ctx, opts, xform, after_asphalt, after_road)
	_sync_preview_cars()


func _draw_decor_ghost(xform: Transform2D) -> void:
	if _edit_mode != EditMode.DECOR:
		return
	if not TrackDecor.is_place_brush(_decor_brush) or not _decor_ghost_active:
		return
	var ghost := TrackDecor.make_item(_decor_brush, _decor_ghost_pos, _decor_ghost_seed)
	TrackDecor.draw_item(_ink(), ghost, xform, 0.45)


func _draw_decor_selection(xform: Transform2D) -> void:
	if _edit_mode != EditMode.DECOR:
		return
	_prune_decor_selection()
	if _drag_decor_mode == "marquee":
		_draw_decor_marquee(xform)
	if _selected_decors.is_empty():
		return
	var frame := Color(0.95, 0.85, 0.2, 0.95)
	var z := absf(xform.get_scale().x)
	var line_w := maxf(1.5, 2.0 * z)
	var handle_r := maxf(4.0, 5.0 * z)
	for idx_v in _selected_decors:
		var idx := int(idx_v)
		var item := TrackDecor.parse_item(_decorations[idx])
		if item.is_empty():
			continue
		_draw_decor_item_frame(item, xform, frame, line_w)
	if _selected_decors.size() == 1:
		var only := TrackDecor.parse_item(_decorations[int(_selected_decors[0])])
		_draw_decor_oriented_handles(only, xform, frame, line_w, handle_r)
	else:
		_draw_decor_group_handles(xform, frame, line_w, handle_r)


func _draw_decor_marquee(xform: Transform2D) -> void:
	var a: Vector2 = xform * _decor_marquee_start
	var b: Vector2 = xform * _decor_marquee_end
	var rect := Rect2(a, Vector2.ZERO).expand(b)
	var fill := Color(0.5, 0.78, 1.0, 0.12)
	var edge := Color(0.5, 0.78, 1.0, 0.85)
	var z := absf(xform.get_scale().x)
	_ink().draw_rect(rect, fill, true)
	_ink().draw_rect(rect, edge, false, maxf(1.0, 1.5 * z), true)


func _draw_decor_item_frame(item: Dictionary, xform: Transform2D, frame: Color, line_w: float) -> void:
	var corners := TrackDecor.selection_corners(item)
	if corners.size() < 4:
		return
	var loop := PackedVector2Array()
	for c in corners:
		loop.append(xform * c)
	loop.append(loop[0])
	_ink().draw_polyline(loop, frame, line_w, true)


func _draw_decor_oriented_handles(
	item: Dictionary, xform: Transform2D, frame: Color, line_w: float, handle_r: float
) -> void:
	if item.is_empty():
		return
	var corners := TrackDecor.selection_corners(item)
	if corners.size() < 4:
		return
	for c2 in corners:
		var p: Vector2 = xform * c2
		_ink().draw_rect(
			Rect2(p - Vector2(handle_r, handle_r), Vector2(handle_r, handle_r) * 2.0),
			frame,
			true
		)
	if TrackDecor.uses_free_size(str(item.type)):
		var edge_r := handle_r * 0.85
		for mid in TrackDecor.selection_edge_mids(item):
			var ep: Vector2 = xform * mid
			_ink().draw_rect(
				Rect2(ep - Vector2(edge_r, edge_r), Vector2(edge_r, edge_r) * 2.0),
				frame,
				true
			)
	var rot_world := TrackDecor.rotate_handle_world(item)
	var rot_screen: Vector2 = xform * rot_world
	var top_mid: Vector2 = xform * corners[0].lerp(corners[1], 0.5)
	_ink().draw_line(top_mid, rot_screen, frame, line_w, true)
	_ink().draw_circle(rot_screen, handle_r * 1.15, frame, true, -1.0, true)
	_ink().draw_arc(
		rot_screen,
		handle_r * 0.7,
		-PI * 0.75,
		PI * 0.75,
		16,
		Palette.INK,
		maxf(1.0, 1.5 * absf(xform.get_scale().x)),
		true
	)


func _draw_decor_group_handles(xform: Transform2D, frame: Color, line_w: float, handle_r: float) -> void:
	var aabb := _decor_selection_aabb()
	if aabb.size.x <= 0.0 or aabb.size.y <= 0.0:
		return
	var corners := _aabb_corners(aabb)
	var loop := PackedVector2Array()
	for c in corners:
		loop.append(xform * c)
	loop.append(loop[0])
	_ink().draw_polyline(loop, frame, line_w, true)
	for c2 in corners:
		var p: Vector2 = xform * c2
		_ink().draw_rect(
			Rect2(p - Vector2(handle_r, handle_r), Vector2(handle_r, handle_r) * 2.0),
			frame,
			true
		)
	var rot_world := _decor_group_rotate_handle(aabb)
	var rot_screen: Vector2 = xform * rot_world
	var top_mid: Vector2 = xform * corners[0].lerp(corners[1], 0.5)
	_ink().draw_line(top_mid, rot_screen, frame, line_w, true)
	_ink().draw_circle(rot_screen, handle_r * 1.15, frame, true, -1.0, true)
	_ink().draw_arc(
		rot_screen,
		handle_r * 0.7,
		-PI * 0.75,
		PI * 0.75,
		16,
		Palette.INK,
		maxf(1.0, 1.5 * absf(xform.get_scale().x)),
		true
	)


func _draw_selection_fills(xform: Transform2D) -> void:
	if _seg_result == null or _seg_result.space_count() < 2:
		return
	if _edit_mode == EditMode.SPACES and _selected_space >= 0:
		_draw_space_fill(_selected_space, SPACE_SELECTED_COLOR, xform)
	elif _edit_mode == EditMode.SECTORS and _selected_sector >= 0:
		_draw_selected_sector_highlight(xform)


func _draw_control_points(font: Font, xform: Transform2D) -> void:
	var z := maxf(absf(xform.get_scale().x), 0.0001)
	for i in _spline.point_count():
		var cp := _spline.get_point(i)
		var selected := i == _selected
		var pos := xform * cp.position
		if selected and cp.type != TrackSpline.PointType.AUTO_SMOOTH:
			var in_h := xform * _spline.in_handle_world(i)
			var out_h := xform * _spline.out_handle_world(i)
			var out_col := Color(0.35, 0.75, 1.0, 0.9)
			var in_col := Color(0.75, 0.45, 1.0, 0.9) if cp.type == TrackSpline.PointType.FREE else out_col
			_ink().draw_line(pos, out_h, out_col, 1.5 * z, true)
			_ink().draw_line(pos, in_h, in_col, 1.5 * z, true)
			var in_r := (6.0 if cp.type == TrackSpline.PointType.FREE else 3.5) * z
			_ink().draw_circle(out_h, 6.0 * z, out_col, true, -1.0, true)
			_ink().draw_circle(in_h, in_r, in_col, true, -1.0, true)

		var fill := _point_fill_color(cp.type, selected)
		var radius := (10.0 if selected else 8.0) * z
		_ink().draw_circle(pos, radius, fill, true, -1.0, true)
		_ink().draw_arc(pos, radius, 0.0, TAU, 24, Color.WHITE if selected else Color(0, 0, 0, 0.7), 2.0 * z, true)
		_ink().draw_string(
			font,
			pos + Vector2(12, -8) * z,
			"%d %s" % [i + 1, _type_letter(cp.type)],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			maxi(1, int(round(13.0 * z))),
			Color(1, 1, 1, 0.85)
		)


func _draw_selected_sector_highlight(xform: Transform2D) -> void:
	var sectors := _compute_sectors()
	if _selected_sector < 0 or _selected_sector >= sectors.size():
		return
	var sector: Dictionary = sectors[_selected_sector]
	var n := _seg_result.space_count()
	var space := int(sector.from)
	while true:
		_draw_space_fill(space, SECTOR_SELECTED_COLOR, xform)
		if space == int(sector.to):
			break
		space = posmod(space + 1, n)


## Fills one space with triangles clamped to its frontiers (no round-cap bleed).
func _draw_space_fill(space: int, color: Color, xform: Transform2D) -> void:
	var quads: Array = _seg_result.space_fill_quads(space, ROAD_HALF_WIDTH)
	for q in quads:
		var p: PackedVector2Array = q
		if p.size() < 4:
			continue
		_draw_fill_tri(p[0], p[1], p[2], color, xform)
		_draw_fill_tri(p[0], p[2], p[3], color, xform)


func _draw_fill_tri(a: Vector2, b: Vector2, c: Vector2, color: Color, xform: Transform2D) -> void:
	# Skip collapsed slivers that Godot may refuse to fill (area in world space).
	var area2 := absf((b - a).cross(c - a))
	if area2 < 0.05:
		return
	_ink().draw_colored_polygon(PackedVector2Array([xform * a, xform * b, xform * c]), color)


func _corner_badge_natural(frontier: TrackSegmenter.Frontier, outside: bool) -> Vector2:
	return SplineTrackPainter.corner_badge_natural(frontier, outside, ROAD_HALF_WIDTH)


func _corner_badge_center(space: int, frontier: Variant = null) -> Vector2:
	return SplineTrackPainter.corner_badge_center(_paint_context(ThemeDB.fallback_font), space, frontier)


func _display_space_number(space_index: int) -> int:
	return SplineTrackPainter.display_space_number(_paint_context(ThemeDB.fallback_font), space_index)


func _point_fill_color(type: int, selected: bool) -> Color:
	match type:
		TrackSpline.PointType.AUTO_SMOOTH:
			return Color(0.45, 0.7, 0.95) if selected else Color(0.55, 0.65, 0.75)
		TrackSpline.PointType.FREE:
			return Color(0.95, 0.55, 0.25) if selected else Color(0.85, 0.7, 0.45)
		_:
			return Color(1.0, 0.35, 0.3) if selected else Color(0.9, 0.9, 0.95)


func _type_letter(type: int) -> String:
	match type:
		TrackSpline.PointType.AUTO_SMOOTH:
			return "A"
		TrackSpline.PointType.FREE:
			return "L"
		_:
			return "T"


func _on_canvas_gui_input(event: InputEvent) -> void:
	if _spline == null:
		return
	if _handle_view_input(event):
		return
	if _edit_mode == EditMode.SPACES:
		_on_spaces_gui_input(event)
		return
	if _edit_mode == EditMode.SECTORS:
		_on_sectors_gui_input(event)
		return
	if _edit_mode == EditMode.DECOR:
		_on_decor_gui_input(event)
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var world := _screen_to_world(mb.position)
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if mb.double_click and _try_cycle_type_at(world):
					pass
				else:
					_begin_left(world)
			else:
				_drag_mode = ""
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_try_remove_at(world)
	elif event is InputEventMouseMotion and _drag_mode != "":
		_continue_drag(_screen_to_world((event as InputEventMouseMotion).position))


func _on_decor_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var world_motion := _screen_to_world(motion.position)
		if TrackDecor.is_place_brush(_decor_brush):
			_decor_ghost_pos = world_motion
			_decor_ghost_active = true
			_canvas.queue_redraw()
		elif _drag_decor_mode == "marquee":
			_decor_marquee_end = world_motion
			_canvas.queue_redraw()
			_canvas.accept_event()
		elif _drag_decor_mode != "" and not _drag_decor_snapshots.is_empty():
			_continue_decor_drag(world_motion)
			_canvas.accept_event()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var world := _screen_to_world(mb.position)
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_clear_decor_drag()
			var hit := TrackDecor.hit_index(_decorations, world)
			if hit < 0:
				return
			_remove_decoration_at(hit)
			_canvas.accept_event()
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			if _decor_brush == TrackDecor.TOOL_SELECT:
				_on_decor_select_press(world, mb.position, mb.shift_pressed)
			else:
				_on_decor_place_press(world)
			_canvas.accept_event()
		else:
			if _drag_decor_mode == "marquee":
				_finish_decor_marquee()
			elif _drag_decor_mode != "":
				_dirty = true
			_clear_decor_drag()
			_canvas.queue_redraw()
		return


func _clear_decor_drag() -> void:
	_drag_decor_mode = ""
	_drag_decor_handle = ""
	_drag_decor_snapshots.clear()


func _prune_decor_selection() -> void:
	var kept: Array = []
	for idx_v in _selected_decors:
		var idx := int(idx_v)
		if idx >= 0 and idx < _decorations.size():
			kept.append(idx)
	_selected_decors = kept


func _is_decor_selected(index: int) -> bool:
	return _selected_decors.has(index)


func _toggle_decor_selected(index: int) -> void:
	if _is_decor_selected(index):
		_selected_decors.erase(index)
	else:
		_selected_decors.append(index)


func _set_decor_selection(indices: Array) -> void:
	_selected_decors.clear()
	for idx_v in indices:
		var idx := int(idx_v)
		if idx >= 0 and idx < _decorations.size() and not _selected_decors.has(idx):
			_selected_decors.append(idx)


func _aabb_corners(aabb: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		aabb.position,
		Vector2(aabb.end.x, aabb.position.y),
		aabb.end,
		Vector2(aabb.position.x, aabb.end.y),
	])


func _decor_selection_aabb() -> Rect2:
	_prune_decor_selection()
	var has_any := false
	var aabb := Rect2()
	for idx_v in _selected_decors:
		var item := TrackDecor.parse_item(_decorations[int(idx_v)])
		if item.is_empty():
			continue
		for corner in TrackDecor.selection_corners(item):
			if not has_any:
				aabb = Rect2(corner, Vector2.ZERO)
				has_any = true
			else:
				aabb = aabb.expand(corner)
	return aabb


func _decor_group_rotate_handle(aabb: Rect2) -> Vector2:
	var top_mid := Vector2(aabb.get_center().x, aabb.position.y)
	return top_mid + Vector2(0.0, -TrackDecor.ROTATE_HANDLE_GAP)


func _decor_handle_at_screen(screen: Vector2) -> String:
	_prune_decor_selection()
	if _selected_decors.is_empty():
		return ""
	var view := _compose_view_xform()
	var thresh := 12.0
	if _selected_decors.size() == 1:
		var item := TrackDecor.parse_item(_decorations[int(_selected_decors[0])])
		if item.is_empty():
			return ""
		var rot_s: Vector2 = view * TrackDecor.rotate_handle_world(item)
		if screen.distance_to(rot_s) <= thresh:
			return "rotate"
		var corners := TrackDecor.selection_corners(item)
		var corner_ids := ["nw", "ne", "se", "sw"]
		for i in mini(corners.size(), corner_ids.size()):
			if screen.distance_to(view * corners[i]) <= thresh:
				if TrackDecor.uses_free_size(str(item.type)):
					return "resize:%s" % corner_ids[i]
				return "scale"
		if TrackDecor.uses_free_size(str(item.type)):
			var edge_ids := ["n", "e", "s", "w"]
			var mids := TrackDecor.selection_edge_mids(item)
			for j in mini(mids.size(), edge_ids.size()):
				if screen.distance_to(view * mids[j]) <= thresh:
					return "resize:%s" % edge_ids[j]
		return ""
	var aabb := _decor_selection_aabb()
	if aabb.size.x <= 0.0 or aabb.size.y <= 0.0:
		return ""
	var rot_g: Vector2 = view * _decor_group_rotate_handle(aabb)
	if screen.distance_to(rot_g) <= thresh:
		return "rotate"
	for corner2 in _aabb_corners(aabb):
		if screen.distance_to(view * corner2) <= thresh:
			return "scale"
	return ""


func _on_decor_select_press(world: Vector2, screen: Vector2, shift: bool) -> void:
	_decor_ghost_active = false
	var handle := _decor_handle_at_screen(screen)
	if handle != "" and not _selected_decors.is_empty():
		_begin_decor_group_drag(handle, world)
		return
	var hit_i := TrackDecor.hit_index(_decorations, world)
	if hit_i >= 0:
		if shift:
			_toggle_decor_selected(hit_i)
			_clear_decor_drag()
		elif _is_decor_selected(hit_i):
			_begin_decor_group_drag("move", world)
		else:
			_set_decor_selection([hit_i])
			_begin_decor_group_drag("move", world)
		_canvas.queue_redraw()
		return
	# Empty press: marquee (replace, or additive with Shift).
	_decor_marquee_additive = shift
	if not shift:
		_selected_decors.clear()
	_drag_decor_mode = "marquee"
	_decor_marquee_start = world
	_decor_marquee_end = world
	_drag_decor_snapshots.clear()
	_canvas.queue_redraw()


func _begin_decor_group_drag(mode: String, world: Vector2) -> void:
	_prune_decor_selection()
	if _selected_decors.is_empty():
		_clear_decor_drag()
		return
	_drag_decor_handle = ""
	if mode.begins_with("resize:"):
		_drag_decor_mode = "resize"
		_drag_decor_handle = mode.substr("resize:".length())
	else:
		_drag_decor_mode = mode
	_drag_decor_start_mouse = world
	_drag_decor_snapshots.clear()
	for idx_v in _selected_decors:
		var idx := int(idx_v)
		var item := TrackDecor.parse_item(_decorations[idx])
		if item.is_empty():
			continue
		_drag_decor_snapshots.append({"index": idx, "item": item.duplicate(true)})
	if _drag_decor_snapshots.is_empty():
		_clear_decor_drag()
		return
	if _selected_decors.size() == 1:
		var only: Dictionary = _drag_decor_snapshots[0].item
		_drag_decor_pivot = only.position
	else:
		_drag_decor_pivot = _decor_selection_aabb().get_center()
	var delta: Vector2 = world - _drag_decor_pivot
	_drag_decor_start_dist = maxf(delta.length(), 1.0)
	_drag_decor_start_angle = delta.angle()


func _continue_decor_drag(world: Vector2) -> void:
	if _drag_decor_snapshots.is_empty():
		_clear_decor_drag()
		return
	match _drag_decor_mode:
		"move":
			var move_delta: Vector2 = world - _drag_decor_start_mouse
			for snap_v in _drag_decor_snapshots:
				var snap: Dictionary = snap_v
				var idx := int(snap.index)
				var start_item: Dictionary = snap.item
				var item := start_item.duplicate(true)
				var start_pos: Vector2 = start_item.position
				item.position = start_pos + move_delta
				_decorations[idx] = item
		"resize":
			_continue_decor_free_resize(world)
		"scale":
			var dist: float = (world - _drag_decor_pivot).length()
			var ratio: float = dist / _drag_decor_start_dist
			for snap_v2 in _drag_decor_snapshots:
				var snap2: Dictionary = snap_v2
				var idx2 := int(snap2.index)
				var start2: Dictionary = snap2.item
				var item2 := start2.duplicate(true)
				var start_pos2: Vector2 = start2.position
				item2.position = _drag_decor_pivot + (start_pos2 - _drag_decor_pivot) * ratio
				if TrackDecor.uses_free_size(str(start2.type)):
					var start_sz: Vector2 = start2.size
					item2.size = TrackDecor.clamp_bleacher_size(start_sz * ratio)
				else:
					item2.scale = TrackDecor.clamp_scale(float(start2.scale) * ratio)
				_decorations[idx2] = item2
		"rotate":
			var ang: float = (world - _drag_decor_pivot).angle()
			var delta_ang: float = ang - _drag_decor_start_angle
			for snap_v3 in _drag_decor_snapshots:
				var snap3: Dictionary = snap_v3
				var idx3 := int(snap3.index)
				var start3: Dictionary = snap3.item
				var item3 := start3.duplicate(true)
				var start_pos3: Vector2 = start3.position
				item3.position = _drag_decor_pivot + (start_pos3 - _drag_decor_pivot).rotated(delta_ang)
				item3.rotation = float(start3.rotation) + delta_ang
				_decorations[idx3] = item3
		_:
			return
	_dirty = true
	_canvas.queue_redraw()


func _continue_decor_free_resize(world: Vector2) -> void:
	## Resize largeur×hauteur d'un seul gradin: le côté/coin opposé reste ancré.
	if _drag_decor_snapshots.size() != 1 or _drag_decor_handle.is_empty():
		return
	var snap: Dictionary = _drag_decor_snapshots[0]
	var start: Dictionary = snap.item
	if not TrackDecor.uses_free_size(str(start.type)):
		return
	var rot := float(start.rotation)
	var start_pos: Vector2 = start.position
	var start_sz: Vector2 = start.size
	var hx := start_sz.x * 0.5
	var hy := start_sz.y * 0.5
	## Coins locaux du cadre de hit (sans HIT_PAD) — taille visuelle réelle.
	var local_mouse: Vector2 = (world - start_pos).rotated(-rot)
	var min_v := Vector2(-hx, -hy)
	var max_v := Vector2(hx, hy)
	var h := _drag_decor_handle
	if h.contains("w"):
		min_v.x = local_mouse.x
	if h.contains("e"):
		max_v.x = local_mouse.x
	if h.contains("n"):
		min_v.y = local_mouse.y
	if h.contains("s"):
		max_v.y = local_mouse.y
	## Empêche l'inversion: impose une taille minimale avant clamp/snap.
	if max_v.x < min_v.x + TrackDecor.BLEACHER_MIN_WIDTH:
		if h.contains("w"):
			min_v.x = max_v.x - TrackDecor.BLEACHER_MIN_WIDTH
		else:
			max_v.x = min_v.x + TrackDecor.BLEACHER_MIN_WIDTH
	if max_v.y < min_v.y + TrackDecor.BLEACHER_TIER_DEPTH:
		if h.contains("n"):
			min_v.y = max_v.y - TrackDecor.BLEACHER_TIER_DEPTH
		else:
			max_v.y = min_v.y + TrackDecor.BLEACHER_TIER_DEPTH
	var raw_size := max_v - min_v
	var new_size := TrackDecor.clamp_bleacher_size(raw_size)
	## Recaler le bord déplacé pour respecter le snap d'étages / clamp largeur.
	if h.contains("w"):
		min_v.x = max_v.x - new_size.x
	elif h.contains("e"):
		max_v.x = min_v.x + new_size.x
	else:
		var cx := (min_v.x + max_v.x) * 0.5
		min_v.x = cx - new_size.x * 0.5
		max_v.x = cx + new_size.x * 0.5
	if h.contains("n"):
		min_v.y = max_v.y - new_size.y
	elif h.contains("s"):
		max_v.y = min_v.y + new_size.y
	else:
		var cy := (min_v.y + max_v.y) * 0.5
		min_v.y = cy - new_size.y * 0.5
		max_v.y = cy + new_size.y * 0.5
	var new_center_local := (min_v + max_v) * 0.5
	var item := start.duplicate(true)
	item.size = new_size
	item.position = start_pos + new_center_local.rotated(rot)
	_decorations[int(snap.index)] = item


func _finish_decor_marquee() -> void:
	var rect := Rect2(_decor_marquee_start, Vector2.ZERO).expand(_decor_marquee_end)
	# Ignore tiny drags — treat as empty click.
	if rect.size.x < 2.0 and rect.size.y < 2.0:
		if not _decor_marquee_additive:
			_selected_decors.clear()
		return
	var picked: Array = []
	for i in _decorations.size():
		var item := TrackDecor.parse_item(_decorations[i])
		if item.is_empty():
			continue
		var pos: Vector2 = item.position
		if rect.has_point(pos):
			picked.append(i)
	if _decor_marquee_additive:
		for idx_v in picked:
			var idx := int(idx_v)
			if not _selected_decors.has(idx):
				_selected_decors.append(idx)
	else:
		_set_decor_selection(picked)


func _on_decor_place_press(world: Vector2) -> void:
	_clear_decor_drag()
	_selected_decors.clear()
	var place_pos := _decor_ghost_pos if _decor_ghost_active else world
	var brush := _decor_brush
	_decorations.append(TrackDecor.make_item(brush, place_pos, _decor_ghost_seed))
	var placed_i := _decorations.size() - 1
	if TrackDecor.uses_free_size(brush):
		## Gradins: passer en sélection pour pouvoir redimensionner tout de suite.
		_roll_decor_place_seed(brush)
		_set_decor_brush(TrackDecor.TOOL_SELECT)
		_set_decor_selection([placed_i])
	else:
		_roll_decor_ghost_seed()
		_decor_ghost_pos = place_pos
		_decor_ghost_active = true
	_dirty = true
	_canvas.queue_redraw()


func _remove_decoration_at(index: int) -> void:
	if index < 0 or index >= _decorations.size():
		return
	_decorations.remove_at(index)
	var kept: Array = []
	for idx_v in _selected_decors:
		var idx := int(idx_v)
		if idx == index:
			continue
		if idx > index:
			kept.append(idx - 1)
		else:
			kept.append(idx)
	_selected_decors = kept
	if _drag_decor_mode != "":
		_clear_decor_drag()
	_dirty = true
	_canvas.queue_redraw()


func _remove_selected_decorations() -> bool:
	_prune_decor_selection()
	if _selected_decors.is_empty():
		return false
	var indices: Array = _selected_decors.duplicate()
	indices.sort()
	## Supprimer du plus grand index au plus petit pour ne pas décaler.
	indices.reverse()
	_clear_decor_drag()
	for idx_v in indices:
		var idx := int(idx_v)
		if idx >= 0 and idx < _decorations.size():
			_decorations.remove_at(idx)
	_selected_decors.clear()
	_dirty = true
	_canvas.queue_redraw()
	return true


func _on_spaces_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var world := _screen_to_world(mb.position)
		if mb.pressed:
			var badge_space := _badge_hit_at(world)
			if badge_space >= 0:
				_selected_space = badge_space
				_drag_corner_space = badge_space
				_drag_corner_grab = world - _corner_badge_center(badge_space)
				_refresh_info()
				_refresh_set_start_button()
				_refresh_corner_ui()
				_refresh_kerb_ui()
				_canvas.queue_redraw()
				_canvas.accept_event()
				return
			_drag_corner_space = -1
			_selected_space = _space_index_at(world)
			_refresh_info()
			_refresh_set_start_button()
			_refresh_corner_ui()
			_refresh_kerb_ui()
			_canvas.queue_redraw()
		elif _drag_corner_space >= 0:
			_drag_corner_space = -1
			_canvas.accept_event()
	elif event is InputEventMouseMotion and _drag_corner_space >= 0:
		if _seg_result == null or _seg_result.space_count() == 0:
			_drag_corner_space = -1
			return
		var world := _screen_to_world((event as InputEventMouseMotion).position)
		var exit_i := posmod(_drag_corner_space + 1, _seg_result.space_count())
		var frontier: TrackSegmenter.Frontier = _seg_result.frontiers[exit_i]
		var natural := _corner_badge_natural(frontier, _corner_outside(_drag_corner_space))
		_set_corner_offset(_drag_corner_space, world - _drag_corner_grab - natural)
		_dirty = true
		_canvas.queue_redraw()
		_canvas.accept_event()


## Closest corner speed badge under `world`, or -1.
func _badge_hit_at(world: Vector2) -> int:
	if _seg_result == null or _corners.is_empty():
		return -1
	var r := _hit_radius(CORNER_BADGE_RADIUS + 2.0)
	var best := -1
	var best_d := r
	for key in _corners.keys():
		var space := int(key)
		var d := world.distance_to(_corner_badge_center(space))
		if d <= best_d:
			best_d = d
			best = space
	return best


func _on_sectors_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
			return
		var space := _space_index_at(_screen_to_world(mb.position))
		if space < 0:
			_selected_sector = -1
		else:
			_selected_sector = _sector_index_at_space(space)
		_refresh_sector_ui()
		_canvas.queue_redraw()
		_canvas.accept_event()


func _space_index_at(pos: Vector2) -> int:
	if _seg_result == null or _seg_result.space_count() < 2:
		return -1
	return _seg_result.space_at_world(pos, ROAD_HALF_WIDTH)


func _begin_left(pos: Vector2) -> void:
	# Handles only exist visually for the selection; then point drag, then insert.
	var handle := _hit_editable_handle(_selected, pos)
	if handle != "":
		_drag_mode = handle
		return
	var best := _nearest_point(pos, _hit_radius(POINT_HIT_RADIUS))
	if best >= 0:
		_selected = best
		_drag_mode = "point"
		_spline.set_point_position(_selected, pos)
		_dirty = true
		_refresh_info()
		_canvas.queue_redraw()
		return
	if _try_insert_at(pos):
		return


func _try_cycle_type_at(pos: Vector2) -> bool:
	var best := _nearest_point(pos, _hit_radius(POINT_HIT_RADIUS))
	if best < 0:
		return false
	_selected = best
	_drag_mode = ""
	var current := _spline.get_point(_selected).type
	var next_type := _next_point_type(current)
	_spline.set_point_type(_selected, next_type)
	_dirty = true
	_refresh_info()
	_canvas.queue_redraw()
	return true


func _next_point_type(type: int) -> int:
	match type:
		TrackSpline.PointType.AUTO_SMOOTH:
			return TrackSpline.PointType.TENSION
		TrackSpline.PointType.TENSION:
			return TrackSpline.PointType.FREE
		_:
			return TrackSpline.PointType.AUTO_SMOOTH


func _hit_editable_handle(index: int, pos: Vector2) -> String:
	var cp := _spline.get_point(index)
	var r := _hit_radius(HANDLE_HIT_RADIUS)
	match cp.type:
		TrackSpline.PointType.AUTO_SMOOTH:
			return ""
		TrackSpline.PointType.TENSION:
			if pos.distance_to(_spline.out_handle_world(index)) <= r:
				return "out_handle"
			if pos.distance_to(_spline.in_handle_world(index)) <= r:
				return "out_handle" # mirrored — either side adjusts tension
			return ""
		TrackSpline.PointType.FREE:
			if pos.distance_to(_spline.out_handle_world(index)) <= r:
				return "out_handle"
			if pos.distance_to(_spline.in_handle_world(index)) <= r:
				return "in_handle"
			return ""
		_:
			return ""


func _try_insert_at(pos: Vector2) -> bool:
	var hit: Dictionary = _spline.closest_on_curve(pos)
	if float(hit.distance) > _hit_radius(CURVE_HIT_RADIUS):
		return false
	var new_index := _spline.insert_point_near(pos)
	if new_index < 0:
		return false
	_selected = new_index
	_drag_mode = "point"
	_dirty = true
	_refresh_status()
	_refresh_info()
	_canvas.queue_redraw()
	return true


func _try_remove_at(pos: Vector2) -> void:
	var best := _nearest_point(pos, _hit_radius(POINT_HIT_RADIUS))
	if best < 0:
		return
	if not _spline.remove_point(best):
		return
	if _selected >= _spline.point_count():
		_selected = _spline.point_count() - 1
	elif _selected > best:
		_selected -= 1
	_dirty = true
	_refresh_status()
	_refresh_info()
	_canvas.queue_redraw()


func _continue_drag(pos: Vector2) -> void:
	var cp := _spline.get_point(_selected)
	match _drag_mode:
		"point":
			_spline.set_point_position(_selected, pos)
			_dirty = true
		"out_handle":
			if cp.type == TrackSpline.PointType.TENSION:
				_spline.set_point_tension(_selected, _spline.tension_from_out_handle(_selected, pos))
			elif cp.type == TrackSpline.PointType.FREE:
				_spline.set_out_handle_world(_selected, pos)
			_dirty = true
		"in_handle":
			if cp.type == TrackSpline.PointType.FREE:
				_spline.set_in_handle_world(_selected, pos)
				_dirty = true
			else:
				return
		_:
			return
	_refresh_info()
	_canvas.queue_redraw()


func _nudge_tension(delta: float) -> void:
	var cp := _spline.get_point(_selected)
	if cp.type != TrackSpline.PointType.TENSION:
		return
	_spline.set_point_tension(_selected, cp.tension + delta)
	_dirty = true
	_refresh_info()
	_canvas.queue_redraw()


func _nearest_point(pos: Vector2, max_dist: float) -> int:
	var best := -1
	var best_d := max_dist * max_dist
	for i in _spline.point_count():
		var d := pos.distance_squared_to(_spline.get_point(i).position)
		if d <= best_d:
			best_d = d
			best = i
	return best
