extends ColorRect

@export var speed: float = 1.0


func _physics_process(_delta: float) -> void:
	position.y = sin(Time.get_ticks_msec() * 0.001 * speed) * 200.0

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		color = Color.from_hsv(randf_range(0.0, 1.0), 1.0, 0.8)
