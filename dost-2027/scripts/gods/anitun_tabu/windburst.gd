class_name WindBurst
extends Node2D

# A gust of Anitun Tabu's wind (scenes/gods/anitun_tabu/WindBurst.tscn). It
# swells around a spot for a moment; the middle of that swell is the window a
# mortal can be caught in. The arena pays the penalty - this only plays.

@export var lifetime := 0.9
@export var hit_at := 0.3      # seconds until the gust is dangerous...
@export var hit_window := 0.35 # ...and how long that danger lasts
@export var radius := 48.0

@onready var ring: Sprite2D = $Ring
@onready var gusts_root: Node2D = $Gusts

var _time := 0.0
var _playing := false


func play() -> void:
	_time = 0.0
	_playing = true
	visible = true


func is_playing() -> bool:
	return _playing


func is_hit_window() -> bool:
	return _playing and _time >= hit_at and _time <= hit_at + hit_window


func is_finished() -> bool:
	return not _playing


func _process(delta: float) -> void:
	if not _playing:
		return
	_time += delta
	if _time >= lifetime:
		_playing = false
		visible = false
		return
	var t := clampf(_time / lifetime, 0.0, 1.0)
	if ring != null:
		ring.scale = Vector2.ONE * lerpf(0.25, 1.35, t)
		ring.modulate.a = (1.0 - t) * 0.8
	_draw_gusts(t)


func _draw_gusts(t: float) -> void:
	if gusts_root == null:
		return
	var children := gusts_root.get_children()
	for index in range(children.size()):
		var line := children[index] as Line2D
		if line == null:
			continue
		var phase := float(index) / maxf(1.0, float(children.size()))
		var angle := TAU * phase + _time * 2.4
		var dist := lerpf(10.0, radius * 0.75, t) + float(index) * 5.0
		var span := 0.5 + phase * 0.35
		var points := PackedVector2Array()
		var steps := 9
		for step in range(steps + 1):
			var f := float(step) / float(steps)
			var a := angle + lerpf(-span, span, f)
			var r := dist + sin(f * PI) * 8.0
			points.append(Vector2(cos(a), sin(a)) * r)
		line.points = points
		line.modulate.a = (1.0 - t) * 0.75
