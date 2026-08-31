extends Control

## Public 3-round garage draft before the race.

const SUMMARY_CARD := Vector2(110, 158)
const ROUND_REVEAL_SEC := 2.0

@onready var _title: Label = $Margin/VBox/Title
@onready var _picks_title: Label = $Margin/VBox/PicksTitle
@onready var _market_scroll: ScrollContainer = $Margin/VBox/MarketScroll
@onready var _picks_scroll: ScrollContainer = $Margin/VBox/PicksScroll
@onready var _round_label: Label = %RoundLabel
@onready var _status: Label = %StatusLabel
@onready var _market: HBoxContainer = %Market
@onready var _picks: VBoxContainer = %Picks
@onready var _continue: Button = %ContinueButton

var _engine: HeatGameEngine
var _selected_id: String = ""
var _revealing_round: int = -1


func _ready() -> void:
	_apply_kit_chrome()
	_continue.pressed.connect(_on_continue)
	%BackButton.pressed.connect(_on_back)
	Net.state_updated.connect(_refresh)
	if Game.engine == null:
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")
		return
	_engine = Game.engine
	if not _in_garage_flow():
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


func _in_garage_flow() -> bool:
	return (
		_engine != null
		and (
			_engine.phase == HeatGameEngine.Phase.GARAGE_DRAFT
			or _engine.phase == HeatGameEngine.Phase.GARAGE_SUMMARY
		)
	)


func _refresh() -> void:
	_engine = Game.engine
	if _engine == null:
		return
	if not _in_garage_flow():
		get_tree().change_scene_to_file("res://view/board.tscn")
		return
	if _engine.phase == HeatGameEngine.Phase.GARAGE_SUMMARY:
		_show_summary()
		Music.set_context(
			MusicContextResolver.for_garage(_engine, Game.is_online(), Game.local_player_id)
		)
		return
	_show_draft()
	Music.set_context(
		MusicContextResolver.for_garage(_engine, Game.is_online(), Game.local_player_id)
	)


func _show_draft() -> void:
	_title.text = "Construis ta voiture"
	_round_label.text = "Ronde %d / 3" % _engine.garage_draft_round
	_picks_title.visible = false
	_market_scroll.visible = true
	_picks_scroll.visible = false
	var revealing := _engine.is_garage_round_complete()
	var picker_id := _engine.garage_picker_id()
	if revealing:
		_status.text = "Ronde %d terminée" % _engine.garage_draft_round
	else:
		var picker_name := "?"
		if picker_id >= 0 and picker_id < _engine.players.size():
			picker_name = _engine.players[picker_id].display_name
		_status.text = "Choix de %s — %d cartes sur le marché" % [picker_name, _engine.garage_market.size()]
	_rebuild_market(picker_id, revealing)
	if revealing or (not _selected_id.is_empty() and _engine.garage_claim_player_id(_selected_id) >= 0):
		_selected_id = ""
	var my_id := Game.local_player_id if Game.is_online() else picker_id
	_continue.text = "Prendre cette carte"
	_continue.disabled = revealing or _selected_id.is_empty() or picker_id != my_id
	_maybe_schedule_round_advance()


func _show_summary() -> void:
	_title.text = "Les voitures"
	_round_label.text = "Draft terminé"
	_picks_title.visible = true
	_picks_title.text = "ÉQUIPAGES"
	_market_scroll.visible = false
	_picks_scroll.visible = true
	_picks_scroll.clip_contents = true
	_picks_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	_picks_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rebuild_summary()
	if Game.is_online():
		_show_online_ready()
	else:
		_status.text = "Vérifiez les améliorations, puis lancez la course."
		_continue.text = "C'est parti"
		_continue.disabled = false


func _show_online_ready() -> void:
	var me := Game.local_player_id
	var waiting: PackedStringArray = PackedStringArray()
	for p in _engine.players:
		if not _engine.is_garage_ready(p.id):
			waiting.append(p.display_name)
	if waiting.is_empty():
		_status.text = "Tout le monde est prêt — la course commence."
	else:
		_status.text = "En attente de : %s" % ", ".join(waiting)
	var already := _engine.is_garage_ready(me)
	_continue.text = "PRÊT ✓" if already else "PRÊT"
	_continue.disabled = already or me < 0


func _rebuild_market(picker_id: int, revealing: bool) -> void:
	for child in _market.get_children():
		child.queue_free()
	var my_id := Game.local_player_id if Game.is_online() else picker_id
	var can_pick := (not revealing) and picker_id == my_id
	for card in _engine.garage_market.cards:
		var claimed_by := _engine.garage_claim_player_id(card.id)
		var taken := claimed_by >= 0
		var slot := VBoxContainer.new()
		slot.add_theme_constant_override("separation", 4)
		slot.alignment = BoxContainer.ALIGNMENT_CENTER
		var view := Card.new()
		view.card_size = Vector2(118, 170)
		view.data = CardCatalog.to_card_data(card.def_id)
		view.selected = (not taken) and (not revealing) and card.id == _selected_id
		view.dimmed = taken or not can_pick
		view.set_meta("card_id", card.id)
		if not taken and can_pick:
			view.clicked.connect(_on_market_clicked)
		slot.add_child(view)
		var tag := Label.new()
		tag.theme_type_variation = &"Caption"
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if taken and claimed_by < _engine.players.size():
			tag.text = _engine.players[claimed_by].display_name
			tag.add_theme_color_override("font_color", Palette.MUSTARD)
		else:
			tag.text = " "
		slot.add_child(tag)
		_market.add_child(slot)


func _on_market_clicked(card: Card) -> void:
	var cid := str(card.get_meta("card_id", ""))
	if _engine.garage_claim_player_id(cid) >= 0:
		return
	_selected_id = cid
	_sync_market_selection()
	var picker := _engine.garage_picker_id()
	var my_id := Game.local_player_id if Game.is_online() else picker
	_continue.disabled = _selected_id.is_empty() or picker != my_id


func _sync_market_selection() -> void:
	for slot in _market.get_children():
		for child in slot.get_children():
			if child is Card:
				var cid := str(child.get_meta("card_id", ""))
				child.selected = cid == _selected_id and _engine.garage_claim_player_id(cid) < 0


func _rebuild_summary() -> void:
	for child in _picks.get_children():
		child.queue_free()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 20)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picks.add_child(grid)
	for p in _engine.players:
		var cell := _make_summary_row(p)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(cell)


func _make_summary_row(p: PlayerState) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var meta := VBoxContainer.new()
	meta.custom_minimum_size.x = 120.0
	meta.add_theme_constant_override("separation", 4)
	meta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var name_label := Label.new()
	name_label.theme_type_variation = &"Stat"
	name_label.text = p.display_name
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta.add_child(name_label)
	if Game.is_online():
		var ready_label := Label.new()
		ready_label.theme_type_variation = &"Caption"
		if _engine.is_garage_ready(p.id):
			ready_label.text = "PRÊT"
			ready_label.add_theme_color_override("font_color", Palette.MUSTARD)
		else:
			ready_label.text = "En attente"
		meta.add_child(ready_label)
	row.add_child(meta)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 8)
	cards.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for heat_card in p.garage_upgrades.cards:
		var view := Card.new()
		view.card_size = SUMMARY_CARD
		view.data = CardCatalog.to_card_data(heat_card.def_id)
		cards.add_child(view)
	row.add_child(cards)
	return row


func _maybe_schedule_round_advance() -> void:
	if _engine == null or not _engine.is_garage_round_complete():
		_revealing_round = -1
		return
	if Game.is_online() and not Net.is_server():
		return
	if _revealing_round == _engine.garage_draft_round:
		return
	_revealing_round = _engine.garage_draft_round
	var round_id := _revealing_round
	get_tree().create_timer(ROUND_REVEAL_SEC).timeout.connect(
		_on_round_reveal_finished.bind(round_id), CONNECT_ONE_SHOT
	)


func _on_round_reveal_finished(round_id: int) -> void:
	if not is_inside_tree() or _engine == null:
		return
	if _engine.garage_draft_round != round_id or not _engine.is_garage_round_complete():
		return
	if Game.is_online():
		Net.host_advance_garage_round()
		return
	var result := _engine.advance_garage_round()
	if not result.ok:
		_status.text = result.error
		return
	_revealing_round = -1
	_refresh()


func _on_continue() -> void:
	if _engine == null:
		return
	if _engine.phase == HeatGameEngine.Phase.GARAGE_SUMMARY:
		_on_summary_continue()
		return
	if _engine.is_garage_round_complete() or _selected_id.is_empty():
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


func _on_summary_continue() -> void:
	if Game.is_online():
		Net.submit_action("ready_garage", {})
		return
	var result := _engine.begin_race_from_garage()
	if not result.ok:
		_status.text = result.error
		return
	_refresh()


func _on_back() -> void:
	Game.clear_race()
	if Game.is_online():
		get_tree().change_scene_to_file("res://ui/lobby.tscn")
	else:
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")
