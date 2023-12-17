extends CharacterBody3D
class_name SimplePlayer

# Constants
const MOUSE_SENSITIVITY := 0.022 * 3.0
const UNIT_CONVERSION := 64.0
const GRAVITY := 800.0 / UNIT_CONVERSION
const JUMP_VELOCITY := 270.0 / UNIT_CONVERSION
const MAX_SPEED := 320.0 / UNIT_CONVERSION
const MAX_SPEED_AIR := 320.0 / UNIT_CONVERSION
const ACCELERATION := 15.0
const ACCELERATION_AIR := 2.0
var WISH_DIRECTION : Vector3
var FRICTION := 6.0

# Friction function
func _apply_friction(velocity : Vector3, delta : float) -> Vector3:
	velocity *= pow(0.9, delta * 60.0)
	if WISH_DIRECTION == Vector3():
		velocity = velocity.move_toward(Vector3(), delta * MAX_SPEED)
	return velocity

# Handling friction
func handle_friction(delta : float):
	if is_on_floor():
		velocity = _apply_friction(velocity, delta)

# Handling acceleration
func handle_acceleration(delta : float):
	if WISH_DIRECTION != Vector3():
		var actual_max_speed := MAX_SPEED if is_on_floor() else MAX_SPEED_AIR
		var wish_direction_length := WISH_DIRECTION.length()
		var actual_acceleration := (ACCELERATION if is_on_floor() else ACCELERATION_AIR) * actual_max_speed * wish_direction_length
		var floor_velocity := Vector3(velocity.x, 0, velocity.z)
		
		var speed_in_wish_direction := floor_velocity.dot(WISH_DIRECTION.normalized())
		var speed := floor_velocity.length()
		
		if speed_in_wish_direction < actual_max_speed:
			var add_limit := actual_max_speed - speed_in_wish_direction
			var add_amount := minf(add_limit, actual_acceleration * delta)
			velocity += WISH_DIRECTION.normalized() * add_amount
			
			if is_on_floor() and speed > actual_max_speed:
				velocity = velocity.normalized() * speed

# Handling friction and acceleration together
func handle_friction_and_acceleration(delta : float):
	handle_friction(delta)
	handle_acceleration(delta)

# Exported variables
@export var enable_camera_smoothing := true
@export var enable_stairs := true
@export var enable_skipping_hack := false
@export var stairs_cause_floor_snap := false
@export var skipping_hack_distance := 0.08
@export var step_height := 0.5

# Stairs climbing variables
var started_process_on_floor := false
var found_stairs := false
var slide_snap_offset : Vector3
var wall_test_travel : Vector3
var wall_remainder : Vector3
var ceiling_position : Vector3
var ceiling_travel_distance : float
var ceiling_collision : KinematicCollision3D
var floor_collision : KinematicCollision3D

# Checking and attempting skipping hack
func check_and_attempt_skipping_hack(distance : float, floor_normal : float):
	# try again with a certain minimum horizontal step distance if there was no wall collision and the wall trace was close
		# go back to where we were at the end of the ceiling collision test
	if !found_stairs and (wall_test_travel * Vector3(1, 0, 1)).length() < distance:
		global_position = ceiling_position
		# calculate a new path for the wall test: horizontal only, length of our fallback distance
		var floor_velocity := Vector3(velocity.x, 0.0, velocity.z)
		var factor := distance / floor_velocity.length()
		
		# step 2, skipping hack version
		wall_test_travel = floor_velocity * factor
		var info := move_and_collide_n_times(floor_velocity, factor, 2)
		velocity = info[0]
		wall_remainder = info[1]
		
		# step 3, skipping hack version
		floor_collision = move_and_collide(Vector3.DOWN * (ceiling_travel_distance + (step_height if started_process_on_floor else 0.0)))
		if floor_collision and floor_collision.get_collision_count() > 0 and floor_collision.get_normal(0).y > floor_normal:
			found_stairs = true

# Moving and colliding multiple times
func move_and_collide_n_times(vector : Vector3, delta : float, slide_count : int, skip_reject_if_ceiling : bool = true) -> Array[Vector3]:
	var collision : KinematicCollision3D
	var remainder := vector
	var adjusted_vector := vector * delta
	var floor_normal := cos(floor_max_angle)
	
	for slide in range(slide_count):
		var new_collision := move_and_collide(adjusted_vector)
		if new_collision:
			collision = new_collision
			remainder = collision.get_remainder()
			adjusted_vector = remainder
			if !skip_reject_if_ceiling or collision.get_normal().y >= -floor_normal:
				adjusted_vector = adjusted_vector.slide(collision.get_normal())
				vector = vector.slide(collision.get_normal())
		else:
			remainder = Vector3()
			break
	
	return [vector, remainder]

# Moving and climbing stairs
func move_and_climb_stairs(delta : float, allow_stair_snapping : bool):
	var start_position := global_position
	var start_velocity := velocity
	
	found_stairs = false
	wall_test_travel = Vector3()
	wall_remainder = Vector3()
	ceiling_position = Vector3()
	ceiling_travel_distance = 0.0
	
	# do move_and_slide and check if we hit a wall
	move_and_slide()
	var slide_velocity := velocity
	var slide_position := global_position
	var hit_wall := false
	var floor_normal := cos(floor_max_angle)
	var max_slide := get_slide_collision_count()
	var accumulated_position := start_position
	
	for slide in max_slide:
		var collision : KinematicCollision3D = get_slide_collision(slide)
		var y : float = collision.get_normal().y
		if y < floor_normal and y > -floor_normal:
			hit_wall = true
		accumulated_position += collision.get_travel()
	
	slide_snap_offset = accumulated_position - global_position
	
	# if we hit a wall, check for simple stairs; three steps
	if hit_wall and enable_stairs and (start_velocity.x != 0.0 or start_velocity.z != 0.0):
		global_position = start_position
		velocity = start_velocity
		# step 1: upwards trace
		
		var up_height := step_height
		ceiling_collision = move_and_collide(up_height * Vector3.UP)
		ceiling_travel_distance = step_height if not ceiling_collision else absf(ceiling_collision.get_travel().y)
		ceiling_position = global_position
		# step 2: "check if there's a wall" trace
		
		wall_test_travel = velocity * delta
		var info := move_and_collide_n_times(velocity, delta, 2)
		velocity = info[0]
		wall_remainder = info[1]
		
		# step 3: downwards trace
		floor_collision = move_and_collide(Vector3.DOWN * (ceiling_travel_distance + (step_height if started_process_on_floor else 0.0)))
		if floor_collision:
			if floor_collision.get_normal(0).y > floor_normal:
				found_stairs = true
	
	# (this section is more complex than it needs to be, because of move_and_slide taking velocity and delta for granted)
	# if we found stairs, climb up them
	if found_stairs:
		if allow_stair_snapping and stairs_cause_floor_snap:
			velocity.y = 0.0
		var old_velocity : Vector3 = velocity
		velocity = wall_remainder / delta
		move_and_slide()
		velocity = old_velocity
	else:
		global_position = slide_position
		velocity = slide_velocity
	
	return found_stairs

# Ready variables
@onready var camera_holder := $CameraHolder as Node3D
@onready var camera_3d := $CameraHolder/Camera3D as Camera3D

# Process function
func _process(delta: float) -> void:
	started_process_on_floor = is_on_floor()
	# for controller camera control
	handle_stick_input(delta)
	
	var allow_stair_snapping := true
	if Input.is_action_pressed("ui_accept") and is_on_floor():
		allow_stair_snapping = false
		velocity.y = JUMP_VELOCITY
		floor_snap_length = 0.0
	elif started_process_on_floor:
		floor_snap_length = step_height + safe_margin
	
	var input_direction := Input.get_vector("left", "right", "forward", "backward") + Input.get_vector("stick_left", "stick_right", "stick_forward", "stick_backward")
	WISH_DIRECTION = Vector3(input_direction.x, 0, input_direction.y).rotated(Vector3.UP, camera_holder.global_rotation.y)
	if WISH_DIRECTION.length_squared() > 1.0:
		WISH_DIRECTION = WISH_DIRECTION.normalized()
	
	handle_friction_and_acceleration(delta)
	
	if not is_on_floor():
		velocity.y -= GRAVITY * delta * 0.5
	
	var start_position := global_position
	# CHANGE ME: replace this with your own movement-and-stair-climbing code
	move_and_climb_stairs(delta, allow_stair_snapping)
	
	if not is_on_floor():
		velocity.y -= GRAVITY * delta * 0.5
	
	handle_camera_adjustment(start_position, delta)

# Stick input handling
const STICK_CAMERA_SPEED := 240.0
func handle_stick_input(delta: float):
	var camera_direction := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down", 0.15)
	var tilt := camera_direction.length()
	var acceleration : float = lerp(0.25, 1.0, tilt)
	camera_direction *= acceleration
	camera_holder.rotation_degrees.y -= camera_direction.x * STICK_CAMERA_SPEED * delta
	camera_holder.rotation_degrees.x -= camera_direction.y * STICK_CAMERA_SPEED * delta
	camera_holder.rotation_degrees.x = clamp(camera_holder.rotation_degrees.x, -90.0, 90.0)

# Input handling
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			camera_holder.rotation_degrees.y -= event.relative.x * MOUSE_SENSITIVITY
			camera_holder.rotation_degrees.x -= event.relative.y * MOUSE_SENSITIVITY
			camera_holder.rotation_degrees.x = clamp(camera_holder.rotation_degrees.x, -90.0, 90.0)

# Unhandled input handling
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("m1") or event.is_action_pressed("m2"):
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

@export var camera_smoothing_meters_per_sec := 3.0
# used to smooth out the camera when climbing stairs
var camera_offset_y : float
func handle_camera_adjustment(start_position : Vector3, delta : float):
	# first/third-person adjustment
	camera_holder.position.y = 1.5
	camera_3d.position.z = 0.0
	
		# NOT NEEDED: camera smoothing
	if enable_camera_smoothing:
		var stair_climb_distance := 0.0
		if found_stairs:
			stair_climb_distance = global_position.y - start_position.y
		elif is_on_floor():
			stair_climb_distance = -slide_snap_offset.y
		
		camera_offset_y -= stair_climb_distance
		camera_offset_y = clamp(camera_offset_y, -step_height, step_height)
		camera_offset_y = move_toward(camera_offset_y, 0.0, delta * camera_smoothing_meters_per_sec)
		
		camera_3d.position.y = 0.0
		camera_3d.position.x = 0.0
		camera_3d.global_position.y += camera_offset_y
