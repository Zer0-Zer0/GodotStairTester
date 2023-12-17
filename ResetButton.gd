extends Button

var start_pos = Vector3()
func _ready() -> void:
	start_pos = $"../Player".global_position

func _on_pressed() -> void:
	$"../Player".global_position = start_pos
	$"../Player".velocity *= 0.0
	$"../Player/CameraHolder".rotation.y = 0.0
	$"../Player/CameraHolder".rotation.x = 0.0
	release_focus()
