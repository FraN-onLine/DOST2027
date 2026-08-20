extends Node2D

@export var duration: float = 0.6
@export var rise_pixels: float = 16.0

@onready var label: Label = $Label

func show_damage(amount: int, world_start: Vector2) -> void:
	# Start state
	global_position = world_start
	label.text = str(amount)
	label.modulate = Color(1, 0.1, 0.1)  # red text
	modulate.a = 1.0  # fully visible

	# Float up + fade out over `duration`
	var end_pos := world_start + Vector2(0, -rise_pixels)
	var tween := create_tween()
	tween.set_parallel()
	tween.tween_property(self, "global_position", end_pos, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, duration)

	await tween.finished
	queue_free()

func show_num(amount: int, world_start: Vector2) -> void:
	# Start state
	global_position = world_start
	label.text = str(amount)
	modulate.a = 1.0  # fully visible

	# Float up + fade out over `duration`
	var end_pos := world_start + Vector2(0, -rise_pixels)
	var tween := create_tween()
	tween.set_parallel()
	tween.tween_property(self, "global_position", end_pos, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, duration)

	await tween.finished
	queue_free()

func show_text(strlols, world_start: Vector2) -> void:
	# Start state
	global_position = world_start
	label.text = strlols
	modulate.a = 1.0  # fully visible

	# Float up + fade out over `duration`
	var end_pos := world_start + Vector2(0, -rise_pixels)
	var tween := create_tween()
	tween.set_parallel()
	tween.tween_property(self, "global_position", end_pos, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, duration)

	await tween.finished
	queue_free()
