class_name CardHandView
extends Control

## The player's hand, drawn with the UI kit's Card rather than plain buttons.
##
## Layout is manual rather than a container: the cards sit on an arc and lift on
## hover, which a GridContainer would fight by re-placing them every frame.

signal selection_changed(selected_ids: Array[String])
signal card_activated(card_id: String)

const CARD_SIZE := Vector2(118, 170)
## Radians between two neighbouring cards.
const FAN_SPREAD := 0.045
## Depth of the arc, in pixels.
const FAN_LIFT := 16.0
## Horizontal step between cards. Wide enough that a card's value stays readable
## when the next one overlaps it.
const FAN_STEP := 104.0

var _selected: Dictionary = {} # id -> true
var _multi_select: bool = true
var _enabled: bool = true
## -1 = unlimited. Caps how many cards can be selected at once.
var _max_selection: int = -1
var _cards: Array[Card] = []


func _ready() -> void:
	if custom_minimum_size.y <= 0.0:
		custom_minimum_size.y = 120.0
	clip_contents = false
	resized.connect(_layout_fan)


func clear_hand() -> void:
	for card in _cards:
		card.queue_free()
	_cards.clear()
	_selected.clear()


func set_selection_limit(max_n: int) -> void:
	_max_selection = max_n
	if _max_selection < 0:
		return
	var ids := selected_ids()
	while ids.size() > _max_selection:
		var drop_id: String = ids.pop_back()
		_selected.erase(drop_id)
		var card := _card_by_id(drop_id)
		if card != null:
			card.selected = false
	selection_changed.emit(selected_ids())


func set_cards(
	cards: Array[HeatCard],
	enabled: bool = true,
	multi_select: bool = true,
	animate: bool = false,
	can_select: Callable = Callable(),
	can_activate: Callable = Callable()
) -> void:
	clear_hand()
	_enabled = enabled
	_multi_select = multi_select
	for heat_card in cards:
		var selectable := enabled
		if selectable and can_select.is_valid():
			selectable = bool(can_select.call(heat_card))
		var activatable := enabled and can_activate.is_valid() and bool(can_activate.call(heat_card))

		var card := Card.new()
		card.card_size = _fitted_card_size()
		add_child(card)
		card.data = _to_card_data(heat_card)
		# Only veil a card the player could otherwise expect to pick. Outside a
		# selection phase the whole hand is simply inert, and veiling all of it
		# turned the cockpit into grey mush.
		card.dimmed = enabled and not selectable and not activatable
		card.set_meta("card_id", heat_card.id)
		if activatable:
			card.clicked.connect(_on_card_activated)
		elif selectable:
			card.clicked.connect(_on_card_clicked)
		_cards.append(card)

		if animate:
			card.modulate.a = 0.0
			var tween := create_tween()
			tween.tween_property(card, "modulate:a", 1.0, 0.22)

	_layout_fan()
	# On the first build the control has no size yet, so lay out again once the
	# containers have run.
	call_deferred("_layout_fan")


func selected_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in _selected.keys():
		if _selected[id]:
			ids.append(id)
	return ids


func clear_selection() -> void:
	_selected.clear()
	for card in _cards:
		card.selected = false
	selection_changed.emit(selected_ids())


# --- Layout ---

func _fitted_card_size() -> Vector2:
	# Leave room to lift on hover without leaving the strip.
	var hover_room := 22.0
	var max_h := maxf(72.0, size.y - hover_room)
	if CARD_SIZE.y <= max_h or size.y <= 1.0:
		return CARD_SIZE
	return CARD_SIZE * (max_h / CARD_SIZE.y)


func _layout_fan() -> void:
	if _cards.is_empty():
		return
	var cs := _fitted_card_size()
	for card in _cards:
		card.card_size = cs
	var mid := float(_cards.size() - 1) * 0.5
	var center_x := size.x * 0.5
	var step := FAN_STEP * (cs.x / CARD_SIZE.x)
	var span := float(_cards.size() - 1) * step + cs.x
	if span > size.x and _cards.size() > 1:
		step = maxf(cs.x * 0.35, (size.x - cs.x) / float(_cards.size() - 1))
	var tilt_drop := cs.x * 0.5 * sin(absf(mid * FAN_SPREAD))
	var crest := mid * FAN_LIFT * 0.5 * (cs.y / CARD_SIZE.y)
	var base_y := size.y - cs.y - crest - tilt_drop - 4.0
	if base_y < 0.0:
		crest = maxf(0.0, crest + base_y)
		base_y = maxf(0.0, size.y - cs.y - crest - tilt_drop)

	for i in _cards.size():
		var card := _cards[i]
		var offset := float(i) - mid
		card.rotation = offset * FAN_SPREAD
		card.position.x = center_x + offset * step - cs.x * 0.5
		card.set_rest_y(base_y + absf(offset) * FAN_LIFT * 0.5 * (cs.y / CARD_SIZE.y))


# --- Selection ---

func _on_card_activated(card: Card) -> void:
	card_activated.emit(str(card.get_meta("card_id")))


func _on_card_clicked(card: Card) -> void:
	var card_id: String = card.get_meta("card_id")
	var pressed := not _selected.has(card_id)
	if pressed and _max_selection >= 0 and selected_ids().size() >= _max_selection:
		return
	if not _multi_select and pressed:
		for other in _cards:
			if other != card:
				other.selected = false
				_selected.erase(other.get_meta("card_id"))
	if pressed:
		_selected[card_id] = true
	else:
		_selected.erase(card_id)
	card.selected = pressed
	selection_changed.emit(selected_ids())


func _card_by_id(card_id: String) -> Card:
	for card in _cards:
		if str(card.get_meta("card_id")) == card_id:
			return card
	return null


# --- Model mapping ---

## Rules-side HeatCard to the kit's presentation-side CardData.
func _to_card_data(card: HeatCard) -> CardData:
	return CardCatalog.to_card_data(card.def_id)
