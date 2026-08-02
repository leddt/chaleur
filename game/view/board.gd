extends Control

const PLAYER_COLORS := TrackView.PLAYER_COLORS
const GEAR_ACTIVE := Color(0.45, 1.0, 0.45)
const GEAR_NORMAL := Color(0.85, 0.88, 0.9)

@onready var _track: TrackView = %TrackView
@onready var _status: Label = %StatusLabel
@onready var _phase: Label = %PhaseLabel
@onready var _log: RichTextLabel = %EventLog
@onready var _hand: CardHandView = %CardHand
@onready var _action_box: VBoxContainer = %ActionBox
@onready var _pass_overlay: ColorRect = %PassOverlay
@onready var _pass_label: Label = %PassLabel
@onready var _finish_overlay: ColorRect = %FinishOverlay
@onready var _finish_label: Label = %FinishLabel
@onready var _hud_players: HBoxContainer = %PlayersHud
@onready var _reveal_banner: PanelContainer = %RevealBanner
@onready var _reveal_label: Label = %RevealLabel
@onready var _corner_dist: Label = %CornerDistLabel
@onready var _heat_value: Label = %HeatValue
@onready var _draw_value: Label = %DrawValue
@onready var _discard_value: Label = %DiscardValue

var _gear_buttons: Array[Button] = []

var _engine: HeatGameEngine
var _revealed_seat: int = -1
var _chosen_gear: int = 1
var _react_cooldown: int = 0
var _react_boost: bool = false
var _react_adrenaline: bool = false
var _log_cursor: int = 0
## Avoid wiping in-progress local drafts (gear/cards) when another peer's snapshot arrives.
var _ui_context_key: String = ""
var _reveal_tween: Tween
var _last_hand_key: String = ""
var _gear_editable: bool = false
var _play_confirm: Button = null
var _play_expected: int = -1
var _play_cluttered: bool = false
var _play_actor_id: int = -1
var _discard_confirm: Button = null


func _ready() -> void:
	_gear_buttons = [
		%Gear1Button as Button,
		%Gear2Button as Button,
		%Gear3Button as Button,
		%Gear4Button as Button,
	]
	if Game.engine == null and not Game.is_online():
		Game.start_local_race()
	_engine = Game.engine
	if _engine != null:
		_track.set_engine(_engine, true)
	_hand.selection_changed.connect(_on_hand_selection_changed)
	%PassContinueButton.pressed.connect(_on_pass_continue)
	%MenuButton.pressed.connect(_on_menu)
	%FinishMenuButton.pressed.connect(_on_menu)
	%RematchButton.pressed.connect(_on_rematch)
	%LobbyButton.pressed.connect(_on_lobby)
	%FinishLobbyButton.pressed.connect(_on_lobby)
	for i in range(_gear_buttons.size()):
		var gear := i + 1
		_gear_buttons[i].pressed.connect(_on_gear_pressed.bind(gear))
	_reveal_banner.visible = false
	Net.state_updated.connect(_on_net_state)
	Net.net_error.connect(_on_net_error)
	Net.return_to_lobby_requested.connect(_on_return_to_lobby)
	if _engine != null:
		_refresh_all()
	else:
		_status.text = "En attente de l'état réseau…"
		_refresh_sidebar_empty()


func _on_net_state() -> void:
	_engine = Game.engine
	if _engine == null:
		_status.text = "Partie réseau terminée"
		_clear_actions()
		_track.set_engine(null, true)
		return
	# New engine instance every snapshot — keep visual positions so moves can tween.
	# Snap only on first bind or fresh race (tiny log), never after cars have moved.
	var snap := _track.engine == null
	if not snap and _engine.event_log.size() <= 2:
		var max_prog := 0
		for p in _engine.players:
			max_prog = maxi(max_prog, p.progress)
		snap = max_prog == 0
	_track.set_engine(_engine, snap)
	_rebuild_log()
	_refresh_all()


func _on_net_error(message: String) -> void:
	_status.text = message


func _on_return_to_lobby() -> void:
	Game.engine = null
	get_tree().change_scene_to_file("res://ui/lobby.tscn")


func _refresh_all() -> void:
	if _engine == null:
		return
	if _log_cursor == 0 and _engine.event_log.size() > 0:
		_rebuild_log()
	else:
		_append_new_logs()
	_refresh_hud()
	_refresh_sidebar()
	_track.refresh(true)
	if _engine.is_race_over():
		_show_finish()
		return
	_finish_overlay.visible = false
	%RematchButton.disabled = false
	%RematchButton.text = "Rejouer"

	if Game.is_online():
		_refresh_online()
	else:
		_refresh_hotseat()
	_refresh_sidebar()


func _refresh_online() -> void:
	_pass_overlay.visible = false
	%LobbyButton.visible = true
	var pending := _engine.pending_actor_ids()
	var me := Game.local_player_id
	if me >= 0 and me in pending:
		var key := _action_context_key(me)
		# Same action context: keep draft UI (e.g. gear chosen but not confirmed).
		if key == _ui_context_key and _action_box.get_child_count() > 0:
			_update_actor_status(me)
			return
		_ui_context_key = key
		_reset_action_drafts()
		_build_actions_for(me)
		return
	_ui_context_key = ""
	_reset_action_drafts()
	_clear_actions()
	_set_hand(_visible_hand(me), false)
	_phase.text = _phase_text()
	if pending.is_empty():
		_status.text = "En attente de résolution…"
	else:
		var names: PackedStringArray = []
		for pid in pending:
			names.append(_engine.players[pid].display_name)
		_status.text = "En attente de: %s" % ", ".join(names)


func _action_context_key(player_id: int) -> String:
	return "%s|%s|%d" % [str(_engine.phase), str(_engine.turn_step), player_id]


func _reset_action_drafts() -> void:
	_chosen_gear = -1
	_react_cooldown = 0
	_react_boost = false
	_react_adrenaline = false


func _update_actor_status(actor_id: int) -> void:
	var p := _engine.players[actor_id]
	_phase.text = _phase_text()
	var finish_note := " — ARRIVÉ (termine ton tour)" if p.finished else ""
	_status.text = "%s%s" % [p.display_name, finish_note]


func _refresh_hotseat() -> void:
	%LobbyButton.visible = false
	var pending := _engine.pending_actor_ids()
	if pending.is_empty():
		_pass_overlay.visible = false
		_clear_actions()
		_set_hand([] as Array[HeatCard], false)
		_status.text = "En attente de résolution… (personne à jouer — possible softlock)"
		return
	var actor_id := pending[0]
	if _revealed_seat != actor_id:
		_show_pass(actor_id)
		return
	_pass_overlay.visible = false
	_build_actions_for(actor_id)


func _show_pass(actor_id: int) -> void:
	_pass_overlay.visible = true
	var p := _engine.players[actor_id]
	_pass_label.text = "Passez l'appareil à %s\n(ne regardez pas la main des autres)" % p.display_name
	_clear_actions()
	_set_hand([] as Array[HeatCard], false)
	_phase.text = _phase_text()
	_status.text = "En attente de %s" % p.display_name


func _on_pass_continue() -> void:
	var pending := _engine.pending_actor_ids()
	if not pending.is_empty():
		_revealed_seat = pending[0]
	_refresh_all()


func _build_actions_for(actor_id: int) -> void:
	_clear_actions()
	var p := _engine.players[actor_id]
	_update_actor_status(actor_id)
	match _engine.phase:
		HeatGameEngine.Phase.SHIFT_GEARS:
			_set_hand(_visible_hand(actor_id), false)
			_build_shift_ui(p)
		HeatGameEngine.Phase.PLAY_CARDS:
			_set_gear_editable(false, p)
			_set_hand(_visible_hand(actor_id), true, true)
			_build_play_ui(p)
		HeatGameEngine.Phase.PLAYER_TURN:
			_set_gear_editable(false, p)
			if _engine.turn_step == HeatGameEngine.TurnStep.DISCARD:
				_set_hand(
					_visible_hand(actor_id),
					true,
					true,
					func(card: HeatCard) -> bool: return card.can_discard()
				)
			else:
				_set_hand(_visible_hand(actor_id), false)
			_build_turn_ui(p)
		_:
			_set_gear_editable(false, p)


func _set_hand(
	cards: Array[HeatCard],
	enabled: bool,
	multi_select: bool = true,
	can_select: Callable = Callable()
) -> void:
	var key := "%s|%s|%d" % [str(_engine.phase), str(_engine.turn_step), cards.size()]
	for c in cards:
		key += "|" + c.id
	var animate := key != _last_hand_key and not cards.is_empty()
	_last_hand_key = key
	_hand.set_cards(cards, enabled, multi_select, animate, can_select)


func _visible_hand(player_id: int) -> Array[HeatCard]:
	if player_id < 0 or player_id >= _engine.players.size():
		return []
	var out: Array[HeatCard] = []
	for card in _engine.players[player_id].hand.cards:
		if card.id.begins_with("hidden_"):
			continue
		out.append(card)
	return out


func _make_action_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 13)
	return label


func _make_action_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.clip_text = false
	return btn


func _make_action_check(text: String) -> CheckButton:
	var btn := CheckButton.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.clip_text = false
	return btn


func _build_shift_ui(p: PlayerState) -> void:
	if _chosen_gear < 1 or _chosen_gear > 4 or absi(_chosen_gear - p.gear) > 2:
		_chosen_gear = p.gear
	_set_gear_editable(true, p)
	_action_box.add_child(_make_action_label("Choisir le rapport (actuel %d)" % p.gear))
	var confirm := _make_action_button("Valider le rapport")
	confirm.pressed.connect(func() -> void:
		_dispatch("shift_gear", {"gear": _chosen_gear}, p.id)
	)
	_action_box.add_child(confirm)


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
	_action_box.add_child(_make_action_label(hint_text))
	_play_confirm = _make_action_button("Jouer la sélection")
	_play_confirm.disabled = true
	_play_confirm.pressed.connect(func() -> void:
		_dispatch("play_cards", {"card_ids": _hand.selected_ids()}, p.id)
	)
	_action_box.add_child(_play_confirm)
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
			_action_box.add_child(_make_action_label(
				"Slipstream disponible (+2 cases, n'augmente pas la Speed virage)"
			))
			var yes := _make_action_button("Slipstream")
			yes.pressed.connect(func() -> void:
				_dispatch("slipstream", {"use": true}, p.id)
			)
			var no := _make_action_button("Non")
			no.pressed.connect(func() -> void:
				_dispatch("slipstream", {"use": false}, p.id)
			)
			_action_box.add_child(yes)
			_action_box.add_child(no)
		HeatGameEngine.TurnStep.DISCARD:
			_action_box.add_child(_make_action_label(
				"Défausse optionnelle (pas Heat/Stress), puis pioche jusqu'à 7"
			))
			_discard_confirm = _make_action_button("Ne rien défausser")
			_discard_confirm.pressed.connect(func() -> void:
				_dispatch("discard", {"card_ids": _hand.selected_ids()}, p.id)
			)
			_action_box.add_child(_discard_confirm)
			_update_discard_confirm()
		_:
			_action_box.add_child(_make_action_label("Résolution automatique…"))


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
	_action_box.add_child(_make_action_label(
		"React — speed actuelle %d%s" % [p.round_speed, " — ADRENALINE" if p.has_adrenaline else ""]
	))

	var cd_label := _make_action_label("Cooldown: 0 (max %d, heat en main %d)" % [max_cd, heat_in_hand])
	_action_box.add_child(cd_label)
	_action_box.add_child(_make_action_label("Choisir le cooldown :"))
	for n in range(0, max_cd + 1):
		if n > heat_in_hand:
			break
		var btn := _make_action_button("Cooldown %d" % n)
		btn.toggle_mode = true
		btn.button_pressed = n == 0
		btn.pressed.connect(func() -> void:
			_react_cooldown = n
			cd_label.text = "Cooldown: %d (max %d, heat en main %d)" % [n, max_cd, heat_in_hand]
			for child in _action_box.get_children():
				if child is Button and child.toggle_mode and str(child.text).begins_with("Cooldown "):
					child.button_pressed = (child == btn)
		)
		_action_box.add_child(btn)

	if p.can_boost_from_gear():
		var boost_btn := _make_action_check("Boost (1 Heat engine, +Speed carte)")
		boost_btn.disabled = p.engine_heat() < 1
		boost_btn.toggled.connect(func(on: bool) -> void: _react_boost = on)
		_action_box.add_child(boost_btn)

	if p.has_adrenaline:
		var ad_btn := _make_action_check("Adrenaline +1 Speed")
		ad_btn.toggled.connect(func(on: bool) -> void: _react_adrenaline = on)
		_action_box.add_child(ad_btn)

	var confirm := _make_action_button("Valider React")
	confirm.pressed.connect(func() -> void:
		_dispatch("react", {
			"cooldown": _react_cooldown,
			"boost": _react_boost,
			"adrenaline": _react_adrenaline,
		}, p.id)
	)
	_action_box.add_child(confirm)


func _dispatch(action: String, payload: Dictionary, player_id: int) -> void:
	if Game.is_online():
		Net.submit_action(action, payload)
		return
	var result: ActionResult
	match action:
		"shift_gear":
			result = _engine.shift_gear(player_id, int(payload.get("gear", 1)))
		"play_cards":
			var ids: Array[String] = []
			for id in payload.get("card_ids", []):
				ids.append(str(id))
			result = _engine.play_cards(player_id, ids)
		"react":
			result = _engine.react(
				player_id,
				int(payload.get("cooldown", 0)),
				bool(payload.get("boost", false)),
				bool(payload.get("adrenaline", false))
			)
		"slipstream":
			result = _engine.slipstream(player_id, bool(payload.get("use", false)))
		"discard":
			var dids: Array[String] = []
			for id in payload.get("card_ids", []):
				dids.append(str(id))
			result = _engine.discard_cards(player_id, dids)
		_:
			result = ActionResult.fail("Unknown action")
	_handle_local_result(result)


func _handle_local_result(result: ActionResult) -> void:
	if not result.ok:
		_status.text = "Action refusée: %s" % result.error
		return
	var pending := _engine.pending_actor_ids()
	if pending.is_empty() or pending[0] != _revealed_seat:
		_revealed_seat = -1
	_hand.clear_selection()
	_refresh_all()


func _clear_actions() -> void:
	_play_confirm = null
	_play_expected = -1
	_play_cluttered = false
	_play_actor_id = -1
	_discard_confirm = null
	_hand.set_selection_limit(-1)
	for child in _action_box.get_children():
		child.queue_free()
	_set_gear_editable(false)


func _on_gear_pressed(gear: int) -> void:
	if not _gear_editable:
		_sync_gear_buttons()
		return
	var viewer := _viewer_player()
	if viewer == null:
		return
	if absi(gear - viewer.gear) > 2:
		_sync_gear_buttons()
		return
	_chosen_gear = gear
	_sync_gear_buttons()


func _set_gear_editable(editable: bool, player: PlayerState = null) -> void:
	_gear_editable = editable
	var p := player if player != null else _viewer_player()
	for i in range(_gear_buttons.size()):
		var gear := i + 1
		var btn := _gear_buttons[i]
		var delta := 0 if p == null else absi(gear - p.gear)
		btn.disabled = not editable or p == null or delta > 2
		if editable and p != null and delta == 2:
			btn.text = "Gear %d (1 Heat)" % gear
		else:
			btn.text = "Gear %d" % gear
	_sync_gear_buttons()


func _sync_gear_buttons() -> void:
	var shown := _chosen_gear
	if shown < 1:
		var p := _viewer_player()
		shown = p.gear if p != null else 1
	for i in range(_gear_buttons.size()):
		var btn := _gear_buttons[i]
		var on := (i + 1) == shown
		btn.set_pressed_no_signal(on)
		_apply_gear_button_color(btn, GEAR_ACTIVE if on else GEAR_NORMAL)


func _apply_gear_button_color(btn: Button, color: Color) -> void:
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_color_override("font_pressed_color", color)
	btn.add_theme_color_override("font_hover_color", color)
	btn.add_theme_color_override("font_hover_pressed_color", color)
	btn.add_theme_color_override("font_focus_color", color)
	btn.add_theme_color_override("font_disabled_color", color)


func _viewer_player_id() -> int:
	if _engine == null:
		return -1
	if Game.is_online():
		return Game.local_player_id
	if _revealed_seat >= 0:
		return _revealed_seat
	var pending := _engine.pending_actor_ids()
	if not pending.is_empty():
		return pending[0]
	return 0 if not _engine.players.is_empty() else -1


func _viewer_player() -> PlayerState:
	var id := _viewer_player_id()
	if id < 0 or id >= _engine.players.size():
		return null
	return _engine.players[id]


func _refresh_sidebar_empty() -> void:
	_corner_dist.text = "Distance au prochain virage: —"
	_heat_value.text = "—"
	_draw_value.text = "—"
	_discard_value.text = "—"
	_chosen_gear = 1
	_set_gear_editable(false)


func _refresh_sidebar() -> void:
	if _engine == null:
		_refresh_sidebar_empty()
		return
	var p := _viewer_player()
	if p == null:
		_refresh_sidebar_empty()
		return
	var dist := _engine.track.distance_to_next_corner(p.progress)
	if p.finished or dist < 0:
		_corner_dist.text = "Distance au prochain virage: —"
	else:
		_corner_dist.text = "Distance au prochain virage: %d" % dist
	_heat_value.text = str(p.engine_heat())
	_draw_value.text = str(p.draw_pile.size())
	_discard_value.text = str(p.discard.size())
	if not _gear_editable:
		_chosen_gear = p.gear
		_set_gear_editable(false, p)
	else:
		_sync_gear_buttons()


func _refresh_hud() -> void:
	for child in _hud_players.get_children():
		child.queue_free()
	var pending := _engine.pending_actor_ids()
	for p in _engine.players:
		var row := Label.new()
		var col := PLAYER_COLORS[p.id % PLAYER_COLORS.size()]
		var mark := _ready_mark(p, pending)
		var fin := ""
		if p.finished:
			if p.finish_rank > 0:
				fin = " FIN#%d" % p.finish_rank
			else:
				fin = " FIN"
		var you := " (toi)" if Game.is_online() and p.id == Game.local_player_id else ""
		row.text = "%s %s%s | G%d H%d P%d%s" % [
			mark,
			p.display_name,
			you,
			p.gear,
			p.engine_heat(),
			p.progress,
			fin,
		]
		row.add_theme_color_override("font_color", col)
		row.add_theme_font_size_override("font_size", 13)
		_hud_players.add_child(row)


func _ready_mark(p: PlayerState, pending: Array[int]) -> String:
	match _engine.phase:
		HeatGameEngine.Phase.SHIFT_GEARS:
			return "✓" if p.gear_locked else "…"
		HeatGameEngine.Phase.PLAY_CARDS:
			return "✓" if p.cards_locked else "…"
		HeatGameEngine.Phase.PLAYER_TURN:
			if p.id in pending:
				return "▶"
			return "·"
		_:
			return "·"


func _phase_text() -> String:
	match _engine.phase:
		HeatGameEngine.Phase.SHIFT_GEARS:
			return "1. Shift Gears — choisissez un rapport"
		HeatGameEngine.Phase.PLAY_CARDS:
			return "2. Play Cards — jouez autant de cartes que le rapport"
		HeatGameEngine.Phase.PLAYER_TURN:
			return "3–9. Tour — %s" % _turn_step_fr()
		HeatGameEngine.Phase.RACE_OVER:
			return "Course terminée"
		_:
			return "Phase: %s" % str(_engine.phase)


func _turn_step_fr() -> String:
	match _engine.turn_step:
		HeatGameEngine.TurnStep.REVEAL_MOVE:
			return "Reveal & Move"
		HeatGameEngine.TurnStep.REACT:
			return "React"
		HeatGameEngine.TurnStep.SLIPSTREAM:
			return "Slipstream"
		HeatGameEngine.TurnStep.CHECK_CORNER:
			return "Check Corner"
		HeatGameEngine.TurnStep.DISCARD:
			return "Discard"
		HeatGameEngine.TurnStep.REPLENISH:
			return "Replenish"
		_:
			return str(_engine.turn_step)


func _rebuild_log() -> void:
	_log.clear()
	_log_cursor = 0
	while _log_cursor < _engine.event_log.size():
		_log.append_text(JournalFormat.to_bbcode(_engine.event_log[_log_cursor]))
		_log_cursor += 1


func _append_new_logs() -> void:
	while _log_cursor < _engine.event_log.size():
		var line: String = _engine.event_log[_log_cursor]
		_log.append_text(JournalFormat.to_bbcode(line))
		if JournalFormat.is_reveal_line(line):
			_flash_reveal(JournalFormat.reveal_banner_text(line))
		_log_cursor += 1


func _flash_reveal(text: String) -> void:
	_reveal_label.text = text
	_reveal_banner.visible = true
	_reveal_banner.modulate.a = 1.0
	if _reveal_tween != null:
		_reveal_tween.kill()
	_reveal_tween = create_tween()
	_reveal_tween.tween_interval(1.4)
	_reveal_tween.tween_property(_reveal_banner, "modulate:a", 0.0, 0.35)
	_reveal_tween.tween_callback(func() -> void:
		_reveal_banner.visible = false
		_reveal_banner.modulate.a = 1.0
	)


func _show_finish() -> void:
	_pass_overlay.visible = false
	_finish_overlay.visible = true
	var lines: PackedStringArray = ["Classement"]
	for p in _engine.ranking():
		lines.append("%d. %s" % [p.finish_rank, p.display_name])
	_finish_label.text = "\n".join(lines)
	_phase.text = "Course terminée"
	_status.text = "Bravo !"
	_clear_actions()
	_set_hand([] as Array[HeatCard], false)
	%FinishLobbyButton.visible = Game.is_online()
	if Game.is_online() and not Net.is_server():
		%RematchButton.text = "En attente de l'hôte…"
		%RematchButton.disabled = true
	else:
		%RematchButton.text = "Rejouer"
		%RematchButton.disabled = false


func _on_hand_selection_changed(_ids: Array[String]) -> void:
	_update_play_confirm()
	_update_discard_confirm()


func _on_menu() -> void:
	if Game.is_online():
		Net.leave()
	Game.clear_race()
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")


func _on_lobby() -> void:
	if Game.is_online():
		Net.request_return_to_lobby()
		return
	Game.clear_race()
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")


func _on_rematch() -> void:
	if Game.is_online():
		if Net.is_server():
			_ui_context_key = ""
			_last_hand_key = ""
			_log_cursor = 0
			_log.clear()
			Net.request_rematch()
		return
	var names: Array[String] = []
	for p in _engine.players:
		names.append(p.display_name)
	Game.start_local_race(names, _engine.track.laps)
	_engine = Game.engine
	_track.set_engine(_engine, true)
	_revealed_seat = -1
	_ui_context_key = ""
	_last_hand_key = ""
	_chosen_gear = 1
	_log_cursor = 0
	_log.clear()
	_refresh_all()
