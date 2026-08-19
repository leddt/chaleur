class_name SalvageOverlay
extends ColorRect

signal confirmed(card_ids: Array)
signal cancelled()

const CARD_SIZE := Vector2(96, 138)

var _max_count: int = 1
var _selected: Array[String] = []
var _grid: HFlowContainer
var _hint: Label
var _confirm: Button
var _empty: Label


func _ready() -> void:
	visible = false
	z_index = 200
	z_as_relative = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	color = Color(0.05, 0.06, 0.08, 0.92)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	add_child(center)

	var inner := VBoxContainer.new()
	inner.custom_minimum_size = Vector2(520, 0)
	inner.add_theme_constant_override("separation", 12)
	center.add_child(inner)

	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = "Salvage"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(title)

	_hint = Label.new()
	_hint.theme_type_variation = &"Caption"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(_hint)

	_empty = Label.new()
	_empty.theme_type_variation = &"Caption"
	_empty.text = "La défausse est vide."
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.visible = false
	inner.add_child(_empty)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 280)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inner.add_child(scroll)

	_grid = HFlowContainer.new()
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	inner.add_child(buttons)

	var cancel := Button.new()
	cancel.text = "Annuler"
	cancel.theme_type_variation = &"Compact"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(func() -> void:
		close()
		cancelled.emit()
	)
	buttons.add_child(cancel)

	_confirm = Button.new()
	_confirm.text = "Récupérer"
	_confirm.theme_type_variation = &"Primary"
	_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm.pressed.connect(func() -> void:
		var ids: Array = []
		for id in _selected:
			ids.append(id)
		close()
		confirmed.emit(ids)
	)
	buttons.add_child(_confirm)


func open(cards: Array[HeatCard], max_count: int) -> void:
	_max_count = maxi(1, max_count)
	_selected.clear()
	for child in _grid.get_children():
		child.queue_free()
	_empty.visible = cards.is_empty()
	_confirm.visible = not cards.is_empty()
	_hint.text = (
		"La défausse est vide."
		if cards.is_empty()
		else "Choisis jusqu'à %d carte(s) dans la défausse." % _max_count
	)
	for heat_card in cards:
		var wrap := Control.new()
		wrap.custom_minimum_size = CARD_SIZE
		var card := Card.new()
		card.card_size = CARD_SIZE
		wrap.add_child(card)
		card.data = CardCatalog.to_card_data(heat_card.def_id)
		card.set_meta("card_id", heat_card.id)
		card.clicked.connect(_on_card_clicked)
		_grid.add_child(wrap)
	_update_confirm()
	visible = true


func close() -> void:
	visible = false
	_selected.clear()
	for child in _grid.get_children():
		child.queue_free()


func _on_card_clicked(card: Card) -> void:
	var cid := str(card.get_meta("card_id"))
	if cid in _selected:
		_selected.erase(cid)
		card.selected = false
	else:
		_selected.append(cid)
		while _selected.size() > _max_count:
			var drop: String = _selected.pop_front()
			var dropped := _card_by_id(drop)
			if dropped != null:
				dropped.selected = false
		card.selected = true
	_update_confirm()


func _card_by_id(card_id: String) -> Card:
	for wrap in _grid.get_children():
		for child in wrap.get_children():
			if child is Card and str(child.get_meta("card_id")) == card_id:
				return child
	return null


func _update_confirm() -> void:
	_confirm.text = "Récupérer" if _selected.is_empty() else "Récupérer %d" % _selected.size()
