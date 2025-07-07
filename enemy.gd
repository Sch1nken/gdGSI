extends ColorRect

@export var speed: float = 1.0


func _physics_process(_delta: float) -> void:
	position.y = sin(Time.get_ticks_msec() * 0.001 * speed) * 200.0
