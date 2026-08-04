class_name CarToken
extends Node2D

## Player car token: rotating body + upright number.
## Place `%NumberAnchor` (Marker2D) on the white circle in the editor —
## it is a child of the sprite so it stays glued when the car scales/rotates.

const TEXTURE_PATH := "res://assets/car.png"
const CAR_LENGTH := 20.0

static var _car_source: Image
static var _tint_cache: Dictionary = {} # String -> Texture2D

@onready var _body: Node2D = %Body
@onready var _sprite: Sprite2D = %Sprite
@onready var _anchor: Marker2D = %NumberAnchor
@onready var _number_host: Node2D = %NumberHost
@onready var _number: Label = %Number
@onready var _finish_ring: Node2D = %FinishRing

var player_id: int = 0


func setup(p_player_id: int) -> void:
	player_id = p_player_id
	var color := PlayerPalette.color_for(player_id)
	var tex := texture_for(color)
	if tex == null:
		return
	_sprite.texture = tex
	var scale_factor := CAR_LENGTH / float(tex.get_width())
	_sprite.scale = Vector2(scale_factor, scale_factor)
	_number.add_theme_font_size_override("font_size", clampi(int(round(CAR_LENGTH * 0.32)), 8, 16))
	_number.add_theme_color_override("font_color", Color(0.08, 0.08, 0.1))
	set_finished(false)
	_apply_number_text(str(player_id + 1))
	_snap_number_to_anchor()


func set_pose(pos: Vector2, heading: Vector2) -> void:
	position = pos
	var dir := heading
	if dir.length_squared() < 0.0001:
		dir = Vector2.RIGHT
	else:
		dir = dir.normalized()
	_body.rotation = dir.angle()
	_snap_number_to_anchor()


func set_finished(finished: bool) -> void:
	_finish_ring.visible = finished
	_apply_number_text("F" if finished else str(player_id + 1))
	_snap_number_to_anchor()


func _apply_number_text(text: String) -> void:
	_number.text = text
	_number.reset_size()
	# Top-left of Label sits at NumberHost origin; offset so text is centered.
	_number.position = -_number.size * 0.5


func _snap_number_to_anchor() -> void:
	# NumberHost is NOT under Body, so it never inherits car rotation.
	_number_host.global_position = _anchor.global_position
	_number_host.global_rotation = 0.0
	_number.rotation = 0.0
	_number.position = -_number.size * 0.5


static func texture_for(player_color: Color) -> Texture2D:
	_ensure_source()
	if _car_source == null:
		return null
	var key := player_color.to_html(false)
	if _tint_cache.has(key):
		return _tint_cache[key] as Texture2D

	var img := _car_source.duplicate() as Image
	for y in img.get_height():
		for x in img.get_width():
			var c: Color = img.get_pixel(x, y)
			if c.a < 0.05:
				continue
			if c.r > 0.82 and c.g > 0.82 and c.b > 0.82:
				img.set_pixel(x, y, Color(1, 1, 1, c.a))
				continue
			var is_body_red := c.r > 0.45 and (c.r - c.g) > 0.2 and (c.r - c.b) > 0.2
			if not is_body_red:
				continue
			var shade: float = clampf(maxf(c.r, maxf(c.g, c.b)), 0.35, 1.0)
			img.set_pixel(
				x,
				y,
				Color(player_color.r * shade, player_color.g * shade, player_color.b * shade, c.a)
			)

	var out := ImageTexture.create_from_image(img)
	_tint_cache[key] = out
	return out


static func _ensure_source() -> void:
	if _car_source != null:
		return
	if not ResourceLoader.exists(TEXTURE_PATH):
		push_warning("CarToken: missing %s" % TEXTURE_PATH)
		return
	var tex := load(TEXTURE_PATH) as Texture2D
	if tex == null:
		return
	_car_source = tex.get_image()
	if _car_source == null:
		return
	if _car_source.is_compressed():
		_car_source.decompress()
