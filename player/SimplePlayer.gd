class_name SimplePlayer extends CharacterBody3D

# Constants
const MOUSE_SENSITIVITY := 0.022 * 3.0
const UNIT_CONVERSION := 64.0
const GRAVITY := 800.0 / UNIT_CONVERSION
const JUMP_VELOCITY := 270.0 / UNIT_CONVERSION
const MAX_SPEED := 320.0 / UNIT_CONVERSION
const MAX_SPEED_AIR := 320.0 / UNIT_CONVERSION
const ACCELERATION := 15.0
const ACCELERATION_AIR := 2.0
const FRICTION := 6.0

var WISH_DIRECTION : Vector3

# Exported variables
@export var enable_camera_smoothing := true
@export var enable_stairs := true
@export var stairs_cause_floor_snap := false
@export var skipping_hack_distance := 0.08
@export var step_height := 0.5
@export var camera_smoothing_meters_per_sec := 3.0

@export var JUMP := "ui_accept"

# Stairs climbing variables
var started_process_on_floor := false
var found_stairs := false
var slide_snap_offset : Vector3
var wall_remainder : Vector3
var ceiling_position : Vector3
var ceiling_travel_distance : float
var ceiling_collision : KinematicCollision3D
var floor_collision : KinematicCollision3D

# Ready variables
@onready var camera_holder := $CameraHolder as Node3D
@onready var camera_3d := $CameraHolder/Camera3D as Camera3D

# Friction function
func apply_friction(velocity_without_friction : Vector3, delta : float) -> Vector3:
	velocity_without_friction *= pow(0.9, delta * 60.0)
	velocity_without_friction = velocity_without_friction.move_toward(Vector3(), delta * MAX_SPEED)
	return velocity_without_friction

# Handling friction
func handle_friction(delta : float) -> void:
	if is_on_floor():
		velocity = apply_friction(velocity, delta)

# Handling acceleration
func handle_acceleration(delta : float) -> void:
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
func handle_friction_and_acceleration(delta : float) -> void:
	handle_acceleration(delta)
	handle_friction(delta)

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

func probe_probable_step_height() -> float:
	const hull_height := 1.75 # edit me
	const center_offset := 0.875 # edit to match the offset between your origin and the center of your hitbox
	const hull_width := 0.625 # approximately the full width of your hull

	var heading := (velocity * Vector3(1, 0, 1)).normalized()

	var offset : Vector3
	var test := move_and_collide(heading * hull_width, true)
	if test and absf(test.get_normal().y) < 0.8:
		offset = (test.get_position(0) - test.get_travel() - global_position) * Vector3(1, 0, 1)

	var raycast := ShapeCast3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = hull_width/2.0
	shape.height = maxf(0.01, hull_height - step_height*2.0 - 0.1)
	raycast.shape = shape
	raycast.max_results = 1
	add_child(raycast)
	raycast.collision_mask = collision_mask
	raycast.position = Vector3(0.0, center_offset, 0.0)
	if offset != Vector3():
		raycast.target_position = heading * hull_width * 0.22 + offset
	else:
		raycast.target_position = heading * hull_width * 0.72
	#raycast.force_raycast_update()
	raycast.force_shapecast_update()
	if raycast.is_colliding():
		#raycast.position = raycast.get_collision_point(0)
		raycast.global_position = raycast.get_collision_point(0)
	else:
		raycast.global_position += raycast.target_position

	var up_distance := 50.0
	raycast.target_position = Vector3(0.0, 50.0, 0.0)
	#raycast.force_raycast_update()
	raycast.force_shapecast_update()
	if raycast.is_colliding():
		up_distance = raycast.get_collision_point(0).y - raycast.position.y

	var down_distance := center_offset
	raycast.target_position = Vector3(0.0, -center_offset, 0.0)
	#raycast.force_raycast_update()
	raycast.force_shapecast_update()
	if raycast.is_colliding():
		down_distance = raycast.position.y - raycast.get_collision_point(0).y

	raycast.queue_free()

	if up_distance + down_distance < hull_height:
		return step_height
	else:
		var highest := up_distance - center_offset
		var lowest := center_offset - down_distance
		return clampf(highest/2.0 + lowest/2.0, 0.0, step_height)

func handle_camera_smoothing(start_position : Vector3, delta : float) -> void:
	var camera_offset_y := 0.0
	var stair_climb_distance := 0.0
	
	if found_stairs:
		stair_climb_distance = global_position.y - start_position.y
	elif is_on_floor():
		stair_climb_distance = -slide_snap_offset.y
	
	camera_offset_y -= stair_climb_distance
	camera_offset_y = clampf(camera_offset_y, -step_height, step_height)
	camera_offset_y = move_toward(camera_offset_y, 0.0, delta * camera_smoothing_meters_per_sec)
	
	camera_3d.position.y = 0.0
	camera_3d.position.x = 0.0
	camera_3d.global_position.y += camera_offset_y

# Moving and climbing stairs
func move_and_climb_stairs(delta : float, allow_stair_snapping : bool) -> void:
	var start_position := global_position
	var start_velocity := velocity
	
	found_stairs = false
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
		var up_height := probe_probable_step_height()
		ceiling_collision = move_and_collide(up_height * Vector3.UP)
		ceiling_travel_distance = absf(ceiling_collision.get_travel().y) if ceiling_collision else step_height
		ceiling_position = global_position
		
		# step 2: "check if there's a wall" trace
		var info := move_and_collide_n_times(velocity, delta, 2)
		velocity = info[0]
		wall_remainder = info[1]
		
		# step 3: downwards trace
		floor_collision = move_and_collide(Vector3.DOWN * (ceiling_travel_distance + (step_height if started_process_on_floor else 0.0)))
		found_stairs = floor_collision and floor_collision.get_normal(0).y > floor_normal
	
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

# Process function
func _physics_process(delta: float) -> void:
	started_process_on_floor = is_on_floor()
	
	var allow_stair_snapping := true
	if Input.is_action_pressed(JUMP) and is_on_floor():
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
	
	var start_position := global_position
	# CHANGE ME: replace this with your own movement-and-stair-climbing code
	move_and_climb_stairs(delta, allow_stair_snapping)
	
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	
	handle_camera_smoothing(start_position, delta)
