class_name CardHandView
extends Control

## The player's hand, drawn with the UI kit's Card rather than plain buttons.
##
## Layout is manual rather than a container: the cards sit on an arc and lift on
## hover, which a GridContainer would fight by re-placing them every frame.

signal selection_changed(selected_ids: Array[String])

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
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(0, CARD_SIZE.y + FAN_LIFT * 2.0 + 20.0)
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
	can_select: Callable = Callable()
) -> void:
	clear_hand()
	_enabled = enabled
	_multi_select = multi_select
	for heat_card in cards:
		var selectable := enabled
		if selectable and can_select.is_valid():
			selectable = bool(can_select.call(heat_card))

		var card := Card.new()
		card.card_size = CARD_SIZE
		add_child(card)
		card.data = _to_card_data(heat_card)
		# Only veil a card the player could otherwise expect to pick. Outside a
		# selection phase the whole hand is simply inert, and veiling all of it
		# turned the cockpit into grey mush.
		card.dimmed = enabled and not selectable
		card.set_meta("card_id", heat_card.id)
		card.tooltip_text = heat_card.id if selectable else "%s (non jouable)" % heat_card.id
		if selectable:
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

func _layout_fan() -> void:
	if _cards.is_empty():
		return
	var mid := float(_cards.size() - 1) * 0.5
	var center_x := size.x * 0.5
	# Tighten the step rather than overflow when the hand is large.
	var step := FAN_STEP
	var span := float(_cards.size() - 1) * step + CARD_SIZE.x
	if span > size.x and _cards.size() > 1:
		# Never tighter than the big number is wide, or the hand stops being readable.
		step = maxf(44.0, (size.x - CARD_SIZE.x) / float(_cards.size() - 1))
	# Cards pivot on their bottom centre, so tilting drops one bottom corner below
	# the pivot. That overhang has to be budgeted or the outer cards get clipped.
	var tilt_drop := CARD_SIZE.x * 0.5 * sin(absf(mid * FAN_SPREAD))
	# The crest is raised by the full drop so the outermost cards still land on the
	# bottom edge instead of hanging past it.
	var crest := mid * FAN_LIFT * 0.5
	var base_y := size.y - CARD_SIZE.y - crest - tilt_drop
	if base_y < 0.0:
		# Not enough height for the full arc: flatten it rather than clip cards.
		crest = maxf(0.0, crest + base_y)
		base_y = maxf(0.0, size.y - CARD_SIZE.y - crest - tilt_drop)

	for i in _cards.size():
		var card := _cards[i]
		var offset := float(i) - mid
		card.rotation = offset * FAN_SPREAD
		card.position.x = center_x + offset * step - CARD_SIZE.x * 0.5
		# Crest at the centre: the arc bulges up in the middle and the ends drop,
		# the way a hand of cards actually sits when it is held.
		card.set_rest_y(base_y + absf(offset) * FAN_LIFT * 0.5)


# --- Selection ---

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
	match card.kind:
		HeatCard.Kind.UPGRADE:
			return CardData.upgrade(card.speed_value)
		HeatCard.Kind.HEAT:
			return CardData.heat()
		HeatCard.Kind.STRESS:
			return CardData.stress()
		_:
			return CardData.speed(card.speed_value)
