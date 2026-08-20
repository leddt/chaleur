class_name ActionPanel
extends Control

## Builds phase-specific action controls; board / Net handle dispatch.
##
## Root is a Control, not a VBox: child minimum sizes must not inflate the
## cockpit (and then the whole board) past the viewport.

signal action_requested(action: String, payload: Dictionary, player_id: int)

var _hand: CardHandView
var _sidebar: PlayerSidebar
var _engine: HeatGameEngine

var _play_confirm: Button = null
var _play_expected: int = -1
var _play_cluttered: bool = false
var _play_actor_id: int = -1
var _discard_confirm: Button = null
var _react_player_id: int = -1
var _finish_confirm: ConfirmationDialog = null
var _armed_direct_play_id: String = ""
var _col: VBoxContainer
var _body_host: Control
var _finish_btn: Button


func _ready() -> void:
	clip_contents = false
	_ensure_hosts()


func _ensure_hosts() -> void:
	if _body_host != null:
		return
	_body_host = Control.new()
	_body_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_body_host.clip_contents = false
	_body_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body_host)
	_col = VBoxContainer.new()
	_col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_col.add_theme_constant_override("separation", 4)
	_body_host.add_child(_col)


func _slot() -> VBoxContainer:
	_ensure_hosts()
	return _col


func _reserve_finish_row(on: bool) -> void:
	_ensure_hosts()
	_body_host.offset_bottom = -44.0 if on else 0.0


func setup(hand: CardHandView, sidebar: PlayerSidebar) -> void:
	_hand = hand
	_sidebar = sidebar


func is_showing() -> bool:
	return _slot().get_child_count() > 0


func reset_drafts() -> void:
	_sidebar.reset_gear_choice()


func clear() -> void:
	_play_confirm = null
	_play_expected = -1
	_play_cluttered = false
	_play_actor_id = -1
	_discard_confirm = null
	_hand.set_selection_limit(-1)
	_speed_choices.clear()
	_reserve_finish_row(false)
	if _finish_btn != null:
		_finish_btn.queue_free()
		_finish_btn = null
	for child in _slot().get_children():
		child.queue_free()
	_sidebar.set_gear_editable(false)


func build_for(engine: HeatGameEngine, actor_id: int) -> void:
	_engine = engine
	if engine.turn_step != HeatGameEngine.TurnStep.REACT:
		_armed_direct_play_id = ""
	clear()
	var p := engine.players[actor_id]
	match engine.phase:
		HeatGameEngine.Phase.GARAGE_DRAFT:
			_sidebar.set_gear_editable(false, p)
			_build_garage_ui()
		HeatGameEngine.Phase.GARAGE_SUMMARY:
			_sidebar.set_gear_editable(false, p)
			_build_garage_ui()
		HeatGameEngine.Phase.SHIFT_GEARS:
			_build_shift_ui(p)
		HeatGameEngine.Phase.PLAY_CARDS:
			_sidebar.set_gear_editable(false, p)
			_build_play_ui(p)
		HeatGameEngine.Phase.PLAYER_TURN:
			_sidebar.set_gear_editable(false, p)
			_build_turn_ui(p)
		_:
			_sidebar.set_gear_editable(false, p)


func on_hand_selection_changed() -> void:
	_update_play_confirm()
	_update_discard_confirm()


var _speed_choices: Dictionary = {}


func _build_garage_ui() -> void:
	_slot().add_child(_make_eyebrow("GARAGE"))
	if _engine.phase == HeatGameEngine.Phase.GARAGE_SUMMARY:
		_slot().add_child(_make_label("Résumé des voitures — confirmez quand vous êtes prêt."))
		return
	var picker := _engine.garage_picker_id()
	var picker_name := "?"
	if picker >= 0 and picker < _engine.players.size():
		picker_name = _engine.players[picker].display_name
	_slot().add_child(_make_label("Ronde %d — à %s de choisir" % [_engine.garage_draft_round, picker_name]))
	_slot().add_child(_make_label("Ouvre l'écran de draft si tu ne vois pas le marché."))


func _build_shift_ui(p: PlayerState) -> void:
	_sidebar.ensure_chosen_gear(p)
	_sidebar.set_gear_editable(true, p)
	_slot().add_child(_make_eyebrow("ÉTAPE 1 — RAPPORT"))
	_slot().add_child(_make_label("En %d · deux crans = 1 Heat" % p.gear))
	var confirm := _make_button("Engager", true)
	confirm.pressed.connect(func() -> void:
		action_requested.emit("shift_gear", {"gear": _sidebar.chosen_gear}, p.id)
	)
	_slot().add_child(confirm)


func _build_play_ui(p: PlayerState) -> void:
	var playable := p.playable_in_hand().size()
	var required := p.gear
	_play_expected = required
	_play_cluttered = playable < required
	_play_actor_id = p.id
	_hand.set_selection_limit(required)
	var hint_text: String
	if _play_cluttered:
		hint_text = "Main encombrée — joue tout ce qui peut l'être, complète avec du Heat"
	elif required == 1:
		hint_text = "Joue 1 carte"
	else:
		hint_text = "Joue %d cartes" % required
	_slot().add_child(_make_eyebrow("ÉTAPE 2 — CARTES"))
	_slot().add_child(_make_label(hint_text))
	_play_confirm = _make_button("Jouer", true)
	_play_confirm.disabled = true
	_play_confirm.pressed.connect(func() -> void:
		action_requested.emit(
			"play_cards",
			{"card_ids": _hand.selected_ids()},
			p.id
		)
	)
	_slot().add_child(_play_confirm)
	_update_play_confirm()


func _play_selection_valid() -> bool:
	if _engine == null or _play_expected < 0 or _play_actor_id < 0:
		return false
	if _play_actor_id >= _engine.players.size():
		return false
	var p := _engine.players[_play_actor_id]
	var ids := _hand.selected_ids()
	if ids.size() != _play_expected:
		return false
	if _play_cluttered:
		var playable := p.playable_in_hand()
		for card in playable:
			if card.id not in ids:
				return false
		var heat_fillers := 0
		for cid in ids:
			var card := p.hand.get_by_id(cid)
			if card == null:
				return false
			if card.kind == HeatCard.Kind.HEAT:
				heat_fillers += 1
			elif not card.is_playable():
				return false
		return heat_fillers == _play_expected - playable.size()
	for cid in ids:
		var card := p.hand.get_by_id(cid)
		if card == null or not card.is_playable() or card.kind == HeatCard.Kind.HEAT:
			return false
	return true


func _update_play_confirm() -> void:
	if _play_confirm == null:
		return
	_play_confirm.disabled = not _play_selection_valid()


func _build_turn_ui(p: PlayerState) -> void:
	match _engine.turn_step:
		HeatGameEngine.TurnStep.SETTLE_HEAT:
			_build_settle_heat_ui(p)
		HeatGameEngine.TurnStep.REACT:
			_build_react_ui(p)
		HeatGameEngine.TurnStep.SLIPSTREAM:
			_slot().add_child(_make_eyebrow("ASPIRATION"))
			_slot().add_child(_make_label(
				"Slipstream disponible (+2 cases, n'augmente pas la Speed virage)"
			))
			var yes := _make_button("Slipstream", true)
			yes.pressed.connect(func() -> void:
				action_requested.emit("slipstream", {"use": true}, p.id)
			)
			var no := _make_button("Non")
			no.pressed.connect(func() -> void:
				action_requested.emit("slipstream", {"use": false}, p.id)
			)
			_slot().add_child(yes)
			_slot().add_child(no)
		HeatGameEngine.TurnStep.DISCARD:
			_slot().add_child(_make_eyebrow("FIN DE TOUR"))
			_slot().add_child(_make_label(
				"Défausse optionnelle (pas Heat/Stress), puis pioche jusqu'à 7"
			))
			_discard_confirm = _make_button("Passer la défausse", true)
			_discard_confirm.pressed.connect(func() -> void:
				action_requested.emit("discard", {"card_ids": _hand.selected_ids()}, p.id)
			)
			_slot().add_child(_discard_confirm)
			_update_discard_confirm()
		_:
			_slot().add_child(_make_label("La course avance…"))


func _discard_button_label(count: int) -> String:
	if count <= 0:
		return "Passer la défausse"
	if count == 1:
		return "Défausser 1 carte"
	return "Défausser %d cartes" % count


func _update_discard_confirm() -> void:
	if _discard_confirm == null:
		return
	_discard_confirm.text = _discard_button_label(_hand.selected_ids().size())


func _build_settle_heat_ui(p: PlayerState) -> void:
	var body := _make_body()
	body.add_child(_make_eyebrow("RÈGLEMENT HEAT"))
	body.add_child(_make_label("Paie le Heat sur la carte, ou refroidis d'abord."))
	var grid := _make_action_grid()
	_add_cooldown_button(grid, p)
	body.add_child(grid)
	_add_finish_button(p, "settle_heat")


func _build_react_ui(p: PlayerState) -> void:
	_react_player_id = p.id
	var body := _make_body()
	body.add_child(_make_eyebrow("RÉACTION"))
	var speed_line := "Ta vitesse est %d" % p.round_speed
	if p.has_adrenaline:
		speed_line += " · Adrénaline"
	body.add_child(_make_label(speed_line))

	var grid := _make_action_grid()

	var ad_btn := _make_icon_action_button(
		[{"kind": CardSymbol.Kind.ACCELERATE, "count": 1}],
		"Adrénaline",
		"Avancez de 1 case. Disponible si vous êtes dernier ce tour "
		+ "(ou avant-dernier à 5 joueurs ou plus).",
		func() -> void:
			action_requested.emit("adrenaline", {}, p.id)
	)
	ad_btn.disabled = not p.can_use_adrenaline()
	_dim_if_disabled(ad_btn)
	grid.add_child(ad_btn)

	var boost_btn := _make_icon_action_button(
		[
			{"kind": CardSymbol.Kind.PLUS, "count": 1},
			{"kind": CardSymbol.Kind.HEAT, "count": 1},
		],
		"Boost",
		"Payez 1 Heat du moteur et retournez des cartes jusqu'à obtenir une carte "
		+ "Vitesse 1–4. Cette carte s'ajoute à votre vitesse et compte comme un symbole +.",
		func() -> void:
			action_requested.emit("boost", {}, p.id)
	)
	boost_btn.disabled = not p.can_use_boost()
	_dim_if_disabled(boost_btn)
	grid.add_child(boost_btn)

	_add_cooldown_button(grid, p)
	_add_grid_spacer(grid)
	body.add_child(grid)

	if not _armed_direct_play_id.is_empty():
		_add_armed_direct_play_speeds(body, p)

	_add_finish_button(p, "react")


func _add_cooldown_button(grid: GridContainer, p: PlayerState) -> void:
	var remaining := p.cooldown_remaining()
	var cd_btn := _make_icon_action_button(
		[{"kind": CardSymbol.Kind.COOLDOWN, "count": maxi(1, remaining)}],
		"Cooldown",
		"Remettez 1 Heat de votre main dans le moteur. Quota restant ce tour : %d." % remaining,
		func() -> void:
			action_requested.emit("cooldown", {}, p.id)
	)
	cd_btn.disabled = not p.can_use_cooldown()
	_dim_if_disabled(cd_btn)
	grid.add_child(cd_btn)


func _make_body() -> VBoxContainer:
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.clip_contents = false
	body.add_theme_constant_override("separation", 4)
	_slot().add_child(body)
	return body


func _add_finish_button(p: PlayerState, action: String) -> void:
	_reserve_finish_row(true)
	var finish := _make_button("Terminer", true)
	finish.theme_type_variation = &"PrimaryStrip"
	finish.autowrap_mode = TextServer.AUTOWRAP_OFF
	finish.clip_text = false
	finish.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	finish.offset_left = 0.0
	finish.offset_right = 0.0
	finish.offset_top = -40.0
	finish.offset_bottom = -4.0
	if action == "react":
		finish.pressed.connect(_on_finish_react_pressed.bind(p.id))
	else:
		finish.pressed.connect(func() -> void:
			action_requested.emit(action, {}, p.id)
		)
	add_child(finish)
	_finish_btn = finish


func _make_action_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	return grid


func _add_grid_spacer(grid: GridContainer) -> void:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_child(spacer)


func on_direct_play_card(card_id: String) -> void:
	if _engine == null:
		return
	var p := _engine.active_player()
	if p == null:
		return
	var card := p.hand.get_by_id(card_id)
	if card == null:
		return
	var def := CardCatalog.get_def(card.def_id)
	if not def.has_symbol(CardSymbol.Kind.DIRECT_PLAY):
		return
	var opts := def.resolved_speed_options()
	if opts.size() <= 1:
		var choice := opts[0] if not opts.is_empty() else -1
		action_requested.emit(
			"direct_play", {"card_id": card_id, "speed_choice": choice}, p.id
		)
		return
	_armed_direct_play_id = card_id
	build_for(_engine, p.id)


func _add_armed_direct_play_speeds(parent: Control, p: PlayerState) -> void:
	var card := p.hand.get_by_id(_armed_direct_play_id)
	if card == null:
		_armed_direct_play_id = ""
		return
	var def := CardCatalog.get_def(card.def_id)
	var opts := def.resolved_speed_options()
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	for v in opts:
		var speed := v
		var cid := _armed_direct_play_id
		var btn := _make_icon_action_button(
			[{"kind": CardSymbol.Kind.DIRECT_PLAY, "count": 1}],
			"Direct Play",
			"Jouez cette carte depuis la main pour une vitesse de %d." % speed,
			func() -> void:
				_armed_direct_play_id = ""
				action_requested.emit(
					"direct_play", {"card_id": cid, "speed_choice": speed}, p.id
				),
			str(speed)
		)
		row.add_child(btn)
	parent.add_child(row)


func selected_stress_ids(p: PlayerState) -> Array:
	var ids: Array = []
	for cid in _hand.selected_ids():
		var card := p.hand.get_by_id(cid)
		if card != null and card.kind == HeatCard.Kind.STRESS:
			ids.append(cid)
	return ids


func _on_finish_react_pressed(player_id: int) -> void:
	if _engine == null or player_id < 0 or player_id >= _engine.players.size():
		return
	var p := _engine.players[player_id]
	if not p.has_pending_react_options():
		action_requested.emit("react", {}, player_id)
		return
	_ensure_finish_confirm()
	_finish_confirm.dialog_text = "Il te reste des réactions. Terminer quand même ?"
	_react_player_id = player_id
	_finish_confirm.popup_centered()


func _ensure_finish_confirm() -> void:
	if _finish_confirm != null:
		return
	_finish_confirm = %FinishReactDialog
	_finish_confirm.transparent = false
	if get_tree().root.theme != null:
		_finish_confirm.theme = get_tree().root.theme
	_finish_confirm.cancel_button_text = "Annuler"
	_finish_confirm.confirmed.connect(_on_finish_react_confirmed)


func _on_finish_react_confirmed() -> void:
	if _react_player_id < 0:
		return
	action_requested.emit("react", {}, _react_player_id)


## The "what am I being asked to do" line. Sits above the controls, always in the
## same place, so the instruction is never something you have to hunt for.
func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.max_lines_visible = 1
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	label.theme_type_variation = "Caption"
	return label


## Small uppercase caption naming the current step, above the instruction.
func _make_eyebrow(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = "Eyebrow"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return label


func _make_button(text: String, primary: bool = false, compact: bool = false) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.clip_text = false
	if primary:
		btn.theme_type_variation = "Primary"
	elif compact:
		btn.theme_type_variation = "Compact"
	return btn


func _make_icon_action_button(
	icons: Array,
	title: String,
	body: String,
	on_press: Callable,
	caption: String = ""
) -> RichTooltipButton:
	var btn := RichTooltipButton.new()
	btn.text = ""
	btn.clip_text = false
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 32)
	btn.theme_type_variation = &"SymbolAction"
	btn.tooltip_bbcode = "[b]%s[/b]\n%s" % [title, body]
	btn.tooltip_text = " "

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)

	for entry in icons:
		var kind: CardSymbol.Kind = entry["kind"]
		var count := int(entry.get("count", 1))
		var icon := CardSymbolIcon.new()
		icon.setup(kind, count)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.set_icon_size(18.0)
		row.add_child(icon)

	if not caption.is_empty():
		var lab := Label.new()
		lab.text = caption
		lab.theme_type_variation = &"Caption"
		lab.add_theme_color_override(&"font_color", Palette.INK)
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(lab)

	center.add_child(row)
	btn.add_child(center)
	btn.pressed.connect(on_press)
	return btn


func _dim_if_disabled(btn: Button) -> void:
	if not btn.disabled:
		return
	for child in btn.get_children():
		child.modulate = Color(1, 1, 1, 0.45)
