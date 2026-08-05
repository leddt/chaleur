extends Control

## Scene de demonstration. Attache ce script a un Control racine (ancre "Full Rect")
## et lance la scene. Tout est construit en code, donc tu peux tout deplacer sans
## te battre avec l'editeur.

const HAND_SIZE := 7
const FAN_SPREAD := 0.055   # radians entre deux cartes
const FAN_LIFT := 26.0      # creux de l'arc, en pixels

var _hand: Array[Card] = []
var _gauge: HeatGauge
var _selected: Card = null


func _ready() -> void:
	# Applique sur ce Control plutot que sur root : la demo reste isolee et
	# ne repeint pas le reste du jeu si elle est ouverte en cours de partie.
	theme = ThemeBuilder.build()
	_build_background()
	_build_header()
	_build_dashboard()
	_build_hand()
	_build_grain_overlay()
	get_viewport().size_changed.connect(_layout_hand)


# --- Fond ---

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = Palette.ASPHALT
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


# --- En-tete : bande de vibreurs + titre ---

func _build_header() -> void:
	var kerb := Kerb.new()
	kerb.set_anchors_preset(Control.PRESET_TOP_WIDE)
	kerb.offset_bottom = 10
	kerb.stripe_width = 22.0
	kerb.slant = 14.0
	kerb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(kerb)
	kerb.animate(45.0)

	var eyebrow := Label.new()
	eyebrow.theme_type_variation = "Eyebrow"
	eyebrow.text = "T O U R   3   /   C I R C U I T   D E   L T B"
	eyebrow.position = Vector2(40, 34)
	add_child(eyebrow)

	var title := Label.new()
	title.theme_type_variation = "TitleLabel"
	title.text = "CHOISIS TA VITESSE"
	title.position = Vector2(40, 52)
	add_child(title)


# --- Tableau de bord : rapport engage + jauge de chaleur ---

func _build_dashboard() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -300
	panel.offset_right = -40
	panel.offset_top = 40
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var gear_row := HBoxContainer.new()
	gear_row.add_theme_constant_override("separation", 12)
	box.add_child(gear_row)

	var gear_label := Label.new()
	gear_label.theme_type_variation = "Eyebrow"
	gear_label.text = "RAPPORT"
	gear_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gear_row.add_child(gear_label)

	var gear_value := Label.new()
	gear_value.theme_type_variation = "Stat"
	gear_value.text = "3"
	gear_row.add_child(gear_value)

	var heat_label := Label.new()
	heat_label.theme_type_variation = "Eyebrow"
	heat_label.text = "CHALEUR MOTEUR"
	box.add_child(heat_label)

	_gauge = HeatGauge.new()
	_gauge.max_value = 6
	_gauge.value = 2
	box.add_child(_gauge)

	var btn := Button.new()
	btn.text = "Pousser la machine"
	btn.pressed.connect(func() -> void: _gauge.add_heat(1))
	box.add_child(btn)


# --- La main, en eventail ---

func _build_hand() -> void:
	var pool: Array[CardData] = [
		CardData.speed(1),
		CardData.speed(2),
		CardData.heat(),
		CardData.speed(3),
		CardData.speed(4),
		CardData.stress(),
		CardData.speed(2),
	]

	for i in HAND_SIZE:
		var card := Card.new()
		add_child(card)
		card.data = pool[i % pool.size()]
		card.clicked.connect(_on_card_clicked)
		_hand.append(card)

	await get_tree().process_frame
	_layout_hand()


func _layout_hand() -> void:
	if _hand.is_empty():
		return
	var center_x := size.x * 0.5
	var base_y := size.y - Card.SIZE_DEFAULT.y * 0.62
	var mid := float(_hand.size() - 1) * 0.5

	for i in _hand.size():
		var card := _hand[i]
		var offset := float(i) - mid
		var angle := offset * FAN_SPREAD
		var x := center_x + offset * 82.0 - Card.SIZE_DEFAULT.x * 0.5
		var y := base_y + absf(offset) * FAN_LIFT * 0.5

		card.rotation = angle
		card.position.x = x
		card.set_rest_y(y)


func _on_card_clicked(card: Card) -> void:
	if _selected == card:
		card.flip()
		return
	if _selected != null:
		_selected.selected = false
	_selected = card
	card.selected = true


# --- Grain de papier par-dessus tout ---

func _build_grain_overlay() -> void:
	var shader := load("res://shaders/paper_grain.gdshader")
	if shader == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader

	var overlay := ColorRect.new()
	overlay.material = mat
	overlay.color = Color.WHITE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
