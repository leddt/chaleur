class_name ActionPanel
extends VBoxContainer

## Builds phase-specific action controls; board / Net handle dispatch.

signal action_requested(action: String, payload: Dictionary, player_id: int)

var _hand: CardHandView
var _sidebar: PlayerSidebar
var _engine: HeatGameEngine

var _react_cooldown: int = 0
var _react_boost: bool = false
var _react_adrenaline: bool = false
var _play_confirm: Button = null
var _play_expected: int = -1
var _play_cluttered: bool = false
var _play_actor_id: int = -1
var _discard_confirm: Button = null


func setup(hand: CardHandView, sidebar: PlayerSidebar) -> void:
	_hand = hand
	_sidebar = sidebar


func is_showing() -> bool:
	return get_child_count() > 0


func reset_drafts() -> void:
	_sidebar.reset_gear_choice()
	_react_cooldown = 0
	_react_boost = false
	_react_adrenaline = false


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
	add_child(_make_label("Choisir le rapport (actuel %d)" % p.gear))
	var confirm := _make_button("Valider le rapport")
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
		hint_text = "Main encombrée : joue toutes les jouables + Heat pour atteindre %d" % required
	else:
		hint_text = "Sélectionne exactement %d carte(s) jouable(s)" % required
	add_child(_make_label(hint_text))
	_play_confirm = _make_button("Jouer la sélection")
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
			add_child(_make_label(
				"Slipstream disponible (+2 cases, n'augmente pas la Speed virage)"
			))
			var yes := _make_button("Slipstream")
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
			add_child(_make_label(
				"Défausse optionnelle (pas Heat/Stress), puis pioche jusqu'à 7"
			))
			_discard_confirm = _make_button("Ne rien défausser")
			_discard_confirm.pressed.connect(func() -> void:
				action_requested.emit("discard", {"card_ids": _hand.selected_ids()}, p.id)
			)
			add_child(_discard_confirm)
			_update_discard_confirm()
		_:
			add_child(_make_label("Résolution automatique…"))


func _discard_button_label(count: int) -> String:
	if count <= 0:
		return "Ne rien défausser"
	if count == 1:
		return "Défausser 1 carte"
	return "Défausser %d cartes" % count


func _update_discard_confirm() -> void:
	if _discard_confirm == null:
		return
	_discard_confirm.text = _discard_button_label(_hand.selected_ids().size())


func _build_react_ui(p: PlayerState) -> void:
	_react_cooldown = 0
	_react_boost = false
	_react_adrenaline = false
	var max_cd := p.cooldown_from_gear()
	if p.has_adrenaline:
		max_cd += 1
	var heat_in_hand := p.hand.count_kind(HeatCard.Kind.HEAT)
	add_child(_make_label(
		"React — speed actuelle %d%s" % [p.round_speed, " — ADRENALINE" if p.has_adrenaline else ""]
	))

	var cd_label := _make_label("Cooldown: 0 (max %d, heat en main %d)" % [max_cd, heat_in_hand])
	add_child(cd_label)
	add_child(_make_label("Choisir le cooldown :"))
	for n in range(0, max_cd + 1):
		if n > heat_in_hand:
			break
		var btn := _make_button("Cooldown %d" % n)
		btn.toggle_mode = true
		btn.button_pressed = n == 0
		btn.pressed.connect(func() -> void:
			_react_cooldown = n
			cd_label.text = "Cooldown: %d (max %d, heat en main %d)" % [n, max_cd, heat_in_hand]
			for child in get_children():
				if child is Button and child.toggle_mode and str(child.text).begins_with("Cooldown "):
					child.button_pressed = (child == btn)
		)
		add_child(btn)

	if p.can_boost_from_gear():
		var boost_btn := _make_check("Boost (1 Heat engine, +Speed carte)")
		boost_btn.disabled = p.engine_heat() < 1
		boost_btn.toggled.connect(func(on: bool) -> void: _react_boost = on)
		add_child(boost_btn)

	if p.has_adrenaline:
		var ad_btn := _make_check("Adrenaline +1 Speed")
		ad_btn.toggled.connect(func(on: bool) -> void: _react_adrenaline = on)
		add_child(ad_btn)

	var confirm := _make_button("Valider React")
	confirm.pressed.connect(func() -> void:
		action_requested.emit("react", {
			"cooldown": _react_cooldown,
			"boost": _react_boost,
			"adrenaline": _react_adrenaline,
		}, p.id)
	)
	add_child(confirm)


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 13)
	return label


func _make_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.clip_text = false
	return btn


func _make_check(text: String) -> CheckButton:
	var btn := CheckButton.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.clip_text = false
	return btn
