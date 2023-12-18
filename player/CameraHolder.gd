extends Node3D

@export var STICK_SENSITIVITY := 240.0
@export var MOUSE_SENSITIVITY := 0.022 * 3.0

func handle_stick_input(delta: float) -> void:
	var camera_direction := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down", 0.15)
	var tilt := camera_direction.length()
	var acceleration : float = lerpf(0.25, 1.0, tilt)
	camera_direction *= acceleration
	rotation_degrees.y -= camera_direction.x * STICK_SENSITIVITY * delta
	rotation_degrees.x -= camera_direction.y * STICK_SENSITIVITY * delta
	rotation_degrees.x = clampf(rotation_degrees.x, -90.0, 90.0)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta : float) -> void:
	handle_stick_input(delta)

# Input handling
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var mouse_input := event as InputEventMouseMotion
			rotation_degrees.y -= mouse_input.relative.x * MOUSE_SENSITIVITY
			rotation_degrees.x -= mouse_input.relative.y * MOUSE_SENSITIVITY
			rotation_degrees.x = clampf(rotation_degrees.x, -90.0, 90.0)

# Unhandled input handling
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("m1") or event.is_action_pressed("m2"):
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
