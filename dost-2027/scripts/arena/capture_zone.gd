extends Node2D

# A glowing box Mayari lights up. Stand inside it and it banks FAVOR over time -
# "king of the hill" style, while her clones sweep the field.

const ICON := preload("res://icon.svg")
const ZONE_FONT := preload("res://Assets/fonts/Minecraftia-Regular.ttf")

var box_size := Vector2(132, 96)
var rate := 35.0  # FAVOR per second while held (current, after modifiers)
var base_rate := 35.0  # the rate this corner was created with
var color := Color(0.55, 0.85, 1.0)
var zone_label := ""
var is_far := false
var held := false

var _pulse := 0.0


func setup(center: Vector2, size_value: Vector2, zone_rate: float, zone_color: Color, label_text: String, far: bool) -> void:
	position = center
	box_size = size_value
	rate = zone_rate
	base_rate = zone_rate
	color = zone_color
	zone_label = label_text
	is_far = far
	queue_redraw()


# Mayari can dim or bless her corners mid-trial.
func set_rate_multiplier(multiplier: float) -> void:
	rate = base_rate * multiplier
	queue_redraw()


func bounds() -> Rect2:
	return Rect2(global_position - box_size * 0.5, box_size)


func contains(point: Vector2) -> bool:
	return bounds().has_point(point)


func _process(delta: float) -> void:
	_pulse += delta
	queue_redraw()


func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_pulse * 3.0 + (1.7 if is_far else 0.0))
	var half := box_size * 0.5
	var box := Rect2(-half, box_size)

	var fill_alpha := (0.32 if held else 0.13) + 0.08 * pulse
	draw_rect(box, Color(color.r, color.g, color.b, fill_alpha), true)
	draw_rect(box.grow(-8.0), Color(color.r, color.g, color.b, 0.10 + 0.08 * pulse), true)

	var border_alpha := 0.55 + 0.45 * pulse
	draw_rect(box, Color(color.r, color.g, color.b, border_alpha), false, 3.0)

	var icon_alpha := 0.28 + 0.20 * pulse
	draw_texture_rect(ICON, Rect2(Vector2(-16, -16), Vector2(32, 32)), false, Color(1, 1, 1, icon_alpha))

	if zone_label != "":
		draw_string(ZONE_FONT, Vector2(-half.x, -half.y - 10.0), zone_label,
			HORIZONTAL_ALIGNMENT_CENTER, box_size.x, 12, Color(color.r, color.g, color.b, 0.9))
	if rate > 0.0:
		draw_string(ZONE_FONT, Vector2(-half.x, half.y + 20.0), "%d FAVOR/s" % int(rate),
			HORIZONTAL_ALIGNMENT_CENTER, box_size.x, 10, Color(1, 1, 1, 0.55))
