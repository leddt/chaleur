extends Control

@onready var _track: TrackView = %TrackView
@onready var _status: Label = %StatusLabel
@onready var _phase: Label = %PhaseLabel
@onready var _log: EventJournal = %EventLog
@onready var _hand: CardHandView = %CardHand
@onready var _actions: ActionPanel = %ActionBox
@onready var _sidebar: PlayerSidebar = %Sidebar
@onready var _hud: PlayersHud = %PlayersHud
@onready var _pass_overlay: ColorRect = %PassOverlay
@onready var _pass_label: Label = %PassLabel
@onready var _finish_overlay: ColorRect = %FinishOverlay
@onready var _finish_label: Label = %FinishLabel
@onready var _reveal_banner: PanelContainer = %RevealBanner
@onready var _reveal_label: Label = %RevealLabel
@onready var _kerb: Kerb = %CockpitKerb

var _engine: HeatGameEngine
var _revealed_seat: int = -1
var _log_cursor: int = 0
## Avoid wiping in-progress local drafts (gear/cards) when another peer's snapshot arrives.
var _ui_context_key: String = ""
var _reveal_tween: Tween
var _last_hand_key: String = ""
var _kerb_scrolling: bool = false


func _ready() -> void:
	# Applied here rather than on the root so the kit's look stays scoped to the
	# board. Without it the cards fall back to Godot's default font and lose the
	# whole printed-cardboard effect.
	theme = ThemeBuilder.build()
	_actions.setup(_hand, _sidebar)
	_actions.action_requested.connect(_dispatch)
	if Game.engine == null and not Game.is_online():
		get_tree().change_scene_to_file("res://ui/local_race_setup.tscn")
		return
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
	_reveal_banner.visible = false
	Net.state_updated.connect(_on_net_state)
	Net.net_error.connect(_on_net_error)
	Net.return_to_lobby_requested.connect(_on_return_to_lobby)
	if _engine != null:
		_refresh_all()
	else:
		_status.text = "En attente de l'état réseau…"
		_sidebar.set_empty()


func _on_net_state() -> void:
	_engine = Game.engine
	if _engine == null:
		_status.text = "Partie réseau terminée"
		_actions.clear()
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
	_hud.refresh(_engine, Game.local_player_id if Game.is_online() else -1)
	_refresh_sidebar()
	_refresh_kerb()
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
		if key == _ui_context_key and _actions.is_showing():
			_update_actor_status(me)
			return
		_ui_context_key = key
		_actions.reset_drafts()
		_build_actions_for(me)
		return
	_ui_context_key = ""
	_actions.reset_drafts()
	_actions.clear()
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
	if player_id < 0 or player_id >= _engine.players.size():
		return "%s|%s|%d" % [str(_engine.phase), str(_engine.turn_step), player_id]
	var p := _engine.players[player_id]
	return "%s|%s|%d|b%d|a%d|c%d|s%d|eh%d|hh%d" % [
		str(_engine.phase),
		str(_engine.turn_step),
		player_id,
		int(p.boost_used),
		int(p.adrenaline_speed_used),
		p.cooldown_used,
		p.round_speed,
		p.engine_heat(),
		p.hand.count_kind(HeatCard.Kind.HEAT),
	]


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
		_actions.clear()
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
	_actions.clear()
	_set_hand([] as Array[HeatCard], false)
	_phase.text = _phase_text()
	_status.text = "En attente de %s" % p.display_name


func _on_pass_continue() -> void:
	var pending := _engine.pending_actor_ids()
	if not pending.is_empty():
		_revealed_seat = pending[0]
	_refresh_all()


func _build_actions_for(actor_id: int) -> void:
	_update_actor_status(actor_id)
	match _engine.phase:
		HeatGameEngine.Phase.SHIFT_GEARS:
			_set_hand(_visible_hand(actor_id), false)
		HeatGameEngine.Phase.PLAY_CARDS:
			var actor := _engine.players[actor_id]
			var cluttered := actor.playable_in_hand().size() < actor.gear
			_set_hand(
				_visible_hand(actor_id),
				true,
				true,
				func(card: HeatCard) -> bool:
					return card.is_playable() or (cluttered and card.kind == HeatCard.Kind.HEAT)
			)
		HeatGameEngine.Phase.PLAYER_TURN:
			if _engine.turn_step == HeatGameEngine.TurnStep.DISCARD:
				_set_hand(
					_visible_hand(actor_id),
					true,
					true,
					func(card: HeatCard) -> bool: return card.can_discard()
				)
			else:
				_set_hand(_visible_hand(actor_id), false)
		_:
			_set_hand(_visible_hand(actor_id), false)
	_actions.build_for(_engine, actor_id)


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
		"boost":
			result = _engine.use_boost(player_id)
		"adrenaline":
			result = _engine.use_adrenaline(player_id)
		"cooldown":
			result = _engine.use_cooldown(player_id)
		"react":
			result = _engine.finish_react(player_id)
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


func _refresh_sidebar() -> void:
	_sidebar.refresh(_engine, _viewer_player())


## The kerb band was pure decoration. It now carries the seat colour of whoever the
## game is waiting on, and scrolls while the engine resolves — so the band answers
## "whose move is it, and is anything happening" without a line of text.
func _refresh_kerb() -> void:
	if _kerb == null or _engine == null:
		return
	var pending := _engine.pending_actor_ids()
	if pending.is_empty():
		# Nobody to act: the race is resolving on its own.
		_kerb.color_a = Palette.MUSTARD
		_kerb.color_b = Palette.INK
		if not _kerb_scrolling:
			_kerb_scrolling = true
			_kerb.animate(70.0)
		return
	if _kerb_scrolling:
		_kerb_scrolling = false
		_kerb.stop_animation()
	_kerb.color_a = PlayerPalette.color_for(pending[0])
	_kerb.color_b = Palette.CARDBOARD


## Player-facing phase name. The engine's own labels are English identifiers and
## have no business appearing in the header.
func _phase_text() -> String:
	match _engine.phase:
		HeatGameEngine.Phase.SHIFT_GEARS:
			return "Choisis ton rapport"
		HeatGameEngine.Phase.PLAY_CARDS:
			return "Joue tes cartes"
		HeatGameEngine.Phase.PLAYER_TURN:
			return _turn_step_fr()
		HeatGameEngine.Phase.RACE_OVER:
			return "Course terminée"
		_:
			return "En course"


func _turn_step_fr() -> String:
	match _engine.turn_step:
		HeatGameEngine.TurnStep.REVEAL_MOVE:
			return "Révélation et déplacement"
		HeatGameEngine.TurnStep.REACT:
			return "Réaction"
		HeatGameEngine.TurnStep.SLIPSTREAM:
			return "Aspiration"
		HeatGameEngine.TurnStep.CHECK_CORNER:
			return "Passage du virage"
		HeatGameEngine.TurnStep.DISCARD:
			return "Défausse"
		HeatGameEngine.TurnStep.REPLENISH:
			return "Réapprovisionnement"
		_:
			return "En course"


func _rebuild_log() -> void:
	_log.clear()
	_log_cursor = 0
	while _log_cursor < _engine.event_log.size():
		_log.append(_engine.event_log[_log_cursor])
		_log_cursor += 1


func _append_new_logs() -> void:
	while _log_cursor < _engine.event_log.size():
		var line: String = _engine.event_log[_log_cursor]
		_log.append(line)
		if JournalFormat.is_reveal_line(line):
			_flash_reveal(JournalFormat.reveal_banner_text(line))
		Sfx.play_for_log_line(line)
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
	var first_show := not _finish_overlay.visible
	_pass_overlay.visible = false
	_finish_overlay.visible = true
	if first_show:
		Sfx.play("podium")
	var lines: PackedStringArray = ["Classement"]
	for p in _engine.ranking():
		lines.append("%d. %s" % [p.finish_rank, p.display_name])
	_finish_label.text = "\n".join(lines)
	_phase.text = "Course terminée"
	_status.text = "Bravo !"
	_actions.clear()
	_set_hand([] as Array[HeatCard], false)
	%FinishLobbyButton.visible = Game.is_online()
	if Game.is_online() and not Net.is_server():
		%RematchButton.text = "En attente de l'hôte…"
		%RematchButton.disabled = true
	else:
		%RematchButton.text = "Rejouer"
		%RematchButton.disabled = false


func _on_hand_selection_changed(_ids: Array[String]) -> void:
	_actions.on_hand_selection_changed()


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
	Game.start_local_race(names, _engine.track.laps, 0, _engine.track.id)
	_engine = Game.engine
	_track.set_engine(_engine, true)
	_revealed_seat = -1
	_ui_context_key = ""
	_last_hand_key = ""
	_sidebar.chosen_gear = 1
	_log_cursor = 0
	_log.clear()
	_refresh_all()
