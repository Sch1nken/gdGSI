extends Control

@onready var enemy_red: ColorRect = $EnemyAnchor/Enemy_Red
@onready var enemy_blue: ColorRect = $EnemyAnchor/Enemy_Blue


func _physics_process(_delta: float) -> void:
	GSI.set_section_data(
		"enemies",
		{
			"enemy_red":
			{
				"position_y": enemy_red.position.y,
				"color_r": enemy_red.color.r8,
				"color_g": enemy_red.color.g8,
				"color_b": enemy_red.color.b8
			}
		}
	)
	GSI.set_section_data(
		"enemies",
		{
			"enemy_blue":
			{
				"position_y": enemy_blue.position.y,
				"color_r": enemy_blue.color.r8,
				"color_g": enemy_blue.color.g8,
				"color_b": enemy_blue.color.b8
			}
		}
	)
