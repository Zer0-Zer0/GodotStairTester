extends Node3D

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	$CharacterBody3D.do_stairs = $StairsSetting.button_pressed
	$CharacterBody3D.do_skipping_hack = $SkippingSetting.button_pressed
