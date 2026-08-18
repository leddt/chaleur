extends Control

## Public 3-round garage draft before the race.

@onready var _round_label: Label = %RoundLabel
@onready var _status: Label = %StatusLabel
@onready var _market: HBoxContainer = %Market
@onready var _picks: VBoxContainer = %Picks
@onready var _continue: Button = %ContinueButton

var _engine: HeatGameEngine
var _selected_id: String = ""


func _ready() -> void:
	_apply_kit_chrome()
	_continue.pressed.connect(_on_continue)
	%BackButton.pressed.connect(_on_back)
	Net.state_updated.connect(_refresh)
	if Game.engine == null:
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")
		return
	_engine = Game.engine
	if _engine.phase != HeatGameEngine.Phase.GARAGE_DRAFT:
		get_tree().change_scene_to_file("res://view/board.tscn")
		return
	_refresh()


func _apply_kit_chrome() -> void:
	var bg := get_node_or_null("Background") as ColorRect
	if bg != null:
		bg.color = Palette.ASPHALT
	var title := get_node_or_null("Margin/VBox/Title") as Label
	if title != null:
		title.theme_type_variation = &"TitleLabel"
	var eyebrow := get_node_or_null("Margin/VBox/Eyebrow") as Label
	if eyebrow != null:
		eyebrow.theme_type_variation = &"Eyebrow"
		eyebrow.text = eyebrow.text.to_upper()
	_status.theme_type_variation = &"Caption"
	_continue.theme_type_variation = &"Primary"
	%BackButton.theme_type_variation = &"Compact"


func _refresh() -> void:
	_engine = Game.engine
	if _engine == null:
		return
	if _engine.phase != HeatGameEngine.Phase.GARAGE_DRAFT:
		get_tree().change_scene_to_file("res://view/board.tscn")
		return
	_round_label.text = "Ronde %d / 3" % _engine.garage_draft_round
	var picker_id := _engine.garage_picker_id()
	var picker_name := "?"
	if picker_id >= 0 and picker_id < _engine.players.size():
		picker_name = _engine.players[picker_id].display_name
	_status.text = "Choix de %s — %d cartes sur le marché" % [picker_name, _engine.garage_market.size()]
	_rebuild_market(picker_id)
	_rebuild_picks()
	var my_id := Game.local_player_id if Game.is_online() else picker_id
	_continue.disabled = _selected_id.is_empty() or picker_id != my_id


func _rebuild_market(picker_id: int) -> void:
	for child in _market.get_children():
		child.queue_free()
	var my_id := Game.local_player_id if Game.is_online() else picker_id
	var can_pick := picker_id == my_id
	for card in _engine.garage_market.cards:
		var view := Card.new()
		view.card_size = Vector2(118, 170)
		view.data = CardCatalog.to_card_data(card.def_id)
		view.selected = card.id == _selected_id
		view.dimmed = not can_pick
		view.set_meta("card_id", card.id)
		view.clicked.connect(_on_market_clicked)
		_market.add_child(view)


func _on_market_clicked(card: Card) -> void:
	_selected_id = str(card.get_meta("card_id", ""))
	_refresh()


func _rebuild_picks() -> void:
	for child in _picks.get_children():
		child.queue_free()
	for p in _engine.players:
		var row := Label.new()
		var names: PackedStringArray = PackedStringArray()
		for card in p.garage_upgrades.cards:
			var def := CardCatalog.get_def(card.def_id)
			names.append(def.title if not def.title.is_empty() else card.def_id)
		row.text = "%s — %s" % [p.display_name, ", ".join(names) if not names.is_empty() else "…"]
		row.theme_type_variation = "Caption"
		_picks.add_child(row)


func _on_continue() -> void:
	if _selected_id.is_empty() or _engine == null:
		return
	var picker := _engine.garage_picker_id()
	if Game.is_online():
		Net.submit_action("pick_garage", {"card_id": _selected_id})
	else:
		var result := _engine.pick_garage_card(picker, _selected_id)
		if not result.ok:
			_status.text = result.error
			return
	_selected_id = ""
	_refresh()


func _on_back() -> void:
	Game.clear_race()
	if Game.is_online():
		get_tree().change_scene_to_file("res://ui/lobby.tscn")
	else:
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")
