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
	add_child(_make_eyebrow("ÉTAPE 1 — RAPPORT"))
	add_child(_make_label(
		"Choisis ton rapport — tu es en %d. Deux crans coûtent 1 Heat." % p.gear
	))
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
	_react_cooldown = 0
	_react_boost = false
	_react_adrenaline = false
	var max_cd := p.cooldown_from_gear()
	if p.has_adrenaline:
		max_cd += 1
	var heat_in_hand := p.hand.count_kind(HeatCard.Kind.HEAT)
	# Cooling moves Heat from the hand back into the engine, so the hand caps it.
	var cd_limit := mini(max_cd, heat_in_hand)
	add_child(_make_eyebrow("RÉACTION"))
	add_child(_make_label(
		"Ta vitesse est %d%s" % [p.round_speed, " — ADRÉNALINE" if p.has_adrenaline else ""]
	))

	if cd_limit > 0:
		add_child(_make_cooldown_stepper(cd_limit))
	elif max_cd > 0:
		add_child(_make_label("Refroidir : aucun Heat en main"))

	if p.can_boost_from_gear():
		var boost_btn := _make_check("Boost — 1 Heat, ajoute une carte de vitesse")
		boost_btn.disabled = p.engine_heat() < 1
		boost_btn.toggled.connect(func(on: bool) -> void: _react_boost = on)
		add_child(boost_btn)

	if p.has_adrenaline:
		var ad_btn := _make_check("Adrénaline — +1 Speed")
		ad_btn.toggled.connect(func(on: bool) -> void: _react_adrenaline = on)
		add_child(ad_btn)

	var confirm := _make_button("Réagir", true)
	confirm.pressed.connect(func() -> void:
		action_requested.emit("react", {
			"cooldown": _react_cooldown,
			"boost": _react_boost,
			"adrenaline": _react_adrenaline,
		}, p.id)
	)
	add_child(confirm)


## Cooling is a quantity, not a menu. One stepper replaces one button per amount,
## which used to stack up to four buttons in the panel.
func _make_cooldown_stepper(limit: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var minus := Button.new()
	minus.text = "-"
	minus.custom_minimum_size = Vector2(36, 0)

	var readout := Label.new()
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	readout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	readout.add_theme_font_size_override("font_size", 13)

	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(36, 0)

	var sync := func() -> void:
		readout.text = "Refroidir %d / %d" % [_react_cooldown, limit]
		minus.disabled = _react_cooldown <= 0
		plus.disabled = _react_cooldown >= limit

	minus.pressed.connect(func() -> void:
		_react_cooldown = maxi(0, _react_cooldown - 1)
		sync.call()
	)
	plus.pressed.connect(func() -> void:
		_react_cooldown = mini(limit, _react_cooldown + 1)
		sync.call()
	)

	row.add_child(minus)
	row.add_child(readout)
	row.add_child(plus)
	sync.call()
	return row


## The "what am I being asked to do" line. Sits above the controls, always in the
## same place, so the instruction is never something you have to hunt for.
func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 14)
	return label


## Small uppercase caption naming the current step, above the instruction.
func _make_eyebrow(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = "Eyebrow"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _make_button(text: String, primary: bool = false) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.clip_text = false
	if primary:
		btn.theme_type_variation = "Primary"
	return btn


func _make_check(text: String) -> CheckButton:
	var btn := CheckButton.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.clip_text = false
	return btn
