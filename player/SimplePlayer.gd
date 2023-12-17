extends CharacterBody3D
class_name SimplePlayer

const mouse_sens := 0.022 * 3.0
const unit_conversion := 64.0
const gravity := 800.0/unit_conversion
const jumpvel := 270.0/unit_conversion
const max_speed := 320.0/unit_conversion
const max_speed_air := 320.0/unit_conversion
const accel := 15.0
const accel_air := 2.0
var wish_dir : Vector3
var friction := 6.0

func _ready():
	floor_constant_speed = true

func _friction(_velocity : Vector3, delta : float) -> Vector3:
	_velocity *= pow(0.9, delta*60.0)
	if wish_dir == Vector3():
		_velocity = _velocity.move_toward(Vector3(), delta * max_speed)
	return _velocity

func handle_friction(delta : float):
	if is_on_floor():
		velocity = _friction(velocity, delta)

func handle_accel(delta : float):
	if wish_dir != Vector3():
		var actual_maxspeed := max_speed if is_on_floor() else max_speed_air
		var wish_dir_length := wish_dir.length()
		var actual_accel := (accel if is_on_floor() else accel_air) * actual_maxspeed * wish_dir_length
		var floor_velocity := Vector3(velocity.x, 0, velocity.z)
		
		var speed_in_wish_dir := floor_velocity.dot(wish_dir.normalized())
		var speed := floor_velocity.length()
		if speed_in_wish_dir < actual_maxspeed:
			var add_limit := actual_maxspeed - speed_in_wish_dir
			var add_amount := minf(add_limit, actual_accel*delta)
			velocity += wish_dir.normalized() * add_amount
			if is_on_floor() and speed > actual_maxspeed:
				velocity = velocity.normalized() * speed

func handle_friction_and_accel(delta : float):
	handle_friction(delta)
	handle_accel(delta)

@export var do_camera_smoothing := true
@export var do_stairs := true
@export var do_skipping_hack := false
@export var stairs_cause_floor_snap := false
@export var skipping_hack_distance := 0.08
@export var step_height := 0.5

var started_process_on_floor := false

var found_stairs := false
var slide_snap_offset : Vector3
var wall_test_travel : Vector3
var wall_remainder : Vector3
var ceiling_position : Vector3
var ceiling_travel_distance : float
var ceiling_collision : KinematicCollision3D
var wall_collision : KinematicCollision3D
var floor_collision : KinematicCollision3D

func check_and_attempt_skipping_hack(distance : float, floor_normal : float):
	ceiling_collision = null
	wall_collision = null
	floor_collision = null
	# try again with a certain minimum horizontal step distance if there was no wall collision and the wall trace was close
	if !found_stairs and (wall_test_travel * Vector3(1,0,1)).length() < distance:
		# go back to where we were at the end of the ceiling collision test
		global_position = ceiling_position
		# calculate a new path for the wall test: horizontal only, length of our fallback distance
		var floor_velocity := Vector3(velocity.x, 0.0, velocity.z)
		var factor := distance / floor_velocity.length()
		
		# step 2, skipping hack version
		wall_test_travel = floor_velocity * factor
		var info = move_and_collide_n_times(floor_velocity, factor, 2)
		velocity = info[0]
		wall_remainder = info[1]
		wall_collision = info[2]
		
		# step 3, skipping hack version
		floor_collision = move_and_collide(Vector3.DOWN * (ceiling_travel_distance + (step_height if started_process_on_floor else 0.0)))
		if floor_collision and floor_collision.get_collision_count() > 0 and floor_collision.get_normal(0).y > floor_normal:
			found_stairs = true

func move_and_collide_n_times(vector : Vector3, delta : float, slide_count : int, skip_reject_if_ceiling : bool = true):
	var collision : KinematicCollision3D
	var remainder := vector
	var adjusted_vector := vector * delta
	var _floor_normal := cos(floor_max_angle)
	for _i in slide_count:
		var new_collision := move_and_collide(adjusted_vector)
		if new_collision:
			collision = new_collision
			remainder = collision.get_remainder()
			adjusted_vector = remainder
			if !skip_reject_if_ceiling or collision.get_normal().y >= -_floor_normal:
				adjusted_vector = adjusted_vector.slide(collision.get_normal())
				vector = vector.slide(collision.get_normal())
		else:
			remainder = Vector3()
			break
	
	return [vector, remainder, collision]

func move_and_climb_stairs(delta : float, allow_stair_snapping : bool):
	var start_position := global_position
	var start_velocity := velocity
	
	found_stairs = false
	wall_test_travel = Vector3()
	wall_remainder = Vector3()
	ceiling_position = Vector3()
	ceiling_travel_distance = 0.0
	ceiling_collision = null
	wall_collision = null
	floor_collision = null
	
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
	if hit_wall and do_stairs and (start_velocity.x != 0.0 or start_velocity.z != 0.0):
		global_position = start_position
		velocity = start_velocity
		# step 1: upwards trace
		var up_height := step_height # NOT NECESSARY. can just be step_height.
		
		ceiling_collision = move_and_collide(up_height * Vector3.UP)
		ceiling_travel_distance = step_height if not ceiling_collision else absf(ceiling_collision.get_travel().y)
		ceiling_position = global_position
		# step 2: "check if there's a wall" trace
		wall_test_travel = velocity * delta
		var info = move_and_collide_n_times(velocity, delta, 2)
		velocity = info[0]
		wall_remainder = info[1]
		wall_collision = info[2]
		
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
		var oldvel : Vector3 = velocity
		velocity = wall_remainder / delta
		move_and_slide()
		velocity = oldvel
	# no stairs, do "normal" non-stairs movement
	else:
		global_position = slide_position
		velocity = slide_velocity
	
	return found_stairs

@onready var CamHolder := $CameraHolder as Node3D
@onready var Cam3D := $CameraHolder/Camera3D as Camera3D

func _process(delta: float) -> void:
	started_process_on_floor = is_on_floor()
	# for controller camera control
	handle_stick_input(delta)
	
	var allow_stair_snapping := true
	if Input.is_action_pressed("ui_accept") and is_on_floor():
		allow_stair_snapping = false
		velocity.y = jumpvel
		floor_snap_length = 0.0
	elif started_process_on_floor:
		floor_snap_length = step_height + safe_margin
	
	var input_dir := Input.get_vector("left", "right", "forward", "backward") + Input.get_vector("stick_left", "stick_right", "stick_forward", "stick_backward")
	wish_dir = Vector3(input_dir.x, 0, input_dir.y).rotated(Vector3.UP, CamHolder.global_rotation.y)
	if wish_dir.length_squared() > 1.0:
		wish_dir = wish_dir.normalized()
	
	handle_friction_and_accel(delta)
	
	if not is_on_floor():
		velocity.y -= gravity * delta * 0.5
	
	var start_position := global_position
	
	# CHANGE ME: replace this with your own movement-and-stair-climbing code
	move_and_climb_stairs(delta, allow_stair_snapping)
	
	if not is_on_floor():
		velocity.y -= gravity * delta * 0.5
	
	handle_camera_adjustment(start_position, delta)

const stick_camera_speed := 240.0
func handle_stick_input(delta: float):
	var camera_dir := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down", 0.15)
	var tilt := camera_dir.length()
	var acceleration : float = lerpf(0.25, 1.0, tilt)
	camera_dir *= acceleration
	CamHolder.rotation_degrees.y -= camera_dir.x * stick_camera_speed * delta
	CamHolder.rotation_degrees.x -= camera_dir.y * stick_camera_speed * delta
	CamHolder.rotation_degrees.x = clampf(CamHolder.rotation_degrees.x, -90.0, 90.0)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			CamHolder.rotation_degrees.y -= event.relative.x * mouse_sens
			CamHolder.rotation_degrees.x -= event.relative.y * mouse_sens
			CamHolder.rotation_degrees.x = clampf(CamHolder.rotation_degrees.x, -90.0, 90.0)

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
	CamHolder.position.y = 1.5
	Cam3D.position.z = 0.0
	
	if do_camera_smoothing:
		# NOT NEEDED: camera smoothing
		var stair_climb_distance := 0.0
		if found_stairs:
			stair_climb_distance = global_position.y - start_position.y
		elif is_on_floor():
			stair_climb_distance = -slide_snap_offset.y
		
		camera_offset_y -= stair_climb_distance
		camera_offset_y = clampf(camera_offset_y, -step_height, step_height)
		camera_offset_y = move_toward(camera_offset_y, 0.0, delta * camera_smoothing_meters_per_sec)
		
		Cam3D.position.y = 0.0
		Cam3D.position.x = 0.0
		Cam3D.global_position.y += camera_offset_y
