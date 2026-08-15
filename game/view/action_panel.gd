class_name ActionPanel
extends VBoxContainer

## Builds phase-specific action controls; board / Net handle dispatch.

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


func setup(hand: CardHandView, sidebar: PlayerSidebar) -> void:
	_hand = hand
	_sidebar = sidebar


func is_showing() -> bool:
	return get_child_count() > 0


func reset_drafts() -> void:
	_sidebar.reset_gear_choice()


func clear() -> void:
	_play_confirm = null
	_play_expected = -1
	_play_cluttered = false
	_play_actor_id = -1
	_discard_confirm = null
	_hand.set_selection_limit(-1)
	for child in get_children():
		child.queue_free()
	_sidebar.set_gear_editable(false)


func build_for(engine: HeatGameEngine, actor_id: int) -> void:
	_engine = engine
	clear()
	var p := engine.players[actor_id]
	match engine.phase:
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


func _build_shift_ui(p: PlayerState) -> void:
	_sidebar.ensure_chosen_gear(p)
	_sidebar.set_gear_editable(true, p)
	add_child(_make_eyebrow("ÉTAPE 1 — RAPPORT"))
	add_child(_make_label("En %d · deux crans = 1 Heat" % p.gear))
	var confirm := _make_button("Engager", true)
	confirm.pressed.connect(func() -> void:
		action_requested.emit("shift_gear", {"gear": _sidebar.chosen_gear}, p.id)
	)
	add_child(confirm)


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
	add_child(_make_eyebrow("ÉTAPE 2 — CARTES"))
	add_child(_make_label(hint_text))
	_play_confirm = _make_button("Jouer", true)
	_play_confirm.disabled = true
	_play_confirm.pressed.connect(func() -> void:
		action_requested.emit("play_cards", {"card_ids": _hand.selected_ids()}, p.id)
	)
	add_child(_play_confirm)
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
		HeatGameEngine.TurnStep.REACT:
			_build_react_ui(p)
		HeatGameEngine.TurnStep.SLIPSTREAM:
			add_child(_make_eyebrow("ASPIRATION"))
			add_child(_make_label(
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
			add_child(yes)
			add_child(no)
		HeatGameEngine.TurnStep.DISCARD:
			add_child(_make_eyebrow("FIN DE TOUR"))
			add_child(_make_label(
				"Défausse optionnelle (pas Heat/Stress), puis pioche jusqu'à 7"
			))
			_discard_confirm = _make_button("Passer la défausse", true)
			_discard_confirm.pressed.connect(func() -> void:
				action_requested.emit("discard", {"card_ids": _hand.selected_ids()}, p.id)
			)
			add_child(_discard_confirm)
			_update_discard_confirm()
		_:
			add_child(_make_label("La course avance…"))


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


func _build_react_ui(p: PlayerState) -> void:
	_react_player_id = p.id
	add_child(_make_eyebrow("RÉACTION"))
	add_child(_make_label(
		"Ta vitesse est %d%s" % [p.round_speed, " — ADRÉNALINE" if p.has_adrenaline else ""]
	))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)

	var ad_btn := _make_button("Adrénaline · +1 vitesse", false, true)
	ad_btn.disabled = not p.can_use_adrenaline()
	ad_btn.pressed.connect(func() -> void:
		action_requested.emit("adrenaline", {}, p.id)
	)
	grid.add_child(ad_btn)

	var boost_btn := _make_button("Boost · +1 carte", false, true)
	boost_btn.disabled = not p.can_use_boost()
	boost_btn.pressed.connect(func() -> void:
		action_requested.emit("boost", {}, p.id)
	)
	grid.add_child(boost_btn)

	var remaining := p.cooldown_remaining()
	var cd_btn := _make_button("Cooldown (%d) · Remet un heat" % remaining, false, true)
	cd_btn.disabled = not p.can_use_cooldown()
	cd_btn.pressed.connect(func() -> void:
		action_requested.emit("cooldown", {}, p.id)
	)
	grid.add_child(cd_btn)

	var finish := _make_button("Terminer", true)
	finish.pressed.connect(_on_finish_react_pressed.bind(p.id))
	grid.add_child(finish)
	add_child(grid)


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
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.theme_type_variation = "Caption"
	return label


## Small uppercase caption naming the current step, above the instruction.
func _make_eyebrow(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = "Eyebrow"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
