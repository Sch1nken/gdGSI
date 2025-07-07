extends Control

@onready var enemy_red: ColorRect = $EnemyAnchor/Enemy_Red
@onready var enemy_blue: ColorRect = $EnemyAnchor/Enemy_Blue


func _physics_process(_delta: float) -> void:
	GSI.set_section_data("enemies", {"enemy_red": {"position_y": enemy_red.position.y}})

	GSI.set_section_data("enemies", {"enemy_blue": {"position_y": enemy_blue.position.y}})
