class_name BakaGauge
extends Control

# LUKSONG BAKA'S BALANCE BAR, drawn (HananArena.tscn -> BarLayer/Bar). Only the
# look lives here: the arena feeds it the vault's numbers every frame (feed()) and
# keeps every rule - _ind_pos, the box, is_inside_box(), the grace time, the blitz.
# One _draw() and a small fixed pool of sparkles: nothing is created per frame.
#
#   FRAME   a carved frame: a night-indigo inset, a thin Bathala-gold banig double
#           border, and end caps - the arrow cap points the way holding pushes (up;
#           down in a blitz vault). The gold warms with the level, whose name sits
#           in small text over the top cap. A blitz vault's frame is red-gold with a
#           slow pulse and an INVERTED tab.
#   ZONE    the target box: a soft vertical gradient in Hanan's accent with brighter
#           top and bottom edges, breathing while the marker is inside. Outside it
#           turns ember, the frame jitters a little and a thin grace meter drains
#           along the zone's edge over the grace time - a trip reads before it lands.
#   MARKER  an arrow notch on the track with a short motion trail; it squashes when
#           it bounces off the floor or the ceiling.
#   TIMER   a thin strip along the frame's outer side fills over the vault window.
#   FX      sparkles off the zone while it pays, a gold flash on a clean vault, a
#           shake and a crack on a trip (the bar lingers a moment to show them).
# With reduce flashing there is no breathing, jitter, pulse, flash or shake.
#
# ART SLOTS (Assets/Gods/Hanan/, each used when it exists): bar_frame.png (drawn over
# the frame area), bar_box.png (stretched over the zone, tinted) and bar_marker.png
# (centred on the marker).

const ART_DIR := "res://Assets/Gods/Hanan/"
const TRACK := Vector2(28.0, 210.0)   # the gauge itself, px
const FRAME := 5.0                    # the frame around it
const CAP := 10.0                     # each end cap
const LABEL_SPACE := 22.0             # the level name (and the INVERTED tab) over the top cap
const TIMER_W := 3.0                  # the vault timer strip
const TIMER_GAP := 3.0
const TRAIL := 6                      # marker positions kept for the trail
const SPARKS := 10                    # the sparkle pool
const LINGER := 0.45                  # seconds the bar stays up after a vault for its flash / crack
const WARM := Color(1.0, 0.55, 0.32)  # the frame's gold at Over the Moon

# What the arena feeds each frame (see feed()).
var ind_pos := 0.5
var box_center := 0.5
var box_size := 0.3
var marker_size := 0.06
var inside := true
var grace := 0.0          # 0 = full grace, 1 = about to trip
var vault := 0.0          # 0..1 of the vault window gone
var level := 1
var level_name := ""
var inverted := false
var earning := false
var calm := false
var accent := Color(1, 0.62, 0.55)
var outer_left := false   # the timer strip (and the pills) go on the side away from the mortal

var _time := 0.0
var _trail: Array[float] = []
var _last_pos := 0.5
var _squash := 0.0
var _flash := 0.0
var _crack := 0.0
var _linger := 0.0
var _spark_pos: Array[Vector2] = []
var _spark_life: Array[float] = []
var _spark_timer := 0.0
var _art_frame: Texture2D
var _art_box: Texture2D
var _art_marker: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = gauge_size()
	size = gauge_size()
	for index in range(SPARKS):
		_spark_pos.append(Vector2.ZERO)
		_spark_life.append(0.0)
	_art_frame = _art("bar_frame.png")
	_art_box = _art("bar_box.png")
	_art_marker = _art("bar_marker.png")
	# The rate and the practice prompt beside the bar are pills, like all game text.
	for pill_name in ["Rate", "HoldPrompt"]:
		var label := get_node_or_null(pill_name) as Label
		if label != null:
			label.add_theme_stylebox_override("normal", _pill(UITokens.JADE if pill_name == "Rate" else UITokens.GOLD))


static func _pill(border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UITokens.NIGHT_900, 0.85)
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style


static func _art(file: String) -> Texture2D:
	var path := ART_DIR + file
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func gauge_size() -> Vector2:
	return Vector2(TRACK.x + FRAME * 2.0 + TIMER_GAP + TIMER_W, LABEL_SPACE + CAP * 2.0 + FRAME * 2.0 + TRACK.y)


# The gauge's track (0..1 bar heights inside it), local px.
func track_rect() -> Rect2:
	var left := FRAME + (TIMER_W + TIMER_GAP if outer_left else 0.0)
	return Rect2(left, LABEL_SPACE + CAP + FRAME, TRACK.x, TRACK.y)


func feed(state: Dictionary) -> void:
	for key in state.keys():
		set(key, state[key])
	_linger = LINGER


# A clean vault: a quick gold flash (the CLEAN! pill is the arena's callout).
func flash_clean() -> void:
	_flash = 0.35
	_linger = LINGER


# A trip: the bar shakes and cracks for a moment.
func crack() -> void:
	_crack = LINGER
	_linger = LINGER


# Still showing a vault that just ended (its flash or its crack).
func lingering() -> bool:
	return _linger > 0.0


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	_linger = maxf(0.0, _linger - delta)
	_flash = maxf(0.0, _flash - delta)
	_crack = maxf(0.0, _crack - delta)
	_squash = maxf(0.0, _squash - delta)
	var edge := ind_pos <= 0.001 or ind_pos >= 0.999
	var was_edge := _last_pos <= 0.001 or _last_pos >= 0.999
	if edge and not was_edge:
		_squash = 0.12
	_last_pos = ind_pos
	_trail.push_front(ind_pos)
	if _trail.size() > TRAIL:
		_trail.pop_back()
	_tick_sparks(delta)
	queue_redraw()


func _tick_sparks(delta: float) -> void:
	var track := track_rect()
	for index in range(SPARKS):
		if _spark_life[index] > 0.0:
			_spark_life[index] -= delta
			_spark_pos[index] += Vector2(0.0, -24.0 * delta)
	if not earning or not inside or calm:
		return
	_spark_timer -= delta
	if _spark_timer > 0.0:
		return
	_spark_timer = 0.08
	for index in range(SPARKS):
		if _spark_life[index] <= 0.0:
			var top := track.position.y + (1.0 - box_center - box_size * 0.5) * track.size.y
			_spark_pos[index] = Vector2(randf_range(track.position.x - 3.0, track.end.x + 3.0), top + randf_range(0.0, box_size * track.size.y))
			_spark_life[index] = 0.5
			return


func _draw() -> void:
	var track := track_rect()
	var shake := Vector2.ZERO
	if not calm:
		if _crack > 0.0:
			shake = Vector2(randf_range(-2.0, 2.0), randf_range(-1.0, 1.0)).round()
		elif not inside and grace > 0.0:
			shake = Vector2(roundf(randf_range(-1.0, 1.0) * grace), 0.0)
	draw_set_transform(shake)
	var gold := UITokens.GOLD.lerp(WARM, clampf(float(level - 1) / 4.0, 0.0, 1.0))
	if inverted:
		var pulse := 0.5 if calm else 0.5 + 0.5 * sin(_time * 2.5)
		gold = UITokens.GOLD.lerp(UITokens.EMBER, 0.35 + 0.4 * pulse)
	if _flash > 0.0 and not calm:
		gold = gold.lerp(UITokens.GOLD_HI, _flash / 0.35)
	var frame := track.grow(FRAME)
	# Inset and the banig double border.
	draw_rect(frame, Color(UITokens.NIGHT_900, 0.9))
	if _art_frame != null:
		draw_texture_rect(_art_frame, frame, false)
	else:
		draw_rect(frame, gold, false, 1.0)
		draw_rect(frame.grow(-2.0), Color(gold, 0.6), false, 1.0)
	draw_rect(track, Color(UITokens.NIGHT_800, 0.95))
	# End caps: the arrow points where holding pushes the marker.
	var top_cap := Rect2(frame.position.x, frame.position.y - CAP, frame.size.x, CAP)
	var bottom_cap := Rect2(frame.position.x, frame.end.y, frame.size.x, CAP)
	_draw_cap(top_cap, not inverted, true, gold)
	_draw_cap(bottom_cap, inverted, false, gold)
	# The zone.
	var zone_top := track.position.y + (1.0 - box_center - box_size * 0.5) * track.size.y
	var zone := Rect2(track.position.x, zone_top, track.size.x, box_size * track.size.y).intersection(track)
	var tint := accent.lightened(0.2) if inside else UITokens.EMBER.darkened(0.1)
	var breathe := 0.0 if calm or not inside else 0.08 * sin(_time * 4.0)
	if _art_box != null:
		draw_texture_rect(_art_box, zone, false, Color(tint, 0.85 + breathe))
	else:
		var mid := zone.position.y + zone.size.y * 0.5
		var edge_a := 0.6 + breathe
		var mid_a := 0.28 + breathe
		_vertical_gradient(Rect2(zone.position, Vector2(zone.size.x, mid - zone.position.y)), Color(tint, edge_a), Color(tint, mid_a))
		_vertical_gradient(Rect2(Vector2(zone.position.x, mid), Vector2(zone.size.x, zone.end.y - mid)), Color(tint, mid_a), Color(tint, edge_a))
		var bright := tint.lightened(0.35)
		draw_line(zone.position, Vector2(zone.end.x, zone.position.y), bright, 1.0)
		draw_line(Vector2(zone.position.x, zone.end.y - 1.0), Vector2(zone.end.x, zone.end.y - 1.0), bright, 1.0)
	# Out of the zone it is hatched as well as ember, so it never reads by colour alone,
	# and the grace meter drains along its inner edge.
	if not inside:
		var hatch := Color(UITokens.NIGHT_900, 0.55)
		var step := 6.0
		var offset := 0.0
		while offset < zone.size.x + zone.size.y:
			var a := zone.position + Vector2(offset, 0.0)
			var b := a + Vector2(-zone.size.y, zone.size.y)
			# clip the diagonal to the zone
			var t0 := maxf(0.0, (a.x - zone.end.x) / maxf(1.0, zone.size.y))
			var t1 := minf(1.0, (a.x - zone.position.x) / maxf(1.0, zone.size.y))
			if t1 > t0:
				draw_line(a.lerp(b, t0), a.lerp(b, t1), hatch, 1.0)
			offset += step
		var left := zone.size.y * (1.0 - clampf(grace, 0.0, 1.0))
		var x := zone.end.x - 2.0 if outer_left else zone.position.x
		draw_rect(Rect2(x, zone.end.y - left, 2.0, left), UITokens.IVORY)
	# Sparkles.
	for index in range(SPARKS):
		if _spark_life[index] > 0.0:
			draw_rect(Rect2(_spark_pos[index].round(), Vector2(2, 2)), Color(UITokens.GOLD_HI, _spark_life[index] / 0.5))
	# The marker: a trail, then the notch.
	var marker_h := maxf(4.0, marker_size * track.size.y)
	for index in range(_trail.size() - 1, 0, -1):
		var y := track.position.y + (1.0 - _trail[index]) * track.size.y
		draw_line(Vector2(track.position.x + 2.0, y), Vector2(track.end.x - 2.0, y), Color(UITokens.GOLD_HI, 0.35 * (1.0 - float(index) / TRAIL)), 1.0)
	var y_mark := roundf(track.position.y + (1.0 - ind_pos) * track.size.y)
	var squash := 1.0 + (1.6 * _squash / 0.12 if not calm else 0.0)
	var half_h := maxf(1.0, marker_h * 0.5 / squash)
	var widen := (squash - 1.0) * 3.0
	if _art_marker != null:
		var marker_size_px := Vector2(track.size.x + 8.0 + widen * 2.0, marker_h / squash * 1.5)
		draw_texture_rect(_art_marker, Rect2(Vector2(track.get_center().x, y_mark) - marker_size_px * 0.5, marker_size_px), false)
	else:
		draw_rect(Rect2(track.position.x - widen, y_mark - half_h, track.size.x + widen * 2.0, half_h * 2.0), Color(UITokens.GOLD_HI, 0.95))
		# The notch points at the bar from the mortal's side.
		var tip := track.position.x - 1.0 if not outer_left else track.end.x + 1.0
		var back := tip - 6.0 if not outer_left else tip + 6.0
		draw_colored_polygon(PackedVector2Array([Vector2(back, y_mark - 5.0), Vector2(tip, y_mark), Vector2(back, y_mark + 5.0)]), UITokens.GOLD_HI)
	# A trip's crack.
	if _crack > 0.0:
		var a := Color(UITokens.EMBER, _crack / LINGER)
		var x0 := track.position.x
		var cy := track.get_center().y
		draw_polyline(PackedVector2Array([Vector2(x0, cy - 30), Vector2(x0 + 9, cy - 18), Vector2(x0 + 5, cy - 6), Vector2(x0 + 16, cy + 4),
			Vector2(x0 + 12, cy + 14), Vector2(x0 + track.size.x, cy + 26)]), a, 1.0)
		draw_polyline(PackedVector2Array([Vector2(x0 + 16, cy + 4), Vector2(x0 + 24, cy - 2)]), a, 1.0)
	# The vault timer along the outer side.
	var timer_x := frame.position.x - TIMER_GAP - TIMER_W if outer_left else frame.end.x + TIMER_GAP
	var timer := Rect2(timer_x, frame.position.y, TIMER_W, frame.size.y)
	draw_rect(timer, Color(UITokens.NIGHT_700, 0.9))
	var filled := timer.size.y * clampf(vault, 0.0, 1.0)
	draw_rect(Rect2(timer.position.x, timer.end.y - filled, TIMER_W, filled), gold)
	# Labels over the top cap: the level's name, and INVERTED on a blitz vault.
	var font := get_theme_default_font()
	if font != null:
		var name_y := top_cap.position.y - 2.0
		_label(font, level_name, Vector2(frame.get_center().x, name_y), gold)
		if inverted:
			_label(font, "INVERTED", Vector2(frame.get_center().x, name_y - 10.0), UITokens.EMBER)
	draw_set_transform(Vector2.ZERO)


func _draw_cap(rect: Rect2, arrow: bool, up: bool, gold: Color) -> void:
	var c := rect.get_center().x
	if arrow:
		var tip_y := rect.position.y + 1.0 if up else rect.end.y - 1.0
		var base_y := rect.end.y if up else rect.position.y
		draw_colored_polygon(PackedVector2Array([Vector2(rect.position.x + 2.0, base_y), Vector2(c, tip_y), Vector2(rect.end.x - 2.0, base_y)]), gold)
	else:
		var y := rect.position.y + 2.0 if up else rect.position.y
		draw_rect(Rect2(rect.position.x + 4.0, y, rect.size.x - 8.0, rect.size.y - 2.0), Color(gold, 0.7))


func _vertical_gradient(rect: Rect2, top: Color, bottom: Color) -> void:
	if rect.size.y <= 0.0:
		return
	draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))


# An 8 px word centred on `at` (its baseline), on a small night plate.
func _label(font: Font, text: String, at: Vector2, tint: Color) -> void:
	if text == "":
		return
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UITokens.CAPTION).x
	var left := roundf(at.x - width * 0.5)
	draw_rect(Rect2(left - 2.0, at.y - 8.0, width + 4.0, 10.0), Color(UITokens.NIGHT_900, 0.85))
	draw_string(font, Vector2(left, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, UITokens.CAPTION, tint)
