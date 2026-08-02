class_name CardHandView
extends GridContainer

signal selection_changed(selected_ids: Array[String])

var _selected: Dictionary = {} # id -> true
var _multi_select: bool = true
var _enabled: bool = true
## -1 = unlimited. Caps how many cards can be selected at once.
var _max_selection: int = -1


func _ready() -> void:
	if columns < 1:
		columns = 4


func clear_hand() -> void:
	for child in get_children():
		child.free()
	_selected.clear()


func set_selection_limit(max_n: int) -> void:
	_max_selection = max_n
	if _max_selection < 0:
		return
	var ids := selected_ids()
	while ids.size() > _max_selection:
		var drop_id: String = ids.pop_back()
		_selected.erase(drop_id)
		for child in get_children():
			if child is Button and str(child.get_meta("card_id")) == drop_id:
				child.set_pressed_no_signal(false)
				break
	selection_changed.emit(selected_ids())


func set_cards(
	cards: Array[HeatCard],
	enabled: bool = true,
	multi_select: bool = true,
	animate: bool = false,
	can_select: Callable = Callable()
) -> void:
	clear_hand()
	_enabled = enabled
	_multi_select = multi_select
	for card in cards:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(52, 72)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.toggle_mode = true
		var selectable := enabled
		if selectable and can_select.is_valid():
			selectable = bool(can_select.call(card))
		btn.disabled = not selectable
		if enabled and not selectable:
			btn.modulate = Color(1, 1, 1, 0.45)
			btn.tooltip_text = "%s (non défaussable)" % card.id
		else:
			btn.tooltip_text = card.id
		btn.text = _label_for(card)
		btn.set_meta("card_id", card.id)
		btn.add_theme_color_override("font_color", _color_for(card))
		if selectable:
			btn.toggled.connect(_on_card_toggled.bind(card.id, btn))
		add_child(btn)
		if animate:
			btn.modulate.a = 0.0 if selectable else 0.45
			btn.scale = Vector2(0.85, 0.85)
			var tween := create_tween()
			tween.set_parallel(true)
			tween.tween_property(btn, "modulate:a", 1.0 if selectable else 0.45, 0.22)
			tween.tween_property(btn, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func selected_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in _selected.keys():
		if _selected[id]:
			ids.append(id)
	return ids


func clear_selection() -> void:
	_selected.clear()
	for child in get_children():
		if child is Button:
			child.set_pressed_no_signal(false)
	selection_changed.emit(selected_ids())


func _on_card_toggled(pressed: bool, card_id: String, btn: Button) -> void:
	if pressed and _max_selection >= 0 and selected_ids().size() >= _max_selection and not _selected.has(card_id):
		btn.set_pressed_no_signal(false)
		return
	if not _multi_select and pressed:
		for child in get_children():
			if child is Button and child != btn:
				child.set_pressed_no_signal(false)
				var other_id: String = child.get_meta("card_id")
				_selected.erase(other_id)
	if pressed:
		_selected[card_id] = true
	else:
		_selected.erase(card_id)
	selection_changed.emit(selected_ids())


func _label_for(card: HeatCard) -> String:
	match card.kind:
		HeatCard.Kind.SPEED:
			return "SPD\n%d" % card.speed_value
		HeatCard.Kind.UPGRADE:
			return "UPG\n%d" % card.speed_value
		HeatCard.Kind.HEAT:
			return "HEAT"
		HeatCard.Kind.STRESS:
			return "STR"
		_:
			return "?"


func _color_for(card: HeatCard) -> Color:
	match card.kind:
		HeatCard.Kind.SPEED:
			return Color(0.7, 0.85, 1.0)
		HeatCard.Kind.UPGRADE:
			return Color(0.7, 1.0, 0.75)
		HeatCard.Kind.HEAT:
			return Color(1.0, 0.55, 0.3)
		HeatCard.Kind.STRESS:
			return Color(0.85, 0.65, 1.0)
		_:
			return Color.WHITE
