class_name EventJournal
extends Control

## Race journal. Collapsed it is a single line — the last thing that happened.
## Clicking opens the full history over the track, scrolled to the start of the
## current round, so the round reads at a glance and earlier rounds are a scroll away.
##
## Hovering only *offers* the expansion — a chevron over a gradient — instead of
## opening it. Opening on hover fired constantly while moving the mouse across the
## board, which made the journal feel like it was in the way.
##
## The expanded panel is drawn upward out of this control's own rect instead of
## being part of the layout: opening the journal must never move the track.

const COLLAPSED_HEIGHT := 26.0
const EXPANDED_HEIGHT := 260.0
## The engine line that opens a round (game_engine.gd).
const ROUND_MARKER := "New round"

var _latest: RichTextLabel
var _panel: PanelContainer
var _full: RichTextLabel
var _affordance: Control
var _expanded: bool = false
var _hovered: bool = false
var _round_start_paragraph: int = 0


func _ready() -> void:
	custom_minimum_size = Vector2(0, COLLAPSED_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Journal de la course"
	clip_contents = false
	_build()


func _build() -> void:
	_latest = RichTextLabel.new()
	_latest.bbcode_enabled = true
	_latest.scroll_active = false
	_latest.clip_contents = true
	_latest.fit_content = false
	_latest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_latest.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_latest)

	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Anchored to this strip's top edge and grown upward, over the track.
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_top = -EXPANDED_HEIGHT
	_panel.offset_bottom = 0.0
	add_child(_panel)

	_full = RichTextLabel.new()
	_full.bbcode_enabled = true
	_full.scroll_following = false
	_full.fit_content = false
	_panel.add_child(_full)

	# Drawn last so the chevron sits over the journal text.
	_affordance = Control.new()
	_affordance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_affordance.set_anchors_preset(Control.PRESET_FULL_RECT)
	_affordance.modulate.a = 0.0
	_affordance.draw.connect(_draw_affordance)
	add_child(_affordance)


func clear() -> void:
	_latest.clear()
	_full.clear()
	_round_start_paragraph = 0


## Takes the raw engine line; formatting and round detection both live here.
func append(raw_line: String) -> void:
	if raw_line.begins_with(ROUND_MARKER):
		_round_start_paragraph = _full.get_paragraph_count()
	var bbcode := JournalFormat.to_bbcode(raw_line)
	_full.append_text(bbcode)
	_latest.clear()
	_latest.append_text(bbcode)
	if _expanded:
		_scroll_to_round()


func _scroll_to_round() -> void:
	# Deferred: the paragraph is not laid out on the frame it is appended.
	await get_tree().process_frame
	if is_instance_valid(_full):
		_full.scroll_to_paragraph(
			mini(_round_start_paragraph, maxi(0, _full.get_paragraph_count() - 1))
		)


# --- Affordance ---

## A chevron over a gradient that rises out of the strip. Up means "there is more
## above"; once open it flips down to mean "put it away".
func _draw_affordance() -> void:
	var w := _affordance.size.x
	var h := _affordance.size.y
	if w <= 0.0 or h <= 0.0:
		return

	var glow := Palette.MUSTARD * Color(1, 1, 1, 0.22)
	var clear_col := Palette.MUSTARD * Color(1, 1, 1, 0.0)
	var top := clear_col if _expanded else glow
	var bottom := glow if _expanded else clear_col
	_affordance.draw_polygon(
		PackedVector2Array([
			Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h),
		]),
		PackedColorArray([top, top, bottom, bottom])
	)

	var center := Vector2(w * 0.5, h * 0.5)
	var s := 5.0
	var dir := 1.0 if _expanded else -1.0
	_affordance.draw_polyline(
		PackedVector2Array([
			center + Vector2(-s * 1.6, -s * 0.5 * dir),
			center + Vector2(0, s * 0.5 * dir),
			center + Vector2(s * 1.6, -s * 0.5 * dir),
		]),
		Palette.MUSTARD, 2.0, true
	)


func _fade_affordance(to: float) -> void:
	var tween := create_tween()
	tween.tween_property(_affordance, "modulate:a", to, 0.12)


# --- Interaction ---

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_set_expanded(not _expanded)
		accept_event()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			_hovered = true
			_fade_affordance(1.0)
		NOTIFICATION_MOUSE_EXIT:
			_hovered = false
			_fade_affordance(0.0)


func _set_expanded(open: bool) -> void:
	_expanded = open
	_panel.visible = open
	# The strip becomes the handle once the panel is up; leaving the last line
	# there would print it twice, once in the panel and once underneath.
	_latest.visible = not open
	_affordance.queue_redraw()
	if open:
		_scroll_to_round()
