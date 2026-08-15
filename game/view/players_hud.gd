class_name PlayersHud
extends HBoxContainer

## Header chips in this round's turn order. P1/P2 labels follow live race place.

const REORDER_SEC := 0.64
const CHIP_SCENE := preload("res://view/player_chip.tscn")

var _slots: Dictionary = {} ## player_id -> slot Control
var _order_ids: Array[int] = []
var _reorder_gen := 0


func refresh(engine: HeatGameEngine, local_player_id: int = -1) -> void:
	if engine == null:
		_clear_chips()
		return
	clip_contents = false
	var pending := engine.pending_actor_ids()
	var old_visual: Dictionary = {}
	for id in _slots.keys():
		var slot: Control = _slots[id]
		var chip: Control = slot.get_meta("chip")
		if is_instance_valid(chip):
			old_visual[id] = chip.global_position
	var seen: Dictionary = {}
	var new_order: Array[int] = []
	var index := 0
	for p in engine.round_order():
		seen[p.id] = true
		new_order.append(p.id)
		var slot := _slots.get(p.id) as Control
		if slot == null or not is_instance_valid(slot):
			var chip := CHIP_SCENE.instantiate()
			slot = _wrap_slot(chip)
			_slots[p.id] = slot
			add_child(slot)
			chip.apply(engine, p, engine.race_place(p.id), pending, local_player_id, false)
		else:
			var chip = slot.get_meta("chip")
			chip.apply(engine, p, engine.race_place(p.id), pending, local_player_id, true)
		move_child(slot, index)
		index += 1
	var stale: Array = []
	for id in _slots.keys():
		if not seen.has(id):
			stale.append(id)
	for id in stale:
		var old: Control = _slots[id]
		_slots.erase(id)
		if is_instance_valid(old):
			old.queue_free()
	var order_changed := not _ids_equal(_order_ids, new_order)
	_order_ids = new_order
	if order_changed and not old_visual.is_empty():
		_queue_reorder(old_visual)


func _wrap_slot(chip: Control) -> Control:
	var slot := Control.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.set_meta("chip", chip)
	chip.resized.connect(func() -> void: _fit_slot(slot, chip))
	slot.add_child(chip)
	_fit_slot(slot, chip)
	return slot


func _fit_slot(slot: Control, chip: Control) -> void:
	if not is_instance_valid(slot) or not is_instance_valid(chip):
		return
	var ms := chip.get_combined_minimum_size()
	if chip.size.x > ms.x:
		ms.x = chip.size.x
	if chip.size.y > ms.y:
		ms.y = chip.size.y
	slot.custom_minimum_size = ms


func _ids_equal(a: Array[int], b: Array[int]) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true


func _queue_reorder(old_visual: Dictionary) -> void:
	_reorder_gen += 1
	var gen := _reorder_gen
	_play_reorder.call_deferred(old_visual, gen)


func _play_reorder(old_visual: Dictionary, gen: int) -> void:
	if gen != _reorder_gen:
		return
	for id in _slots.keys():
		if not old_visual.has(id):
			continue
		var slot: Control = _slots[id]
		if not is_instance_valid(slot):
			continue
		var chip: Control = slot.get_meta("chip")
		if not is_instance_valid(chip):
			continue
		var dest := slot.global_position
		var start: Vector2 = old_visual[id]
		var delta := start - dest
		_kill_move_tween(chip)
		if delta.length() < 0.5:
			chip.position = Vector2.ZERO
			continue
		chip.position = delta
		chip.z_index = 2
		var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		chip.set_meta("move_tween", tw)
		tw.tween_property(chip, "position", Vector2.ZERO, REORDER_SEC)
		tw.tween_callback(
			func() -> void:
				if is_instance_valid(chip):
					chip.z_index = 0
		)


func _kill_move_tween(chip: Control) -> void:
	if not chip.has_meta("move_tween"):
		return
	var tw: Tween = chip.get_meta("move_tween")
	if tw != null and is_instance_valid(tw):
		tw.kill()
	chip.remove_meta("move_tween")


func _clear_chips() -> void:
	_reorder_gen += 1
	_order_ids.clear()
	for id in _slots.keys():
		var slot: Control = _slots[id]
		if is_instance_valid(slot):
			slot.queue_free()
	_slots.clear()
	for child in get_children():
		child.queue_free()


