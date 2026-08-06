@tool
class_name HeatGauge
extends Control

## Jauge de chaleur du moteur. Segments dessines, couleur derivee du ratio.
## Remplace avantageusement une barre de progression texturee : elle se lit
## d'un coup d'oeil et se recolorie toute seule.

@export var value: int = 0:
	set(v):
		value = clampi(v, 0, max_value)
		queue_redraw()

@export var max_value: int = 6:
	set(v):
		max_value = maxi(1, v)
		value = clampi(value, 0, max_value)
		queue_redraw()

@export var segment_gap: float = 4.0:
	set(v):
		segment_gap = v
		queue_redraw()

## Quand la valeur est une reserve qui se vide (la chaleur moteur de Chaleur, par
## exemple), c'est le vide qui est dangereux, pas le plein. La rampe de couleur
## s'inverse : jauge pleine = froid, jauge presque vide = rouge.
@export var danger_when_empty: bool = false:
	set(v):
		danger_when_empty = v
		queue_redraw()

var _pulse := 0.0


## 0.0 = tout va bien, 1.0 = moteur au bout du rouleau.
func danger_ratio() -> float:
	var filled := float(value) / float(max_value)
	return 1.0 - filled if danger_when_empty else filled


func _ready() -> void:
	# Taille de repli seulement : une scene qui fixe la sienne la garde.
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(220, 34)
	set_process(true)


func _process(delta: float) -> void:
	# Le dernier segment pulse quand le moteur est dans le rouge.
	if danger_ratio() >= 0.83:
		_pulse = fmod(_pulse + delta * 3.0, TAU)
		queue_redraw()
	elif _pulse != 0.0:
		_pulse = 0.0
		queue_redraw()


func _draw() -> void:
	var seg_w := (size.x - segment_gap * float(max_value - 1)) / float(max_value)
	# En mode reserve, tous les segments partagent la couleur du niveau courant :
	# c'est la barre entiere qui vire au rouge en se vidant, pas un segment isole.
	var danger := danger_ratio()
	for i in max_value:
		var r := Rect2(float(i) * (seg_w + segment_gap), 0.0, seg_w, size.y)
		var filled := i < value
		if filled:
			var col := Palette.heat_color(
				danger if danger_when_empty else float(i + 1) / float(max_value)
			)
			if i == value - 1 and _pulse != 0.0:
				col = col.lerp(Palette.CARDBOARD, 0.25 + 0.25 * sin(_pulse))
			draw_rect(r, col)
		else:
			draw_rect(r, Palette.INK)
			draw_rect(r, Palette.SMOKE * Color(1, 1, 1, 0.5), false, 1.0)


## Anime la montee de chaleur. A appeler quand le joueur pousse la machine.
func add_heat(amount: int = 1) -> void:
	var target := clampi(value + amount, 0, max_value)
	var tween := create_tween()
	tween.tween_method(func(v: int) -> void: value = v, value, target, 0.25 * float(absi(amount)))
