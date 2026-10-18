@tool
class_name PixelStyleBox
extends StyleBox

# Placeholder art for every panel and button in bathala_theme.tres, until the
# artist's 9-slices (UI/theme/ART_SLOTS.md) replace it.
#
# Why not StyleBoxFlat: the pixel look needs a HARD 2 px drop shadow and a 1 px
# inner highlight on the top edge. StyleBoxFlat blurs any shadow it draws
# (shadow_size 1 is a soft smear) and draws none at shadow_size 0, and it has
# one border colour, so it cannot carry a highlight inside the border. This box
# draws exactly four rectangles, snapped to whole pixels - nothing else.
#
# Swapping in real art later: replace a PixelStyleBox in the theme with a
# StyleBoxTexture of the same content margins. Nothing outside the theme names
# this class except UITokens.accent_box(), which already handles both.

@export var bg_color := Color(0, 0, 0, 0):
	set(value):
		bg_color = value
		emit_changed()
@export var border_color := Color(0, 0, 0, 0):
	set(value):
		border_color = value
		emit_changed()
@export var border_width := 2:
	set(value):
		border_width = value
		emit_changed()
# The hard shadow: the face drawn again, offset, in this colour (no blur).
@export var shadow_color := Color(0, 0, 0, 0):
	set(value):
		shadow_color = value
		emit_changed()
@export var shadow_offset := Vector2(0, 2):
	set(value):
		shadow_offset = value
		emit_changed()
# A line just inside the top border: the lit edge of a raised surface.
@export var highlight_color := Color(0, 0, 0, 0):
	set(value):
		highlight_color = value
		emit_changed()
@export var highlight_width := 1:
	set(value):
		highlight_width = value
		emit_changed()
# Moves the face inside the control's rect. A pressed button sets (0, 2) and
# drops its shadow, so it reads as pushed down into where the shadow was.
@export var face_offset := Vector2.ZERO:
	set(value):
		face_offset = value
		emit_changed()
# Grows the drawn rect past the control (a focus ring that sits outside it).
@export var grow := 0:
	set(value):
		grow = value
		emit_changed()
# Dashed border: an empty slot ("Waiting for a mortal...") instead of a frame.
@export var dash := 0:
	set(value):
		dash = value
		emit_changed()


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var face := Rect2(
		(rect.position + face_offset).floor() - Vector2(grow, grow),
		rect.size.floor() + Vector2(grow, grow) * 2)
	if shadow_color.a > 0.0 and shadow_offset != Vector2.ZERO:
		RenderingServer.canvas_item_add_rect(to_canvas_item, Rect2(face.position + shadow_offset, face.size), shadow_color)
	if bg_color.a > 0.0:
		RenderingServer.canvas_item_add_rect(to_canvas_item, face, bg_color)
	var b := float(border_width)
	if border_color.a > 0.0 and b > 0.0:
		if dash > 0:
			_dashed(to_canvas_item, face, b)
		else:
			RenderingServer.canvas_item_add_rect(to_canvas_item, Rect2(face.position, Vector2(face.size.x, b)), border_color)
			RenderingServer.canvas_item_add_rect(to_canvas_item, Rect2(face.position.x, face.end.y - b, face.size.x, b), border_color)
			RenderingServer.canvas_item_add_rect(to_canvas_item, Rect2(face.position.x, face.position.y + b, b, face.size.y - b * 2), border_color)
			RenderingServer.canvas_item_add_rect(to_canvas_item, Rect2(face.end.x - b, face.position.y + b, b, face.size.y - b * 2), border_color)
	if highlight_color.a > 0.0 and highlight_width > 0:
		RenderingServer.canvas_item_add_rect(to_canvas_item,
			Rect2(face.position.x + b, face.position.y + b, face.size.x - b * 2, highlight_width), highlight_color)


func _dashed(item: RID, face: Rect2, b: float) -> void:
	var step := float(dash * 2)
	var x := face.position.x
	while x < face.end.x:
		var w := minf(dash, face.end.x - x)
		RenderingServer.canvas_item_add_rect(item, Rect2(x, face.position.y, w, b), border_color)
		RenderingServer.canvas_item_add_rect(item, Rect2(x, face.end.y - b, w, b), border_color)
		x += step
	var y := face.position.y
	while y < face.end.y:
		var h := minf(dash, face.end.y - y)
		RenderingServer.canvas_item_add_rect(item, Rect2(face.position.x, y, b, h), border_color)
		RenderingServer.canvas_item_add_rect(item, Rect2(face.end.x - b, y, b, h), border_color)
		y += step


func _get_draw_rect(rect: Rect2) -> Rect2:
	var drawn := rect.grow(grow)
	return drawn.merge(Rect2(drawn.position + shadow_offset, drawn.size)) if shadow_color.a > 0.0 else drawn
