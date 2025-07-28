extends ColorRect

@export var speed: float = 1.0
var cycle_speed: float = 0.1

func _process(delta: float) -> void:
	var hue: float = color.h + cycle_speed * delta
	hue = fmod(hue, 1.0)
	
	color = Color.from_hsv(hue, color.s, color.v)

func _physics_process(_delta: float) -> void:
	position.y = sin(Time.get_ticks_msec() * 0.001 * speed) * 200.0
