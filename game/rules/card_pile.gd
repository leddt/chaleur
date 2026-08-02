class_name CardPile
extends RefCounted

var cards: Array[HeatCard] = []


func clear() -> void:
	cards.clear()


func size() -> int:
	return cards.size()


func is_empty() -> bool:
	return cards.is_empty()


func add(card: HeatCard) -> void:
	cards.append(card)


func add_many(more: Array[HeatCard]) -> void:
	for card in more:
		cards.append(card)


func remove_at(index: int) -> HeatCard:
	return cards.pop_at(index)


func remove_id(card_id: String) -> HeatCard:
	for i in cards.size():
		if cards[i].id == card_id:
			return remove_at(i)
	return null


func has_id(card_id: String) -> bool:
	for card in cards:
		if card.id == card_id:
			return true
	return false


func get_by_id(card_id: String) -> HeatCard:
	for card in cards:
		if card.id == card_id:
			return card
	return null


func draw_top() -> HeatCard:
	if cards.is_empty():
		return null
	return cards.pop_front()


func peek_top() -> HeatCard:
	if cards.is_empty():
		return null
	return cards[0]


func shuffle(rng: RandomNumberGenerator) -> void:
	for i in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := cards[i]
		cards[i] = cards[j]
		cards[j] = tmp


func ids() -> Array[String]:
	var out: Array[String] = []
	for card in cards:
		out.append(card.id)
	return out


func count_kind(kind: HeatCard.Kind) -> int:
	var n := 0
	for card in cards:
		if card.kind == kind:
			n += 1
	return n
